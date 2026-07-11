import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";

import { createApp } from "../src/app.mjs";
import { calculatePaymobTransactionHmac } from "../src/paymob.mjs";
import { verifyPassword } from "../src/security.mjs";

function activeSubscription() {
  return {
    plan: "professional",
    status: "active",
    expires_at: "2099-01-01T00:00:00.000Z",
  };
}

function fakeRepository() {
  const user = {
    id: 1,
    username: "teacher",
    email: "teacher@example.com",
    phone: "01012345678",
    full_name: "Test Teacher",
    role: "teacher",
    is_active: true,
    password: createHash("sha256").update("password-123").digest("hex"),
    subscription: activeSubscription(),
  };
  return {
    user,
    createdUsers: [],
    savedUser: null,
    sessions: [],
    hierarchyRequests: [],
    classroomRequests: [],
    savedCatalog: null,
    async findUserByUsername(username) {
      if (username === this.user.username) return { ...this.user };
      const created = this.createdUsers.find(
        (candidate) => candidate.username === username,
      );
      return created ? { ...created } : null;
    },
    async getUserById(id) {
      if (String(id) === String(this.user.id)) return { ...this.user };
      const created = this.createdUsers.find(
        (candidate) => String(candidate.id) === String(id),
      );
      return created ? { ...created } : null;
    },
    async saveUser(updated) {
      if (String(updated.id) === String(this.user.id)) {
        this.user = { ...updated };
      } else {
        const index = this.createdUsers.findIndex(
          (candidate) => String(candidate.id) === String(updated.id),
        );
        if (index < 0) throw new Error("User was not found.");
        this.createdUsers[index] = { ...updated };
      }
      this.savedUser = { ...updated };
    },
    async listUsers() {
      return [{ ...this.user }, ...this.createdUsers.map((item) => ({ ...item }))];
    },
    async createUser(newUser) {
      if (
        [this.user, ...this.createdUsers].some(
          (candidate) => candidate.username === newUser.username,
        )
      ) {
        throw new Error("Username already exists.");
      }
      const created = { ...newUser, id: 2 + this.createdUsers.length };
      this.createdUsers.push(created);
      return { ...created };
    },
    async registerDevice() {
      return { activeDevices: 1, assignedSeats: 1 };
    },
    async createSession(session) {
      this.sessions.push(session);
    },
    async rotateRefreshToken(oldHash, next) {
      const session = this.sessions.find(
        (entry) => entry.refresh_hash === oldHash && !entry.revoked,
      );
      if (!session) return null;
      Object.assign(session, next);
      return { ...session };
    },
    async isSessionActive(sessionId, userId) {
      return this.sessions.some(
        (entry) =>
          entry.id === sessionId &&
          String(entry.user_id) === String(userId) &&
          !entry.revoked,
      );
    },
    async revokeSession(sessionId) {
      const session = this.sessions.find((entry) => entry.id === sessionId);
      if (session) session.revoked = true;
    },
    async revokeUserSessions(userId) {
      for (const session of this.sessions) {
        if (String(session.user_id) === String(userId)) session.revoked = true;
      }
    },
    async appendLog() {},
    async getHierarchy(userId) {
      this.hierarchyRequests.push(userId);
      return [
        {
          id: 10,
          name: "Primary",
          classes: [{ id: 101, name: "Class A", subject: "Arabic" }],
        },
      ];
    },
    async getClassroom(userId, classId, subject, period) {
      this.classroomRequests.push({ userId, classId, subject, period });
      if (classId !== 101) return null;
      return {
        class_id: 101,
        class_name: "Class A",
        subject,
        grade_structure: [{ name: "oral", label: "Oral", max: 15 }],
        students: Array.from({ length: 30 }, (_, index) => ({
          id: index + 1,
          student_number: String(index + 1),
          name: `Student ${index + 1}`,
          existing_grades: {},
        })),
      };
    },
    async saveCatalog(userId, catalog) {
      this.savedCatalog = { userId, catalog };
    },
  };
}

