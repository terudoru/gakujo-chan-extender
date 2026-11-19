import { headerColumns } from "./tables.mjs";
import { normalize } from "../study.mjs";

function textLines(items) {
  const tokens = items
    .filter((item) => item.str?.trim())
    .map((item) => ({
      // Some Japanese PDF fonts map ordinary kanji to equivalent radical
      // glyphs (e.g. 科⽬). Recover those without folding titles like 英語Ⅰ.
      text: item.str
        .trim()
        .replace(/[\u2f00-\u2fd5]/gu, (glyph) => glyph.normalize("NFKC")),
      x: item.transform[4],
      y: item.transform[5],
      end: item.transform[4] + item.width,
      height: Math.abs(item.height) || 10,
    }))
    .sort((a, b) => b.y - a.y || a.x - b.x);
  const lines = [];
  for (const token of tokens) {
    let line = lines.at(-1);
    if (
      !line ||
      Math.abs(line.y - token.y) > Math.min(2, token.height * 0.28)
    ) {
      line = { y: token.y, cells: [] };
      lines.push(line);
    }
    line.cells.push(token);
  }
  for (const line of lines) {
    const cells = [];
    for (const cell of line.cells.sort((a, b) => a.x - b.x)) {
      const prev = cells.at(-1),
        gap = prev ? cell.x - prev.end : Infinity;
      if (
        prev &&
        gap >= -cell.height * 0.4 &&
        gap <= Math.max(1, cell.height * 0.3)
      ) {
        prev.text += cell.text;
        prev.end = Math.max(prev.end, cell.end);
      } else cells.push({ ...cell });
    }
    line.cells = cells;
  }
  return lines;
}
const center = (c) => (c.x + c.end) / 2;

// Official right-hand table: two pairs of subcolumns. The other half of
// the same physical page may contain an unrelated course table.
function officialBalanceColumns(lines, index) {
  const sub = lines[index].cells.filter((c) =>
    ["昼間", "夜間"].includes(normalize(c.text)),
  );
  if (sub.map((c) => normalize(c.text)).join("/") !== "昼間/夜間/昼間/夜間")
    return null;
  const top = lines
    .slice(Math.max(0, index - 3), index + 1)
    .filter((l) => l.y - lines[index].y < sub[0].height * 3)
    .flatMap((l) => l.cells);
  const anchors = sub.map(center);
  const nearGroup = (name, a, b) =>
    top.some(
      (c) =>
        name.test(normalize(c.text)) &&
        center(c) > anchors[a] - sub[a].height &&
        center(c) < anchors[b] + sub[b].height,
    );
  if (
    !nearGroup(/^履修単位(?:数)?$/, 0, 1) ||
    !nearGroup(/^既修得単位(?:数)?$/, 2, 3)
  )
    return null;
  const label = top
    .filter(
      (c) =>
        ["区分", "科目区分"].includes(normalize(c.text)) &&
        center(c) < anchors[0],
    )
    .sort((a, b) => b.x - a.x)[0];
  if (!label) return null;
  const step = (anchors[3] - anchors[0]) / 3;
  const leftEdge = anchors[0] - step / 2;
  return {
    anchors,
    step,
    labelRight: leftEdge,
    labelLeft: center(label) * 2 - leftEdge - label.height,
  };
}

function balanceCells(cells, grid) {
  const units = grid.anchors.map((anchor) =>
    cells.filter((c) => Math.abs(center(c) - anchor) < grid.step * 0.48),
  );
  const label = cells.filter(
    (c) => c.x >= grid.labelLeft && center(c) < grid.labelRight,
  );
  if (!label.length) return null;
  return [
    label.map((c) => c.text).join(""),
    ...units.map((c) => (c.length === 1 ? c[0].text : "")),
  ];
}

export function pdfPageRows(items, kind) {
  const lines = textLines(items),
    rows = [];
  let header = null,
    grid = null;
  for (const [index, { cells }] of lines.entries()) {
    const raw = cells.map((c) => c.text);
    if (kind === "balances") {
      const found = officialBalanceColumns(lines, index);
      if (found) {
        grid = found;
        rows.push([
          "区分",
          "履修単位(昼間)",
          "履修単位(夜間)",
          "既修得単位(昼間)",
          "既修得単位(夜間)",
        ]);
        continue;
      }
    }
    if (headerColumns(kind, raw)) {
      grid = null;
      header = cells;
      rows.push(raw);
      continue;
    }
    if (grid) {
      const aligned = balanceCells(cells, grid);
      // Never feed unrelated columns to the regular parser under this header.
      rows.push(aligned || [""]);
      continue;
    }
    // PDF text extraction does not emit empty cells. Restore them only
    // when the remaining runs sit under their own header anchors.
    if (header && raw.length > 1 && raw.length < header.length) {
      const aligned = Array(header.length).fill("");
      let previous = -1;
      const ok = cells.every((c) => {
        const candidates = header
          .map((h, i) => ({
            i,
            d: Math.min(
              Math.abs(h.x - c.x),
              Math.abs(h.end - c.end),
              Math.abs(center(h) - center(c)),
            ),
          }))
          .filter(({ d }) => d <= c.height)
          .sort((a, b) => a.d - b.d);
        const best = candidates[0];
        if (
          !best ||
          best.i <= previous ||
          (candidates[1] && candidates[1].d - best.d < 1)
        )
          return false;
        aligned[best.i] = c.text;
        previous = best.i;
        return true;
      });
      rows.push(ok ? aligned : raw);
    } else rows.push(raw);
  }
  return rows;
}
