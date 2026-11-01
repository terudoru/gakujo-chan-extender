// GENERATED FILE - DO NOT EDIT.
// Source: web_scripts/src/calendar_extraction/main.ts
// Regenerate with: npm --prefix web_scripts run build

const String gakujoCalendarExtractionJs = r'''
(function() {
"use strict";
(() => {
  // web_scripts/src/calendar_extraction/main.ts
  function calendarExtraction() {
    var results = [];
    var seen = {};
    function rawTextOf(node) {
      return (node && (node.innerText || node.textContent) || "").replace(/\r\n?/g, "\n").replace(/\u00a0/g, " ").trim();
    }
    function textOf(node) {
      return rawTextOf(node).replace(/\s+/g, " ").trim();
    }
    function addCourse(course) {
      if (!course || !course.title || !course.weekday || !course.period) {
        return;
      }
      var key = [
        course.title,
        course.weekday,
        course.period,
        course.location || "",
        course.sourceDate || "",
        course.termHint || "",
        course.courseCode || ""
      ].join("");
      if (seen[key]) {
        for (var i = 0; i < results.length; i += 1) {
          var existing = results[i];
          var existingKey = [
            existing.title,
            existing.weekday,
            existing.period,
            existing.location || "",
            existing.sourceDate || "",
            existing.termHint || "",
            existing.courseCode || ""
          ].join("");
          if (existingKey === key) {
            existing.teacher = existing.teacher || course.teacher || "";
            existing.officialTitle = existing.officialTitle || course.officialTitle || "";
            existing.officialLocation = existing.officialLocation || course.officialLocation || "";
            existing.officialDescription = existing.officialDescription || course.officialDescription || "";
            existing.sourceDate = existing.sourceDate || course.sourceDate || "";
            existing.termHint = existing.termHint || course.termHint || "";
            existing.courseCode = existing.courseCode || course.courseCode || "";
            existing.authoritativeTimetableCell = existing.authoritativeTimetableCell || course.authoritativeTimetableCell || false;
            if (!existing.location && course.location) {
              existing.location = course.location;
            }
            return;
          }
        }
        return;
      }
      seen[key] = true;
      results.push(course);
    }
    function normalizeTitle(text) {
      return String(text || "").replace(/\s+/g, "").toLowerCase();
    }
    function titleLooksSame(a, b) {
      var left = normalizeTitle(a);
      var right = normalizeTitle(b);
      return left && right && (left === right || left.indexOf(right) >= 0 || right.indexOf(left) >= 0);
    }
    function titleLooksUseful(title) {
      var normalized = String(title || "").replace(/\s+/g, " ").trim();
      var compact = normalized.replace(/\s+/g, "");
      if (!compact || /^[0-9]+$/.test(compact) || /^[0-9]{4}[\/年-][0-9]{1,2}[\/月-][0-9]{1,2}日?/.test(compact) || /^(mon|tue|wed|thu|fri|sat|sun)$/i.test(compact) || /^[月火水木金土日]$/.test(compact) || /^(myスケジュール|リンク|新着情報|home)$/i.test(compact)) {
        return false;
      }
      return /[A-Za-zＡ-Ｚａ-ｚ一-龯ぁ-んァ-ヶ]/.test(compact);
    }
    function weekdayFromLabel(label) {
      var value = String(label || "").toLowerCase();
      if (/mon|月/.test(value)) return 1;
      if (/tue|火/.test(value)) return 2;
      if (/wed|水/.test(value)) return 3;
      if (/thu|木/.test(value)) return 4;
      if (/fri|金/.test(value)) return 5;
      if (/sat|土/.test(value)) return 6;
      if (/sun|日/.test(value)) return 7;
      return 0;
    }
    function weekdayFromDateLine(line) {
      var text = String(line || "");
      var labelMatch = text.match(/\(([^)]+)\)/);
      var labelWeekday = weekdayFromLabel(labelMatch && labelMatch[1]);
      if (labelWeekday) {
        return labelWeekday;
      }
      var dateMatch = text.match(/(20[0-9]{2})[\/年-]([0-9]{1,2})[\/月-]([0-9]{1,2})日?/);
      if (!dateMatch) {
        return 0;
      }
      var date = new Date(
        Number(dateMatch[1]),
        Number(dateMatch[2]) - 1,
        Number(dateMatch[3])
      );
      var day = date.getDay();
      return day === 0 ? 7 : day;
    }
    function sourceDateFromLine(line) {
      var match = String(line || "").match(/(20[0-9]{2})[\/年-]([0-9]{1,2})[\/月-]([0-9]{1,2})日?/);
      if (!match) {
        return "";
      }
      function pad(value) {
        return String(value).padStart(2, "0");
      }
      return match[1] + "-" + pad(match[2]) + "-" + pad(match[3]);
    }
    function sourceDateFromNode(node) {
      if (!node) {
        return "";
      }
      var addLink = node.querySelector && node.querySelector('[onclick*="addSchedule("]');
      var addMatch = addLink && String(addLink.getAttribute("onclick") || "").match(/addSchedule\(\s*'?(20[0-9]{2})([0-9]{2})([0-9]{2})/);
      if (addMatch) {
        return addMatch[1] + "-" + addMatch[2] + "-" + addMatch[3];
      }
      var direct = sourceDateFromLine(rawTextOf(node));
      if (direct) {
        return direct;
      }
      var candidates = Array.prototype.slice.call(
        node.querySelectorAll && node.querySelectorAll("[onclick],[href]") || []
      );
      candidates.unshift(node);
      for (var i = 0; i < candidates.length; i += 1) {
        var candidate = candidates[i];
        var text = [
          candidate.getAttribute && candidate.getAttribute("onclick") || "",
          candidate.getAttribute && candidate.getAttribute("href") || ""
        ].join(" ");
        var match = text.match(/(20[0-9]{2})[_\/-]([0-9]{1,2})[_\/-]([0-9]{1,2})/);
        if (match) {
          let pad2 = function(value) {
            return String(value).padStart(2, "0");
          };
          var pad = pad2;
          return match[1] + "-" + pad2(match[2]) + "-" + pad2(match[3]);
        }
      }
      return "";
    }
    function termHintFromText(text) {
      var match = String(text || "").match(/第\s*([1-4１-４])\s*ターム/);
      return match ? match[0].replace(/\s+/g, "") : "";
    }
    function termCodesFromHint(text) {
      var normalized = String(text || "").replace(/[１-４]/g, function(ch) {
        return String("１２３４".indexOf(ch) + 1);
      });
      var terms = {};
      var match;
      var pattern = /第\s*([1-4])\s*ターム/g;
      while ((match = pattern.exec(normalized)) !== null) {
        terms[Number(match[1])] = true;
      }
      return terms;
    }
    function normalizeCourseCode(text) {
      var full = "０１２３４５６７８９ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺ";
      var half = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
      return String(text || "").toUpperCase().replace(/[０-９Ａ-Ｚ]/g, function(ch) {
        var index = full.indexOf(ch);
        return index >= 0 ? half.charAt(index) : ch;
      });
    }
    function courseCodeFromText(text) {
      var value = normalizeCourseCode(text);
      var match = value.match(/(?:^|[^A-Z0-9])([0-9]{2}[0-4][A-Z][A-Z0-9]{3,})(?=$|[^A-Z0-9])/);
      return match ? match[1] : "";
    }
    function termCodeFromCourseCode(code) {
      var normalized = normalizeCourseCode(code);
      var match = normalized.match(/^([0-9]{2})([0-4])([A-Z][A-Z0-9]{3,})$/);
      return match ? Number(match[2]) : null;
    }
    function termHintFromCourseCode(code) {
      var termCode = termCodeFromCourseCode(code);
      return termCode && termCode >= 1 && termCode <= 4 ? "第" + termCode + "ターム" : "";
    }
    function splitTitleAndLocation(raw) {
      var value = String(raw || "").replace(/\s+/g, " ").trim();
      var courseCode = courseCodeFromText(value);
      if (courseCode) {
        value = normalizeCourseCode(value).replace(courseCode, " ").replace(/\s+/g, " ").trim();
      }
      var parts = value.split(/\s*[@＠]\s*/);
      return {
        title: (parts.shift() || "").trim(),
        location: parts.join(" @ ").trim(),
        courseCode
      };
    }
    function addDailyLineCourse(weekday, period, rawTitleAndLocation, sourceDate, termHint, authoritativeTimetableCell) {
      var split = splitTitleAndLocation(rawTitleAndLocation);
      if (!weekday || !period || !titleLooksUseful(split.title)) {
        return;
      }
      addCourse({
        title: split.title,
        weekday,
        period,
        location: split.location,
        teacher: "",
        sourceDate: sourceDate || "",
        termHint: termHint || termHintFromCourseCode(split.courseCode) || termHintFromText(rawTitleAndLocation),
        courseCode: split.courseCode || courseCodeFromText(rawTitleAndLocation),
        authoritativeTimetableCell: authoritativeTimetableCell === true
      });
    }
    function periodFromTimeText(text) {
      var value = String(text || "").replace(/\s+/g, "");
      var match = value.match(/([0-9]{1,2})[:：]([0-9]{2})\s*[~〜～\-−ー]\s*([0-9]{1,2})[:：]([0-9]{2})/);
      if (!match) {
        return 0;
      }
      var start = Number(match[1]) * 60 + Number(match[2]);
      var starts = {
        525: 1,
        630: 2,
        780: 3,
        885: 4,
        990: 5,
        1090: 6,
        1185: 7
      };
      return starts[start] || 0;
    }
    function cleanCourseText(text) {
      return String(text || "").replace(/\b[0-9]{1,2}[:：][0-9]{2}\s*[~〜～\-−ー]\s*[0-9]{1,2}[:：][0-9]{2}\b/g, " ").replace(/^\s*[0-9]{1,2}\s*$/, " ").replace(/\s+/g, " ").trim();
    }
    function cleanTimetableCellText(text, courseCode) {
      var value = normalizeCourseCode(text).replace(courseCode, " ").replace(/\(\s*T\s*[0-9,，、]+\s*\)/gi, " ").replace(/第\s*[1-4１-４]\s*ターム/g, " ").replace(/備考欄参照\s*\/?\s*See\s*remarks/gi, " ").replace(/[0-9]+(?:\.[0-9]+)?\s*単位/g, " ").replace(/\s+/g, " ").trim();
      return value;
    }
    function splitTimetableTitleAndLocation(text) {
      var value = String(text || "").replace(/\s+/g, " ").trim();
      var location = "";
      var locationMatch = value.match(
        /\s((?:総合教育研究棟|工学部|農学部|人文学部|教育学部|理学部|医学部|歯学部|図書館|未定)\s*[A-ZＡ-Ｚ]?-?[0-9０-９A-ZＡ-Ｚ,\- 　]*)$/i
      );
      if (!locationMatch) {
        locationMatch = value.match(
          /\s([A-ZＡ-Ｚ]-?[0-9０-９]{2,}[A-ZＡ-Ｚ,\- 　]*)$/i
        );
      }
      if (locationMatch) {
        location = locationMatch[1].trim();
        value = value.substring(0, locationMatch.index).trim();
      }
      return {
        title: value,
        location
      };
    }
    function addTimetableGridCellCourse(weekday, period, raw) {
      if (!weekday || !period) {
        return;
      }
      var rawText = String(raw || "");
      var code = courseCodeFromText(rawText);
      if (!code) {
        return;
      }
      var cleaned = cleanTimetableCellText(rawText, code);
      var split = splitTimetableTitleAndLocation(cleaned);
      if (!titleLooksUseful(split.title)) {
        return;
      }
      addCourse({
        title: split.title,
        weekday,
        period,
        location: split.location,
        teacher: "",
        sourceDate: "",
        termHint: termHintFromCourseCode(code) || termHintFromText(rawText),
        courseCode: code
      });
    }
    function parseScheduleTextWithWeekday(weekday, raw, sourceDate, termHint) {
      if (!weekday) {
        return;
      }
      var text = String(raw || "").replace(/\r\n?/g, "\n");
      var dateHint = sourceDate || sourceDateFromLine(text);
      var termHintValue = termHint || termHintFromText(text);
      var periodPattern = /(?:^|[\n\s　])([1-7])\s*限\s*[:：]\s*([\s\S]*?)(?=(?:[\n\s　][1-7]\s*限\s*[:：])|$)/g;
      var match;
      var foundPeriod = false;
      while ((match = periodPattern.exec(text)) !== null) {
        foundPeriod = true;
        addDailyLineCourse(
          weekday,
          Number(match[1]),
          cleanCourseText(match[2]),
          dateHint,
          termHintValue
        );
      }
      if (foundPeriod) {
        return;
      }
      var period = periodFromTimeText(text);
      if (!period) {
        return;
      }
      var lines = text.split(/\n+/).map(function(line) {
        return cleanCourseText(line);
      }).filter(function(line) {
        return titleLooksUseful(line) && !/[0-9]{1,2}[:：][0-9]{2}/.test(line);
      });
      if (lines.length) {
        addDailyLineCourse(
          weekday,
          period,
          lines.join(" "),
          dateHint,
          termHintValue
        );
      }
    }
    function parseDailySummaryCell(weekday, raw, sourceDate) {
      if (!weekday) {
        return;
      }
      var text = String(raw || "").replace(/\r\n?/g, "\n");
      var pattern = /(?:^|[\s\n　])([1-7])\s*限\s*[:：]\s*([\s\S]*?)(?=(?:[\s\n　][1-7]\s*限\s*[:：])|(?:[\s\n　]*\[[^\]]+\])|$)/g;
      var match;
      while ((match = pattern.exec(text)) !== null) {
        addDailyLineCourse(
          weekday,
          Number(match[1]),
          cleanCourseText(match[2]),
          sourceDate,
          termHintFromText(text),
          true
        );
      }
    }
    function weekdayFromHeaderCell(text) {
      var value = String(text || "").replace(/[0-9０-９\s\/\-.,:：()（）\[\]［］]/g, "").toLowerCase();
      if (/^(mon|tue|wed|thu|fri|sat|sun)[a-z]*$/.test(value) || /^[月火水木金土日](曜日?)?$/.test(value)) {
        return weekdayFromLabel(value);
      }
      return 0;
    }
    function columnWeekdayMapFromRow(row) {
      var cells = Array.prototype.slice.call(row.children || []);
      var map = {};
      var found = 0;
      for (var i = 0; i < cells.length; i += 1) {
        var weekday = weekdayFromHeaderCell(textOf(cells[i]));
        if (weekday) {
          map[i] = weekday;
          found += 1;
        }
      }
      return found >= 3 ? map : null;
    }
    function columnDateMapFromRow(row) {
      var cells = Array.prototype.slice.call(row.children || []);
      var map = {};
      for (var i = 0; i < cells.length; i += 1) {
        var date = sourceDateFromLine(textOf(cells[i]));
        if (date) {
          map[i] = date;
        }
      }
      return map;
    }
    function headerMapFromRow(row) {
      var cells = Array.prototype.slice.call(row.children || []);
      var map = {};
      var hits = 0;
      for (var i = 0; i < cells.length; i += 1) {
        var text = textOf(cells[i]);
        if (/開講番号|講義番号|科目番号/.test(text)) {
          map.code = i;
          hits += 1;
        } else if (/科目名|授業科目|講義名/.test(text)) {
          map.title = i;
          hits += 1;
        } else if (/曜日/.test(text)) {
          map.weekday = i;
          hits += 1;
        } else if (/時限|時限目|校時|時間/.test(text)) {
          map.period = i;
          hits += 1;
        } else if (/教室|場所|講義室/.test(text)) {
          map.location = i;
        } else if (/担当|教員/.test(text)) {
          map.teacher = i;
        }
      }
      return hits >= 2 && map.code !== void 0 ? map : null;
    }
    function exactWeekdayFromCell(text) {
      var value = String(text || "").replace(/\s+/g, "").toLowerCase();
      if (/^(mon|月|月曜|月曜日)$/.test(value)) return 1;
      if (/^(tue|火|火曜|火曜日)$/.test(value)) return 2;
      if (/^(wed|水|水曜|水曜日)$/.test(value)) return 3;
      if (/^(thu|木|木曜|木曜日)$/.test(value)) return 4;
      if (/^(fri|金|金曜|金曜日)$/.test(value)) return 5;
      if (/^(sat|土|土曜|土曜日)$/.test(value)) return 6;
      if (/^(sun|日|日曜|日曜日)$/.test(value)) return 7;
      return weekdayFromDateLine(text);
    }
    function periodFromCell(text) {
      var value = String(text || "").replace(/\s+/g, "");
      var match = value.match(/^([1-7])(?:限|時限|時限目|校時)?$/);
      if (match) {
        return Number(match[1]);
      }
      match = value.match(/([1-7])(?:限|時限|時限目|校時)/);
      if (match) {
        return Number(match[1]);
      }
      return periodFromTimeText(value);
    }
    function periodFromRowHeaderCell(text) {
      var value = String(text || "").replace(/\s+/g, "");
      var match = value.match(/^([1-7])(?:限|時限|時限目|校時)$/);
      return match ? Number(match[1]) : 0;
    }
    function cellAt(cells, index) {
      if (index === void 0 || index < 0 || index >= cells.length) {
        return "";
      }
      return textOf(cells[index]);
    }
    function scanCourseRows(doc) {
      var tables = Array.prototype.slice.call(doc.querySelectorAll("table"));
      for (var t = 0; t < tables.length; t += 1) {
        var rows = Array.prototype.slice.call(tables[t].querySelectorAll("tr"));
        var headerMap = null;
        for (var r = 0; r < rows.length; r += 1) {
          var row = rows[r];
          var maybeHeader = headerMapFromRow(row);
          if (maybeHeader) {
            headerMap = maybeHeader;
            continue;
          }
          if (!headerMap && columnWeekdayMapFromRow(row)) {
            break;
          }
          var cells = Array.prototype.slice.call(row.children || []);
          if (!cells.length) {
            continue;
          }
          var rowText = rawTextOf(row);
          var code = headerMap ? courseCodeFromText(cellAt(cells, headerMap.code)) || courseCodeFromText(rowText) : courseCodeFromText(rowText);
          if (!code) {
            continue;
          }
          var title = headerMap ? cellAt(cells, headerMap.title) : "";
          if (!title) {
            for (var c = 0; c < cells.length; c += 1) {
              var candidate = textOf(cells[c]);
              if (candidate.indexOf(code) >= 0) {
                continue;
              }
              if (titleLooksUseful(candidate) && !exactWeekdayFromCell(candidate) && !periodFromCell(candidate)) {
                title = candidate;
                break;
              }
            }
          }
          var weekday = headerMap ? exactWeekdayFromCell(cellAt(cells, headerMap.weekday)) : 0;
          var period = headerMap ? periodFromCell(cellAt(cells, headerMap.period)) : 0;
          if (!weekday || !period) {
            for (var p = 0; p < cells.length; p += 1) {
              var cellText = textOf(cells[p]);
              weekday = weekday || exactWeekdayFromCell(cellText);
              period = period || periodFromCell(cellText);
            }
          }
          if (!weekday || !period || !titleLooksUseful(title)) {
            continue;
          }
          addCourse({
            title: splitTitleAndLocation(title).title,
            weekday,
            period,
            location: headerMap ? cellAt(cells, headerMap.location) : "",
            teacher: headerMap ? cellAt(cells, headerMap.teacher) : "",
            sourceDate: sourceDateFromLine(rowText),
            termHint: termHintFromCourseCode(code) || termHintFromText(rowText),
            courseCode: code
          });
        }
      }
    }
    function scanScheduleTables(doc) {
      var tables = Array.prototype.slice.call(doc.querySelectorAll("table"));
      for (var t = 0; t < tables.length; t += 1) {
        var table = tables[t];
        var rows = Array.prototype.slice.call(table.querySelectorAll("tr"));
        var columnWeekdays = null;
        var columnDates = null;
        for (var r = 0; r < rows.length; r += 1) {
          var row = rows[r];
          var rowMap = columnWeekdayMapFromRow(row);
          if (rowMap) {
            columnWeekdays = rowMap;
            columnDates = columnDateMapFromRow(row);
            continue;
          }
          var cells = Array.prototype.slice.call(row.children || []);
          if (!columnWeekdays) {
            continue;
          }
          var rowPeriod = cells.length ? periodFromRowHeaderCell(textOf(cells[0])) : 0;
          if (!rowPeriod) {
            for (var sc = 0; sc < cells.length; sc += 1) {
              if (!columnWeekdays[sc]) {
                continue;
              }
              parseDailySummaryCell(
                columnWeekdays[sc],
                rawTextOf(cells[sc]),
                sourceDateFromNode(cells[sc]) || columnDates && columnDates[sc] || ""
              );
            }
            continue;
          }
          for (var c = 0; c < cells.length; c += 1) {
            var cellText = rawTextOf(cells[c]);
            if (rowPeriod && columnWeekdays[c] && courseCodeFromText(cellText)) {
              addTimetableGridCellCourse(columnWeekdays[c], rowPeriod, cellText);
              continue;
            }
          }
        }
      }
    }
    function hasOfficialFields(course) {
      return !!(course && (course.officialTitle || course.officialLocation || course.officialDescription));
    }
    function mergeOfficialEventIntoCourse(course, event) {
      course.officialTitle = event.officialTitle || course.officialTitle || "";
      course.officialLocation = event.officialLocation || course.officialLocation || "";
      course.officialDescription = event.officialDescription || course.officialDescription || "";
      course.sourceDate = event.sourceDate || course.sourceDate || "";
      course.termHint = event.termHint || course.termHint || "";
      course.courseCode = course.courseCode || event.courseCode || "";
      if (!course.location && event.location) {
        course.location = event.location;
      }
    }
    function canMergePotentialSameTerm(course, event) {
      var courseCode = courseCodeFromText(course && course.courseCode || "");
      var eventCode = courseCodeFromText(event && event.courseCode || "");
      if (courseCode && eventCode && courseCode !== eventCode) {
        return false;
      }
      var courseTerm = termCodeFromCourseCode(course && course.courseCode || "");
      var eventTerm = termCodeFromCourseCode(event && event.courseCode || "");
      if (courseTerm !== null && eventTerm !== null && courseTerm >= 1 && courseTerm <= 4 && eventTerm >= 1 && eventTerm <= 4 && courseTerm !== eventTerm) {
        return false;
      }
      var courseHintTerms = termCodesFromHint(course && course.termHint || "");
      var eventHintTerms = termCodesFromHint(event && event.termHint || "");
      if (courseTerm !== null && courseTerm >= 1 && courseTerm <= 4 && Object.keys(eventHintTerms).length && !eventHintTerms[courseTerm]) {
        return false;
      }
      if (courseTerm !== null && courseTerm >= 1 && courseTerm <= 4 && eventTerm === null && !Object.keys(eventHintTerms).length) {
        return false;
      }
      if (eventTerm !== null && eventTerm >= 1 && eventTerm <= 4 && Object.keys(courseHintTerms).length && !courseHintTerms[eventTerm]) {
        return false;
      }
      if (eventTerm !== null && eventTerm >= 1 && eventTerm <= 4 && courseTerm === null && !Object.keys(courseHintTerms).length) {
        return false;
      }
      if (course && event && course.sourceDate && event.sourceDate && course.sourceDate !== event.sourceDate) {
        return false;
      }
      return true;
    }
    function sameSlotCourses(event) {
      return results.filter(function(course) {
        return course.weekday === event.weekday && course.period === event.period && canMergePotentialSameTerm(course, event);
      });
    }
    function googleStartDate(start) {
      var match = String(start || "").match(/^(\d{4})(\d{2})(\d{2})(?:T?(\d{2})(\d{2})(\d{2})?)?(Z)?/);
      if (!match) {
        return null;
      }
      var year = Number(match[1]);
      var month = Number(match[2]) - 1;
      var day = Number(match[3]);
      var hour = Number(match[4] || 0);
      var minute = Number(match[5] || 0);
      var second = Number(match[6] || 0);
      if (match[7] === "Z") {
        var jstDate = new Date(
          Date.UTC(year, month, day, hour, minute, second) + 9 * 60 * 60 * 1e3
        );
        var utcDay = jstDate.getUTCDay();
        return {
          hour: jstDate.getUTCHours(),
          minute: jstDate.getUTCMinutes(),
          weekday: utcDay === 0 ? 7 : utcDay,
          sourceDate: [
            jstDate.getUTCFullYear(),
            String(jstDate.getUTCMonth() + 1).padStart(2, "0"),
            String(jstDate.getUTCDate()).padStart(2, "0")
          ].join("-")
        };
      }
      var localDate = new Date(year, month, day, hour, minute, second);
      var localDay = localDate.getDay();
      return {
        hour: localDate.getHours(),
        minute: localDate.getMinutes(),
        weekday: localDay === 0 ? 7 : localDay,
        sourceDate: [
          localDate.getFullYear(),
          String(localDate.getMonth() + 1).padStart(2, "0"),
          String(localDate.getDate()).padStart(2, "0")
        ].join("-")
      };
    }
    function googlePeriodFromStart(start) {
      var date = googleStartDate(start);
      if (!date) {
        return 0;
      }
      var minutes = date.hour * 60 + date.minute;
      var starts = {
        525: 1,
        630: 2,
        780: 3,
        885: 4,
        990: 5,
        1090: 6,
        1185: 7
      };
      return starts[minutes] || 0;
    }
    function googleWeekdayFromStart(start) {
      var date = googleStartDate(start);
      if (!date) {
        return 0;
      }
      return date.weekday;
    }
    function extractGoogleUrls(raw, baseUrl) {
      var values = [];
      var text = String(raw || "").replace(/&amp;/g, "&").replace(/\\u0026/g, "&");
      var matches = text.match(/https?:\/\/[^'"<>\s)]+/g) || [];
      if (/calendar/i.test(text) && /^https?:\/\//i.test(text)) {
        matches.push(text);
      }
      for (var i = 0; i < matches.length; i += 1) {
        try {
          var url = new URL(matches[i], baseUrl);
          var host = url.hostname.toLowerCase();
          var path = url.pathname.toLowerCase();
          if (url.protocol === "https:" && host === "calendar.google.com" && path.indexOf("/calendar") >= 0 && (url.searchParams.has("text") || url.searchParams.has("details") || url.searchParams.has("dates"))) {
            values.push(url);
          }
        } catch (e) {
        }
      }
      return values;
    }
    function officialEventFromUrl(url) {
      var title = (url.searchParams.get("text") || url.searchParams.get("title") || "").trim();
      var location = (url.searchParams.get("location") || "").trim();
      var details = (url.searchParams.get("details") || "").trim();
      var dates = (url.searchParams.get("dates") || "").split("/")[0] || "";
      var courseCode = courseCodeFromText(title + " " + details + " " + location);
      var weekday = googleWeekdayFromStart(dates);
      var period = googlePeriodFromStart(dates);
      var startDate = googleStartDate(dates);
      if (!title || !weekday || !period) {
        return null;
      }
      return {
        title,
        weekday,
        period,
        location,
        teacher: "",
        officialTitle: title,
        officialLocation: location,
        officialDescription: details,
        sourceDate: startDate && startDate.sourceDate || "",
        termHint: termHintFromCourseCode(courseCode) || termHintFromText(title + " " + details),
        courseCode
      };
    }
    function attachOfficialEvent(event) {
      if (!event) {
        return;
      }
      var matchingCourses = sameSlotCourses(event);
      for (var i = 0; i < matchingCourses.length; i += 1) {
        var course = matchingCourses[i];
        if (titleLooksSame(course.title, event.title)) {
          mergeOfficialEventIntoCourse(course, event);
          return;
        }
      }
      if (matchingCourses.length === 1 && !hasOfficialFields(matchingCourses[0]) && (!matchingCourses[0].courseCode || event.courseCode)) {
        mergeOfficialEventIntoCourse(matchingCourses[0], event);
        return;
      }
      addCourse(event);
    }
    function scanOfficialGoogleCalendarLinks(doc) {
      var nodes = Array.prototype.slice.call(
        doc.querySelectorAll("a,button,input,[onclick],[data-url],[data-href]")
      );
      var seenUrls = {};
      for (var n = 0; n < nodes.length; n += 1) {
        var node = nodes[n];
        var sources = [
          node.getAttribute && node.getAttribute("href") || "",
          node.getAttribute && node.getAttribute("onclick") || "",
          node.value || ""
        ];
        var attrs = node.attributes || [];
        for (var a = 0; a < attrs.length; a += 1) {
          if (/^data-/i.test(attrs[a].name)) {
            sources.push(attrs[a].value || "");
          }
        }
        for (var s = 0; s < sources.length; s += 1) {
          var urls = extractGoogleUrls(sources[s], doc.location.href);
          for (var u = 0; u < urls.length; u += 1) {
            var href = urls[u].href;
            if (seenUrls[href]) {
              continue;
            }
            seenUrls[href] = true;
            attachOfficialEvent(officialEventFromUrl(urls[u]));
          }
        }
      }
    }
    function collect(win) {
      try {
        if (!win || !win.document) {
          return;
        }
        var beforeStructuredRows = results.length;
        scanCourseRows(win.document);
        var addedStructuredRows = results.slice(beforeStructuredRows).some(function(course) {
          return !!course.courseCode;
        });
        if (!addedStructuredRows) {
          scanScheduleTables(win.document);
        }
        scanOfficialGoogleCalendarLinks(win.document);
        for (var i = 0; i < win.frames.length; i += 1) {
          collect(win.frames[i]);
        }
      } catch (e) {
      }
    }
    function allPageText() {
      var texts = [];
      function collectText(win) {
        try {
          if (!win || !win.document || !win.document.body) {
            return;
          }
          texts.push(textOf(win.document.body));
          for (var i = 0; i < win.frames.length; i += 1) {
            collectText(win.frames[i]);
          }
        } catch (e) {
        }
      }
      collectText(window);
      return texts.join("\n");
    }
    function termRangeTextFrom(pageText2) {
      var lines = String(pageText2 || "").split(/\n+/);
      var picked = [];
      for (var i = 0; i < lines.length; i += 1) {
        var line = lines[i].replace(/\s+/g, " ").trim();
        if (!line) {
          continue;
        }
        if (/(ターム|学期|授業期間|開講期間|履修期間|授業日程|期間)/.test(line) && /([0-9]{4}[年\/-])?[0-9]{1,2}[月\/-][0-9]{1,2}日?/.test(line)) {
          picked.push(line);
        }
        if (picked.length >= 12) {
          break;
        }
      }
      return picked.join("\n");
    }
    collect(window);
    if (results.some(function(course) {
      return !!course.courseCode;
    })) {
      results = results.filter(function(course) {
        return !!course.courseCode || hasOfficialFields(course) || course.authoritativeTimetableCell === true;
      });
    }
    results.forEach(function(course) {
      delete course.authoritativeTimetableCell;
    });
    var pageText = allPageText();
    return JSON.stringify({
      courses: results,
      termRangeText: termRangeTextFrom(pageText),
      pageText
    });
  }
  __mbgEntryResult = calendarExtraction();
})();
var __mbgEntryResult;
return __mbgEntryResult;
})()
''';
