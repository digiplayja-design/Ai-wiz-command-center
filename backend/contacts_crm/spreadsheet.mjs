import { CATEGORIES, fail } from './core.mjs';

export const IMPORT_FIELDS = {
  name: ['name', 'fullname', 'displayname', 'contactname', 'customername', 'clientname'],
  first_name: ['firstname', 'givenname', 'first'],
  last_name: ['lastname', 'familyname', 'surname', 'last'],
  email: ['email', 'emailaddress', 'email1value', 'email1address', 'workemail', 'primaryemail'],
  phone: ['phone', 'telephone', 'telephonenumber', 'phonenumber', 'mobilephone', 'mobile', 'phone1value', 'businessphone', 'workphone', 'cell', 'cellphone'],
  category: ['status', 'category', 'relationship', 'contacttype'],
  company: ['company', 'companyname', 'organization', 'organization1name', 'businessname'],
  notes: ['notes', 'note', 'comments', 'description'],
  tags: ['tags', 'labels', 'groups'],
  follow_up_on: ['followupon', 'followup', 'followupdate', 'nextfollowup'],
};
const key = value => String(value ?? '').toLowerCase().replace(/[^a-z0-9]/g, '');
const identity = mapping => ['name', 'first_name', 'last_name', 'email', 'phone'].some(f => Number.isInteger(mapping[f]));

export function decodeSpreadsheetText(bytes) {
  if (bytes[0] === 0xff && bytes[1] === 0xfe) return bytes.subarray(2).toString('utf16le');
  if (bytes[0] === 0xfe && bytes[1] === 0xff) {
    const text = Buffer.from(bytes.subarray(2));
    if (text.length % 2) fail('This spreadsheet text file is incomplete. Export it as UTF-8 CSV.');
    return text.swap16().toString('utf16le');
  }
  return bytes.toString('utf8').replace(/^\uFEFF/, '');
}

// A single separator is chosen outside quoted fields. Tabs inside CSV notes
// and commas inside TSV names must remain part of the original value.
function detectDelimiter(text) {
  const counts = new Map([[',', 0], ['\t', 0], [';', 0]]);
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '"') {
      if (quoted && text[i + 1] === '"') i++;
      else quoted = !quoted;
    } else if (!quoted && /[\r\n]/.test(c)) {
      if ([...counts.values()].some(Boolean)) break;
    } else if (!quoted && counts.has(c)) counts.set(c, counts.get(c) + 1);
  }
  return [...counts].sort((a, b) => b[1] - a[1])[0][0];
}

export function parseCsv(input, delimiter) {
  let text = String(input).replace(/^\uFEFF/, '');
  let line = 1, startLine = 1;
  const separator = /^sep=([,;\t])\r?\n/i.exec(text);
  if (separator) { delimiter = separator[1]; text = text.slice(separator[0].length); line = startLine = 2; }
  delimiter ??= detectDelimiter(text);
  const rows = [], rowNumbers = [];
  let row = [], cell = '', quoted = false, closed = false;
  const finish = () => {
    row.push(cell);
    if (row.length > 100) fail('Use at most 100 columns.');
    if (row.some(value => value.trim())) { rows.push(row); rowNumbers.push(startLine); }
    if (rows.length > 1020) fail('Import up to 1,000 contacts at a time.');
    row = []; cell = ''; closed = false;
  };
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') { cell += '"'; i++; }
        else { quoted = false; closed = true; }
      } else { cell += c; if (c === '\n' || (c === '\r' && text[i + 1] !== '\n')) line++; }
    } else if (c === '"' && !cell && !closed) quoted = true;
    else if (c === delimiter) { row.push(cell); cell = ''; closed = false; }
    else if (c === '\r' || c === '\n') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      finish(); line++; startLine = line;
    } else {
      if (closed && c.trim()) fail('The CSV contains an invalid quoted field.');
      if (!closed) cell += c;
    }
  }
  if (quoted) fail('The CSV has an unfinished quoted field.');
  finish();
  Object.defineProperty(rows, 'rowNumbers', { value: rowNumbers });
  return rows;
}