const env = {
  JWT_SECRET: "a-test-jwt-secret-that-is-at-least-32-characters",
  PRICE_PROFESSIONAL_MONTHLY_EGP: "100",
  PAYMOB_SECRET_KEY: "paymob-secret",
  PAYMOB_PUBLIC_KEY: "paymob-public",
  PAYMOB_CARD_INTEGRATION_ID: "5344998",
};

async function loginUser(app, username = "teacher", password = "password-123") {
  const response = await app(
    new Request("https://example.test/api/mobile/token/", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-device-id": `device-${username}-12345678`,
      },
      body: JSON.stringify({ username, password }),
    }),
  );
  assert.equal(response.status, 200);
  return response.json();
}

test("login upgrades legacy password and never returns password material", async () => {
  const repository = fakeRepository();
  const app = createApp({ repository, env });
  const response = await app(
    new Request("https://example.test/api/mobile/token/", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-device-id": "device-1234567890",
      },
      body: JSON.stringify({ username: "teacher", password: "password-123" }),
    }),
  );
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.match(repository.savedUser.password, /^scrypt\$/);
  assert.equal("password" in body.user, false);
  assert.equal(typeof body.access, "string");
  assert.equal(typeof body.refresh, "string");
});

test("a developer can create, list, update, and deactivate commercial users", async () => {
  const repository = fakeRepository();
  repository.user.username = "developer";
  repository.user.email = "developer@example.com";
  repository.user.role = "developer";
  repository.user.subscription = {
    plan: "enterprise",
    status: "active",
    lifetime: true,
  };
  const app = createApp({ repository, env });
  const developerSession = await loginUser(app, "developer");

  const createdResponse = await app(
    new Request("https://example.test/api/mobile/admin/users/", {
      method: "POST",
      headers: {
        authorization: `Bearer ${developerSession.access}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        username: "new.teacher",
        password: "TeacherPass-2026",
        email: "new.teacher@example.com",
        role: "teacher",
        full_name: "New Teacher",
        subscription: { plan: "starter", status: "active" },
      }),
    }),
  );
  const createdBody = await createdResponse.json();

  assert.equal(createdResponse.status, 201);
  assert.equal(createdBody.user.username, "new.teacher");
  assert.equal(createdBody.user.subscription.plan, "starter");
  assert.equal("password" in createdBody.user, false);
  assert.equal("password_hash" in createdBody.user, false);
  assert.match(repository.createdUsers[0].password, /^scrypt\$/);
  assert.equal(
    await verifyPassword("TeacherPass-2026", repository.createdUsers[0].password),
    true,
  );

  const listResponse = await app(
    new Request("https://example.test/api/mobile/admin/users/", {
      headers: { authorization: `Bearer ${developerSession.access}` },
    }),
  );
  const listed = await listResponse.json();
  assert.equal(listResponse.status, 200);
  assert.equal(listed.users.length, 2);
  assert.equal(listed.users.some((user) => "password" in user), false);

  const managedSession = await loginUser(
    app,
    "new.teacher",
    "TeacherPass-2026",
  );
  const updateResponse = await app(
    new Request(`https://example.test/api/mobile/admin/users/${createdBody.user.id}/`, {
      method: "PUT",
      headers: {
        authorization: `Bearer ${developerSession.access}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        full_name: "Updated Teacher",
        new_password: "UpdatedPass-2026",
      }),
    }),
  );
  assert.equal(updateResponse.status, 200);
  assert.equal(repository.createdUsers[0].full_name, "Updated Teacher");

  const revokedSessionResponse = await app(
    new Request("https://example.test/api/mobile/account/me/", {
      headers: { authorization: `Bearer ${managedSession.access}` },
    }),
  );
  assert.equal(revokedSessionResponse.status, 401);
  const renewedSession = await loginUser(app, "new.teacher", "UpdatedPass-2026");

  const deleteResponse = await app(
    new Request(`https://example.test/api/mobile/admin/users/${createdBody.user.id}/`, {
      method: "DELETE",
      headers: { authorization: `Bearer ${developerSession.access}` },
    }),
  );
  assert.equal(deleteResponse.status, 204);
  assert.equal(repository.createdUsers[0].is_active, false);

  const deactivatedResponse = await app(
    new Request("https://example.test/api/mobile/account/me/", {
      headers: { authorization: `Bearer ${renewedSession.access}` },
    }),
  );
  assert.equal(deactivatedResponse.status, 401);
});

test("commercial user management rejects unauthorized roles and duplicates", async () => {
  const teacherRepository = fakeRepository();
  const teacherApp = createApp({ repository: teacherRepository, env });
  const teacherSession = await loginUser(teacherApp);
  const forbidden = await teacherApp(
    new Request("https://example.test/api/mobile/admin/users/", {
      headers: { authorization: `Bearer ${teacherSession.access}` },
    }),
  );
  assert.equal(forbidden.status, 403);

  const repository = fakeRepository();
  repository.user.username = "developer";
  repository.user.role = "developer";
  repository.user.subscription = {
    plan: "enterprise",
    status: "active",
    lifetime: true,
  };
  const app = createApp({ repository, env });
  const { access } = await loginUser(app, "developer");
  const create = (overrides = {}) =>
    app(
      new Request("https://example.test/api/mobile/admin/users/", {
        method: "POST",
        headers: {
          authorization: `Bearer ${access}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          username: "commercial.teacher",
          password: "Commercial-2026",
          email: "commercial@example.com",
          role: "teacher",
          ...overrides,
        }),
      }),
    );

  assert.equal((await create({ role: "developer" })).status, 400);
  assert.equal((await create()).status, 201);
  assert.equal((await create()).status, 409);
  assert.equal(
    (await create({ username: "another.teacher" })).status,
    409,
  );
});

test("protected grade sync rejects a missing access token", async () => {
  const app = createApp({ repository: fakeRepository(), env });
  const response = await app(
    new Request("https://example.test/api/mobile/grades/sync/", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ grades: [] }),
    }),
  );

  assert.equal(response.status, 401);
});

test("CORS preflight is restricted to configured origins", async () => {
  const app = createApp({
    repository: fakeRepository(),
    env: {
      ...env,
      ALLOWED_ORIGINS:
        "https://studygrades-2026.netlify.app,https://admin.studygrades.app",
    },
  });

  const allowed = await app(
    new Request("https://example.test/api/mobile/token/", {
      method: "OPTIONS",
      headers: {
        origin: "https://studygrades-2026.netlify.app",
        "access-control-request-method": "POST",
      },
    }),
  );
  const denied = await app(
    new Request("https://example.test/api/mobile/token/", {
      method: "OPTIONS",
      headers: {
        origin: "https://evil.example",
        "access-control-request-method": "POST",
      },
    }),
  );

  assert.equal(allowed.status, 204);
  assert.equal(
    allowed.headers.get("access-control-allow-origin"),
    "https://studygrades-2026.netlify.app",
  );
  assert.match(
    allowed.headers.get("access-control-allow-headers"),
    /authorization/,
  );
  assert.equal(denied.status, 204);
  assert.equal(denied.headers.get("access-control-allow-origin"), null);
  assert.equal(denied.headers.get("vary"), "Origin");
});

test("CORS headers are attached to error responses for allowed origins", async () => {
  const app = createApp({
    repository: fakeRepository(),
    env: { ...env, ALLOWED_ORIGINS: "https://studygrades-2026.netlify.app" },
  });
  const response = await app(
    new Request("https://example.test/api/mobile/unknown/", {
      headers: { origin: "https://studygrades-2026.netlify.app" },
    }),
  );

  assert.equal(response.status, 404);
  assert.equal(
    response.headers.get("access-control-allow-origin"),
    "https://studygrades-2026.netlify.app",
  );
});

test("payment return page is static and cannot activate a subscription", async () => {
  const repository = fakeRepository();
  const app = createApp({ repository, env });
  const response = await app(
    new Request(
      "https://example.test/api/mobile/billing/paymob/return/?success=true&reference=%3Cscript%3E",
    ),
  );
  const body = await response.text();

  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type"), /^text\/html/);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.match(response.headers.get("content-security-policy"), /default-src 'none'/);
  assert.match(body, /StudyGrades/);
  assert.doesNotMatch(body, /<script>/);
  assert.equal(repository.savedUser, null);
});

test("hierarchy is loaded for the authenticated account only", async () => {
  const repository = fakeRepository();
  const app = createApp({ repository, env });
  const login = await app(
    new Request("https://example.test/api/mobile/token/", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-device-id": "device-1234567890",
      },
      body: JSON.stringify({ username: "teacher", password: "password-123" }),
    }),
  );
  const { access } = await login.json();

  const response = await app(
    new Request("https://example.test/api/mobile/hierarchy/?user_id=999", {
      headers: { authorization: `Bearer ${access}` },
    }),
  );
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.hierarchy[0].classes[0].id, 101);
  assert.deepEqual(repository.hierarchyRequests, [1]);
});

test("account endpoint returns the current safe entitlement", async () => {
  const repository = fakeRepository();
  const app = createApp({ repository, env });
  const login = await app(
    new Request("https://example.test/api/mobile/token/", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-device-id": "device-1234567890",
      },
      body: JSON.stringify({ username: "teacher", password: "password-123" }),
    }),
  );
  const { access } = await login.json();
  repository.user.subscription = {
    plan: "school",
    status: "active",
    expires_at: "2099-01-01T00:00:00.000Z",
  };

  const response = await app(
    new Request("https://example.test/api/mobile/account/me/", {
      headers: { authorization: `Bearer ${access}` },
    }),
  );
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.user.subscription.plan, "school");
  assert.equal("password" in body.user, false);
});

test("expired accounts can renew but cannot use protected academic data", async () => {
  const repository = fakeRepository();
  repository.user.subscription = {
    plan: "professional",
    status: "expired",
    expires_at: "2020-01-01T00:00:00.000Z",
  };
  repository.payment = null;
  repository.createPayment = async (payment) => {
    repository.payment = { ...payment };
  };
  repository.updatePayment = async (_reference, patch) => {
    repository.payment = { ...repository.payment, ...patch };
  };
  const app = createApp({
    repository,
    env,
    paymobFetch: async () =>
      new Response(
        JSON.stringify({ id: "intent-expired", client_secret: "client-secret" }),
        { status: 201, headers: { "content-type": "application/json" } },
      ),
  });

  const login = await app(
    new Request("https://example.test/api/mobile/token/", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-device-id": "device-1234567890",
      },
      body: JSON.stringify({ username: "teacher", password: "password-123" }),
    }),
  );
  const loginBody = await login.json();

  assert.equal(login.status, 200);
  assert.equal(loginBody.user.subscription.is_usable, false);

  const account = await app(
    new Request("https://example.test/api/mobile/account/me/", {
      headers: { authorization: `Bearer ${loginBody.access}` },
    }),
  );
  assert.equal(account.status, 200);

  const renewal = await app(
    new Request("https://example.test/api/mobile/billing/intention/", {
      method: "POST",
      headers: {
        authorization: `Bearer ${loginBody.access}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        plan: "professional",
        billing_cycle: "monthly",
      }),
    }),
  );
  assert.equal(renewal.status, 201);
  assert.equal(repository.payment.status, "intention_created");

  const protectedData = await app(
    new Request("https://example.test/api/mobile/hierarchy/", {
      headers: { authorization: `Bearer ${loginBody.access}` },
    }),
  );
  const protectedBody = await protectedData.json();

  assert.equal(protectedData.status, 403);
  assert.equal(protectedBody.subscription.is_usable, false);
});

test("refresh keeps expired-account sessions alive for renewal flows", async () => {
  const repository = fakeRepository();
  repository.user.subscription = {
    plan: "professional",
    status: "expired",
    expires_at: "2020-01-01T00:00:00.000Z",
  };
  const app = createApp({ repository, env });
  const login = await app(
    new Request("https://example.test/api/mobile/token/", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-device-id": "device-1234567890",
      },
      body: JSON.stringify({ username: "teacher", password: "password-123" }),
    }),
  );
  const { refresh } = await login.json();

  const response = await app(
    new Request("https://example.test/api/mobile/token/refresh/", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ refresh }),
    }),
  );
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(typeof body.access, "string");
  assert.equal(typeof body.refresh, "string");
});

