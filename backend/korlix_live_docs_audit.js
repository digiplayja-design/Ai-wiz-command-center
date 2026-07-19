// KORLIX_LIVE_DOCS_DETERMINISTIC_AUDIT_BUILD131_BEGIN
import ExcelJS from "exceljs";
import {
  AlignmentType,
  Document,
  HeadingLevel,
  Packer,
  Paragraph,
  Table,
  TableCell,
  TableRow,
  TextRun,
  WidthType,
} from "docx";
import { PDFDocument, StandardFonts, rgb } from "pdf-lib";

const OUTCOMES = Object.freeze([
  "Pass",
  "Fail",
  "Needs Improvement",
]);

function clean(value, max = 10000) {
  const text = String(value ?? "").trim();
  return text.length <= max ? text : text.slice(0, max);
}

function normalizedHeader(value) {
  return clean(value, 300)
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function cellText(cellOrValue) {
  const value =
    cellOrValue && typeof cellOrValue === "object" && "value" in cellOrValue
      ? cellOrValue.value
      : cellOrValue;

  if (value == null) return "";
  if (value instanceof Date) return value.toISOString();
  if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
    return String(value).trim();
  }
  if (Array.isArray(value?.richText)) {
    return value.richText.map((part) => clean(part?.text, 1000)).join("").trim();
  }
  if (value?.result != null) return cellText(value.result);
  if (value?.text != null) return clean(value.text, 10000);
  if (value?.hyperlink != null) return clean(value.text || value.hyperlink, 10000);
  return clean(value, 10000);
}

function headerScore(header, kind) {
  const normalized = normalizedHeader(header);
  if (!normalized) return 0;

  if (kind === "technician") {
    const exact = new Map([
      ["installation technician", 100],
      ["install technician", 98],
      ["technician name", 96],
      ["technician", 94],
      ["installer name", 92],
      ["installer", 90],
      ["tech name", 88],
      ["tech", 75],
    ]);
    if (exact.has(normalized)) return exact.get(normalized);
    if (normalized.includes("technician")) return 85;
    if (normalized.includes("installer")) return 82;
    if (/\btech\b/.test(normalized)) return 70;
    return 0;
  }

  const exact = new Map([
    ["final audit result", 100],
    ["final audit outcome", 99],
    ["audit result", 97],
    ["audit outcome", 96],
    ["final result", 94],
    ["final outcome", 93],
    ["result", 82],
    ["outcome", 81],
    ["audit status", 78],
  ]);
  if (exact.has(normalized)) return exact.get(normalized);
  if (normalized.includes("audit") && normalized.includes("result")) return 91;
  if (normalized.includes("audit") && normalized.includes("outcome")) return 90;
  if (normalized.includes("final") && normalized.includes("result")) return 88;
  return 0;
}

function normalizeOutcome(value) {
  const normalized = normalizedHeader(value);
  if (!normalized) return null;

  if (/^(pass|passed|successful|success|meets expectations)$/.test(normalized)) {
    return "Pass";
  }
  if (/^(fail|failed|failure|unsuccessful|does not meet expectations)$/.test(normalized)) {
    return "Fail";
  }
  if (
    /^(needs improvement|need improvement|improvement needed|requires improvement|needs attention|ni)$/.test(
      normalized,
    )
  ) {
    return "Needs Improvement";
  }
  return null;
}

function sourceName(file, index) {
  return clean(file?.originalname || file?.name || file?.displayName, 300) || `Source ${index + 1}`;
}

function sourceMime(file) {
  return clean(file?.mimetype || file?.mimeType, 200).toLowerCase();
}

function sourceBuffer(file) {
  const value = file?.buffer ?? file?.bytes;
  if (Buffer.isBuffer(value)) return value;
  if (value instanceof Uint8Array) return Buffer.from(value);
  if (typeof file?.contentBase64 === "string" && file.contentBase64.trim()) {
    return Buffer.from(file.contentBase64, "base64");
  }
  return null;
}

