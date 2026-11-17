export const LIMITS = Object.freeze({ title: 80, content: 4000, steps: 2000, expected: 1000, version: 40, diagnostic: 20000 });
export const PLATFORMS = Object.freeze(['', 'windows', 'macos', 'linux', 'android', 'ios', 'other']);
export const TYPES = Object.freeze(['bug', 'request']);

// Count UTF-16 code units consistently with HTML maxlength and browser counters.
export function cleanText(value) {
  return value.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f]/g, '').trim();
}

export function validateReport(input) {
  const errors = {};
  const value = {};
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    return { value, errors: { form: '入力内容を確認してください。' } };
  }
  for (const [key, limit] of Object.entries(LIMITS)) {
    if (input[key] !== undefined && typeof input[key] !== 'string') {
      errors[key] = '文字で入力してください。';
      value[key] = '';
      continue;
    }
    value[key] = cleanText(input[key] ?? '');
    if (value[key].length > limit) errors[key] = `${limit}文字以内で入力してください。`;
  }
  for (const key of ['title', 'content']) {
    if (!value[key] && !errors[key]) errors[key] = '入力してください。';
  }
  value.type = input.type;
  if (!TYPES.includes(value.type)) errors.type = '種類を選んでください。';
  value.platform = input.platform ?? '';
  if (!PLATFORMS.includes(value.platform)) errors.platform = 'OS（Windows・Mac・Android など）を選び直してください。';
  if (input.consent !== true) errors.consent = '確認してチェックを入れてください。';
  if (value.type === 'request') {
    value.steps = '';
    value.expected = '';
  }
  return { value, errors };
}
