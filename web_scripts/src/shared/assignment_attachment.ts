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
  const view = input.ownerDocument.defaultView;
  if (!view || !input.isConnected || input.type !== 'file' || input.matches(':disabled') ||
      !acceptsAttachment(input, file.name, file.type)) return false;
  const current = Array.from(input.files || []);
  if (replace && !current.includes(replace)) return false;
  const next = replace ? current.map(item => item === replace ? file : item)
    : input.multiple ? [...current, file] : [file];
  try {
    const transfer = new view.DataTransfer();
    next.forEach(item => transfer.items.add(item));
    input.files = transfer.files;
    if (input.files?.length !== next.length) return false;
  } catch (_) { return false; }
  input.dispatchEvent(new view.Event('input', {bubbles: true, composed: true}));
  input.dispatchEvent(new view.Event('change', {bubbles: true}));
  return true;
}