function isSpreadsheetSource(file) {
  const name = sourceName(file, 0).toLowerCase();
  const mime = sourceMime(file);
  return (
    name.endsWith(".xlsx") ||
    name.endsWith(".xlsm") ||
    mime.includes("spreadsheet") ||
    mime.includes("excel")
  );
}

function bestHeaderCandidate(worksheet) {
  let best = null;
  const maxRows = Math.min(Math.max(worksheet.rowCount, 1), 30);

  for (let rowNumber = 1; rowNumber <= maxRows; rowNumber += 1) {
    const row = worksheet.getRow(rowNumber);
    const values = [];
    const maxColumns = Math.max(worksheet.columnCount, row.cellCount, 1);

    for (let column = 1; column <= maxColumns; column += 1) {
      values.push(cellText(row.getCell(column)));
    }

    let technician = { index: -1, score: 0 };
    let outcome = { index: -1, score: 0 };

    values.forEach((value, index) => {
      const technicianScore = headerScore(value, "technician");
      const outcomeScore = headerScore(value, "outcome");
      if (technicianScore > technician.score) technician = { index, score: technicianScore };
      if (outcomeScore > outcome.score) outcome = { index, score: outcomeScore };
    });

    if (technician.index < 0 || outcome.index < 0 || technician.index === outcome.index) continue;

    const combined = technician.score + outcome.score - rowNumber * 0.05;
    if (!best || combined > best.score) {
      best = {
        rowNumber,
        headers: values.map((value, index) => clean(value, 300) || `Column ${index + 1}`),
        technicianColumn: technician.index + 1,
        outcomeColumn: outcome.index + 1,
        score: combined,
      };
    }
  }

  return best && best.score >= 150 ? best : null;
}

function rowRawValues(row, width) {
  const values = [];
  for (let column = 1; column <= width; column += 1) {
    values.push(cellText(row.getCell(column)));
  }
  return values;
}

function percentage(count, total) {
  return total > 0 ? count / total : 0;
}

function technicianSort(left, right) {
  return left.technician.localeCompare(right.technician, "en", {
    sensitivity: "base",
  });
}

