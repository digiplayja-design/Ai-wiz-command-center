import assert from "node:assert/strict";
import ExcelJS from "exceljs";

import {
  analyzeKorlixTechnicianAuditFiles,
  tryCreateKorlixTechnicianAuditArtifacts,
} from "./korlix_live_docs_audit.js";

const technicianCounts = new Map([
  ["Aly Halaoui", 2],
  ["Anthony Williams", 2],
  ["Bernard Holloway", 1],
  ["Derek Jackson", 1],
  ["Dylan Saucer", 1],
  ["Gilberto Grimaldo", 1],
  ["Issa Hijazin", 1],
  ["Kevin McKenzie", 1],
  ["Marcus McCormick", 2],
  ["Michael Novotni", 2],
  ["Stacy Layne", 2],
  ["Zacharie Jones", 1],
]);

const sourceWorkbook = new ExcelJS.Workbook();
const sourceSheet = sourceWorkbook.addWorksheet("December 2024 Audits");
sourceSheet.addRow([
  "Audit ID",
  "Installation Technician",
  "Final Audit Result",
  "Completed Date",
]);
let auditId = 1;
for (const [technician, count] of technicianCounts) {
  for (let index = 0; index < count; index += 1) {
    sourceSheet.addRow([
      `AUD-${String(auditId).padStart(3, "0")}`,
      technician,
      "Pass",
      `2024-12-${String(((auditId - 1) % 28) + 1).padStart(2, "0")}`,
    ]);
    auditId += 1;
  }
}

const sourceBuffer = Buffer.from(await sourceWorkbook.xlsx.writeBuffer());
const sourceFiles = [
  {
    originalname: "Dec2024_audits.xlsx",
    mimetype: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    buffer: sourceBuffer,
  },
];

const analysis = await analyzeKorlixTechnicianAuditFiles(sourceFiles);
assert.ok(analysis, "audit spreadsheet should be recognized");
assert.equal(analysis.reportType, "technician_audit_summary");
assert.equal(analysis.totalAudits, 17);
assert.equal(analysis.outcomeCounts.Pass, 17);
assert.equal(analysis.outcomeCounts.Fail, 0);
assert.equal(analysis.outcomeCounts["Needs Improvement"], 0);
assert.equal(analysis.outcomePercentages.Pass, 1);
assert.equal(analysis.outcomePercentages.Fail, 0);
assert.equal(analysis.outcomePercentages["Needs Improvement"], 0);
assert.equal(analysis.distinctTechnicians, 12);
assert.equal(
  analysis.technicianBreakdown.reduce((sum, entry) => sum + entry.total, 0),
  17,
);
assert.equal(
  Object.values(analysis.outcomeCounts).reduce((sum, value) => sum + value, 0),
  17,
);
assert.equal(
  analysis.technicianBreakdown.find(
    (entry) => entry.technician === "Kevin McKenzie",
  )?.total,
  1,
);

const generated = await tryCreateKorlixTechnicianAuditArtifacts({
  sourceFiles,
  formats: ["xlsx", "docx", "pdf"],
  title: "December 2024 Technician Audit Summary",
  instructions: "Create an internal technician audit summary.",
  brief: {
    audience: "Internal operations",
    tone: "Professional",
    allow_web_research: false,
  },
});
assert.ok(generated?.deterministic);
assert.deepEqual(
  generated.artifacts.map((artifact) => artifact.format),
  ["xlsx", "docx", "pdf"],
);
for (const artifact of generated.artifacts) {
  assert.ok(artifact.byteLength > 500, `${artifact.format} artifact should contain real bytes`);
  assert.ok(artifact.contentBase64.length > 500);
}

const xlsxArtifact = generated.artifacts.find((artifact) => artifact.format === "xlsx");
const resultWorkbook = new ExcelJS.Workbook();
await resultWorkbook.xlsx.load(Buffer.from(xlsxArtifact.contentBase64, "base64"));
assert.deepEqual(
  resultWorkbook.worksheets.map((sheet) => sheet.name),
  ["Summary", "Technician Breakdown", "Audit Results", "Raw Data"],
);
assert.equal(resultWorkbook.getWorksheet("Audit Results").rowCount, 20);
assert.equal(resultWorkbook.getWorksheet("Raw Data").rowCount, 18);

console.log("KORLIX_LIVE_DOCS_AUDIT_TEST_PASS=true");
console.log("EXPECTED_TOTAL_AUDITS=17");
console.log("EXPECTED_PASS_AUDITS=17");
console.log("EXPECTED_DISTINCT_TECHNICIANS=12");
console.log("EXPECTED_KEVIN_MCKENZIE_AUDITS=1");