test("device limit violations still block new logins", async () => {
  const repository = fakeRepository();
  repository.user.subscription = {
    plan: "starter",
    status: "active",
    expires_at: "2099-01-01T00:00:00.000Z",
  };
  repository.registerDevice = async () => ({
    activeDevices: 2,
    assignedSeats: 1,
  });
  const app = createApp({ repository, env });
  const response = await app(
    new Request("https://example.test/api/mobile/token/", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-device-id": "device-1234567890",
      },
      body: JSON.stringify({ username: "teacher", password: "password-123" }),
    }),
  );
  const body = await response.json();

  assert.equal(response.status, 403);
  assert.equal(body.subscription.device_limit_reached, true);
});

test("students endpoint validates the class and enforces the server plan limit", async () => {
  const repository = fakeRepository();
  repository.user.subscription = {
    plan: "trial",
    status: "active",
    expires_at: "2099-01-01T00:00:00.000Z",
  };
  const app = createApp({ repository, env });
  const login = await app(
    new Request("https://example.test/api/mobile/token/", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-device-id": "device-1234567890",
      },
      body: JSON.stringify({ username: "teacher", password: "password-123" }),
    }),
  );
  const { access } = await login.json();

  const response = await app(
    new Request(
      "https://example.test/api/mobile/students/?class_id=101&subject=Arabic&term_id=2&week_number=7&user_id=999",
      { headers: { authorization: `Bearer ${access}` } },
    ),
  );
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.students.length, 25);
  assert.deepEqual(repository.classroomRequests, [
    {
      userId: 1,
      classId: 101,
      subject: "Arabic",
      period: { termId: 2, weekNumber: 7 },
    },
  ]);
});

