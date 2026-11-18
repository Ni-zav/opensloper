// Opens the spike's page in headless Chromium and prints what it measured,
// with anything the page or the worker logged. Serve the repository root first
// (python3 -m http.server 8765 --bind 127.0.0.1); --url overrides the address.
// Node runs this TypeScript as it is.
import { writeFile } from 'node:fs/promises';
import { launch } from 'puppeteer-core';
import { isRecord } from './replies.ts';

function argument(name: string, fallback: string): string {
  const index = process.argv.indexOf(name);
  return index > 0 ? (process.argv[index + 1] ?? fallback) : fallback;
}

const base = argument('--url', 'http://127.0.0.1:8765/web/engine/out/browser/index.html');
const svgFile = argument('--svg', '');
const query = new URLSearchParams({
  pattern: argument('--pattern', 'skirt-pieces.sloper'),
  measurements: argument('--measurements', 'skirt-small.slm'),
});
const browser = await launch({
  executablePath: process.env.CHROMIUM ?? '/usr/bin/chromium',
  args: ['--no-sandbox', '--disable-gpu'],
});
try {
  const page = await browser.newPage();
  page.on('console', (message) => {
    console.error(`console ${message.type()}: ${message.text()}`);
  });
  page.on('pageerror', (error: unknown) => {
    console.error(`page error: ${String(error)}`);
  });
  page.on('workercreated', (worker) => {
    console.error(`worker started: ${worker.url()}`);
  });
  await page.goto(`${base}?${query.toString()}`);
  await page.waitForFunction(() => document.title === 'done', { timeout: 60000 });
  const text = await page.$eval('#results', (element) => element.textContent);
  const results: unknown = JSON.parse(text);
  if (!isRecord(results)) {
    throw new Error(`the page gave no results: ${text.slice(0, 80)}`);
  }
  const { svg, ...rest } = results;
  if (svgFile !== '') {
    await writeFile(svgFile, typeof svg === 'string' ? svg : '');
  }
  console.log(JSON.stringify(rest, null, 2));
} finally {
  await browser.close();
}
