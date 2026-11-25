// Drives the built Publish app in headless Chromium: a pattern opened without
// its measurement file names the file it needs, then with it starts a layout;
// a layout whose sources sit in other folders finds its files by name.
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { launchBrowser, serveApp, status, waitForData, waitForStatus, watchProblems } from './browser.ts';

const PATTERN = '../docs/examples/skirt-block/skirt-darts.sloper';
const MEASUREMENTS = '../docs/examples/skirt-block/skirt.slm';

// A layout of the skirt as saved beside a folder of patterns, whose
// measurement file the pattern names beside itself
const LAYOUT = {
  format: 'layout',
  version: 1,
  units: 'mm',
  name: 'Skirt for cutting',
  nextId: 2,
  sources: [{ id: 1, pattern: 'patterns/skirt-darts.sloper' }],
};

const folder = await mkdtemp(join(tmpdir(), 'opensloper-publish-'));
const app = await serveApp({ root: 'out/publish' });
const browser = await launchBrowser();
try {
  const layoutFile = join(folder, 'skirt.slayout');
  await writeFile(layoutFile, JSON.stringify(LAYOUT));
  const page = await browser.newPage();
  const problems = watchProblems(page);
  await page.goto(`http://127.0.0.1:${String(app.port)}/`);
  await waitForData(page, 'ready', 'true');
  const input = await page.$('input#open-input');
  assert.ok(input);

  await input.uploadFile(PATTERN);
  await waitForStatus(page, 'The layout needs skirt.slm');
  assert.match(await page.$eval('#problem-count', (count) => count.textContent), /stop printing/u);

  await input.uploadFile(PATTERN, MEASUREMENTS);
  await waitForStatus(page, 'Started a layout for skirt-darts.sloper');
  assert.equal(await page.title(), 'skirt-darts — OpenSloper Publish');
  assert.doesNotMatch(await status(page), /stop printing/u);

  await input.uploadFile(layoutFile, PATTERN, MEASUREMENTS);
  await waitForStatus(page, 'Opened skirt.slayout');
  assert.equal(await page.title(), 'Skirt for cutting — OpenSloper Publish');
  // Every file was found; its pieces wait in the tray, so nothing would print
  assert.doesNotMatch(await status(page), /needs/u);
  assert.match(await page.$eval('#problem-count', (count) => count.textContent), /stop printing/u);

  await input.uploadFile(MEASUREMENTS);
  await waitForStatus(page, 'skirt.slm is not a layout');

  assert.deepEqual(problems, []);
  console.log('Publish app passed');
} finally {
  await browser.close();
  app.close();
  await rm(folder, { recursive: true, force: true });
}
