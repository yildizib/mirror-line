import { access, readFile } from "node:fs/promises";

const requiredFiles = [
  "_site/index.html",
  "_site/en/index.html",
  "_site/assets/site.css",
  "_site/assets/site.js",
  "_site/assets/logo.svg",
  "_site/assets/flow.svg",
  "_site/assets/security.svg",
  "_site/.nojekyll"
];

await Promise.all(requiredFiles.map((file) => access(file)));

const tr = await readFile("_site/index.html", "utf8");
const en = await readFile("_site/en/index.html", "utf8");

const expectations = [
  [tr, "Geliştirme aşamasında"],
  [tr, "7 gün"],
  [tr, "5 Kaynak Telefon"],
  [tr, "github.com/yildizib/mirror-line"],
  [en, "Under development"],
  [en, "7 days"],
  [en, "5 Source Phones"],
  [en, "github.com/yildizib/mirror-line"]
];

for (const [document, phrase] of expectations) {
  if (!document.includes(phrase)) {
    throw new Error(`Missing expected content: ${phrase}`);
  }
}

console.log("Validated Turkish and English builds, project links, and assets.");
