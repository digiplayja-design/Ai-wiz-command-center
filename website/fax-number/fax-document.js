const sendLimit = 8 * 1024 * 1024,
  receiveLimit = 50 * 1024 * 1024;
let engine, writer;
async function renderer() {
  if (!engine)
    engine = import("./assets/pdf.min.mjs")
      .then((lib) => {
        lib.GlobalWorkerOptions.workerSrc = new URL(
          "./assets/pdf.worker.min.mjs",
          import.meta.url,
        ).href;
        return lib;
      })
      .catch((error) => {
        engine = null;
        throw error;
      });
  return engine;
}
async function pdfWriter() {
  if (!writer)
    writer = new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = new URL("./assets/pdf-lib.min.js", import.meta.url).href;
      script.onload = () => resolve(window.PDFLib);
      script.onerror = () => {
        writer = null;
        reject(Error("Could not load the PDF tools."));
      };
      document.head.append(script);
    });
  return writer;
}
export function clearDoc(doc) {
  if (doc?.pdf) doc.pdf.destroy().catch(() => {});
  if (doc?.url) URL.revokeObjectURL(doc.url);
}
export async function readPdf(file, received = false) {
  if (
    !file ||
    file.size < 5 ||
    file.size > (received ? receiveLimit : sendLimit)
  )
    throw Error(
      received
        ? "This PDF exceeds the 50 MB viewing limit."
        : "Choose a PDF up to 8 MB.",
    );
  const lib = await renderer();
  const bytes = new Uint8Array(await file.arrayBuffer());
  let pdf;
  try {
    pdf = await lib.getDocument({
      data: bytes,
      isEvalSupported: false,
      useSystemFonts: true,
    }).promise;
  } catch (err) {
    throw Error(
      err.name === "PasswordException"
        ? "Unlock the PDF before using it here."
        : "This PDF could not be opened. Choose another file.",
    );
  }
  const doc = {
    file,
    pdf,
    name: file.name || "Document.pdf",
    pages: pdf.numPages,
    images: new Map(),
    url: URL.createObjectURL(file),
  };
  try {
    await pageImage(doc, 0);
    return doc;
  } catch (e) {
    clearDoc(doc);
    throw e;
  }
}
export async function pageImage(doc, index) {
  if (doc.images.has(index)) return doc.images.get(index);
  const page = await doc.pdf.getPage(index + 1);
  const natural = page.getViewport({ scale: 1 });
  const view = page.getViewport({
    scale: Math.min(1.5, 900 / natural.width, 1400 / natural.height),
  });
  const canvas = document.createElement("canvas");
  canvas.width = Math.ceil(view.width);
  canvas.height = Math.ceil(view.height);
  await page.render({ canvasContext: canvas.getContext("2d"), viewport: view })
    .promise;
  const img = canvas.toDataURL("image/jpeg", 0.85);
  page.cleanup();
  canvas.width = canvas.height = 0;
  if (doc.images.size >= 4) {
    const oldest = [...doc.images.keys()].find((i) => i !== 0);
    if (oldest !== undefined) doc.images.delete(oldest);
  }
  doc.images.set(index, img);
  return img;
}
async function jpegPage(file) {
  if (file.size > 32 * 1024 * 1024)
    throw Error("Choose a smaller photo for this page.");
  const src = URL.createObjectURL(file);
  const image = new Image();
  image.src = src;
  try {
    await image.decode();
    const scale = Math.min(
      1,
      1800 / Math.max(image.naturalWidth, image.naturalHeight),
    );
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
    canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "#fff";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(image, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise((resolve) =>
      canvas.toBlob(resolve, "image/jpeg", 0.8),
    );
    canvas.width = canvas.height = 0;
    if (!blob) throw Error();
    return new Uint8Array(await blob.arrayBuffer());
  } catch {
    throw Error(
      "This photo could not be read. Choose a JPEG or PNG or take another photo.",
    );
  } finally {
    URL.revokeObjectURL(src);
  }
}
export async function scanPages(files, previous) {
  const pages = previous?.scanPages ? [...previous.scanPages] : [];
  let size = pages.reduce((n, p) => n + p.length, 0);
  for await (const file of files) {
    const page = await jpegPage(file);
    size += page.length;
    if (size > sendLimit)
      throw Error("These scans exceed 8 MB. Use fewer pages per fax.");
    pages.push(page);
  }
  const lib = await pdfWriter();
  const pdf = await lib.PDFDocument.create();
  for (const bytes of pages) {
    const img = await pdf.embedJpg(bytes);
    const wide = img.width > img.height;
    const w = wide ? 792 : 612,
      h = wide ? 612 : 792;
    const scale = Math.min(w / img.width, h / img.height);
    const iw = img.width * scale,
      ih = img.height * scale;
    pdf.addPage([w, h]).drawImage(img, {
      x: (w - iw) / 2,
      y: (h - ih) / 2,
      width: iw,
      height: ih,
    });
  }
  const file = new File([await pdf.save()], "Scanned pages.pdf", {
    type: "application/pdf",
  });
  const doc = await readPdf(file);
  doc.scanPages = pages;
  return doc;
}

export async function receiptPdf(title, fields, id) {
  const lib = await pdfWriter();
  const pdf = await lib.PDFDocument.create();
  pdf.setTitle(title + " · FAX Number by Korlix");
  pdf.setAuthor("Korlix");
  const font = await pdf.embedFont(lib.StandardFonts.Helvetica);
  const bold = await pdf.embedFont(lib.StandardFonts.HelveticaBold);
  const page = pdf.addPage([612, 792]);
  const ink = lib.rgb(0.05, 0.12, 0.12),
    teal = lib.rgb(0.01, 0.37, 0.34);
  page.drawRectangle({ x: 0, y: 779, width: 612, height: 13, color: teal });
  page.drawText("FAX Number by Korlix", {
    x: 52,
    y: 723,
    font: bold,
    size: 15,
    color: teal,
  });
  page.drawText(title, { x: 52, y: 667, font: bold, size: 30, color: ink });
  const supported = new Set(font.getCharacterSet());
  let y = 610;
  for (const [key, raw] of fields) {
    if (raw == null || raw === "") continue;
    const text = String(raw).replace(/[\u0000-\u001f\u007f]/g, " ");
    page.drawText(key, { x: 52, y, font: bold, size: 10, color: teal });
    y -= 19;
    // Draw non-Latin names with the browser font when the built-in PDF font lacks a glyph.
    const useFont = [...text].every((c) => supported.has(c.codePointAt(0)));
    const canvas = document.createElement("canvas");
    canvas.width = 1020;
    canvas.height = 40;
    const ctx = canvas.getContext("2d");
    ctx.font = "26px Inter, sans-serif";
    const measure = (s) =>
      useFont ? font.widthOfTextAtSize(s, 13) : ctx.measureText(s).width / 2;
    const lines = [];
    let line = "";
    for (const char of text) {
      if (line && measure(line + char) > 505) {
        lines.push(line);
        line = "";
      }
      line += char;
    }
    if (line) lines.push(line);
    for (const s of lines) {
      if (useFont) page.drawText(s, { x: 52, y, font, size: 13, color: ink });
      else {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.fillStyle = "#102020";
        ctx.fillText(s, 0, 29);
        const img = await pdf.embedPng(canvas.toDataURL("image/png"));
        page.drawImage(img, { x: 52, y: y - 5.5, width: 510, height: 20 });
      }
      y -= 17;
    }
    canvas.width = canvas.height = 0;
    y -= 10;
  }
  return new File([await pdf.save()], "Korlix-Fax-Receipt-" + id + ".pdf", {
    type: "application/pdf",
  });
}
