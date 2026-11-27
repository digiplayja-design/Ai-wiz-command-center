import { sampleWorkspace } from "./sample-workspace.js";
import { Capacitor, registerPlugin } from "@capacitor/core";
import { sha256 } from "@noble/hashes/sha2.js";
import { Directory, Filesystem } from "@capacitor/filesystem";
import { Share } from "@capacitor/share";
import { DocumentScanner, ResponseType } from "@capgo/capacitor-document-scanner";

const ios = Capacitor.getPlatform() === "ios";
const appleScanner = registerPlugin("FaxScanner");
const androidFiles = registerPlugin("FaxFiles");
async function share(options) {
  try {
    await Share.share(options);
  } catch (error) {
    if (!/cancel/i.test(error.message)) throw error;
  }
}

async function scan() {
  let result;
  try {
    result = ios ? await appleScanner.scan() : await DocumentScanner.scanDocument({
      responseType: ResponseType.ImageFilePath, croppedImageQuality: 85, maxNumDocuments: 24
    });
  } catch (error) {
    throw Error((error.message || "The scanner could not open.") + " You can also choose a PDF.");
  }
  if (result.status === "cancel" || !result.scannedImages?.length) return null;
  const paths = result.scannedImages;
  async function* images() {
    try {
      for (const path of paths) {
        const response = await fetch(Capacitor.convertFileSrc(path));
        if (!response.ok) throw Error("A scanned page could not be opened. Scan that page again.");
        yield await response.blob();
      }
    } finally {
      await Promise.allSettled(paths.map(path => Filesystem.deleteFile({
        path: path.startsWith("/") ? "file://" + path : path
      })));
    }
  }
  return images();
}

function base64(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(Error("The file could not be prepared."));
    reader.onload = () => resolve(String(reader.result).split(",")[1]);
    reader.readAsDataURL(blob);
  });
}

async function saveFile(file, suggestedName) {
  const mime = file.type.split(";")[0];
  const ext = mime === "text/csv" ? ".csv" : ".pdf";
  const clean = suggestedName.replace(/[\\/:*?"<>|\u0000-\u001f]/g, "_").replace(/^\.+/, "").slice(0,150);
  const name = clean.toLowerCase().endsWith(ext) ? clean : (clean || "Fax") + ext;
  const folder = "fax-exports/" + crypto.randomUUID();
  const path = folder + "/" + name;
  const directory = Directory.Cache;
  await Filesystem.mkdir({ directory, path: folder, recursive: true });
  try {
    const chunk = 192 * 1024;
    const first = await Filesystem.writeFile({ directory, path, data: await base64(file.slice(0, chunk)) });
    for (let pos = chunk; pos < file.size; pos += chunk) {
      await Filesystem.appendFile({ directory, path, data: await base64(file.slice(pos, pos + chunk)) });
    }
    if (ios) await share({ title: name, files: [first.uri] });
    else await androidFiles.save({ uri: first.uri, name });
  } finally {
    await Filesystem.rmdir({ directory, path: folder, recursive: true }).catch(() => {});
  }
}
if (Capacitor.isNativePlatform()) {
  // Older WKWebView versions can omit secure-context methods for bundled URL schemes.
  if (!crypto.randomUUID) {
    crypto.randomUUID = () => {
      const bytes = crypto.getRandomValues(new Uint8Array(16));
      bytes[6] = (bytes[6] & 15) | 64;
      bytes[8] = (bytes[8] & 63) | 128;
      const hex = Array.from(bytes, x => x.toString(16).padStart(2, "0")).join("");
      return [hex.slice(0,8), hex.slice(8,12), hex.slice(12,16), hex.slice(16,20), hex.slice(20)].join("-");
    };
  }
  if (!AbortSignal.timeout) AbortSignal.timeout = duration => {
    const controller = new AbortController();
    setTimeout(() => controller.abort(), duration);
    return controller.signal;
  };
  window.KorlixFaxNative = {
    sample: sessionStorage.getItem('korlixFaxSession') === 'sample' ? sampleWorkspace : null,
    scan, saveFile, hash: bytes => sha256(new Uint8Array(bytes)),
    shareNumber: text => share({title: "Fax number", text})
  };
}