test("students endpoint rejects invalid or unknown classes", async () => {
  const repository = fakeRepository();
  const app = createApp({ repository, env });
  const login = await app(
    new Request("https://example.test/api/mobile/token/", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-device-id": "device-1234567890",
      },
      body: JSON.stringify({ username: "teacher", password: "password-123" }),
    }),
  );
  const { access } = await login.json();
  const request = (query) =>
    app(
      new Request(`https://example.test/api/mobile/students/?${query}`, {
        headers: { authorization: `Bearer ${access}` },
      }),
    );

  assert.equal((await request("class_id=nope&subject=Arabic")).status, 400);
  assert.equal((await request("class_id=404&subject=Arabic")).status, 404);
  assert.equal((await request("class_id=101&subject=")).status, 400);
});

test("a developer can import a validated catalog for an account", async () => {
  const repository = fakeRepository();
  repository.user.role = "developer";
  repository.user.subscription = {
    plan: "enterprise",
    status: "active",
    lifetime: true,
  };
  const app = createApp({ repository, env });
  const login = await app(
    new Request("https://example.test/api/mobile/token/", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-device-id": "device-1234567890",
      },
      body: JSON.stringify({ username: "teacher", password: "password-123" }),
    }),
  );
  const { access } = await login.json();
  const response = await app(
    new Request("https://example.test/api/mobile/admin/catalog/", {
      method: "PUT",
      headers: {
        authorization: `Bearer ${access}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        target_user_id: 1,
        classrooms: [
          {
            stage_id: 1,
            stage_name: "Primary",
            class_id: 101,
            class_name: "Class A",
            subject: "Arabic",
            grade_structure: [{ name: "oral", label: "Oral", max: 15 }],
            students: [{ id: 1, student_number: "001", name: "Student One" }],
          },
        ],
      }),
    }),
  );
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(repository.savedCatalog.userId, 1);
  assert.equal(repository.savedCatalog.catalog.classrooms.length, 1);
  assert.equal(body.summary.students, 1);
});

test("a teacher cannot import or replace a catalog", async () => {
  const repository = fakeRepository();
  const app = createApp({ repository, env });
  const login = await app(
    new Request("https://example.test/api/mobile/token/", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-device-id": "device-1234567890",
      },
      body: JSON.stringify({ username: "teacher", password: "password-123" }),
    }),
  );
  const { access } = await login.json();
  const response = await app(
    new Request("https://example.test/api/mobile/admin/catalog/", {
      method: "PUT",
      headers: {
        authorization: `Bearer ${access}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ target_user_id: 1, classrooms: [] }),
    }),
  );

  assert.equal(response.status, 403);
  assert.equal(repository.savedCatalog, null);
});

