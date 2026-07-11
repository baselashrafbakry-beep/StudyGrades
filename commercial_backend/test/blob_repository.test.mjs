import assert from "node:assert/strict";
import test from "node:test";

import { BlobRepository } from "../src/blob_repository.mjs";

class MemoryStore {
  constructor(seed = {}) {
    this.values = new Map(
      Object.entries(seed).map(([key, value]) => [key, structuredClone(value)]),
    );
    this.versions = new Map([...this.values.keys()].map((key) => [key, 1]));
  }

  async get(key) {
    const value = this.values.get(key);
    return value == null ? null : structuredClone(value);
  }

  async setJSON(key, value, options = {}) {
    return this.#write(key, value, options);
  }

  async set(key, value, options = {}) {
    return this.#write(key, JSON.parse(value), options);
  }

  #write(key, value, options) {
    const currentVersion = this.versions.get(key);
    if (options.onlyIfNew && currentVersion != null) {
      return { modified: false };
    }
    if (
      options.onlyIfMatch &&
      options.onlyIfMatch !== `etag-${currentVersion ?? 0}`
    ) {
      return { modified: false };
    }
    const nextVersion = (currentVersion ?? 0) + 1;
    this.values.set(key, structuredClone(value));
    this.versions.set(key, nextVersion);
    return { modified: true, etag: `etag-${nextVersion}` };
  }

  async getWithMetadata(key) {
    const value = this.values.get(key);
    if (value == null) return null;
    return {
      data: structuredClone(value),
      etag: `etag-${this.versions.get(key)}`,
      metadata: {},
    };
  }

  async delete(key) {
    this.values.delete(key);
    this.versions.delete(key);
  }
}

function catalog(className = "Class A") {
  return {
    hierarchy: [
      {
        id: 10,
        name: "Primary",
        classes: [{ id: 101, name: className, subject: "Arabic" }],
      },
    ],
    classrooms: [
      {
        class_id: 101,
        class_name: className,
        subject: "Arabic",
        grade_structure: [{ name: "oral", label: "Oral", max: 15 }],
        students: [
          { id: 1, student_number: "001", name: "Student One" },
          { id: 2, student_number: "002", name: "Student Two" },
        ],
      },
    ],
  };
}

test("catalog reads are scoped to the authenticated user", async () => {
  const repository = new BlobRepository(
    new MemoryStore({
      "catalog/1": catalog("Account One"),
      "catalog/2": catalog("Account Two"),
    }),
  );

  const first = await repository.getHierarchy(1);
  const second = await repository.getHierarchy(2);

  assert.equal(first[0].classes[0].name, "Account One");
  assert.equal(second[0].classes[0].name, "Account Two");
});

test("a default catalog is used only when the account has no catalog", async () => {
  const repository = new BlobRepository(
    new MemoryStore({ "catalog/default": catalog("Template Class") }),
  );

  assert.equal((await repository.getHierarchy(77))[0].classes[0].name, "Template Class");
});

test("saved grades are restored for the requested term and week without cross-account leakage", async () => {
  const repository = new BlobRepository(
    new MemoryStore({
      "catalog/1": catalog(),
      "catalog/2": catalog(),
    }),
  );
  const payload = {
    term_id: 2,
    week_number: 7,
    class_id: 101,
    subject: "Arabic",
    grades: [{ student_id: 1, grades: { oral: 12.5 } }],
  };

  await repository.saveGrades(1, payload, "a".repeat(64));
  const matching = await repository.getClassroom(1, 101, "Arabic", {
    termId: 2,
    weekNumber: 7,
  });
  const otherWeek = await repository.getClassroom(1, 101, "Arabic", {
    termId: 2,
    weekNumber: 8,
  });
  const otherUser = await repository.getClassroom(2, 101, "Arabic", {
    termId: 2,
    weekNumber: 7,
  });

  assert.deepEqual(matching.students[0].existing_grades, { oral: 12.5 });
  assert.deepEqual(otherWeek.students[0].existing_grades, {});
  assert.deepEqual(otherUser.students[0].existing_grades, {});
});

test("unknown classes and subjects are not substituted", async () => {
  const repository = new BlobRepository(
    new MemoryStore({ "catalog/1": catalog() }),
  );

  assert.equal(await repository.getClassroom(1, 999, "Arabic"), null);
  assert.equal(await repository.getClassroom(1, 101, "Math"), null);
});

test("concurrent repository instances do not lose user creations", async () => {
  const store = new MemoryStore({
    users: {
      users: [{ id: 1, username: "owner", email: "owner@example.com" }],
    },
  });
  const firstRepository = new BlobRepository(store);
  const secondRepository = new BlobRepository(store);

  const [first, second] = await Promise.all([
    firstRepository.createUser({
      username: "first.teacher",
      email: "first@example.com",
    }),
    secondRepository.createUser({
      username: "second.teacher",
      email: "second@example.com",
    }),
  ]);
  const users = await firstRepository.listUsers();

  assert.equal(users.length, 3);
  assert.deepEqual(
    users.map((user) => user.username).sort(),
    ["first.teacher", "owner", "second.teacher"],
  );
  assert.notEqual(first.id, second.id);
});
