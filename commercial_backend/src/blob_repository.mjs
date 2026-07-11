import { getStore } from "@netlify/blobs";

const STORE_NAME = "studygrades-data";

export class BlobRepository {
  constructor(store = null) {
    this._store = store;
    this.locks = new Map();
  }

  get store() {
    this._store ??= getStore(STORE_NAME);
    return this._store;
  }

  async readJson(key, fallback = null) {
    const value = await this.store.get(key, {
      type: "json",
      consistency: "strong",
    });
    return value ?? fallback;
  }

  async writeJson(key, value) {
    await this.store.setJSON(key, value);
  }

  async mutateJson(key, fallback, mutation) {
    const previous = this.locks.get(key) ?? Promise.resolve();
    const operation = previous.catch(() => {}).then(async () => {
      if (!this.store.getWithMetadata || !this.store.set) {
        const current = await this.readJson(key, structuredClone(fallback));
        const next = await mutation(current);
        await this.writeJson(key, next);
        return next;
      }

      for (let attempt = 0; attempt < 8; attempt += 1) {
        const snapshot = await this.store.getWithMetadata(key, {
          type: "json",
          consistency: "strong",
        });
        const current = structuredClone(snapshot?.data ?? fallback);
        const next = await mutation(current);
        const condition = snapshot
          ? { onlyIfMatch: snapshot.etag }
          : { onlyIfNew: true };
        if (snapshot && !snapshot.etag) {
          throw new Error("Blob mutation cannot continue without an ETag.");
        }
        const result = await this.store.set(key, JSON.stringify(next), condition);
        if (result.modified) return next;
        await new Promise((resolve) =>
          setTimeout(resolve, 5 * (attempt + 1) + Math.floor(Math.random() * 10)),
        );
      }
      throw new Error("Blob mutation could not be committed after concurrent updates.");
    });
    this.locks.set(key, operation);
    try {
      return await operation;
    } finally {
      if (this.locks.get(key) === operation) this.locks.delete(key);
    }
  }

  async findUserByUsername(username) {
    const document = await this.readJson("users", { users: [] });
    return (
      document.users.find(
        (user) => String(user.username).trim().toLowerCase() === username,
      ) ?? null
    );
  }

  async getUserById(id) {
    const document = await this.readJson("users", { users: [] });
    return (
      document.users.find((user) => String(user.id) === String(id)) ?? null
    );
  }

  async saveUser(updated) {
    await this.mutateJson("users", { users: [] }, (document) => {
      const index = document.users.findIndex(
        (user) => String(user.id) === String(updated.id),
      );
      if (index < 0) throw new Error("User was not found.");
      document.users[index] = { ...document.users[index], ...updated };
      return document;
    });
  }

  async createUser(user) {
    let created = null;
    await this.mutateJson("users", { users: [] }, (document) => {
      const username = String(user.username).trim().toLowerCase();
      const email = String(user.email ?? "").trim().toLowerCase();
      if (
        document.users.some(
          (candidate) =>
            String(candidate.username).trim().toLowerCase() === username,
        )
      ) {
        throw new Error("Username already exists.");
      }
      if (
        email &&
        document.users.some(
          (candidate) =>
            String(candidate.email ?? "").trim().toLowerCase() === email,
        )
      ) {
        throw new Error("Email address already exists.");
      }
      const maxId = document.users.reduce((current, candidate) => {
        const id = Number(candidate.id);
        return Number.isSafeInteger(id) && id > current ? id : current;
      }, 0);
      created = { ...user, id: maxId + 1 };
      document.users.push(created);
      return document;
    });
    return structuredClone(created);
  }

  async listUsers() {
    const document = await this.readJson("users", { users: [] });
    return document.users;
  }

  async getHierarchy(userId) {
    const catalog = await this.#getCatalog(userId);
    const hierarchy = Array.isArray(catalog.hierarchy)
      ? catalog.hierarchy
      : Array.isArray(catalog.stages)
        ? catalog.stages
        : [];
    return structuredClone(hierarchy);
  }

