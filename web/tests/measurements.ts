// Drives the built Measurements app in headless Chromium: the page asks for a
// file until one is open; a set opens with its name, notes and a row a
// measurement; Show in shows the values in cm and inches. In the grid a value
// is changed, one that is not a number refused, a key renamed and a
// description typed; Add makes a row whose key is typed, Up moves it, Delete
// asks and deletes it, and Undo and Redo step through. Opening another file
// asks before dropping the changes. A size table has a column a size, and a
// file that is not a measurement file, or cannot be read, is refused with the
// set open kept. Its sizes are renamed, moved, added and deleted with the size
// buttons, which act on the column of the chosen cell. SCREENSHOT, as in design.ts, keeps
// the page at the end.
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { Page } from 'puppeteer-core';
import { launchBrowser, serveApp, status, waitForData, waitForStatus, watchProblems } from './browser.ts';

const SET = '../docs/examples/skirt-block/skirt.slm';
const SIZE_TABLE = '../docs/examples/measurements/size-table.slm';
const PATTERN = '../docs/examples/skirt-block/skirt-darts.sloper';

// The table's captions, and its rows' cells
async function table(page: Page): Promise<{ head: string[]; rows: string[][] }> {
  return page.$eval('#table', (element) => ({
    head: [...element.querySelectorAll('th')].map((cell) => cell.textContent),
    rows: [...element.querySelectorAll('tbody tr')].map((row) =>
      [...row.querySelectorAll('td')].map((cell) => cell.textContent),
    ),
  }));
}

async function waitForRows(page: Page, count: number): Promise<void> {
  await page.waitForFunction((expected) => document.querySelectorAll('#table tbody tr').length === expected, {}, count);
}

// The table's cell, from 1 as CSS counts
function cellAt(row: number, column: number): string {
  return `#table tbody tr:nth-child(${String(row)}) td:nth-child(${String(column)})`;
}

async function keys(page: Page): Promise<string[]> {
  return page.$$eval('#table tbody tr', (rows) => rows.map((row) => (row as HTMLElement).dataset.key ?? ''));
}

// Clicks the button with this caption, once it is enabled
async function press(page: Page, caption: string): Promise<void> {
  await page.waitForFunction(
    (text) => {
      const button = [...document.querySelectorAll('button')].find(
        (each) => each.textContent === text && !each.disabled,
      );
      button?.click();
      return button !== undefined;
    },
    {},
    caption,
  );
}

// Types into the cell and commits it with Enter
async function typeIn(page: Page, selector: string, text: string): Promise<void> {
  await page.click(selector);
  await page.keyboard.type(text);
  await page.keyboard.press('Enter');
}

async function showIn(page: Page, unit: string, waist: string): Promise<void> {
  await page.select('#show-in', unit);
  await page.waitForFunction(
    (text) => document.querySelector('#table tbody tr td:nth-child(2)')?.textContent === text,
    {},
    waist,
  );
}

