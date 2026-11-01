const vm: any = require('node:vm');
const generatedScript = process.argv[2];
const values: any = new Map([
  ['MBG_LOGIN_AUTOFILL_ERROR:/login:key', '1'],
  ['MBG_LOGIN_AUTOFILL_SUBMIT_COUNT:/login:key', '1'],
  ['MBG_LOGIN_AUTOFILL_LAST_CREDENTIAL:/login', 'key'],
  ['MBG_2FA_AUTOFILL_ERROR:/2fa:key', '1'],
  ['MBG_2FA_AUTOFILL_SUBMIT_COUNT:/2fa:key', '1'],
  ['UNRELATED', 'keep']
]);
const window: any = {
  __MBG_LOGIN_AUTOFILL_SUBMITTED_KEY: 'credentials',
  __MBG_2FA_AUTO_SUBMITTED_KEY: 'secret',
  sessionStorage: {
    get length() { return values.size; },
    key(index) { return Array.from(values.keys())[index] || null; },
    removeItem(key) { values.delete(key); }
  }
};
window.window = window;
vm.runInNewContext(generatedScript, {window});
process.stdout.write(JSON.stringify({
  hasLoginDocumentGuard:
    Object.prototype.hasOwnProperty.call(window, '__MBG_LOGIN_AUTOFILL_SUBMITTED_KEY'),
  hasTwoFactorDocumentGuard:
    Object.prototype.hasOwnProperty.call(window, '__MBG_2FA_AUTO_SUBMITTED_KEY'),
  keys: Array.from(values.keys())
}));

