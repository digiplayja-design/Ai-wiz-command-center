import { build } from "esbuild";
import { cp, mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const root = dirname(fileURLToPath(import.meta.url));
const source = join(root, "../../website/fax-number");
const out = join(root, "www");
await rm(out, { recursive: true, force: true });
await cp(source, out, { recursive: true });
for (const page of ["index.html", "account.html"]) {
  const file = join(out, page);
  let html = await readFile(file, "utf8");
  if (page === "account.html") {
    const form = await readFile(join(root, "signup-form.html"), "utf8");
    html = html.replace("<!-- Packaged account controls -->", form)
      .replace("https://korlixdeveloper.com/privacy-policy.html", "./privacy.html")
      .replace("</head>", '<link rel="stylesheet" href="mobile-account.css"><script type="module" src="mobile-account.js"></script></head>')
      .replace("Korlix company sign-in", "Fax by Korlix");
  }
  await writeFile(file, html.replace("</head>", '<script src="fax-mobile.js"></script>\n  </head>'));
}
for (const asset of ["mobile-account.js", "mobile-account.css"]) {
  await cp(join(root, asset), join(out, asset));
}
// WKWebView and Android's asset handler both serve .js files with a module-compatible MIME type.
for (const name of ["pdf.min", "pdf.worker.min"]) {
  await rename(join(out, "assets", name + ".mjs"), join(out, "assets", name + ".js"));
}
const documentModule = join(out, "fax-document.js");
await writeFile(documentModule, (await readFile(documentModule, "utf8")).replaceAll(".min.mjs", ".min.js"));
await build({
  entryPoints: [join(root, "native.js")], outfile: join(out, "fax-mobile.js"),
  bundle: true, minify: true, format: "iife", target: ["safari15", "chrome100"]
});

const logo = join(source, "korlix.png");
const ios = join(root, "ios/App/App/Assets.xcassets");
const android = join(root, "android/app/src/main/res");
const background = "#010404";
async function png(file, data) {
  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, data);
}
await png(join(ios, "AppIcon.appiconset/AppIcon-512@2x.png"), await sharp(logo).flatten({background}).removeAlpha().png().toBuffer());
await png(join(ios, "Splash.imageset/logo.png"), await sharp(logo).resize(240).png().toBuffer());
for (const [density, scale] of Object.entries({mdpi:1, hdpi:1.5, xhdpi:2, xxhdpi:3, xxxhdpi:4})) {
  const dir = join(android, "mipmap-" + density);
  const legacy = await sharp(logo).resize(48 * scale).png().toBuffer();
  await png(join(dir, "ic_launcher.png"), legacy);
  const dimension = 108 * scale;
  const inner = Math.round(66 * scale);
  const foreground = await sharp(logo).resize(inner).extend({
    top: Math.floor((dimension - inner)/2), bottom: Math.ceil((dimension - inner)/2),
    left: Math.floor((dimension - inner)/2), right: Math.ceil((dimension - inner)/2),
    background
  }).png().toBuffer();
  await png(join(dir, "ic_launcher_foreground.png"), foreground);
}