  async getClassroom(
    userId,
    classId,
    subject,
    { termId = 1, weekNumber = 1 } = {},
  ) {
    const catalog = await this.#getCatalog(userId);
    const rawClassrooms = catalog.classrooms;
    const classrooms = Array.isArray(rawClassrooms)
      ? rawClassrooms
      : rawClassrooms && typeof rawClassrooms === "object"
        ? Object.values(rawClassrooms)
        : [];
    const normalizedSubject = String(subject).trim().toLocaleLowerCase("en");
    let classroom = null;
    for (const candidate of classrooms) {
      if (
        !candidate ||
        typeof candidate !== "object" ||
        Number(candidate.class_id ?? candidate.id) !== Number(classId)
      ) {
        continue;
      }
      if (candidate.subjects && typeof candidate.subjects === "object") {
        const matchingKey = Object.keys(candidate.subjects).find(
          (key) => key.trim().toLocaleLowerCase("en") === normalizedSubject,
        );
        if (matchingKey) {
          classroom = {
            ...candidate,
            ...candidate.subjects[matchingKey],
            subject: matchingKey,
          };
          delete classroom.subjects;
          break;
        }
      }
      if (
        String(candidate.subject ?? "")
          .trim()
          .toLocaleLowerCase("en") === normalizedSubject
      ) {
        classroom = { ...candidate };
        break;
      }
    }
    if (!classroom) return null;

    const subjectKey = Buffer.from(String(subject).trim()).toString("base64url");
    const period = await this.readJson(
      `grades/${userId}/${termId}/${weekNumber}/${classId}/${subjectKey}`,
      { students: {} },
    );
    const periodStudents =
      period?.students && typeof period.students === "object"
        ? period.students
        : {};
    const students = Array.isArray(classroom.students)
      ? classroom.students.map((student) => ({
          ...student,
          existing_grades: {
            ...(student.existing_grades ?? {}),
            ...(periodStudents[String(student.id)] ?? {}),
          },
        }))
      : [];
    return {
      ...classroom,
      class_id: Number(classroom.class_id ?? classroom.id),
      subject: String(subject).trim(),
      students,
    };
  }

  async saveCatalog(userId, catalog) {
    await this.writeJson(`catalog/${userId}`, catalog);
  }

  async registerDevice(userId, deviceId, { maxDevices }) {
    const key = `devices/${userId}`;
    let limitRejected = false;
    const document = await this.mutateJson(key, { devices: [] }, (current) => {
      const now = new Date().toISOString();
      const active = current.devices.filter((device) => !device.revoked);
      const existing = active.find((device) => device.id === deviceId);
      if (existing) {
        existing.last_seen_at = now;
      } else if (maxDevices > 0 && active.length >= maxDevices) {
        limitRejected = true;
      } else {
        current.devices.push({
          id: deviceId,
          created_at: now,
          last_seen_at: now,
          revoked: false,
        });
      }
      return current;
    });
    const activeDevices = document.devices.filter((device) => !device.revoked).length;
    return {
      activeDevices: limitRejected ? activeDevices + 1 : activeDevices,
      assignedSeats: 1,
    };
  }

  async getUsage(userId) {
    const document = await this.readJson(`devices/${userId}`, { devices: [] });
    return {
      activeDevices: document.devices.filter((device) => !device.revoked).length,
      assignedSeats: 1,
    };
  }

  async createSession(session) {
    await this.writeJson(`sessions/${session.id}`, session);
    await this.writeJson(`refresh/${session.refresh_hash}`, {
      session_id: session.id,
    });
    await this.mutateJson(
      `user-sessions/${session.user_id}`,
      { session_ids: [] },
      (document) => {
        const ids = Array.isArray(document.session_ids)
          ? document.session_ids.filter((id) => id !== session.id)
          : [];
        ids.push(session.id);
        document.session_ids = ids.slice(-100);
        return document;
      },
    );
  }

