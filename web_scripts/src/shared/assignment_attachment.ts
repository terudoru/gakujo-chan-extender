export function acceptsAttachment(input: HTMLInputElement, name: string, mime: string): boolean {
  const filters = input.accept.toLowerCase().split(',').map(value => value.trim()).filter(Boolean);
  const fileName = name.toLowerCase();
  const type = mime.toLowerCase();
  return !filters.length || filters.some(filter =>
    filter.startsWith('.') ? fileName.endsWith(filter)
      : filter.endsWith('/*') ? type.startsWith(filter.slice(0, -1))
        : type === filter);
}

export function setAssignmentAttachment(input: HTMLInputElement, file: File, replace?: File): boolean {
  return setAssignmentAttachments(input, [file], replace);
}

export function setAssignmentAttachments(input: HTMLInputElement, files: readonly File[], replace?: File): boolean {
  const view = input.ownerDocument.defaultView;
  if (!view || !input.isConnected || input.type !== 'file' || input.matches(':disabled') ||
      !files.length || (!input.multiple && files.length !== 1) ||
      !files.every(file => acceptsAttachment(input, file.name, file.type))) return false;
  const current = Array.from(input.files || []);
  if (replace && (files.length !== 1 || !current.includes(replace))) return false;
  const next = replace ? current.map(item => item === replace ? files[0] : item)
    : input.multiple ? [...current, ...files] : files;
  try {
    const transfer = new view.DataTransfer();
    next.forEach(item => transfer.items.add(item));
    if (transfer.files.length !== next.length) return false;
    input.files = transfer.files;
  } catch (_) { return false; }
  if (input.files?.length !== next.length) return false;
  input.dispatchEvent(new view.Event('input', {bubbles: true, composed: true}));
  input.dispatchEvent(new view.Event('change', {bubbles: true}));
  return true;
}