export async function analyzeKorlixTechnicianAuditFiles(sourceFiles = []) {
  const spreadsheetFiles = sourceFiles.filter(
    (file) => isSpreadsheetSource(file) && sourceBuffer(file),
  );
  if (!spreadsheetFiles.length) return null;

  const auditRows = [];
  const rawRows = [];
  const rawHeaders = new Set(["Source File", "Source Sheet", "Source Row"]);
  let recognizedWorkbookCount = 0;

  for (let fileIndex = 0; fileIndex < spreadsheetFiles.length; fileIndex += 1) {
    const file = spreadsheetFiles[fileIndex];
    const workbook = new ExcelJS.Workbook();

    try {
      await workbook.xlsx.load(sourceBuffer(file));
    } catch {
      continue;
    }

    for (const worksheet of workbook.worksheets) {
      const candidate = bestHeaderCandidate(worksheet);
      if (!candidate) continue;

      const dataRows = [];
      const width = Math.max(candidate.headers.length, worksheet.columnCount);
      for (const header of candidate.headers) rawHeaders.add(header);

      let invalidOutcomeFound = false;

      for (
        let rowNumber = candidate.rowNumber + 1;
        rowNumber <= worksheet.rowCount;
        rowNumber += 1
      ) {
        const row = worksheet.getRow(rowNumber);
        const rawValues = rowRawValues(row, width);
        if (!rawValues.some((value) => clean(value))) continue;

        const technician = clean(row.getCell(candidate.technicianColumn), 300);
        const rawOutcome = clean(row.getCell(candidate.outcomeColumn), 300);

        if (!technician && !rawOutcome) continue;
        if (!technician || !rawOutcome) continue;

        const outcome = normalizeOutcome(rawOutcome);
        if (!outcome) {
          invalidOutcomeFound = true;
          break;
        }

        const raw = {};
        candidate.headers.forEach((header, index) => {
          raw[header] = rawValues[index] ?? "";
        });

        dataRows.push({
          technician,
          outcome,
          rawOutcome,
          sourceFile: sourceName(file, fileIndex),
          sourceSheet: worksheet.name,
          sourceRow: rowNumber,
          raw,
        });
      }

      if (invalidOutcomeFound || !dataRows.length) continue;

      recognizedWorkbookCount += 1;
      for (const row of dataRows) {
        auditRows.push({
          auditNumber: auditRows.length + 1,
          ...row,
        });
        rawRows.push(row);
      }
    }
  }

  if (!recognizedWorkbookCount || !auditRows.length) return null;

  const outcomeCounts = {
    Pass: 0,
    Fail: 0,
    "Needs Improvement": 0,
  };
  const technicians = new Map();

  for (const row of auditRows) {
    outcomeCounts[row.outcome] += 1;
    const key = row.technician.trim();
    const existing = technicians.get(key) || {
      technician: key,
      total: 0,
      Pass: 0,
      Fail: 0,
      "Needs Improvement": 0,
    };
    existing.total += 1;
    existing[row.outcome] += 1;
    technicians.set(key, existing);
  }

  const totalAudits = auditRows.length;
  const technicianBreakdown = [...technicians.values()]
    .map((entry) => ({
      technician: entry.technician,
      total: entry.total,
      pass: entry.Pass,
      fail: entry.Fail,
      needsImprovement: entry["Needs Improvement"],
      passPercentage: percentage(entry.Pass, entry.total),
    }))
    .sort(technicianSort);

  const outcomeTotal = OUTCOMES.reduce((sum, outcome) => sum + outcomeCounts[outcome], 0);
  const technicianTotal = technicianBreakdown.reduce((sum, entry) => sum + entry.total, 0);

  if (outcomeTotal !== totalAudits || technicianTotal !== totalAudits) {
    throw new Error("Deterministic technician-audit totals failed validation.");
  }

  return {
    reportType: "technician_audit_summary",
    totalAudits,
    outcomeCounts,
    outcomePercentages: {
      Pass: percentage(outcomeCounts.Pass, totalAudits),
      Fail: percentage(outcomeCounts.Fail, totalAudits),
      "Needs Improvement": percentage(outcomeCounts["Needs Improvement"], totalAudits),
    },
    distinctTechnicians: technicianBreakdown.length,
    technicianBreakdown,
    auditRows,
    rawHeaders: [...rawHeaders],
    rawRows,
    sourceFiles: spreadsheetFiles.map(sourceName),
    validated: true,
  };
}

function normalizedFormats(formats) {
  const requested = Array.isArray(formats) ? formats : [formats];
  const valid = [];
  for (const item of requested) {
    const value = clean(item, 20).toLowerCase();
    if (["xlsx", "docx", "pdf"].includes(value) && !valid.includes(value)) valid.push(value);
  }
  return valid.length ? valid : ["xlsx", "docx", "pdf"];
}

function reportTitle(title) {
  return clean(title, 300) || "Technician Audit Summary";
}

function deterministicReport({ analysis, title, brief, sourceFiles }) {
  const pass = analysis.outcomeCounts.Pass;
  const fail = analysis.outcomeCounts.Fail;
  const needsImprovement = analysis.outcomeCounts["Needs Improvement"];
  const sourceNames = sourceFiles.map(sourceName);

  return {
    reportType: "technician_audit_summary",
    title: reportTitle(title),
    subtitle: "Deterministic operational audit report",
    audience: clean(brief?.audience, 300) || "Internal operations",
    executiveSummary:
      `${analysis.totalAudits} audits were analyzed across ` +
      `${analysis.distinctTechnicians} technicians. ` +
      `${pass} passed, ${fail} failed, and ${needsImprovement} need improvement.`,
    metrics: [
      { label: "Total Audits", value: analysis.totalAudits },
      { label: "Pass", value: pass },
      { label: "Fail", value: fail },
      { label: "Needs Improvement", value: needsImprovement },
      { label: "Distinct Technicians", value: analysis.distinctTechnicians },
    ],
    findings: [],
    sections: [],
    recommendations: [],
    nextSteps: [],
    assumptions: [],
    limitations: [
      "Counts are calculated directly from recognized technician and final audit-result spreadsheet columns.",
    ],
    sourceFiles: sourceNames,
    generatedAt: new Date().toISOString(),
    deterministicAnalysis: analysis,
  };
}

