import { acceptsAttachment, setAssignmentAttachments } from '../shared/assignment_attachment.js';

export function isFileDrag(event: DragEvent) {
  return Array.from(event.dataTransfer?.types || []).includes('Files');
}

export function createAttachmentDropZone(input: HTMLInputElement) {
  const doc = input.ownerDocument;
  const zone = doc.createElement('span');
  const info = doc.createElement('span');
  const caption = doc.createElement('span');
  caption.textContent = 'ファイルをここにドロップ';
  info.setAttribute('aria-live', 'polite');
  info.style.cssText = 'display:block';
  zone.setAttribute('data-mbg-attachment-drop', '');
  zone.style.cssText = 'box-sizing:border-box;display:block;width:fit-content;max-width:100%;' +
    'margin:6px 0;padding:8px 12px;border:1px dashed currentColor;border-radius:4px';
  zone.append(caption, info);

  function highlight(active: boolean) {
    zone.style.backgroundColor = active ? 'rgba(41,110,234,.16)' : '';
  }

  zone.addEventListener('dragover', event => {
    if (!isFileDrag(event)) return;
    event.preventDefault();
    event.stopPropagation();
    const allowed = !input.matches(':disabled') && input.isConnected;
    event.dataTransfer!.dropEffect = allowed ? 'copy' : 'none';
    highlight(allowed);
  });
  zone.addEventListener('dragleave', event => {
    if (event.relatedTarget instanceof Node && zone.contains(event.relatedTarget)) return;
    highlight(false);
  });
  zone.addEventListener('drop', event => {
    if (!isFileDrag(event)) return;
    event.preventDefault();
    event.stopPropagation();
    highlight(false);
    const transfer = event.dataTransfer!;
    const files = Array.from(transfer.files);
    if (!files.length || Array.from(transfer.items || []).some(item =>
      item.webkitGetAsEntry?.()?.isDirectory)) {
      info.textContent = 'ファイルを選んでください。';
    } else if (!input.multiple && files.length > 1) {
      info.textContent = 'この欄にはファイルを1つだけ添付できます。';
    } else if (files.some(file => !acceptsAttachment(input, file.name, file.type))) {
      info.textContent = 'この欄で使えるファイル形式を選んでください。';
    } else if (setAssignmentAttachments(input, files)) {
      info.textContent = files.length === 1 ? 'ファイルを選択しました。' : files.length + '件のファイルを選択しました。';
    } else {
      info.textContent = '添付できませんでした。ファイル選択からやり直してください。';
    }
  });
  return zone;
}
