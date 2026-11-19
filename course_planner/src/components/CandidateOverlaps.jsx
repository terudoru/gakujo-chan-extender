import React, { useMemo, useState } from "react";
import { ActionLink, slotTitle } from "../ui.jsx";
import {
  countCandidateOverlaps,
  formatOverlapTerms,
  overlapsForCourse,
} from "./candidate-overlaps.mjs";

export function CandidateOverlaps({ course, index, onOpenCourse }) {
  const [openCode, setOpenCode] = useState(null);
  const open = Boolean(course?.code) && openCode === course.code;

  const count = useMemo(
    () => countCandidateOverlaps(course, index),
    [course, index],
  );

  const matches = useMemo(
    () => (open && count > 0 ? overlapsForCourse(course, index) : []),
    [open, count, course, index],
  );

  if (count === 0) return null;

  return (
    <details
      className="candidate-overlaps"
      open={open}
      onToggle={(e) => setOpenCode(e.currentTarget.open ? course.code : null)}
    >
      <summary>他の候補と{count}件重複</summary>
      {open && (
        <ul className="rows">
          {matches.map(({ course: other, lists, terms, slots }) => {
            const when = [
              formatOverlapTerms(terms),
              slots.map(slotTitle).join("・"),
            ]
              .filter(Boolean)
              .join(" · ");
            const listLine = lists.length
              ? `${other.code} · ${lists.join("・")}`
              : other.code;
            return (
              <li key={other.code}>
                {typeof onOpenCourse === "function" ? (
                  <ActionLink onClick={() => onOpenCourse(other)}>
                    {other.title}
                  </ActionLink>
                ) : (
                  <strong>{other.title}</strong>
                )}
                <small className="conflict">{when}で重複</small>
                <small>{listLine}</small>
              </li>
            );
          })}
        </ul>
      )}
    </details>
  );
}
