import React from "react";
import { Button } from "@astryxdesign/core/Button";
import { Selector } from "@astryxdesign/core/Selector";
import {
  SegmentedControl,
  SegmentedControlItem,
} from "@astryxdesign/core/SegmentedControl";
import { Dialog, DialogHeader } from "@astryxdesign/core/Dialog";
import { ArrowUpRight, Check, Plus } from "lucide-react";
import { syllabusURL } from "./study.mjs";

export { Button };
export const PlannerError = React.createContext("");
export function Segments({ label, value, change, options }) {
  return (
    <SegmentedControl
      size="sm"
      label={label}
      value={String(value)}
      onChange={change}
    >
      {options.map(([id, name]) => (
        <SegmentedControlItem key={id} value={String(id)} label={name} />
      ))}
    </SegmentedControl>
  );
}
export function Select({ label, value, change, options, hide = false }) {
  return (
    <Selector
      label={label}
      isLabelHidden={hide}
      value={value || undefined}
      placeholder={label}
      options={options.map((o) =>
        Array.isArray(o) ? { value: o[0], label: o[1] } : o,
      )}
      onChange={change}
      presentation="adaptive"
    />
  );
}
export function Modal({ title, close, children }) {
  return (
    <Dialog
      isOpen
      onOpenChange={(open) => {
        if (!open) close();
      }}
      width={500}
      aria-label={title}
    >
      <DialogHeader
        title={title}
        onOpenChange={(open) => {
          if (!open) close();
        }}
      />
      <div className="dialog-inner">
        {children}
        <PlannerError.Consumer>
          {(error) =>
            error ? (
              <p role="alert" className="error">
                {error}
              </p>
            ) : null
          }
        </PlannerError.Consumer>
      </div>
    </Dialog>
  );
}
export function External({ href, children }) {
  return (
    <a
      className="external"
      href={href}
      target="_blank"
      rel="noopener noreferrer"
    >
      {children}
      <ArrowUpRight size={14} aria-hidden="true" />
    </a>
  );
}
export const slotTitle = (slot) =>
  slot === "他" ? "集中・時限未定" : slot[0] + "曜" + slot.slice(1) + "限";
export function CourseLine({ course, fields, details = false }) {
  return (
    <div className="course-line">
      <strong>{course.title}</strong>
      <span>
        {[course.period, course.schedule, (course.credits ?? "要確認") + "単位"]
          .filter(Boolean)
          .join(" · ")}
      </span>
      {details && (
        <>
          <span>
            {[course.code, course.teacher].filter(Boolean).join(" · ")}
          </span>
          <span>
            分野　
            {course.fields.map((n) => n + " " + (fields[n] ?? "")).join("、") ||
              "要確認"}
          </span>
          <External href={syllabusURL(course)}>公式シラバス</External>
        </>
      )}
    </div>
  );
}
export function ListPicker({ lists, id, setId }) {
  return (
    <Select
      label="追加先リスト"
      value={id}
      change={setId}
      options={lists.map((l) => [l.id, l.name])}
    />
  );
}
export function AddCourse({ course, list, mutate, onAdded }) {
  const saved = list?.codes.includes(course.code);
  return (
    <Button
      size="sm"
      variant={saved ? "ghost" : "secondary"}
      icon={saved ? <Check size={15} /> : <Plus size={15} />}
      label={saved ? "追加済み" : "リストに追加"}
      isDisabled={saved || !list}
      onClick={async () => {
        if (
          await mutate((s) => {
            const target = s.lists.find((l) => l.id === list.id);
            if (!target) throw Error("追加先リストを選び直してください。");
            if (!target.codes.includes(course.code))
              target.codes.push(course.code);
          })
        )
          onAdded?.();
      }}
    />
  );
}
export function ActionLink({ children, onClick }) {
  return (
    <button type="button" className="action-link" onClick={onClick}>
      {children}
    </button>
  );
}