const COLORS = Object.freeze({
  navy: "071722",
  cyan: "21D4F4",
  aqua: "62D6A7",
  magenta: "E93FEA",
  gold: "F2C14E",
  white: "F0F7F8",
  pale: "E8F1F4",
  gray: "62727B",
  red: "FF5A6E",
  amber: "F5A623",
});

function applyTitleRow(row, height = 28) {
  row.height = height;
  row.eachCell((cell) => {
    cell.font = { bold: true, size: 18, color: { argb: `FF${COLORS.white}` } };
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: `FF${COLORS.navy}` } };
    cell.alignment = { vertical: "middle", horizontal: "left" };
  });
}

function applyHeaderRow(row) {
  row.height = 23;
  row.eachCell((cell) => {
    cell.font = { bold: true, color: { argb: `FF${COLORS.navy}` } };
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: `FF${COLORS.cyan}` } };
    cell.alignment = { vertical: "middle", horizontal: "center", wrapText: true };
    cell.border = {
      top: { style: "thin", color: { argb: "FF9EBCC6" } },
      left: { style: "thin", color: { argb: "FF9EBCC6" } },
      bottom: { style: "thin", color: { argb: "FF9EBCC6" } },
      right: { style: "thin", color: { argb: "FF9EBCC6" } },
    };
  });
}

function applyBodyBorders(row) {
  row.eachCell((cell) => {
    cell.alignment = { vertical: "top", wrapText: true };
    cell.border = {
      top: { style: "hair", color: { argb: "FFD5E0E4" } },
      left: { style: "hair", color: { argb: "FFD5E0E4" } },
      bottom: { style: "hair", color: { argb: "FFD5E0E4" } },
      right: { style: "hair", color: { argb: "FFD5E0E4" } },
    };
  });
}

function applyOutcomeCell(cell, outcome) {
  const color =
    outcome === "Pass" ? COLORS.aqua : outcome === "Fail" ? COLORS.red : COLORS.amber;
  cell.font = { bold: true, color: { argb: `FF${COLORS.navy}` } };
  cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: `FF${color}` } };
  cell.alignment = { horizontal: "center", vertical: "middle" };
}