  async rotateRefreshToken(oldHash, patch) {
    return this.#withLock(`refresh:${oldHash}`, async () => {
      const pointer = await this.readJson(`refresh/${oldHash}`);
      if (!pointer?.session_id) return null;
      const sessionKey = `sessions/${pointer.session_id}`;
      const session = await this.readJson(sessionKey);
      if (
        !session ||
        session.revoked ||
        session.refresh_hash !== oldHash ||
        new Date(session.expires_at) <= new Date()
      ) {
        return null;
      }
      const updated = { ...session, ...patch };
      await this.store.delete(`refresh/${oldHash}`);
      await this.writeJson(sessionKey, updated);
      await this.writeJson(`refresh/${updated.refresh_hash}`, {
        session_id: updated.id,
      });
      return updated;
    });
  }

  async isSessionActive(sessionId, userId) {
    const session = await this.readJson(`sessions/${sessionId}`);
    return Boolean(
      session &&
        String(session.user_id) === String(userId) &&
        !session.revoked &&
        new Date(session.expires_at) > new Date(),
    );
  }

  async revokeSession(sessionId) {
    const key = `sessions/${sessionId}`;
    const session = await this.readJson(key);
    if (!session) return;
    await this.writeJson(key, {
      ...session,
      revoked: true,
      revoked_at: new Date().toISOString(),
    });
    if (session.refresh_hash) {
      await this.store.delete(`refresh/${session.refresh_hash}`);
    }
  }

  async revokeUserSessions(userId) {
    const indexKey = `user-sessions/${userId}`;
    const document = await this.readJson(indexKey, { session_ids: [] });
    const ids = Array.isArray(document.session_ids) ? document.session_ids : [];
    await Promise.all(ids.map((sessionId) => this.revokeSession(sessionId)));
    await this.writeJson(indexKey, { session_ids: [] });
  }

  async createPayment(payment) {
    await this.writeJson(`payments/${payment.reference}`, payment);
  }

  async getPayment(reference) {
    return this.readJson(`payments/${reference}`);
  }

  async updatePayment(reference, patch) {
    await this.mutateJson(`payments/${reference}`, {}, (payment) => ({
      ...payment,
      ...patch,
    }));
  }

  async recordPaymentDeclined(reference, patch) {
    await this.mutateJson(`payments/${reference}`, {}, (payment) => {
      if (!payment?.reference || ["paid", "fulfilling"].includes(payment.status)) {
        return payment;
      }
      return { ...payment, ...patch };
    });
  }

  async claimPaymentForFulfillment(reference, patch, { lockTtlMs = 300_000 } = {}) {
    const nowIso = patch.fulfillment_started_at ?? new Date().toISOString();
    const nowMs = Date.parse(nowIso);
    let result = { status: "missing", payment: null };
    await this.mutateJson(`payments/${reference}`, {}, (payment) => {
      if (!payment?.reference) {
        result = { status: "missing", payment: null };
        return payment;
      }
      if (payment.status === "paid") {
        result = { status: "already_paid", payment: { ...payment } };
        return payment;
      }
      const lockStarted = Date.parse(payment.fulfillment_started_at ?? "");
      const lockIsFresh =
        payment.status === "fulfilling" &&
        Number.isFinite(lockStarted) &&
        Number.isFinite(nowMs) &&
        nowMs - lockStarted < lockTtlMs;
      if (lockIsFresh) {
        result = { status: "in_progress", payment: { ...payment } };
        return payment;
      }
      const claimed = {
        ...payment,
        ...patch,
        status: "fulfilling",
        fulfillment_started_at: nowIso,
        updated_at: nowIso,
      };
      result = { status: "claimed", payment: { ...claimed } };
      return claimed;
    });
    return result;
  }

  async appendLog(entry) {
    await this.mutateJson("logs", { logs: [] }, (document) => {
      const nextId = document.logs.reduce(
        (highest, item) => Math.max(highest, Number(item.id) || 0),
        0,
      ) + 1;
      document.logs.push({ id: nextId, ...entry });
      if (document.logs.length > 1000) {
        document.logs = document.logs.slice(-1000);
      }
      return document;
    });
  }

  async saveGrades(userId, payload, idempotencyKey) {
    const receiptKey = `idempotency/${userId}/${idempotencyKey}`;
    const existing = await this.readJson(receiptKey);
    if (existing) return existing.response;
    const termId = positiveInteger(payload.term_id, "term_id");
    const weekNumber = positiveInteger(payload.week_number, "week_number");
    const classId = positiveInteger(payload.class_id, "class_id");
    const subject = String(payload.subject ?? "").trim();
    if (!subject || subject.length > 100) throw new Error("Invalid subject.");
    const subjectKey = Buffer.from(subject).toString("base64url");
    const savedAt = new Date().toISOString();
    const normalizedEntries = [];
    for (const item of payload.grades) {
      const studentId = positiveInteger(item.student_id, "student_id");
      if (!item.grades || typeof item.grades !== "object" || Array.isArray(item.grades)) {
        throw new Error("Invalid grade entry.");
      }
      const normalized = {};
      for (const [field, rawValue] of Object.entries(item.grades)) {
        const value = Number(rawValue);
        if (!/^[A-Za-z0-9_.-]{1,64}$/.test(field) || !Number.isFinite(value) || value < 0 || value > 1000) {
          throw new Error("Invalid grade value.");
        }
        normalized[field] = value;
      }
      normalizedEntries.push({ studentId, grades: normalized });
    }
    const gradesKey = `grades/${userId}/${termId}/${weekNumber}/${classId}/${subjectKey}`;
    await this.mutateJson(gradesKey, { students: {} }, (document) => {
      if (!document.students || typeof document.students !== "object") {
        document.students = {};
      }
      for (const entry of normalizedEntries) {
        const key = String(entry.studentId);
        document.students[key] = {
          ...(document.students[key] ?? {}),
          ...entry.grades,
        };
      }
      document.updated_at = savedAt;
      return document;
    });
    const response = { synced: payload.grades.length, saved_at: savedAt };
    await this.writeJson(receiptKey, {
      response,
      created_at: savedAt,
      expires_at: new Date(Date.now() + 7 * 86_400_000).toISOString(),
    });
    return response;
  }

  async #getCatalog(userId) {
    const own = await this.readJson(`catalog/${userId}`);
    if (own && typeof own === "object") return own;
    return this.readJson("catalog/default", { hierarchy: [], classrooms: [] });
  }

  async #withLock(key, operation) {
    const previous = this.locks.get(key) ?? Promise.resolve();
    const current = previous.catch(() => {}).then(operation);
    this.locks.set(key, current);
    try {
      return await current;
    } finally {
      if (this.locks.get(key) === current) this.locks.delete(key);
    }
  }
}

function positiveInteger(value, name) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`Invalid ${name}.`);
  }
  return parsed;
}
