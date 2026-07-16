import assert from "node:assert/strict";

import {
  buildKorlixLiveDocsReportPrompt,
  createKorlixLiveDocsArtifacts,
  normalizeKorlixLiveDocsFormats,
  parseKorlixLiveDocsReportJson,
} from "./korlix_live_docs_generation.js";

const prompt = buildKorlixLiveDocsReportPrompt({
  title: "December 2024 Audit Report",
  instructions:
    "Create an executive audit report with exact figures.",
  brief: {
    audience: "Executive leadership",
    tone: "Professional and concise",
    requiredSections: [
      "Executive Summary",
      "Findings",
      "Recommendations",
    ],
  },
  sourceDossier:
    "Dec2024_audits.xlsx reports 14 open findings. " +
    "imagined-picture.png shows a blue control-room dashboard.",
  sourceFiles: [
    "Dec2024_audits.xlsx",
    "imagined-picture.png",
  ],
  formats: ["xlsx", "docx", "pdf"],
  language: "English",
});

assert.match(prompt, /untrusted source dossier/i);
assert.match(prompt, /Do not invent/i);
assert.match(prompt, /Dec2024_audits\.xlsx/);

const report = parseKorlixLiveDocsReportJson(
  JSON.stringify({
    title: "December 2024 Audit Report",
    subtitle: "Executive review",
    audience: "Executive leadership",
    executiveSummary:
      "Fourteen open findings require prioritized remediation.",
    metrics: [
      {
        label: "Open findings",
        value: "14",
        context: "December audit workbook",
        source: "Dec2024_audits.xlsx",
      },
    ],
    findings: [
      {
        title: "Open audit findings",
        severity: "high",
        evidence:
          "The source dossier reports 14 open findings.",
        implication:
          "Delayed remediation increases exposure.",
        recommendation:
          "Assign owners and target dates to every finding.",
        source: "Dec2024_audits.xlsx",
      },
    ],
    sections: [
      {
        heading: "Audit Overview",
        paragraphs: [
          "The report consolidates the processed sources.",
        ],
        bullets: ["Prioritize high-risk items."],
        table: {
          title: "Finding Summary",
          columns: ["Category", "Count"],
          rows: [["Open", "14"]],
        },
      },
    ],
    recommendations: [
      "Create a weekly remediation dashboard.",
    ],
    nextSteps: ["Assign accountable owners."],
    assumptions: [
      "The source dossier accurately reflects the workbook.",
    ],
    limitations: [
      "Only processed source content was used.",
    ],
    sourceFiles: [
      "Dec2024_audits.xlsx",
      "imagined-picture.png",
    ],
  }),
);

assert.equal(report.title, "December 2024 Audit Report");
assert.equal(report.findings.length, 1);
assert.equal(report.metrics[0].value, "14");

assert.deepEqual(
  normalizeKorlixLiveDocsFormats([
    "xlsx",
    "docx",
    "pdf",
    "xlsx",
    "invalid",
  ]),
  ["xlsx", "docx", "pdf"],
);

const generated = await createKorlixLiveDocsArtifacts({
  report,
  formats: ["xlsx", "docx", "pdf"],
  sourceFiles: [],
  sourceDossier:
    "Processed source dossier used for deterministic tests.",
});

assert.equal(generated.artifacts.length, 3);

const byFormat = Object.fromEntries(
  generated.artifacts.map((artifact) => [
    artifact.format,
    artifact,
  ]),
);

const xlsxBytes = Buffer.from(
  byFormat.xlsx.contentBase64,
  "base64",
);

const docxBytes = Buffer.from(
  byFormat.docx.contentBase64,
  "base64",
);

const pdfBytes = Buffer.from(
  byFormat.pdf.contentBase64,
  "base64",
);

assert.equal(
  xlsxBytes.subarray(0, 2).toString("utf8"),
  "PK",
);

assert.equal(
  docxBytes.subarray(0, 2).toString("utf8"),
  "PK",
);

assert.equal(
  pdfBytes.subarray(0, 4).toString("utf8"),
  "%PDF",
);

assert.ok(byFormat.xlsx.byteLength > 1000);
assert.ok(byFormat.docx.byteLength > 1000);
assert.ok(byFormat.pdf.byteLength > 1000);

console.log("KORLIX_LIVE_DOCS_GENERATOR_TEST_PASS=true");
console.log(`XLSX_BYTES=${byFormat.xlsx.byteLength}`);
console.log(`DOCX_BYTES=${byFormat.docx.byteLength}`);
console.log(`PDF_BYTES=${byFormat.pdf.byteLength}`);