async function xlsxArtifact({ analysis, report }) {
  const workbook = new ExcelJS.Workbook();
  workbook.creator = "Korlix LIVE DOCS";
  workbook.created = new Date(report.generatedAt);
  workbook.modified = new Date(report.generatedAt);

  const summary = workbook.addWorksheet("Summary", {
    views: [{ state: "frozen", ySplit: 6 }],
  });
  summary.mergeCells("A1:C1");
  summary.getCell("A1").value = report.title;
  applyTitleRow(summary.getRow(1));
  summary.getCell("A2").value = report.subtitle;
  summary.getCell("A3").value = `Audience: ${report.audience}`;
  summary.getCell("A4").value = `Generated: ${report.generatedAt}`;
  summary.getCell("A5").value = `Sources: ${report.sourceFiles.join(", ") || "Submitted workbook"}`;
  summary.addRow(["Metric", "Count", "Percentage"]);
  applyHeaderRow(summary.getRow(6));
  const summaryRows = [
    ["Total Audits", analysis.totalAudits, null],
    ["Pass", analysis.outcomeCounts.Pass, analysis.outcomePercentages.Pass],
    ["Fail", analysis.outcomeCounts.Fail, analysis.outcomePercentages.Fail],
    [
      "Needs Improvement",
      analysis.outcomeCounts["Needs Improvement"],
      analysis.outcomePercentages["Needs Improvement"],
    ],
    ["Distinct Technicians", analysis.distinctTechnicians, null],
  ];
  for (const values of summaryRows) {
    const row = summary.addRow(values);
    applyBodyBorders(row);
    if (typeof values[2] === "number") row.getCell(3).numFmt = "0.0%";
    if (OUTCOMES.includes(values[0])) applyOutcomeCell(row.getCell(1), values[0]);
  }
  summary.autoFilter = { from: "A6", to: "C11" };
  summary.columns = [{ width: 28 }, { width: 14 }, { width: 16 }];

  const technicians = workbook.addWorksheet("Technician Breakdown", {
    views: [{ state: "frozen", ySplit: 3 }],
  });
  technicians.mergeCells("A1:F1");
  technicians.getCell("A1").value = `${report.title} — Technician Breakdown`;
  applyTitleRow(technicians.getRow(1));
  technicians.addRow([]);
  technicians.addRow([
    "Technician",
    "Total Audits",
    "Pass",
    "Fail",
    "Needs Improvement",
    "Pass Percentage",
  ]);
  applyHeaderRow(technicians.getRow(3));
  for (const entry of analysis.technicianBreakdown) {
    const row = technicians.addRow([
      entry.technician,
      entry.total,
      entry.pass,
      entry.fail,
      entry.needsImprovement,
      entry.passPercentage,
    ]);
    row.getCell(6).numFmt = "0.0%";
    applyBodyBorders(row);
  }
  technicians.autoFilter = { from: "A3", to: `F${technicians.rowCount}` };
  technicians.columns = [
    { width: 28 },
    { width: 15 },
    { width: 11 },
    { width: 11 },
    { width: 20 },
    { width: 18 },
  ];

  const results = workbook.addWorksheet("Audit Results", {
    views: [{ state: "frozen", ySplit: 3 }],
  });
  results.mergeCells("A1:F1");
  results.getCell("A1").value = `${report.title} — Audit Results`;
  applyTitleRow(results.getRow(1));
  results.addRow([]);
  results.addRow([
    "Audit #",
    "Technician",
    "Final Audit Result",
    "Source File",
    "Source Sheet",
    "Source Row",
  ]);
  applyHeaderRow(results.getRow(3));
  for (const entry of analysis.auditRows) {
    const row = results.addRow([
      entry.auditNumber,
      entry.technician,
      entry.outcome,
      entry.sourceFile,
      entry.sourceSheet,
      entry.sourceRow,
    ]);
    applyBodyBorders(row);
    applyOutcomeCell(row.getCell(3), entry.outcome);
  }
  results.autoFilter = { from: "A3", to: `F${results.rowCount}` };
  results.columns = [
    { width: 11 },
    { width: 28 },
    { width: 22 },
    { width: 28 },
    { width: 24 },
    { width: 12 },
  ];

  const raw = workbook.addWorksheet("Raw Data", {
    views: [{ state: "frozen", ySplit: 1 }],
  });
  const rawHeaders = analysis.rawHeaders;
  raw.addRow(rawHeaders);
  applyHeaderRow(raw.getRow(1));
  for (const entry of analysis.rawRows) {
    const rowObject = {
      "Source File": entry.sourceFile,
      "Source Sheet": entry.sourceSheet,
      "Source Row": entry.sourceRow,
      ...entry.raw,
    };
    const row = raw.addRow(rawHeaders.map((header) => rowObject[header] ?? ""));
    applyBodyBorders(row);
  }
  const lastRawColumn = raw.getColumn(rawHeaders.length).letter;
  raw.autoFilter = { from: "A1", to: `${lastRawColumn}${raw.rowCount}` };
  raw.columns = rawHeaders.map((header) => ({
    width: Math.min(42, Math.max(14, header.length + 4)),
  }));

  const buffer = Buffer.from(await workbook.xlsx.writeBuffer());
  return {
    format: "xlsx",
    fileName: `${safeStem(report.title)}.xlsx`,
    mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    byteLength: buffer.length,
    contentBase64: buffer.toString("base64"),
  };
}

function docxText(text, options = {}) {
  return new TextRun({ text: clean(text, 20000), size: 21, ...options });
}

