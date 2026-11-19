import { normalize, syllabusURL } from "./study.mjs";
import { scanTables, readYear, readUnits } from "./imports/tables.mjs";
export { delimitedRows } from "./imports/tables.mjs";

const pass = /^(?:秀|優|良|可|合格|修得|認定|S|A\+?|B\+?|C\+?|P)$/i;
const failedFinal = /^(?:不可|不合格)$/;
const compatibleFailResult = /^(?:不可|不合格|否)$/;
const compatibleFinalStatus =
  /^(?:確定(?:済み?)?|成績確定|評価確定|評価済み?|不可|不合格|否)$/;
const noEvaluation =
  /^(?:欠席|棄権|放棄|(?:履修)?(?:辞退|取消|撤回|中止)|未受験|未評価|未確定|保留|履修中|評価待ち|申請中|受講中|不許可)$/;
const notEarned =
  /^(?:不可|不合格|未修得|履修中|未確定|保留|欠席|放棄|辞退|取消|履修取消|F|D)$/i;

function identity(row) {
  const parts = [
    row.year,
    row.code,
    row.title,
    row.section,
    row.term,
    row.courseId,
  ];
  if (row.offeringDepartment) parts.push(row.offeringDepartment);
  return JSON.stringify(parts.map(normalize));
}
function evidence(row) {
  return JSON.stringify(
    [
      row.credits,
      row.grade,
      row.alternativeTitle,
      row.allocationLabel,
      !!row.duplicate,
    ].map(normalize),
  );
}

function compatibleAttempt(a, b) {
  return [
    "year",
    "code",
    "term",
    "section",
    "courseId",
    "offeringDepartment",
  ].every(
    (key) => !a[key] || !b[key] || normalize(a[key]) === normalize(b[key]),
  );
}

function holdUncertainEvaluation(grade) {
  if (grade.finalEvaluation && grade.identityUncertain)
    Object.assign(grade, {
      matchedCourse: null,
      fields: [],
      category: "",
      department: "",
    });
}

