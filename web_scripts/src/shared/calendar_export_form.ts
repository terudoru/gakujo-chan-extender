export function textOf(node: HTMLElement & { value?: string; name?: string }) {
  if (!node) return '';
  return [
    node.innerText || node.textContent || '',
    node.value || '',
    node.name || '',
    node.id || '',
    node.className || '',
    node.getAttribute && node.getAttribute('onclick') || '',
    node.getAttribute && node.getAttribute('href') || '',
    node.getAttribute && node.getAttribute('title') || ''
  ].join(' ').replace(/\s+/g, ' ').trim();
}

export function normalize(text: string) {
  return String(text || '').replace(/\s+/g, '').toLowerCase();
}

export function isExportForm(form: HTMLFormElement) {
  var value = normalize(textOf(form));
  return value.indexOf('scheduleexportform') >= 0 ||
    (value.indexOf('カテゴリ') >= 0 &&
     value.indexOf('対象期間') >= 0 &&
     value.indexOf('時間割コマ情報') >= 0);
}

function notifyInputChange(input: HTMLInputElement) {
  input.dispatchEvent(new Event('input', { bubbles: true }));
  input.dispatchEvent(new Event('change', { bubbles: true }));
}

export function configureInputs(
  form: HTMLFormElement,
  startDate: string,
  endDate: string,
  notifyCategories: boolean,
) {
  var dates = Array.from(form.querySelectorAll('input')).filter(function(input) {
    var type = String(input.getAttribute('type') || 'text').toLowerCase();
    return !['hidden', 'button', 'submit', 'checkbox', 'radio', 'image'].includes(type);
  });
  [startDate, endDate].forEach(function(value, index) {
    var input = dates[index];
    if (input && value) {
      input.value = value;
      notifyInputChange(input);
    }
  });
  for (var checkbox of Array.from(form.querySelectorAll<HTMLInputElement>('input[type="checkbox"]'))) {
    checkbox.checked = checkbox.name === 'check2' || checkbox.id === 'check21';
    if (notifyCategories) notifyInputChange(checkbox);
  }
}

export function diagnosticsFor(doc: Document, form: HTMLFormElement) {
  return {
    url: String(doc.location.href || '').split('?')[0],
    title: doc.title || '',
    formTextLength: textOf(form).length,
    controls: Array.from(
      form.querySelectorAll<HTMLElement>('button,input,a,[onclick]')
    ).slice(0, 32).map(function(control) {
      return String(control.tagName || '').toLowerCase() + ':' +
        textOf(control).slice(0, 120);
    })
  };
}
