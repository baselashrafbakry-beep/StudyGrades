import assert from "node:assert/strict";
import test from "node:test";

import { normalizeCatalog } from "../src/catalog.mjs";

function validInput() {
  return {
    classrooms: [
      {
        stage_id: 1,
        stage_name: "Primary",
        class_id: 101,
        class_name: "Class A",
        subject: "Arabic",
        grade_structure: [
          { name: "oral", label: "Oral", max: 15 },
          { name: "written", label: "Written", max: 25 },
        ],
        students: [
          { id: 1, student_number: "001", name: "Student One" },
          { id: 2, student_number: "002", name: "Student Two" },
        ],
      },
      {
        stage_id: 1,
        stage_name: "Primary",
        class_id: 101,
        class_name: "Class A",
        subject: "Math",
        grade_structure: [{ name: "quiz", label: "Quiz", max: 20 }],
        students: [
          { id: 1, student_number: "001", name: "Student One" },
          { id: 2, student_number: "002", name: "Student Two" },
        ],
      },
    ],
  };
}

test("catalog normalization builds a deterministic hierarchy and summary", () => {
  const result = normalizeCatalog(validInput());

  assert.deepEqual(result.catalog.hierarchy, [
    {
      id: 1,
      name: "Primary",
      classes: [{ id: 101, name: "Class A" }],
    },
  ]);
  assert.equal(result.catalog.classrooms.length, 2);
  assert.deepEqual(result.summary, {
    stages: 1,
    classes: 1,
    classroom_subjects: 2,
    students: 2,
  });
});

test("catalog normalization rejects duplicate students and grade fields", () => {
  const duplicateStudent = validInput();
  duplicateStudent.classrooms[0].students.push({
    id: 1,
    student_number: "003",
    name: "Duplicate",
  });
  assert.throws(() => normalizeCatalog(duplicateStudent), /student id/i);

  const duplicateField = validInput();
  duplicateField.classrooms[0].grade_structure.push({
    name: "oral",
    label: "Duplicate",
    max: 10,
  });
  assert.throws(() => normalizeCatalog(duplicateField), /grade field/i);
});

test("catalog normalization rejects conflicting class metadata and unsafe values", () => {
  const conflict = validInput();
  conflict.classrooms[1].class_name = "Different Name";
  assert.throws(() => normalizeCatalog(conflict), /class metadata/i);

  const unsafeField = validInput();
  unsafeField.classrooms[0].grade_structure[0].name = "oral score";
  assert.throws(() => normalizeCatalog(unsafeField), /grade field name/i);

  const emptyStudents = validInput();
  emptyStudents.classrooms[0].students = [];
  assert.throws(() => normalizeCatalog(emptyStudents), /students/i);
});