test("refresh tokens are rotated and cannot be reused", async () => {
  const repository = fakeRepository();
  const app = createApp({ repository, env });
  const login = await app(
    new Request("https://example.test/api/mobile/token/", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-device-id": "device-1234567890",
      },
      body: JSON.stringify({ username: "teacher", password: "password-123" }),
    }),
  );
  const original = await login.json();
  const refreshRequest = (refresh) =>
    new Request("https://example.test/api/mobile/token/refresh/", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ refresh }),
    });

  const rotated = await app(refreshRequest(original.refresh));
  const rotatedBody = await rotated.json();
  const reused = await app(refreshRequest(original.refresh));

  assert.equal(rotated.status, 200);
  assert.notEqual(rotatedBody.refresh, original.refresh);
  assert.equal(reused.status, 401);
});

test("changing a password verifies the current secret and revokes every session", async () => {
  const repository = fakeRepository();
  const app = createApp({ repository, env });
  const login = await app(
    new Request("https://example.test/api/mobile/token/", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-device-id": "device-1234567890",
      },
      body: JSON.stringify({ username: "teacher", password: "password-123" }),
    }),
  );
  const { access } = await login.json();

  const response = await app(
    new Request("https://example.test/api/mobile/account/password/", {
      method: "POST",
      headers: {
        authorization: `Bearer ${access}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        current_password: "password-123",
        new_password: "NewPassword-456",
      }),
    }),
  );

  assert.equal(response.status, 200);
  assert.equal(await verifyPassword("NewPassword-456", repository.user.password), true);
  assert.equal(await verifyPassword("password-123", repository.user.password), false);
  assert.equal(repository.sessions.every((session) => session.revoked), true);
  assert.deepEqual(await response.json(), { reauthentication_required: true });
});

test("changing a password rejects an incorrect current password without mutation", async () => {
  const repository = fakeRepository();
  const app = createApp({ repository, env });
  const login = await app(
    new Request("https://example.test/api/mobile/token/", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-device-id": "device-1234567890",
      },
      body: JSON.stringify({ username: "teacher", password: "password-123" }),
    }),
  );
  const { access } = await login.json();
  const before = repository.user.password;

  const response = await app(
    new Request("https://example.test/api/mobile/account/password/", {
      method: "POST",
      headers: {
        authorization: `Bearer ${access}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        current_password: "wrong-password",
        new_password: "NewPassword-456",
      }),
    }),
  );

  assert.equal(response.status, 401);
  assert.equal(repository.user.password, before);
  assert.equal(repository.sessions.some((session) => session.revoked), false);
});

