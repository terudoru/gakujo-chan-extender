// Export positioned text from the university's course listing for build_catalog.py.
const fs = require("node:fs");
const pdf = require("../../assets/js/upload_compression/pdf.min.js");
pdf.GlobalWorkerOptions.workerSrc = require.resolve(
  "../../assets/js/upload_compression/pdf.worker.min.js",
);

(async () => {
  const data = new Uint8Array(fs.readFileSync(process.argv[2]));
  const document = await pdf.getDocument({
    data,
    verbosity: 0,
    isEvalSupported: false,
  }).promise;
  const pages = [];
  for (let n = 1; n <= document.numPages; n++) {
    const page = await document.getPage(n);
    const content = await page.getTextContent();
    pages.push(
      content.items
        .filter((item) => item.str?.trim())
        .map((item) => [item.transform[4], item.transform[5], item.str]),
    );
  }
  fs.writeFileSync(process.argv[3], JSON.stringify(pages));
})().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
