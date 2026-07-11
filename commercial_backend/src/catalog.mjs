function positiveInteger(value, label) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`Invalid ${label}.`);
  }
  return parsed;
}

function requiredText(value, label, maxLength) {
  const text = String(value ?? "").trim();
  if (!text || text.length > maxLength) {
    throw new Error(`Invalid ${label}.`);
  }
  return text;
}

export function normalizeCatalog(input) {
  const rawClassrooms = input?.classrooms;
  if (!Array.isArray(rawClassrooms) || rawClassrooms.length < 1) {
    throw new Error("Catalog classrooms are required.");
  }
  if (rawClassrooms.length > 500) {
    throw new Error("Catalog has too many classroom subjects.");
  }

  const stages = new Map();
  const classMetadata = new Map();
  const classroomSubjects = new Set();
  const uniqueStudents = new Set();
  const classrooms = [];

  for (const raw of rawClassrooms) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      throw new Error("Invalid classroom entry.");
    }
    const stageId = positiveInteger(raw.stage_id, "stage id");
    const stageName = requiredText(raw.stage_name, "stage name", 120);
    const classId = positiveInteger(raw.class_id, "class id");
    const className = requiredText(raw.class_name, "class name", 120);
    const subject = requiredText(raw.subject, "subject", 100);
    const stageKey = String(stageId);
    const classKey = String(classId);
    const subjectKey = `${classKey}:${subject.toLocaleLowerCase("en")}`;

    const previousStageName = stages.get(stageKey)?.name;
    if (previousStageName && previousStageName !== stageName) {
      throw new Error("Conflicting stage metadata.");
    }
    const previousClass = classMetadata.get(classKey);
    if (
      previousClass &&
      (previousClass.name !== className || previousClass.stageId !== stageId)
    ) {
      throw new Error("Conflicting class metadata.");
    }
    if (classroomSubjects.has(subjectKey)) {
      throw new Error("Duplicate classroom subject.");
    }
    classroomSubjects.add(subjectKey);
    classMetadata.set(classKey, { id: classId, name: className, stageId });
    const stage = stages.get(stageKey) ?? {
      id: stageId,
      name: stageName,
      classes: new Map(),
    };
    stage.classes.set(classKey, { id: classId, name: className });
    stages.set(stageKey, stage);

    if (
      !Array.isArray(raw.grade_structure) ||
      raw.grade_structure.length < 1 ||
      raw.grade_structure.length > 50
    ) {
      throw new Error("Each classroom subject requires grade fields.");
    }
    const fieldNames = new Set();
    const gradeStructure = raw.grade_structure.map((field) => {
      const name = requiredText(field?.name, "grade field name", 64);
      if (!/^[A-Za-z0-9_.-]+$/.test(name)) {
        throw new Error("Invalid grade field name.");
      }
      const normalizedName = name.toLowerCase();
      if (fieldNames.has(normalizedName)) {
        throw new Error("Duplicate grade field.");
      }
      fieldNames.add(normalizedName);
      const max = Number(field?.max);
      if (!Number.isFinite(max) || max <= 0 || max > 1000) {
        throw new Error("Invalid grade field maximum.");
      }
      return {
        name,
        label: requiredText(field?.label ?? name, "grade field label", 120),
        max,
      };
    });

    if (
      !Array.isArray(raw.students) ||
      raw.students.length < 1 ||
      raw.students.length > 5000
    ) {
      throw new Error("Each classroom subject requires students.");
    }
    const studentIds = new Set();
    const students = raw.students.map((student) => {
      const id = positiveInteger(student?.id, "student id");
      const idKey = String(id);
      if (studentIds.has(idKey)) throw new Error("Duplicate student id.");
      studentIds.add(idKey);
      uniqueStudents.add(`${classKey}:${idKey}`);
      return {
        id,
        student_number: requiredText(
          student?.student_number ?? student?.number,
          "student number",
          64,
        ),
        name: requiredText(student?.name ?? student?.full_name, "student name", 200),
      };
    });
    students.sort((a, b) => a.id - b.id);
    classrooms.push({
      class_id: classId,
      class_name: className,
      subject,
      grade_structure: gradeStructure,
      students,
    });
  }

  const hierarchy = [...stages.values()]
    .sort((a, b) => a.id - b.id)
    .map((stage) => ({
      id: stage.id,
      name: stage.name,
      classes: [...stage.classes.values()].sort((a, b) => a.id - b.id),
    }));
  classrooms.sort(
    (a, b) =>
      a.class_id - b.class_id || a.subject.localeCompare(b.subject, "en"),
  );
  return {
    catalog: { version: 1, hierarchy, classrooms },
    summary: {
      stages: hierarchy.length,
      classes: classMetadata.size,
      classroom_subjects: classrooms.length,
      students: uniqueStudents.size,
    },
  };
}