test("changing a password rejects weak or unchanged passwords", async () => {
  const repository = fakeRepository();
  const app = createApp({ repository, env });
  const login = await app(
    new Request("https://example.test/api/mobile/token/", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-device-id": "device-1234567890",
      },
      body: JSON.stringify({ username: "teacher", password: "password-123" }),
    }),
  );
  const { access } = await login.json();

  for (const newPassword of ["short1", "password-123", "allletterslong"]) {
    const response = await app(
      new Request("https://example.test/api/mobile/account/password/", {
        method: "POST",
        headers: {
          authorization: `Bearer ${access}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          current_password: "password-123",
          new_password: newPassword,
        }),
      }),
    );
    assert.equal(response.status, 400, newPassword);
  }
});

test("checkout amount is selected on the server", async () => {
  const repository = fakeRepository();
  repository.createPayment = async () => {};
  repository.updatePayment = async () => {};
  const paymobBodies = [];
  const app = createApp({
    repository,
    env,
    paymobFetch: async (_url, options) => {
      paymobBodies.push(JSON.parse(options.body));
      return new Response(
        JSON.stringify({ id: "intent-1", client_secret: "client-secret" }),
        { status: 201, headers: { "content-type": "application/json" } },
      );
    },
  });

  const login = await app(
    new Request("https://example.test/api/mobile/token/", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-device-id": "device-1234567890",
      },
      body: JSON.stringify({ username: "teacher", password: "password-123" }),
    }),
  );
  const { access } = await login.json();
  const response = await app(
    new Request("https://example.test/api/mobile/billing/intention/", {
      method: "POST",
      headers: {
        authorization: `Bearer ${access}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        plan: "professional",
        billing_cycle: "monthly",
        amount_cents: 1,
      }),
    }),
  );

  assert.equal(response.status, 201);
  assert.equal(paymobBodies[0].amount, 10_000);
  assert.equal(paymobBodies[0].billing_data.phone_number, "+201012345678");
  assert.equal(paymobBodies[0].billing_data.email, "teacher@example.com");
});