const folder = await mkdtemp(join(tmpdir(), 'opensloper-measurements-'));
const app = await serveApp({ root: 'out/measurements' });
const browser = await launchBrowser();
try {
  const page = await browser.newPage();
  const problems = watchProblems(page);
  await page.goto(`http://127.0.0.1:${String(app.port)}/`);
  await waitForData(page, 'ready', 'true');
  assert.equal(await page.title(), 'OpenSloper Measurements');
  assert.equal(await page.$('#table input[type=search]'), null, 'no search box before a set is open');
  assert.match(await page.$eval('#table', (element) => element.textContent), /Open a measurement file/u);
  const input = await page.$('input#open-input');
  assert.ok(input);

  // A set without sizes: one Value column, in mm to start with
  await input.uploadFile(SET);
  await waitForStatus(page, 'Opened skirt.slm');
  await waitForRows(page, 4);
  assert.equal(await page.title(), 'skirt.slm — OpenSloper Measurements');
  assert.equal(await page.$eval('#set-name', (box) => (box instanceof HTMLInputElement ? box.value : '')), 'Tutorial');
  assert.ok(await page.$eval('#set-name', (box) => box instanceof HTMLInputElement && box.readOnly));
  assert.ok(
    await page.$eval('#table .list-header', (header) => header instanceof HTMLElement && header.offsetHeight === 0),
    'the table has no search box',
  );
  let shown = await table(page);
  assert.deepEqual(shown.head, ['Key', 'Value', 'Description']);
  assert.deepEqual(shown.rows[0], ['waist', '660', 'Waist circumference']);
  await showIn(page, 'cm', '66');
  await showIn(page, 'in', '25.9843');
  await showIn(page, 'mm', '660');

  // Edits in the grid, each one undo step
  assert.ok(
    await page.$eval(
      '#toolbar button:nth-of-type(2)',
      (button) => button instanceof HTMLButtonElement && button.disabled,
    ),
    'nothing to undo',
  );
  await typeIn(page, cellAt(1, 2), '680');
  await waitForData(page, 'undo', 'Change value');
  assert.equal(await page.title(), '• skirt.slm — OpenSloper Measurements');
  assert.equal(await page.$eval(cellAt(1, 2), (element) => element.textContent), '680');
  await typeIn(page, cellAt(1, 2), 'wide');
  await page.waitForSelector('#table td.refused');
  assert.equal(await status(page), 'A value must be a number, such as 82.5');
  // Escape on the reopened cell drops the refused text
  await page.keyboard.press('Enter');
  await page.keyboard.press('Escape');
  await page.waitForFunction(() => document.querySelector('#table td.refused') === null);
  await typeIn(page, cellAt(1, 1), 'waist_circumference');
  await waitForStatus(page, 'Renamed to @waist_circumference. Patterns using @waist');
  await waitForData(page, 'undo', 'Rename measurement');
  await typeIn(page, cellAt(1, 3), 'Round the natural waist');
  await waitForData(page, 'undo', 'Change description');
  // Add opens the new row's key to type; Up moves it; Delete asks first
  await press(page, 'Add');
  await page.waitForSelector('input.cell-editor');
  await page.keyboard.type('seat');
  await page.keyboard.press('Enter');
  await page.waitForSelector('#table tr[data-key="seat"]');
  assert.equal((await keys(page)).at(-1), 'seat');
  await press(page, 'Up');
  await waitForData(page, 'undo', 'Move measurement');
  assert.equal((await keys(page)).at(-2), 'seat', 'moved up, and still chosen');
  page.once('dialog', (dialog) => {
    void dialog.accept();
  });
  await press(page, 'Delete');
  await waitForData(page, 'undo', 'Delete measurement');
  assert.ok(!(await keys(page)).includes('seat'));
  await press(page, 'Undo');
  await waitForData(page, 'undo', 'Move measurement');
  assert.ok((await keys(page)).includes('seat'), 'undo brings it back');
  await press(page, 'Redo');
  await waitForData(page, 'undo', 'Delete measurement');

  // Opening another file asks before dropping the changes
  page.once('dialog', (dialog) => {
    void dialog.dismiss();
  });
  await input.uploadFile(SIZE_TABLE);
  await new Promise((resolve) => setTimeout(resolve, 300));
  assert.equal(await page.title(), '• skirt.slm — OpenSloper Measurements', 'kept when the user says no');
  page.once('dialog', (dialog) => {
    void dialog.accept();
  });

  // A size table: a column a size
  await input.uploadFile(SIZE_TABLE);
  await waitForData(page, 'undo', '');
  await waitForStatus(page, 'Opened size-table.slm');
  await waitForRows(page, 11);
  shown = await table(page);
  assert.deepEqual(shown.head, ['Key', '8', '10', '12', '14', '16', 'Description']);
  assert.deepEqual(shown.rows[0], [
    'bust_circumference',
    '820',
    '870',
    '920',
    '970',
    '1020',
    'Around the fullest part of the bust',
  ]);
  assert.equal(
    await page.$eval('#set-name', (box) => (box instanceof HTMLInputElement ? box.value : '')),
    "Women's sizes 8 to 16",
  );

  // The size buttons act on the column of the chosen cell, as on the desktop
  async function sizeButton(caption: string, enabled: boolean): Promise<void> {
    await page.waitForFunction(
      (text, on) =>
        [...document.querySelectorAll('#table-buttons button')].some(
          (button) => button instanceof HTMLButtonElement && button.textContent === text && button.disabled !== on,
        ),
      {},
      caption,
      enabled,
    );
  }
  async function head(expected: string[]): Promise<void> {
    await page.waitForFunction(
      (captions) => [...document.querySelectorAll('#table th')].map((cell) => cell.textContent).join() === captions,
      {},
      expected.join(),
    );
  }
  await sizeButton('Rename size…', false);
  await page.click(cellAt(1, 3));
  await sizeButton('Size left', true);
  await sizeButton('Size right', true);
  await page.click(cellAt(1, 1));
  await sizeButton('Rename size…', false);
  await page.click(cellAt(1, 3));
  page.once('dialog', (dialog) => {
    void dialog.accept('Ten');
  });
  await press(page, 'Rename size…');
  await head(['Key', '8', 'Ten', '12', '14', '16', 'Description']);
  assert.equal(await page.title(), '• size-table.slm — OpenSloper Measurements');
  await press(page, 'Size right');
  await head(['Key', '8', '12', 'Ten', '14', '16', 'Description']);
  assert.equal(await page.$eval(cellAt(1, 4), (element) => element.textContent), '870', 'the values go with it');
  assert.ok(
    await page.$eval(cellAt(1, 4), (element) => element.classList.contains('current')),
    'the chosen cell goes with it',
  );
  page.once('dialog', (dialog) => {
    void dialog.accept('12');
  });
  await press(page, 'Add size…');
  await waitForStatus(page, 'Size "12" is already in the table');
  page.once('dialog', (dialog) => {
    void dialog.accept('18');
  });
  await press(page, 'Add size…');
  await head(['Key', '8', '12', 'Ten', '14', '16', '18', 'Description']);
  assert.equal(await page.$eval(cellAt(1, 7), (element) => element.textContent), '', 'a new size has no values');
  page.once('dialog', (dialog) => {
    void dialog.accept();
  });
  await press(page, 'Delete size');
  await head(['Key', '8', '12', '14', '16', '18', 'Description']);
  await press(page, 'Undo');
  await waitForData(page, 'undo', 'Add size');
  await head(['Key', '8', '12', 'Ten', '14', '16', '18', 'Description']);

  // Refused: another kind of file, and one that cannot be read; the size table stays
  await input.uploadFile(PATTERN);
  await waitForStatus(page, 'skirt-darts.sloper is not a measurement file');
  const broken = join(folder, 'broken.slm');
  await writeFile(broken, '{"format": "measurements"');
  page.once('dialog', (dialog) => {
    void dialog.accept();
  });
  await input.uploadFile(broken);
  await waitForStatus(page, 'Could not open broken.slm');
  assert.equal(await page.title(), '• size-table.slm — OpenSloper Measurements');
  assert.equal((await table(page)).rows.length, 11);

  // SCREENSHOT names a PNG file to keep what the page shows at the end
  if ((process.env.SCREENSHOT ?? '') !== '') {
    await page.screenshot({ path: `${process.env.SCREENSHOT ?? ''}.png` });
  }
  assert.deepEqual(problems, []);
  console.log('Measurements app passed');
} finally {
  await browser.close();
  app.close();
  await rm(folder, { recursive: true, force: true });
}
