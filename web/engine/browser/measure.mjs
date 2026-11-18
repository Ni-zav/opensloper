// Opens the spike's page in headless Chromium and prints what it measured,
// with anything the page or the worker logged. Serve the repository root first
// (python3 -m http.server 8765 --bind 127.0.0.1); --url overrides the address.
import puppeteer from 'puppeteer-core';

const argument = (name, fallback) => {
  const index = process.argv.indexOf(name);
  return index > 0 ? process.argv[index + 1] : fallback;
};
const base = argument('--url', 'http://127.0.0.1:8765/web/engine/out/browser/index.html');
const query = new URLSearchParams({
  pattern: argument('--pattern', 'skirt-pieces.sloper'),
  measurements: argument('--measurements', 'skirt-small.slm'),
});
const browser = await puppeteer.launch({
  executablePath: process.env.CHROMIUM ?? '/usr/bin/chromium',
  args: ['--no-sandbox', '--disable-gpu'],
});
try {
  const page = await browser.newPage();
  page.on('console', (message) => console.error(`console ${message.type()}: ${message.text()}`));
  page.on('pageerror', (error) => console.error(`page error: ${error.message}`));
  page.on('workercreated', (worker) => console.error(`worker started: ${worker.url()}`));
  await page.goto(`${base}?${query}`);
  await page.waitForFunction(() => document.title === 'done', { timeout: 60000 });
  const results = JSON.parse(await page.$eval('#results', (element) => element.textContent));
  if (argument('--svg', '')) {
    const { writeFile } = await import('node:fs/promises');
    await writeFile(argument('--svg', ''), results.svg ?? '');
  }
  delete results.svg;
  console.log(JSON.stringify(results, null, 2));
} finally {
  await browser.close();
}