test("checkout rejects missing customer contact data before creating a payment", async () => {
  const repository = fakeRepository();
  repository.user.phone = "";
  let paymentCreated = false;
  repository.createPayment = async () => {
    paymentCreated = true;
  };
  const app = createApp({ repository, env });
  const { access } = await loginUser(app);

  const response = await app(
    new Request("https://example.test/api/mobile/billing/intention/", {
      method: "POST",
      headers: {
        authorization: `Bearer ${access}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        plan: "professional",
        billing_cycle: "monthly",
      }),
    }),
  );

  assert.equal(response.status, 400);
  assert.equal(paymentCreated, false);
});

test("a verified successful webhook activates the paid plan exactly once", async () => {
  const repository = fakeRepository();
  repository.payment = {
    reference: "SG-1-order",
    user_id: 1,
    plan: "professional",
    billing_cycle: "monthly",
    amount_cents: 10_000,
    currency: "EGP",
    status: "intention_created",
  };
  repository.getPayment = async () => ({ ...repository.payment });
  repository.updatePayment = async (_reference, patch) => {
    repository.payment = { ...repository.payment, ...patch };
  };
  const transaction = {
    amount_cents: 10_000,
    created_at: "2026-07-03T00:00:00.000Z",
    currency: "EGP",
    error_occured: false,
    has_parent_transaction: false,
    id: 987,
    integration_id: 5344998,
    is_3d_secure: true,
    is_auth: false,
    is_capture: false,
    is_refunded: false,
    is_standalone_payment: true,
    is_voided: false,
    order: { id: 456, merchant_order_id: "SG-1-order" },
    owner: 789,
    pending: false,
    source_data: { pan: "2346", sub_type: "MasterCard", type: "card" },
    success: true,
  };
  const webhookEnv = { ...env, PAYMOB_HMAC_SECRET: "test-hmac-secret" };
  const hmac = calculatePaymobTransactionHmac(
    transaction,
    webhookEnv.PAYMOB_HMAC_SECRET,
  );
  const app = createApp({ repository, env: webhookEnv });
  const request = () =>
    new Request(
      `https://example.test/api/mobile/billing/paymob/webhook/?hmac=${hmac}`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ type: "TRANSACTION", obj: transaction }),
      },
    );

  const first = await app(request());
  const firstExpiry = repository.user.subscription.expires_at;
  const second = await app(request());

  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.equal(repository.payment.status, "paid");
  assert.equal(repository.user.subscription.plan, "professional");
  assert.equal(repository.user.subscription.expires_at, firstExpiry);
});

test("concurrent verified Paymob callbacks claim a payment once", async () => {
  const repository = fakeRepository();
  let saveUserCalls = 0;
  const saveUser = repository.saveUser.bind(repository);
  repository.saveUser = async (updated) => {
    saveUserCalls += 1;
    await new Promise((resolve) => setTimeout(resolve, 20));
    await saveUser(updated);
  };
  repository.payment = {
    reference: "SG-1-concurrent",
    user_id: 1,
    plan: "professional",
    billing_cycle: "monthly",
    amount_cents: 10_000,
    currency: "EGP",
    status: "intention_created",
  };
  repository.getPayment = async () => ({ ...repository.payment });
  repository.updatePayment = async (_reference, patch) => {
    repository.payment = { ...repository.payment, ...patch };
  };
  repository.claimPaymentForFulfillment = async (_reference, patch) => {
    if (repository.payment.status === "paid") {
      return { status: "already_paid", payment: { ...repository.payment } };
    }
    if (repository.payment.status === "fulfilling") {
      return { status: "in_progress", payment: { ...repository.payment } };
    }
    repository.payment = {
      ...repository.payment,
      ...patch,
      status: "fulfilling",
      updated_at: patch.fulfillment_started_at,
    };
    return { status: "claimed", payment: { ...repository.payment } };
  };
  const transaction = {
    amount_cents: 10_000,
    created_at: "2026-07-03T00:00:00.000Z",
    currency: "EGP",
    error_occured: false,
    has_parent_transaction: false,
    id: 988,
    integration_id: 5344998,
    is_3d_secure: true,
    is_auth: false,
    is_capture: false,
    is_refunded: false,
    is_standalone_payment: true,
    is_voided: false,
    order: { id: 457, merchant_order_id: "SG-1-concurrent" },
    owner: 789,
    pending: false,
    source_data: { pan: "2346", sub_type: "MasterCard", type: "card" },
    success: true,
  };
  const webhookEnv = { ...env, PAYMOB_HMAC_SECRET: "test-hmac-secret" };
  const hmac = calculatePaymobTransactionHmac(
    transaction,
    webhookEnv.PAYMOB_HMAC_SECRET,
  );
  const app = createApp({ repository, env: webhookEnv });
  const request = () =>
    new Request(
      `https://example.test/api/mobile/billing/paymob/webhook/?hmac=${hmac}`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ type: "TRANSACTION", obj: transaction }),
      },
    );

  const [first, second] = await Promise.all([app(request()), app(request())]);

  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.equal(saveUserCalls, 1);
  assert.equal(repository.payment.status, "paid");
  assert.equal(repository.user.subscription.plan, "professional");
});

