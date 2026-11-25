import { api, displayNumber } from "./fax-api.js";

export const currentMonth = () => new Date().toISOString().slice(0, 7);
export const validMonth = (month) =>
  /^[1-9]\d{3}-(0[1-9]|1[0-2])$/.test(month) && month <= currentMonth();

export function activityPage(month, cursor = null) {
  const params = new URLSearchParams({ month });
  if (cursor) params.set("cursor", cursor);
  return api("/activity?" + params);
}

const headings = ["Completed (UTC)", "Direction", "From", "To", "Document", "Status", "Pages", "Page count status", "Fax reference"];

function csvRow(values) {
  return values.map((value) => {
    let cell = String(value ?? "");
    // Spreadsheet apps may interpret a quoted filename as a formula.
    if (/^(?:[\t\r\n]|\s*[=+@＝＋＠－-])/u.test(cell)) cell = "'" + cell;
    return '"' + cell.replaceAll('"', '""') + '"';
  }).join(",") + "\r\n";
}

export async function activityCsv(month, getPage = activityPage) {
  const parts = ["\uFEFF", csvRow(headings)];
  let cursor = null;
  do {
    const page = await getPage(month, cursor);
    for (const item of page.items) {
      const inbound = item.direction === "inbound";
      parts.push(csvRow([
        new Date(item.updated_at).toISOString(), inbound ? "Inbound" : "Outbound",
        displayNumber(item.sender), displayNumber(item.recipient), item.name,
        inbound ? "Received" : "Delivered", item.pages,
        Number.isInteger(item.pages) ? "Confirmed" : "Pending", item.id,
      ]));
    }
    cursor = page.next;
  } while (cursor);
  return new Blob(parts, { type: "text/csv;charset=utf-8" });
}