function namesIndex(records) {
  const titles = new Map(),
    codes = new Map(),
    aliases = new Map();
  function add(record) {
    for (const [index, name] of [
      [titles, record.title],
      [codes, record.code],
      [aliases, record.alternativeTitle],
    ]) {
      if (!name) continue;
      const key = normalize(name);
      if (!index.has(key)) index.set(key, new Set());
      index.get(key).add(record);
    }
  }
  function hasAlternative(row) {
    const oldNames = titles.get(normalize(row.alternativeTitle)) ?? [];
    const newNames = aliases.get(normalize(row.title)) ?? [];
    return [...oldNames, ...newNames].some(
      (other) =>
        !failedFinal.test(other.grade) &&
        identity(other) !== identity(row) &&
        (normalize(other.title) === normalize(row.alternativeTitle) ||
          normalize(other.alternativeTitle) === normalize(row.title)),
    );
  }
  function conflictsWithFinal(row) {
    const peers = new Set([
      ...(titles.get(normalize(row.title)) ?? []),
      ...(codes.get(normalize(row.code)) ?? []),
    ]);
    const isFinal = failedFinal.test(row.grade);
    for (const peer of peers) {
      const disputed =
        isFinal &&
        (peer.duplicate === true ||
          peer.finalEvaluation === false ||
          peer.evaluated === false ||
          peer.passed === true ||
          peer.earned === true ||
          (peer.status && !compatibleFinalStatus.test(peer.status)) ||
          (peer.result && !compatibleFailResult.test(peer.result)));
      if (failedFinal.test(peer.grade) === isFinal && !disputed) continue;
      if (compatibleAttempt(row, peer)) return true;
    }
    return false;
  }
  records.forEach(add);
  return { titles, add, hasAlternative, conflictsWithFinal };
}
export function reviewGrades(
  packet,
  {
    byCode = new Map(),
    catalogYear = 2026,
    grades = [],
    deferMatch = false,
  } = {},
) {
  const rows = [];
  const nonEarned = new Set();
  const outcomes = namesIndex(grades);
  const issue = (id, reason) => rows.push({ id, label: "要確認", reason });
  scanTables(
    packet,
    (v, origin) => {
      const year = v.year ? readYear(v.year) : origin.year;
      const code = v.code?.toUpperCase() || "";
      const lookup = year && byCode.get(code);
      const offering =
        lookup && String(lookup.year ?? catalogYear) === year ? lookup : null;
      const title = v.title || offering?.title;
      const label =
        [code, title].filter(Boolean).join(" ") || "科目を特定できない行";
      const evaluation = v.grade || v.result;
      const final = failedFinal.test(evaluation);
      const attempt = { ...v, year, code, title, grade: evaluation };
      const conflictingResult =
        v.grade &&
        v.result &&
        !(final
          ? compatibleFailResult.test(v.result)
          : v.result === v.grade ||
            (pass.test(v.grade) && /^(合|合格)$/.test(v.result)));
      const conflictingStatus = [v.status, v.assessmentStatus].some(
        (status) =>
          status &&
          (final
            ? !compatibleFinalStatus.test(status)
            : noEvaluation.test(status) || compatibleFailResult.test(status)),
      );
      outcomes.add(attempt);
      if (notEarned.test(evaluation) || conflictingResult || conflictingStatus)
        nonEarned.add(identity(attempt));
      const creditCell = v.credits ?? v.earnedCredits;
      const starred = [v.credits, v.earnedCredits].some((s) =>
        /^\s*\*/.test(s),
      );
      const earned = readUnits(v.earnedCredits?.replace(/^\s*\*\s*/, ""), 99);
      const sameCourse =
        offering &&
        normalize(offering.title) === normalize(title) &&
        (!v.section || normalize(offering.section) === normalize(v.section)) &&
        (!v.courseId || normalize(offering.courseId) === normalize(v.courseId));
      // A zero in 修得単位 is not the course's allocated credit value.
      const lookupCredits =
        final &&
        v.credits == null &&
        earned === 0 &&
        sameCourse &&
        (!v.offeringDepartment ||
          normalize(v.offeringDepartment) === normalize(offering.department)) &&
        (!v.term ||
          [offering.term, offering.period, offering.semester].some(
            (term) => normalize(term) === normalize(v.term),
          ));
      const credits =
        final && v.credits == null
          ? lookupCredits
            ? readUnits(offering.credits, 99)
            : null
          : readUnits(creditCell?.replace(/^\s*\*\s*/, ""), 99);
      const invalidFinal =
        final &&
        (starred ||
          (v.duplicate && !["なし", "-", "無"].includes(v.duplicate)) ||
          (v.earnedCredits && earned !== 0) ||
          credits == null);
      if (
        conflictingResult ||
        conflictingStatus ||
        invalidFinal ||
        (!final && notEarned.test(evaluation))
      ) {
        if (invalidFinal || conflictingResult || conflictingStatus)
          outcomes.add({ ...attempt, grade: "" });
        rows.push({
          id: origin.id,
          label,
          skipped: true,
          reason:
            invalidFinal || conflictingResult || conflictingStatus
              ? "要確認：評価・履修状況・配当単位を原票で確認してください。"
              : evaluation + "（修得単位に含みません）",
        });
        return;
      }
      if (
        (!pass.test(evaluation) && !final) ||
        (!final &&
          v.credits != null &&
          v.earnedCredits != null &&
          earned !== credits) ||
        (final ? credits == null : !credits) ||
        !title ||
        (code && !/^[A-Z0-9][-A-Z0-9]{2,19}$/.test(code)) ||
        (v.year && !year)
      ) {
        rows.push({
          id: origin.id,
          label,
          reason: "科目・単位数・評価・履修年度の列を確認してください。",
        });
        return;
      }
      const recognized = evaluation === "認定";
      const duplicate =
        v.duplicate === "重複" ||
        v.duplicate === "重複単位" ||
        (starred && normalize(origin.heading) === "成績確認表");
      const starUnclear =
        (starred && !duplicate) ||
        (v.duplicate &&
          !["重複", "重複単位", "なし", "-", "無"].includes(v.duplicate));
      const sameOffering =
        sameCourse &&
        (offering.credits == null || offering.credits === credits);
      const match =
        sameOffering &&
        !deferMatch &&
        (!v.offeringDepartment ||
          normalize(v.offeringDepartment) === normalize(offering.department));
      const grade = {
        year,
        code,
        title,
        credits,
        grade: evaluation,
        section: v.section || "",
        term: v.term || "",
        courseId: v.courseId || "",
        ...(v.offeringDepartment
          ? { offeringDepartment: v.offeringDepartment }
          : {}),
        alternativeTitle: v.alternativeTitle || "",
        recognized,
        allocationLabel: v.category || "",
        duplicate,
        counts: !final && !duplicate && !starUnclear,
        ...(final ? { finalEvaluation: true } : {}),
        source: ["単位修得状況照会", "成績確認表", "本人入力"].includes(
          normalize(origin.heading),
        )
          ? normalize(origin.heading)
          : "成績表",
        fields: match ? [...(offering.fields ?? [])] : [],
        category: match ? offering.category || "" : "",
        department: match ? offering.department || "" : "",
      };
      if (match) {
        grade.matchedCourse = {
          year,
          code,
          title: offering.title,
          department: grade.department,
          fields: [...grade.fields],
          category: grade.category,
          sourceUrl: offering.sourceUrl || syllabusURL(offering, year),
          confirmed: true,
        };
      }
      const notes = [];
      if (duplicate) notes.push("重複単位のため算入しません。");
      if (starUnclear)
        notes.push("要確認：重複記号の意味を確認できないため算入しません。");
      if (!match)
        notes.push("要確認：履修年度のシラバスとの対応が未確認です。");
      if (recognized && !grade.allocationLabel)
        notes.push(
          "要確認：認定単位の算入先は所属学部の認定結果で確認してください。",
        );
      if (grade.alternativeTitle)
        notes.push(
          "読替科目「" +
            grade.alternativeTitle +
            "」との重複を確認してください。",
        );
      rows.push({
        id: origin.id,
        label,
        value: grade,
        ...(final ? { skipped: true } : {}),
        ...(offering && !sameOffering ? { offeringConflict: true } : {}),
        reason: notes.join(" "),
      });
    },
    issue,
  );

  // Weak name-only entries can represent several sections. Keep the evidence
  // and each occurrence, without silently counting or overwriting either one.
  const groups = new Map();
  for (const row of rows) {
    if (!row.value) continue;
    const key = identity(row.value);
    if (
      (!row.value.finalEvaluation && nonEarned.has(key)) ||
      outcomes.conflictsWithFinal(row.value)
    ) {
      delete row.value;
      row.reason =
        "要確認：同じ履修情報で修得と未修得、または評価・履修状況が一致しません。";
      continue;
    }
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(row);
  }
  for (const [key, group] of groups) {
    const seen = new Map();
    const first = group[0].value;
    const repeated =
      (first.code || first.courseId) &&
      group.every((r) => evidence(r.value) === evidence(first));
    for (const row of group) {
      const g = row.value;
      if (group.length > 1 && repeated) {
        g.importId = key;
      } else if (group.length > 1 || (!g.code && !g.courseId)) {
        const variant = evidence(g),
          occurrence = seen.get(variant) ?? 0;
        seen.set(variant, occurrence + 1);
        g.importId = JSON.stringify([key, variant, occurrence]);
        if (group.length > 1) {
          g.identityUncertain = true;
          g.counts = false;
          row.reason +=
            " 要確認：同じ履修情報が複数あります。科目を識別できるまで算入しません。";
        }
      } else g.importId = key;
    }
  }
  const names = namesIndex([
    ...grades,
    ...rows.flatMap((r) => (r.value ? [r.value] : [])),
  ]);
  for (const row of rows) {
    const g = row.value;
    if (g && !g.finalEvaluation && !g.duplicate && names.hasAlternative(g)) {
      g.possibleDuplicate = true;
      g.counts = false;
      row.reason +=
        " 要確認：読替名の科目も履歴にあります。同じ単位か照合してください。";
    }
    if (g?.finalEvaluation) {
      holdUncertainEvaluation(g);
      row.finalEvaluationCandidate = g;
      delete row.value;
    }
  }
  return rows;
}