function docxCell(text, { bold = false } = {}) {
  return new TableCell({
    children: [
      new Paragraph({
        children: [docxText(text, { bold })],
        spacing: { after: 0 },
      }),
    ],
  });
}

async function docxArtifact({ analysis, report }) {
  const outcomeRows = OUTCOMES.map(
    (outcome) =>
      new TableRow({
        children: [
          docxCell(outcome, { bold: true }),
          docxCell(String(analysis.outcomeCounts[outcome])),
          docxCell(`${(analysis.outcomePercentages[outcome] * 100).toFixed(1)}%`),
        ],
      }),
  );
  const technicianRows = analysis.technicianBreakdown.map(
    (entry) =>
      new TableRow({
        children: [
          docxCell(entry.technician),
          docxCell(String(entry.total)),
          docxCell(String(entry.pass)),
          docxCell(String(entry.fail)),
          docxCell(String(entry.needsImprovement)),
        ],
      }),
  );

  const document = new Document({
    sections: [
      {
        properties: {
          page: {
            margin: { top: 540, right: 540, bottom: 540, left: 540 },
          },
        },
        children: [
          new Paragraph({
            heading: HeadingLevel.TITLE,
            alignment: AlignmentType.CENTER,
            children: [docxText(report.title, { bold: true, size: 34 })],
          }),
          new Paragraph({
            alignment: AlignmentType.CENTER,
            children: [docxText(`Prepared for ${report.audience}`, { italics: true })],
            spacing: { after: 180 },
          }),
          new Paragraph({
            heading: HeadingLevel.HEADING_1,
            children: [docxText("Operational Summary", { bold: true, size: 26 })],
          }),
          new Paragraph({
            children: [docxText(report.executiveSummary)],
            spacing: { after: 140 },
          }),
          new Table({
            width: { size: 100, type: WidthType.PERCENTAGE },
            rows: [
              new TableRow({
                children: [
                  docxCell("Outcome", { bold: true }),
                  docxCell("Count", { bold: true }),
                  docxCell("Percentage", { bold: true }),
                ],
              }),
              ...outcomeRows,
            ],
          }),
          new Paragraph({
            heading: HeadingLevel.HEADING_1,
            children: [docxText("Technician Breakdown", { bold: true, size: 26 })],
            spacing: { before: 180 },
          }),
          new Table({
            width: { size: 100, type: WidthType.PERCENTAGE },
            rows: [
              new TableRow({
                children: [
                  docxCell("Technician", { bold: true }),
                  docxCell("Total", { bold: true }),
                  docxCell("Pass", { bold: true }),
                  docxCell("Fail", { bold: true }),
                  docxCell("Needs Improvement", { bold: true }),
                ],
              }),
              ...technicianRows,
            ],
          }),
          new Paragraph({
            children: [
              docxText(
                "Counts and percentages were calculated directly from the submitted spreadsheet rows. Review this report before consequential use.",
                { italics: true, size: 18 },
              ),
            ],
            spacing: { before: 180 },
          }),
        ],
      },
    ],
  });

  const buffer = await Packer.toBuffer(document);
  return {
    format: "docx",
    fileName: `${safeStem(report.title)}.docx`,
    mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    byteLength: buffer.length,
    contentBase64: buffer.toString("base64"),
  };
}

function safeStem(value) {
  const stem = clean(value, 160)
    .replace(/[^a-z0-9]+/gi, "-")
    .replace(/^-+|-+$/g, "")
    .toLowerCase();
  return stem || "korlix-live-docs-report";
}

function wrapText(text, font, size, maxWidth) {
  const words = clean(text, 30000).split(/\s+/).filter(Boolean);
  const lines = [];
  let line = "";
  for (const word of words) {
    const next = line ? `${line} ${word}` : word;
    if (font.widthOfTextAtSize(next, size) <= maxWidth) {
      line = next;
    } else {
      if (line) lines.push(line);
      line = word;
    }
  }
  if (line) lines.push(line);
  return lines;
}

