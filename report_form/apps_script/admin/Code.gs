/** @OnlyCurrentDoc */
// Bound to the private spreadsheet. Never deploy this project as a web app.
function dailyCleanup() {
  let held = false;
  let lock;
  try {
    const properties = PropertiesService.getScriptProperties();
    const raw = properties.getProperty('RETENTION_DAYS');
    const days = raw === null ? 180 : Number(raw);
    if ((raw !== null && !/^[1-9]\d*$/.test(raw)) || !Number.isSafeInteger(days * 86400000) || days <= 0) return;
    lock = LockService.getScriptLock();
    held = lock.tryLock(10000);
    if (!held) return;
    const now = Date.now();
    const last = Number(properties.getProperty('cleanup_last_ms'));
    if (last > 0 && now - last < 12 * 3600000) return;
    const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('reports');
    if (!sheet || sheet.getLastRow() === 0 || sheet.getRange(1, 3, 1, 1).getValues()[0][0] !== 'createdAt') return;
    const lastRow = sheet.getLastRow();
    if (lastRow > 1) {
      const dates = sheet.getRange(2, 3, lastRow - 1, 1).getValues();
      const cutoff = now - days * 86400000;
      let count = 0;
      for (let i = dates.length - 1; i >= 0; i--) {
        const time = new Date(dates[i][0]).getTime();
        if (Number.isFinite(time) && time < cutoff) count++;
        else if (count) { sheet.deleteRows(i + 3, count); count = 0; }
      }
      if (count) sheet.deleteRows(2, count);
    }
    properties.setProperty('cleanup_last_ms', String(now));
  } catch (_) { /* Never log or return stored content. A later trigger can retry. */ }
  finally {
    if (held) { try { SpreadsheetApp.flush(); } finally { lock.releaseLock(); } }
  }
}