function autoMapping(header) {
  const keys = header.map(key), mapping = {};
  for (const [field, aliases] of Object.entries(IMPORT_FIELDS)) {
    const index = aliases.map(alias => keys.indexOf(alias)).find(i => i >= 0);
    mapping[field] = index ?? null;
  }
  return mapping;
}
function headerScore(row) {
  const mapping = autoMapping(row);
  return identity(mapping) ? Object.values(mapping).filter(Number.isInteger).length : 0;
}
function cellText(cell) {
  const value = cell.value;
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  if (typeof value === 'number' && Number.isSafeInteger(value) && /^0{2,15}$/.test(cell.numFmt)) {
    return String(value).padStart(cell.numFmt.length, '0');
  }
  // ExcelJS exposes stored formula results only; never evaluate formulas or links.
  return cell.text;
}
export function workbookTable(workbook, requestedSheet) {
  const sheets = workbook.worksheets.filter(sheet => !sheet.state || sheet.state === 'visible');
  if (!sheets.length) fail('This workbook has no visible worksheets.');
  let sheet;
  if (requestedSheet != null) {
    sheet = sheets.find(s => s.name === requestedSheet);
    if (!sheet) fail('Choose a worksheet from this workbook.');
  } else {
    sheet = sheets.find(s => {
      for (let n = 1; n <= Math.min(s.rowCount, 20); n++) {
        if (headerScore(Array.from({ length: Math.min(s.columnCount, 100) }, (_, i) => s.getRow(n).getCell(i + 1).text))) return true;
      }
      return false;
    }) ?? sheets.find(s => s.actualRowCount > 0) ?? sheets[0];
  }
  if (sheet.rowCount > 1020 || sheet.columnCount > 100) fail('Use at most 1,000 contacts and 100 columns. Remove unused formatted rows if needed.');
  const values = [], rowNumbers = [];
  sheet.eachRow(row => {
    const cells = Array.from({ length: sheet.columnCount }, (_, i) => cellText(row.getCell(i + 1)));
    if (cells.some(c => String(c).trim())) { values.push(cells); rowNumbers.push(row.number); }
  });
  Object.defineProperty(values, 'rowNumbers', { value: rowNumbers });
  return { values, sheets: sheets.map(s => s.name), worksheet: sheet.name };
}

export function spreadsheetRecords(values, body, workbook = {}) {
  if (!values.length) fail('No contacts were found in this worksheet.');
  const numbers = values.rowNumbers ?? values.map((_, i) => i + 1);
  let headerIndex = 0;
  if (body.headerRow != null) {
    if (!Number.isInteger(body.headerRow) || (headerIndex = numbers.indexOf(body.headerRow)) < 0) fail('Choose a nonempty header row from this file.');
  } else {
    let score = 0;
    values.slice(0, 20).forEach((row, i) => { const s = headerScore(row); if (s > score) { score = s; headerIndex = i; } });
  }
  const header = values[headerIndex], data = values.slice(headerIndex + 1);
  if (data.length > 1000) fail('Import up to 1,000 contacts at a time.');
  const mapping = autoMapping(header);
  if (body.mapping != null) {
    if (!body.mapping || typeof body.mapping !== 'object' || Array.isArray(body.mapping)) fail('Choose valid column matches.');
    for (const [field, index] of Object.entries(body.mapping)) {
      if (!Object.hasOwn(IMPORT_FIELDS, field) || (index !== null && (!Number.isInteger(index) || index < 0 || index >= header.length))) fail('Choose valid column matches.');
      mapping[field] = index;
    }
  }
  const used = Object.values(mapping).filter(Number.isInteger);
  if (new Set(used).size !== used.length) fail('Match each spreadsheet column to only one contact field.');
  const defaultCategory = body.defaultCategory ?? 'unknown';
  if (!CATEGORIES.includes(defaultCategory)) fail('Choose a valid default contact status.');
  const text = (row, field) => Number.isInteger(mapping[field]) ? String(row[mapping[field]] ?? '').trim() : '';
  const metadata = {
    ...workbook,
    columns: header.map((label, index) => ({ index, label: String(label).slice(0, 160) || `Column ${index + 1}`, sample: data.map(row => String(row[index] ?? '').trim()).find(Boolean)?.slice(0, 100) ?? '' })),
    mapping, headerRow: numbers[headerIndex],
    headerRows: values.slice(0, 20).map((row, i) => ({ row: numbers[i], label: row.join(' · ').slice(0, 100) })),
    defaultCategory,
    needsMapping: !identity(mapping),
  };
  return {
    metadata,
    rowNumbers: numbers.slice(headerIndex + 1),
    rows: metadata.needsMapping ? [] : data.map(row => ({
      name: text(row, 'name') || [text(row, 'first_name'), text(row, 'last_name')].filter(Boolean).join(' ') || text(row, 'email') || text(row, 'phone'),
      email: text(row, 'email'), phone: text(row, 'phone'),
      category: text(row, 'category') || defaultCategory,
      company: text(row, 'company'), notes: text(row, 'notes'),
      tags: text(row, 'tags').split(/[;,]/).map(t => t.trim()).filter(Boolean),
      follow_up_on: text(row, 'follow_up_on'),
    })),
  };
}