async function pdfArtifact({ analysis, report }) {
  const pdf = await PDFDocument.create();
  const regular = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const italic = await pdf.embedFont(StandardFonts.HelveticaOblique);
  const pageSize = [612, 792];
  const margin = 46;
  const maxWidth = pageSize[0] - margin * 2;
  let page = pdf.addPage(pageSize);
  let y = 742;

  const newPage = () => {
    page = pdf.addPage(pageSize);
    y = 742;
  };

  const line = (text, { font = regular, size = 10, gap = 4, indent = 0 } = {}) => {
    const lines = wrapText(text, font, size, maxWidth - indent);
    for (const value of lines) {
      if (y < 52) newPage();
      page.drawText(value, {
        x: margin + indent,
        y,
        size,
        font,
        color: rgb(0.06, 0.12, 0.16),
      });
      y -= size + gap;
    }
  };

  line(report.title, { font: bold, size: 20, gap: 7 });
  line(`Prepared for ${report.audience}`, { font: italic, size: 10, gap: 7 });
  y -= 5;
  line("Operational Summary", { font: bold, size: 14, gap: 6 });
  line(report.executiveSummary, { size: 10, gap: 5 });
  y -= 6;
  line("Audit Outcomes", { font: bold, size: 14, gap: 6 });
  for (const outcome of OUTCOMES) {
    line(
      `${outcome}: ${analysis.outcomeCounts[outcome]} (${(
        analysis.outcomePercentages[outcome] * 100
      ).toFixed(1)}%)`,
      { size: 10, gap: 4, indent: 10 },
    );
  }
  y -= 6;
  line("Technician Breakdown", { font: bold, size: 14, gap: 6 });
  for (const entry of analysis.technicianBreakdown) {
    line(
      `${entry.technician}: ${entry.total} total; ${entry.pass} Pass; ${entry.fail} Fail; ${entry.needsImprovement} Needs Improvement`,
      { size: 9.5, gap: 4, indent: 10 },
    );
  }
  y -= 8;
  line(
    "Counts and percentages were calculated directly from the submitted spreadsheet rows. Review this report before consequential use.",
    { font: italic, size: 8.5, gap: 4 },
  );

  const buffer = Buffer.from(await pdf.save());
  return {
    format: "pdf",
    fileName: `${safeStem(report.title)}.pdf`,
    mimeType: "application/pdf",
    byteLength: buffer.length,
    contentBase64: buffer.toString("base64"),
  };
}

export async function createKorlixTechnicianAuditArtifacts({
  analysis,
  formats,
  title,
  brief = {},
  sourceFiles = [],
}) {
  if (!analysis?.validated || analysis.reportType !== "technician_audit_summary") {
    throw new Error("A validated technician-audit analysis is required.");
  }

  const report = deterministicReport({ analysis, title, brief, sourceFiles });
  const artifacts = [];
  for (const format of normalizedFormats(formats)) {
    if (format === "xlsx") artifacts.push(await xlsxArtifact({ analysis, report }));
    if (format === "docx") artifacts.push(await docxArtifact({ analysis, report }));
    if (format === "pdf") artifacts.push(await pdfArtifact({ analysis, report }));
  }
  return { report, artifacts, analysis, deterministic: true };
}

export async function tryCreateKorlixTechnicianAuditArtifacts({
  sourceFiles = [],
  formats = [],
  title = "",
  instructions = "",
  brief = {},
}) {
  const analysis = await analyzeKorlixTechnicianAuditFiles(sourceFiles);
  if (!analysis) return null;

  const request = `${clean(title, 1000)} ${clean(instructions, 12000)} ${clean(
    brief?.goal,
    12000,
  )}`.toLowerCase();

  const requestLooksRelevant =
    request.includes("audit") ||
    request.includes("technician") ||
    request.includes("installer") ||
    analysis.totalAudits > 0;

  if (!requestLooksRelevant) return null;
  return createKorlixTechnicianAuditArtifacts({
    analysis,
    formats,
    title,
    brief,
    sourceFiles,
  });
}
// KORLIX_LIVE_DOCS_DETERMINISTIC_AUDIT_BUILD131_END
