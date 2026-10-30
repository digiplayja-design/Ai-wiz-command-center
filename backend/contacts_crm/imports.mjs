import { inflateRawSync } from "node:zlib";
import { zipDirectory } from "../archive_security.mjs";
import { ContactError, fail, normalizeContact, SOURCES } from "./core.mjs";
const MAX_ROWS = 1000,
  MAX_BYTES = 2 * 1024 * 1024;
import { parseCsv, decodeSpreadsheetText, workbookTable, spreadsheetRecords } from './spreadsheet.mjs';
export { parseCsv } from './spreadsheet.mjs';
function vcards(text) {
  const unescape = (s) =>
    s.replace(/\\[nN]/g, "\n").replace(/\\([,;\\])/g, "$1");
  const unfolded = text.replace(/\r?\n[ \t]/g, "");
  const cards = [];
  let c = null;
  for (const line of unfolded.split(/\r?\n/)) {
    if (/^BEGIN:VCARD$/i.test(line)) {
      c = {};
      continue;
    }
    if (/^END:VCARD$/i.test(line)) {
      if (c) cards.push(c);
      c = null;
      continue;
    }
    if (!c) continue;
    const colon = line.indexOf(":");
    if (colon < 0) continue;
    const prop = line
        .slice(0, colon)
        .split(";")[0]
        .split(".")
        .pop()
        .toUpperCase(),
      value = unescape(line.slice(colon + 1));
    if (prop === "FN") c.name = value;
    else if (prop === "N" && !c.name) {
      const a = value.split(";");
      c.name = [a[1], a[0]].filter(Boolean).join(" ");
    } else if (prop === "EMAIL" && !c.email)
      c.email = value.replace(/^mailto:/i, "");
    else if (prop === "TEL" && !c.phone) c.phone = value.replace(/^tel:/i, "");
    else if (prop === "ORG") c.company = value.replaceAll(";", " ");
    else if (prop === "NOTE") c.notes = value;
  }
  if (c) fail("The vCard file is incomplete.");
  return cards;
}
function jsonRecords(data, source) {
  if (Array.isArray(data)) return data;
  if (source === "facebook") {
    if (Array.isArray(data.friends_v2)) return data.friends_v2;
    if (Array.isArray(data.friends)) return data.friends;
  }
  if (Array.isArray(data.contacts)) return data.contacts;
  fail("Choose a contacts export JSON file.");
}
// Inspect ZIP central-directory sizes before ExcelJS decompresses a workbook.
function checkXlsxZip(b) {
  let directory;
  try { directory = zipDirectory(b); }
  catch { fail("This is not a valid Excel workbook. Export contacts as CSV."); }
  const count = directory.count;
  let pos = directory.start,
    total = 0;
  if (count > 300 || count === 0xffff)
    fail("This workbook is too complex. Export it as CSV.");
  for (let i = 0; i < count; i++) {
    if (pos + 46 > b.length || b.readUInt32LE(pos) !== 0x02014b50)
      fail("Invalid Excel workbook.");
    const declared = b.readUInt32LE(pos + 24),
      compressed = b.readUInt32LE(pos + 20),
      method = b.readUInt16LE(pos + 10),
      local = b.readUInt32LE(pos + 42);
    if (
      declared > 20 * 1024 * 1024 - total ||
      local + 30 > b.length ||
      b.readUInt32LE(local) !== 0x04034b50 ||
      b.readUInt16LE(pos + 8) & 1
    )
      fail("This workbook is too large or encrypted. Export contacts as CSV.");
    const start =
      local + 30 + b.readUInt16LE(local + 26) + b.readUInt16LE(local + 28);
    if (start + compressed > b.length || ![0, 8].includes(method))
      fail("Invalid Excel workbook.");
    let actual;
    try {
      actual =
        method === 0
          ? compressed
          : inflateRawSync(b.subarray(start, start + compressed), {
              maxOutputLength: Math.max(1, 20 * 1024 * 1024 - total),
            }).length;
    } catch {
      fail("This workbook cannot be safely expanded. Export contacts as CSV.");
    }
    if (actual !== declared || total + actual > 20 * 1024 * 1024)
      fail("Invalid Excel workbook size.");
    total += actual;
    pos +=
      46 +
      b.readUInt16LE(pos + 28) +
      b.readUInt16LE(pos + 30) +
      b.readUInt16LE(pos + 32);
  }
}
export async function previewImport(body, { loadWorkbook } = {}) {
  if (!SOURCES.includes(body.source) || body.source === "manual")
    fail("Choose an import source.");
  let rows = [], rowNumbers = [], spreadsheet;
  if (Array.isArray(body.contacts)) {
    rows = body.contacts;
  } else {
    if (
      typeof body.content !== "string" ||
      body.content.length > Math.ceil((MAX_BYTES * 4) / 3) + 4
    )
      fail("Choose a file smaller than 2 MB.");
    const b = Buffer.from(body.content, "base64");
    if (b.length > MAX_BYTES) fail("Choose a file smaller than 2 MB.");
    const ext = String(body.filename || "")
      .split(".")
      .pop()
      .toLowerCase();
    if (ext === "xlsx") {
      checkXlsxZip(b);
      const workbook = loadWorkbook
        ? await loadWorkbook(b)
        : await (async () => {
            const { default: ExcelJS } = await import("exceljs");
            const w = new ExcelJS.Workbook();
            await w.xlsx.load(b);
            return w;
          })();
      const { values, sheets, worksheet } = workbookTable(workbook, body.worksheet);
      const parsed = spreadsheetRecords(values, body, { sheets, worksheet });
      ({ rows, rowNumbers } = parsed);
      spreadsheet = parsed.metadata;
    } else if (["csv", "tsv"].includes(ext)) {
      const parsed = spreadsheetRecords(parseCsv(decodeSpreadsheetText(b), ext === 'tsv' ? '\t' : undefined), body);
      ({ rows, rowNumbers } = parsed);
      spreadsheet = parsed.metadata;
    }
    else if (["vcf", "vcard"].includes(ext)) rows = vcards(b.toString("utf8"));
    else if (ext === "json") {
      try {
        rows = jsonRecords(JSON.parse(b.toString("utf8")), body.source);
      } catch (e) {
        if (e instanceof ContactError) throw e;
        fail("This JSON file could not be read.");
      }
    } else fail("Choose CSV, Excel (.xlsx), vCard (.vcf) or contacts JSON.");
  }
  if (!rows.length && !spreadsheet) fail("No contacts were found in this file.");
  if (rows.length > MAX_ROWS) fail("Import up to 1,000 contacts at a time.");
  const contacts = [],
    errors = [];
  let duplicates = 0;
  const emails = new Set(),
    phones = new Set(),
    names = new Set();
  rows.forEach((r, i) => {
    try {
      const c = normalizeContact(
        {
          ...r,
          name: r.name || r.displayName || r.email || "",
          source: body.source,
        },
        { imported: true },
      );
      const nameKey = c.name.toLocaleLowerCase();
      if (
        (c.email && emails.has(c.email)) ||
        (c.phone_key && phones.has(c.phone_key)) ||
        (!c.email && !c.phone_key && names.has(nameKey))
      ) {
        duplicates++;
        return;
      }
      if (c.email) emails.add(c.email);
      if (c.phone_key) phones.add(c.phone_key);
      if (!c.email && !c.phone_key) names.add(nameKey);
      contacts.push(c);
    } catch (e) {
      errors.push({ row: rowNumbers[i] ?? i + 1, message: e.message });
    }
  });
  return { contacts, errors, duplicates, total: rows.length, ...(spreadsheet ? { spreadsheet } : {}) };
}