// Compatibility for the original transcript dialog.
export function reviewGradeRows(rows, byCode) {
  const parsed = reviewGrades(
    { v: 1, kind: "grades", tables: [{ heading: "成績確認表", rows }] },
    { byCode },
  );
  return {
    candidates: parsed.flatMap((r) => (r.value ? [r.value] : [])),
    missing: parsed.filter((r) => !r.value && !r.skipped),
  };
}

export function mergeGrades(state, rows, reconcileMatch) {
  const grades = state.grades.map((g) => ({ ...g }));
  const names = namesIndex(grades);
  for (const incoming of rows) {
    const row = { ...incoming };
    if (names.conflictsWithFinal(row))
      throw Error(
        "保存済みの評価と一致しません。原票と履修履歴を確認してください。",
      );
    const key = identity(row);
    const sameTitle = [...(names.titles.get(normalize(row.title)) ?? [])];
    const related = sameTitle.filter((g) => identity(g) === key);
    let old = related.find((g) => g.importId && g.importId === row.importId);
    if (!old && (row.code || row.courseId)) {
      const identical = related.filter((g) => evidence(g) === evidence(row));
      if (identical.length === 1) old = identical[0];
    }
    // A PDF and a native table can disagree on which identifying columns are
    // printed. Merge only if they share an offering and no evidence conflicts.
    if (!old && !related.length) {
      const possible = sameTitle.filter((g) => compatibleAttempt(row, g));
      const previous = possible.length === 1 ? possible[0] : null;
      const confirmed = previous?.matchedCourse;
      const sameOffering =
        previous &&
        row.year &&
        row.code &&
        ((row.year === previous.year && row.code === previous.code) ||
          (confirmed?.confirmed &&
            row.year === String(confirmed.year) &&
            row.code === confirmed.code));
      if (
        sameOffering &&
        row.credits === previous.credits &&
        row.grade === previous.grade &&
        !previous.identityUncertain &&
        !row.identityUncertain
      ) {
        old = previous;
        for (const k of ["section", "term", "courseId", "offeringDepartment"])
          row[k] ||= old[k] || "";
        row.importId = identity(row);
      } else if (possible.length) {
        row.identityUncertain = true;
        row.counts = false;
      }
    }
    if (!old) {
      const legacy = related.filter(
        (g) =>
          !g.importId &&
          (g.code || g.courseId || evidence(g) === evidence(row)),
      );
      if (legacy.length === 1 && !row.identityUncertain) old = legacy[0];
    }
    if (
      !old &&
      related.length === 1 &&
      (row.code || row.courseId) &&
      row.importId === key &&
      !related[0].identityUncertain
    )
      old = related[0];
    if (
      !old &&
      !row.importId &&
      related.length === 1 &&
      (row.code || evidence(row) === evidence(related[0]))
    )
      old = related[0];
    if (!old) {
      if (related.length) {
        row.identityUncertain = true;
        row.counts = false;
      }
      if (
        !row.finalEvaluation &&
        !row.duplicateReviewed &&
        names.hasAlternative(row)
      ) {
        row.possibleDuplicate = true;
        row.counts = false;
      }
      holdUncertainEvaluation(row);
      grades.push(row);
      names.add(row);
      continue;
    }
    // An authoritative negative can revoke only the exact association checked.
    // All other reimports retain reviewed category and duplicate decisions.
    const decision = reconcileMatch?.(old, row);
    const confirmed =
      decision !== undefined
        ? decision
        : old.matchedCourse?.confirmed
          ? old.matchedCourse
          : row.matchedCourse;
    const reviewed =
      old.duplicate || old.duplicateReviewed || old.identityUncertain
        ? { counts: old.counts, duplicate: old.duplicate }
        : {};
    const allocation =
      old.allocationKey &&
      (!row.allocationLabel ||
        normalize(old.allocationLabel) === normalize(row.allocationLabel))
        ? {
            allocationKey: old.allocationKey,
            allocationScope: old.allocationScope,
            allocationLabel: old.allocationLabel,
          }
        : {};
    if (
      row.allocationLabel &&
      normalize(old.allocationLabel) !== normalize(row.allocationLabel)
    ) {
      delete old.allocationKey;
      delete old.allocationScope;
    }
    Object.assign(
      old,
      row,
      {
        importId: old.importId || row.importId,
        title: old.title || row.title,
        code: old.code || row.code,
        year: old.year || row.year,
      },
      reviewed,
      allocation,
    );
    names.add(old);
    if (confirmed || decision === null)
      Object.assign(old, {
        matchedCourse: confirmed,
        fields: confirmed?.fields ?? [],
        category: confirmed?.category || "",
        department: confirmed?.department || "",
      });
    if (row.duplicate) old.duplicate = true;
    if (old.duplicate || old.identityUncertain || old.finalEvaluation)
      old.counts = false;
  }
  state.grades = grades;
}
