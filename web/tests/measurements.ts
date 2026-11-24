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

// The standalone editor, from the local file picker through Wasm and back
// to a browser download. A refused edit leaves the open set in place.
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout } from 'node:timers/promises';
import { launchBrowser, serveApp, waitForStatus, watchProblems } from './browser.ts';

const downloads = await mkdtemp(join(tmpdir(), 'opensloper-measurements-'));
const app = await serveApp({ root: 'out/measurements' });
const browser = await launchBrowser();
try {
  const page = await browser.newPage();
  const problems = watchProblems(page);
  const client = await page.createCDPSession();
  await client.send('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: downloads });
  await page.setViewport({ width: 390, height: 844 });
  await page.goto(`http://127.0.0.1:${String(app.port)}/`);
  await page.waitForSelector('#editor:enabled');
  const file = await page.waitForSelector('input#file');
  assert.ok(file);
  await file.uploadFile('../docs/examples/measurements/person.slm');
  await page.waitForFunction(() => document.querySelector('#file-name')?.textContent === 'person.slm');
  assert.ok(await page.$('#rows input[type=number]'));
  await page.click('#add-row');
  await page.waitForFunction(() => document.activeElement === document.querySelector('#rows tr:last-child input'));

  await page.type('#size-name', 'Small');
  await page.click('#add-size button');
  await page.waitForSelector('input[aria-label="Size Small"]');
  await page.type('#size-name', 'Large');
  await page.click('#add-size button');
  await page.waitForSelector('input[aria-label="Size Large"]');
  assert.equal(
    await page.$eval('#rows tr:last-child input[type=number]:last-of-type', (field) => field.type),
    'number',
  );
  const newValue = '#rows tr:last-child td:nth-child(4) input';
  await page.type(newValue, '923.5');
  await page.click('h2');
  await page.click('#undo');
  await page.waitForFunction(
    (selector) => document.querySelector<HTMLInputElement>(selector)?.value === '',
    {},
    newValue,
  );
  await page.click('#redo');
  await page.waitForFunction(
    (selector) => document.querySelector<HTMLInputElement>(selector)?.value === '923.5',
    {},
    newValue,
  );

  // A rejected replacement must preserve the table and its undo history.
  const badFile = join(downloads, 'bad.slm');
  await writeFile(badFile, '{}');
  page.once('dialog', (dialog) => {
    void dialog.accept();
  });
  await file.uploadFile(badFile);
  await page.waitForSelector('#status[data-error]');
  assert.equal(await page.$eval(newValue, (field) => field.value), '923.5');
  assert.equal(await page.$eval('button#undo', (button) => button.disabled), false);

  await page.click('#save');
  await waitForStatus(page, 'Download requested');
  const output = join(downloads, 'person.slm');
  let result = '';
  for (let attempt = 0; attempt < 40 && result === ''; attempt += 1) {
    // oxlint-disable-next-line no-await-in-loop
    result = await readFile(output, 'utf8').catch(() => '');
    // oxlint-disable-next-line no-await-in-loop
    if (result === '') await setTimeout(50);
  }
  assert.match(result, /923\.5/u);
  assert.match(result, /"sizes"\s*:\s*\[\s*"Small"\s*,\s*"Large"/u);

  await page.click('#new');
  await page.waitForFunction(() => document.querySelector('#file-name')?.textContent === 'Untitled.slm');
  await file.uploadFile(output);
  await page.waitForFunction(() => document.querySelector('#file-name')?.textContent === 'person.slm');
  assert.equal(await page.$eval(newValue, (field) => field.value), '923.5');
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth), 390);
  assert.deepEqual(problems, []);
  console.log('Measurements browser round trip passed');
} finally {
  await browser.close();
  app.close();
  await rm(downloads, { recursive: true, force: true });
}