test("checkout provider network failure marks the payment as failed", async () => {
  const repository = fakeRepository();
  repository.payment = null;
  repository.createPayment = async (payment) => {
    repository.payment = { ...payment };
  };
  repository.updatePayment = async (_reference, patch) => {
    repository.payment = { ...repository.payment, ...patch };
  };
  const app = createApp({
    repository,
    env,
    paymobFetch: async () => {
      throw new Error("simulated Paymob outage");
    },
  });
  const login = await app(
    new Request("https://example.test/api/mobile/token/", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-device-id": "device-1234567890",
      },
      body: JSON.stringify({ username: "teacher", password: "password-123" }),
    }),
  );
  const { access } = await login.json();
  const response = await app(
    new Request("https://example.test/api/mobile/billing/intention/", {
      method: "POST",
      headers: {
        authorization: `Bearer ${access}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        plan: "professional",
        billing_cycle: "monthly",
      }),
    }),
  );

  assert.equal(response.status, 502);
  assert.equal(repository.payment.status, "intention_failed");
});

test("an invalid Paymob HMAC cannot change payment state", async () => {
  const repository = fakeRepository();
  repository.getPayment = async () => {
    throw new Error("must not read payment before HMAC verification");
  };
  const app = createApp({
    repository,
    env: { ...env, PAYMOB_HMAC_SECRET: "test-hmac-secret" },
  });
  const response = await app(
    new Request(
      "https://example.test/api/mobile/billing/paymob/webhook/?hmac=invalid",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ type: "TRANSACTION", obj: {} }),
      },
    ),
  );

  assert.equal(response.status, 401);
});
