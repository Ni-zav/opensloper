/*
  OpenSloper - parametric sewing pattern drafting
  Copyright (C) 2026 The OpenSloper authors

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/

// Opens a real example with measurements. In particular, undo and reopen
// must resolve the sources again in the browser instead of reading disk.
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout } from 'node:timers/promises';
import { launchBrowser, serveApp, watchProblems } from './browser.ts';

const downloads = await mkdtemp(join(tmpdir(), 'opensloper-publish-'));
const app = await serveApp({ root: 'out/publish' });
const browser = await launchBrowser();

async function readDownload(name: string): Promise<Buffer> {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    // oxlint-disable-next-line no-await-in-loop
    const bytes = await readFile(join(downloads, name)).catch(() => undefined);
    if (bytes !== undefined) return bytes;
    // oxlint-disable-next-line no-await-in-loop
    await setTimeout(50);
  }
  throw new Error(`No download for ${name}`);
}

try {
  const page = await browser.newPage();
  const problems = watchProblems(page);
  const client = await page.createCDPSession();
  await client.send('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: downloads });
  await page.setViewport({ width: 390, height: 844 });
  await page.goto(`http://127.0.0.1:${String(app.port)}/`);
  await page.waitForSelector('#tools:enabled');
  const file = await page.waitForSelector('input#files');
  assert.ok(file);
  const pattern = '../docs/examples/skirt-block/skirt-darts.sloper';
  const measurements = '../docs/examples/skirt-block/skirt.slm';

  await file.uploadFile(pattern);
  await page.waitForSelector('#status[data-error]');
  assert.match(await page.$eval('#status', (output) => output.textContent), /skirt\.slm/u);
  await file.uploadFile(pattern, measurements);
  await page.waitForSelector('#save:enabled');
  await page.waitForFunction(() => document.querySelector<HTMLImageElement>('#preview')?.naturalWidth);
  const initialX = await page.$eval('input#x', (input) => input.value);
  await page.$eval('input#x', (input) => {
    input.value = String(input.valueAsNumber + 50);
  });
  await page.click('#placement button[type=submit]');
  await page.waitForSelector('#undo:enabled');
  assert.equal(await page.$eval('input#x', (input) => input.valueAsNumber), Number(initialX) + 50);
  await page.click('#undo');
  await page.waitForSelector('#redo:enabled');
  assert.equal(await page.$eval('input#x', (input) => input.value), initialX);

  await page.click('#pack');
  await page.waitForSelector('#pdf:enabled');
  await page.click('#pdf');
  assert.equal((await readDownload('skirt-darts.pdf')).subarray(0, 5).toString(), '%PDF-');
  await page.waitForSelector('#svg:enabled');
  await page.click('#svg');
  assert.match((await readDownload('skirt-darts.svg')).toString(), /<svg[\s>]/u);
  await page.waitForSelector('#save:enabled');
  await page.click('#save');
  const layoutName = 'skirt-darts.slayout';
  assert.match((await readDownload(layoutName)).toString(), /"placements"/u);
  await file.uploadFile(join(downloads, layoutName), pattern, measurements);
  await page.waitForSelector('#save:enabled');
  await page.waitForFunction(() => document.querySelector('#name')?.textContent === 'skirt-darts');
  assert.equal(await page.$eval('button#undo', (button) => button.disabled), true);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth), 390);
  assert.deepEqual(problems, []);
  console.log('Publish browser round trip passed');
} finally {
  await browser.close();
  app.close();
  await rm(downloads, { recursive: true, force: true });
}
