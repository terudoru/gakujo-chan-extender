export type Viewport = {
  width: number;
  height: number;
  convertToPdfPoint(x: number, y: number): number[];
};
export type Point = { x: number; y: number };
type PenEdit = { kind: 'pen'; points: Point[] };
type TextEdit = {
  kind: 'text';
  origin: Point;
  width: number;
  height: number;
  canvas: HTMLCanvasElement;
};
export type Edit = PenEdit | TextEdit;
export type EditedPage = { viewport: Viewport; edits: Edit[] };
type PdfOutputPage = {
  drawLine(options: { start: Point; end: Point; thickness: number; color: unknown; lineCap: number }): void;
  drawCircle(options: { x: number; y: number; size: number; color: unknown }): void;
  drawImage(image: unknown, options: { x: number; y: number; width: number; height: number; rotate: unknown }): void;
};
export type WorksheetPdfLibrary = {
  PDFDocument: {
    load(bytes: ArrayBuffer, options: { updateMetadata: boolean }): Promise<{
      getPage(index: number): PdfOutputPage;
      embedPng(data: string): Promise<unknown>;
      save(): Promise<Uint8Array<ArrayBuffer>>;
    }>;
  };
  rgb(red: number, green: number, blue: number): unknown;
  degrees(value: number): unknown;
};
export const penThickness = 1.6;

function pdfPoint(viewport: Viewport, point: Point): Point {
  const [x, y] = viewport.convertToPdfPoint(point.x * viewport.width, point.y * viewport.height);
  return {x, y};
}

export function worksheetTextPlacement(viewport: Viewport, origin: Point, width: number, height: number) {
  const left = pdfPoint(viewport, {x: origin.x, y: origin.y + height});
  const right = pdfPoint(viewport, {x: origin.x + width, y: origin.y + height});
  const top = pdfPoint(viewport, origin);
  return {
    ...left,
    width: Math.hypot(right.x - left.x, right.y - left.y),
    height: Math.hypot(top.x - left.x, top.y - left.y),
    degrees: Math.atan2(right.y - left.y, right.x - left.x) * 180 / Math.PI,
  };
}

export async function writeWorksheetPdf(
  library: WorksheetPdfLibrary,
  source: ArrayBuffer,
  editsByPage: ReadonlyMap<number, EditedPage>,
): Promise<Uint8Array<ArrayBuffer>> {
  const output = await library.PDFDocument.load(source, {updateMetadata: false});
  const color = library.rgb(23 / 255, 61 / 255, 145 / 255);
  for (const [pageNumber, edited] of editsByPage) {
    const page = output.getPage(pageNumber - 1);
    for (const edit of edited.edits) {
      if (edit.kind === 'text') {
        const image = await output.embedPng(edit.canvas.toDataURL('image/png'));
        const placement = worksheetTextPlacement(edited.viewport, edit.origin, edit.width, edit.height);
        page.drawImage(image, {
          x: placement.x,
          y: placement.y,
          width: placement.width,
          height: placement.height,
          rotate: library.degrees(placement.degrees),
        });
      } else {
        const points = edit.points.map(point => pdfPoint(edited.viewport, point));
        if (points.length === 1) page.drawCircle({...points[0], size: penThickness / 2, color});
        for (let index = 1; index < points.length; index++) {
          page.drawLine({start: points[index - 1], end: points[index], thickness: penThickness, color, lineCap: 1});
        }
      }
    }
  }
  return output.save();
}
