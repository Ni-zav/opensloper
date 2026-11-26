// Drives the built Publish app in headless Chromium: a pattern opened without
// its measurement file names the file it needs, then with it starts a layout
// whose pages the preview draws and whose pieces a click selects. The
// Patterns tab adds a pattern and removes it, and reads the pattern with a
// size table at one of its sizes and then with its own measurements again. The
// selected piece is turned, flipped and sent back to the tray, from which a
// double-click places it again; a piece is dragged, and a copy dragged from
// the tray onto the pages. The Output tab changes the paper, refuses a
// margin that leaves nothing to print on, and turns the pages into one large
// sheet and back; a right-click leaves a page out. A sheet note is added,
// typed in, refused a font, dragged on the pages and deleted. The Materials
// tab lists what the patterns need. The Info tab hides the date from the
// information block and shows it again, moves the block to the top right,
// and hides the block and shows it again. The layout is packed, undone and redone,
// saved and exported, and the saved file opens again. A layout whose sources
// sit in other folders finds its files by name, lists what stops it printing
// in the Problems tab, and its waiting pieces are placed.
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { Page } from 'puppeteer-core';
import { bodyData, launchBrowser, serveApp, status, waitForData, waitForStatus, watchProblems } from './browser.ts';

const PATTERN = '../docs/examples/skirt-block/skirt-darts.sloper';
const MEASUREMENTS = '../docs/examples/skirt-block/skirt.slm';
const OTHER_PATTERN = '../docs/examples/skirt-block/skirt-hem.sloper';
const SIZE_TABLE = '../docs/examples/measurements/size-table.slm';

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

// Clicks the toolbar's button with this caption, once it is enabled
async function command(page: Page, caption: string): Promise<void> {
  await page.waitForFunction(
    (text) => {
      const button = [...document.querySelectorAll('#toolbar button')].find(
        (each) => each.textContent === text && each instanceof HTMLButtonElement && !each.disabled,
      );
      if (button instanceof HTMLButtonElement) {
        button.click();
        return true;
      }
      return false;
    },
    {},
    caption,
  );
}

// Opens the side panel's tab whose content has this class, unless it shows:
// clicking the open tab's icon folds the panel
async function openTab(page: Page, key: string): Promise<void> {
  if ((await page.$(`.${key}:not([hidden])`)) === null || (await page.$(`.side-page[hidden]`)) !== null) {
    await page.click(`.side-column button[data-tab="${key}"]`);
  }
  await page.waitForSelector(`.${key}`, { visible: true });
}

// Clicks the Pieces tab's button with this caption, once it is enabled,
// opening the tab first
async function piecesButton(page: Page, caption: string): Promise<void> {
  await openTab(page, 'pieces');
  await page.waitForFunction(
    (text) => {
      const button = [...document.querySelectorAll('.pieces button')].find(
        (each) => each.textContent === text && each instanceof HTMLButtonElement && !each.disabled,
      );
      if (button instanceof HTMLButtonElement) {
        button.click();
        return true;
      }
      return false;
    },
    {},
    caption,
  );
}

// Waits for the status bar's message to hold the text anywhere
async function waitForMessagePart(page: Page, part: string): Promise<void> {
  await page.waitForFunction((text) => document.querySelector('#message')?.textContent.includes(text), {}, part);
}

// Clicks the Notes tab's button with this caption, once it is enabled
async function notesButton(page: Page, caption: string): Promise<void> {
  await page.waitForFunction(
    (text) => {
      const button = [...document.querySelectorAll('.notes button')].find(
        (each) => each.textContent === text && each instanceof HTMLButtonElement && !each.disabled,
      );
      if (button instanceof HTMLButtonElement) {
        button.click();
        return true;
      }
      return false;
    },
    {},
    caption,
  );
}

// Clicks the Patterns tab's button with this caption, once it is enabled
async function patternsButton(page: Page, caption: string): Promise<void> {
  await page.waitForFunction(
    (text) => {
      const button = [...document.querySelectorAll('.patterns button')].find(
        (each) => each.textContent === text && each instanceof HTMLButtonElement && !each.disabled,
      );
      if (button instanceof HTMLButtonElement) {
        button.click();
        return true;
      }
      return false;
    },
    {},
    caption,
  );
}

// The middle of what the preview draws in the selection's blue, in page
// pixels: the chosen note's frame and text
async function selectionMiddle(page: Page): Promise<{ x: number; y: number }> {
  const found = await page.evaluate(() => {
    const canvas = document.querySelector('#preview');
    if (!(canvas instanceof HTMLCanvasElement)) {
      return undefined;
    }
    const pixels = canvas.getContext('2d')?.getImageData(0, 0, canvas.width, canvas.height).data ?? [];
    let minX = Infinity;
    let minY = Infinity;
    let maxX = -Infinity;
    let maxY = -Infinity;
    for (let index = 0; index < pixels.length; index += 4) {
      // Near rgb(37, 116, 214), as antialiasing blends it
      const red = pixels[index] ?? 0;
      const green = pixels[index + 1] ?? 0;
      const blue = pixels[index + 2] ?? 0;
      if (red < 110 && green > 100 && green < 170 && blue > 190) {
        const pixel = index / 4;
        const x = pixel % canvas.width;
        const y = Math.floor(pixel / canvas.width);
        minX = Math.min(minX, x);
        minY = Math.min(minY, y);
        maxX = Math.max(maxX, x);
        maxY = Math.max(maxY, y);
      }
    }
    if (minX > maxX) {
      return undefined;
    }
    const bounds = canvas.getBoundingClientRect();
    const ratio = canvas.width / bounds.width;
    return { x: bounds.left + (minX + maxX) / 2 / ratio, y: bounds.top + (minY + maxY) / 2 / ratio };
  });
  assert.ok(found, 'nothing drawn in the selection colour');
  return found;
}

// Waits for the toolbar's Undo to name this step
async function waitForUndo(page: Page, step: string): Promise<void> {
  await page.waitForSelector(`#toolbar button[title="Undo ${step}"]:enabled`);
}

// A downloaded file's contents, once the browser has written it
async function download(folder: string, name: string): Promise<Buffer> {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    // oxlint-disable-next-line no-await-in-loop
    const bytes = await readFile(join(folder, name)).catch(() => undefined);
    if (bytes !== undefined && bytes.length > 0) {
      return bytes;
    }
    // oxlint-disable-next-line no-await-in-loop
    await new Promise((resolve) => {
      setTimeout(resolve, 50);
    });
  }
  throw new Error(`${name} was not downloaded`);
}

// Waits for the preview to draw paper: white pages on the grey desk
async function waitForPaper(page: Page): Promise<void> {
  await page.waitForFunction(() => {
    const canvas = document.querySelector('#preview');
    if (!(canvas instanceof HTMLCanvasElement)) {
      return false;
    }
    const pixels = canvas.getContext('2d')?.getImageData(0, 0, canvas.width, canvas.height).data ?? [];
    let count = 0;
    for (let index = 0; index < pixels.length; index += 4) {
      if (pixels[index] === 255 && pixels[index + 1] === 255 && pixels[index + 2] === 255) {
        count += 1;
      }
    }
    return count > 1000;
  });
}

// Clicks across the preview until a piece is selected; its placement index
// and the point clicked
async function selectSomePiece(page: Page): Promise<{ placement: string; x: number; y: number }> {
  const box = await (await page.$('#preview'))?.boundingBox();
  assert.ok(box);
  // Nothing selected first, so an earlier selection is not taken for a hit
  await page.mouse.click(box.x + 2, box.y + 2);
  await page.waitForFunction(() => Number(document.body.dataset.selected ?? '-1') < 0);
  const steps = 6;
  for (let row = 1; row < steps; row += 1) {
    for (let column = 1; column < steps; column += 1) {
      // One click at a time, each waiting for the engine's answer
      const x = box.x + (box.width * column) / steps;
      const y = box.y + (box.height * row) / steps;
      // oxlint-disable-next-line no-await-in-loop
      await page.mouse.click(x, y);
      // oxlint-disable-next-line no-await-in-loop
      const selected = await page
        .waitForFunction(() => Number(document.body.dataset.selected ?? '-1') >= 0, { timeout: 300 })
        .then(
          () => true,
          () => false,
        );
      if (selected) {
        // oxlint-disable-next-line no-await-in-loop
        return { placement: await bodyData(page, 'selected'), x, y };
      }
    }
  }
  throw new Error('no click selected a piece');
}

const folder = await mkdtemp(join(tmpdir(), 'opensloper-publish-'));
const downloads = join(folder, 'downloads');
const app = await serveApp({ root: 'out/publish' });
const browser = await launchBrowser();
try {
  const layoutFile = join(folder, 'skirt.slayout');
  await writeFile(layoutFile, JSON.stringify(LAYOUT));
  const page = await browser.newPage();
  const problems = watchProblems(page);
  const session = await page.createCDPSession();
  await session.send('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: downloads });
  await page.goto(`http://127.0.0.1:${String(app.port)}/`);
  await waitForData(page, 'ready', 'true');
  const input = await page.$('input#open-input');
  assert.ok(input);

  await input.uploadFile(PATTERN);
  await waitForStatus(page, 'The layout needs skirt.slm');
  assert.match(await page.$eval('#problem-count', (count) => count.textContent), /stop printing/u);

  await input.uploadFile(PATTERN, MEASUREMENTS);
  await waitForStatus(page, 'Started a layout for skirt-darts.sloper');
  assert.equal(await page.title(), '• skirt-darts — OpenSloper Publish', 'not saved yet');
  assert.doesNotMatch(await status(page), /stop printing/u);
  await waitForPaper(page);
  // The Patterns tab: each change one step, files chosen by the browser
  await openTab(page, 'patterns');
  await page.waitForFunction(() => document.querySelector('.patterns-list li')?.textContent === 'skirt-darts.sloper');
  const addPicker = await page.$('.patterns input[type="file"][multiple]');
  assert.ok(addPicker);
  await addPicker.uploadFile(OTHER_PATTERN);
  await waitForMessagePart(page, 'new copies in the tray');
  await waitForUndo(page, 'Add pattern');
  assert.equal((await page.$$('.patterns-list li')).length, 2);
  await page.click('.patterns-list li[data-index="1"]');
  await patternsButton(page, 'Remove pattern');
  await waitForUndo(page, 'Remove pattern');
  await page.waitForFunction(() => document.querySelectorAll('.patterns-list li').length === 1);
  const setPicker = await page.$('.patterns input[type="file"]:not([multiple])');
  assert.ok(setPicker);
  await setPicker.uploadFile(SIZE_TABLE);
  await waitForUndo(page, 'Change measurements');
  await page.waitForSelector('.patterns select[name="size"]:enabled option[value="12"]');
  assert.equal(await page.$eval('.patterns-set', (name) => name.textContent), 'size-table.slm');
  await page.select('.patterns select[name="size"]', '12');
  await waitForUndo(page, 'Change size');
  await page.waitForFunction(
    () => document.querySelector('.patterns-list li')?.textContent === 'skirt-darts.sloper, size 12',
  );
  await patternsButton(page, "Use the pattern's own");
  await page.waitForFunction(() => document.querySelector('.patterns-set')?.textContent === 'skirt.slm');
  await page.waitForFunction(() => document.querySelector('.patterns-list li')?.textContent === 'skirt-darts.sloper');

  const { placement: selected } = await selectSomePiece(page);
  // The selected piece turned, flipped and sent back to the tray, each one step
  await piecesButton(page, 'Turn 90°');
  await waitForUndo(page, 'Turn piece');
  await piecesButton(page, 'Flip');
  await waitForUndo(page, 'Flip piece');
  await piecesButton(page, 'Back to tray');
  await waitForUndo(page, 'Unplace piece');
  await waitForData(page, 'selected', '-1');
  // A double-click in the tray places it again, selected
  const waiting = await page.waitForSelector('.tray-list li[data-index="0"]', { visible: true });
  assert.ok(waiting);
  await waiting.click({ count: 2 });
  await waitForUndo(page, 'Place piece');
  await page.waitForFunction(() => Number(document.body.dataset.selected ?? '-1') >= 0);
  await page.waitForFunction(() => document.querySelector('.tray-list li')?.textContent === 'Every piece is placed');
  // A drag moves a piece, one step however many moves
  const grabbed = await selectSomePiece(page);
  await page.mouse.move(grabbed.x, grabbed.y);
  await page.mouse.down();
  for (let step = 1; step <= 6; step += 1) {
    // oxlint-disable-next-line no-await-in-loop
    await page.mouse.move(grabbed.x + step * 10, grabbed.y + step * 4);
  }
  await page.mouse.up();
  await waitForUndo(page, 'Move piece');
  assert.equal(await bodyData(page, 'selected'), grabbed.placement, 'still selected');
  // A copy dragged from the tray is placed where it is let go
  await piecesButton(page, 'Back to tray');
  await waitForUndo(page, 'Unplace piece');
  await page.waitForSelector('.tray-list li[data-index="0"][draggable="true"]');
  await page.evaluate(() => {
    const line = document.querySelector('.tray-list li[data-index="0"]');
    const canvas = document.querySelector('#preview');
    if (line === null || canvas === null) {
      throw new Error('no tray line or preview');
    }
    const bounds = canvas.getBoundingClientRect();
    const carried = new DataTransfer();
    line.dispatchEvent(new DragEvent('dragstart', { bubbles: true, dataTransfer: carried }));
    const at = { clientX: bounds.left + bounds.width / 2, clientY: bounds.top + bounds.height / 2 };
    canvas.dispatchEvent(new DragEvent('dragover', { bubbles: true, cancelable: true, dataTransfer: carried, ...at }));
    canvas.dispatchEvent(new DragEvent('drop', { bubbles: true, cancelable: true, dataTransfer: carried, ...at }));
  });
  await waitForUndo(page, 'Place piece');
  await page.waitForFunction(() => Number(document.body.dataset.selected ?? '-1') >= 0);
  // A click on the desk's corner selects nothing
  const box = await (await page.$('#preview'))?.boundingBox();
  assert.ok(box);
  await page.mouse.click(box.x + 2, box.y + 2);
  await waitForData(page, 'selected', '-1');
  assert.notEqual(selected, '-1');
  // The view zooms without failing, and fits again
  await command(page, 'Zoom In');
  await command(page, 'Fit Pages');

  // Pack, undone and redone, each one step
  await piecesButton(page, 'Pack pieces');
  await waitForStatus(page, 'Packed');
  await waitForUndo(page, 'Pack pieces');
  await command(page, 'Undo');
  await waitForUndo(page, 'Place piece');
  await command(page, 'Redo');
  await waitForUndo(page, 'Pack pieces');

  // The Output tab: each change one step, as the desktop's
  await openTab(page, 'output');
  await page.waitForSelector('.output select[name="paper"] option[value="A3"]');
  await page.select('.output select[name="paper"]', 'A3');
  await waitForUndo(page, 'Change paper');
  await waitForMessagePart(page, 'pages, ');
  await page.$eval('.output input[name="margin"]', (margin) => {
    if (margin instanceof HTMLInputElement) {
      margin.value = '200';
      margin.dispatchEvent(new Event('change'));
    }
  });
  await waitForStatus(page, 'The margin and overlap leave nothing to print on');
  // Put back as it was, since the engine refused it
  await page.waitForFunction(
    () => document.querySelector<HTMLInputElement>('.output input[name="margin"]')?.value !== '200',
  );
  await page.select('.output select[name="kind"]', 'large');
  await waitForStatus(page, 'One sheet');
  // The tab reads its settings again after the status changes
  await page.waitForSelector('.output input[name="rollWidth"]:enabled');
  await page.waitForSelector('.output select[name="paper"]:disabled');
  await page.select('.output select[name="kind"]', 'tiled');
  await waitForMessagePart(page, ', 0 left out');
  // A right-click leaves the page under it out, and again puts it back
  const sheet = await (await page.$('#preview'))?.boundingBox();
  assert.ok(sheet);
  await page.mouse.click(sheet.x + sheet.width / 2, sheet.y + sheet.height / 2, { button: 'right' });
  await waitForUndo(page, 'Leave page out');
  await waitForMessagePart(page, ', 1 left out');
  await page.mouse.click(sheet.x + sheet.width / 2, sheet.y + sheet.height / 2, { button: 'right' });
  await waitForMessagePart(page, ', 0 left out');

  // A sheet note: added below the pieces, chosen, and its text typed over
  await openTab(page, 'notes');
  await notesButton(page, 'Add note');
  await waitForUndo(page, 'Add note');
  await waitForData(page, 'note', '0');
  await page.waitForFunction(() => document.activeElement?.getAttribute('name') === 'text');
  // A font the engine cannot use is refused and said, before anything is typed
  await page.$eval('.notes input[name="font"]', (font) => {
    if (font instanceof HTMLInputElement) {
      font.value = 'Serif, Sans';
      font.dispatchEvent(new Event('change'));
    }
  });
  await waitForStatus(page, 'A font name cannot hold ,');
  await page.$eval('.notes textarea', (area) => {
    if (area instanceof HTMLTextAreaElement) {
      area.focus();
      area.select();
    }
  });
  await page.keyboard.type('Cut on the bias');
  await waitForUndo(page, 'Change note');
  await page.waitForFunction(
    () => document.querySelector<HTMLTextAreaElement>('.notes textarea')?.value === 'Cut on the bias',
  );
  // Large enough to see and grab at the fitted zoom, then dragged by its middle, one step
  await page.$eval('.notes input[name="size"]', (size) => {
    if (size instanceof HTMLInputElement) {
      size.value = '120';
      size.dispatchEvent(new Event('change'));
    }
  });
  await page.waitForFunction(
    () => document.querySelector<HTMLInputElement>('.notes input[name="size"]')?.value === '120',
  );
  await command(page, 'Fit Pages');
  await new Promise((resolve) => {
    setTimeout(resolve, 300);
  });
  const note = await selectionMiddle(page);
  await page.mouse.move(note.x, note.y);
  await page.mouse.down();
  for (let step = 1; step <= 5; step += 1) {
    // oxlint-disable-next-line no-await-in-loop
    await page.mouse.move(note.x + step * 8, note.y);
  }
  await page.mouse.up();
  await waitForUndo(page, 'Move note');
  assert.equal(await bodyData(page, 'note'), '0', 'still chosen');
  await notesButton(page, 'Delete note');
  await waitForUndo(page, 'Delete note');
  await waitForData(page, 'note', '-1');

  // The Materials tab lists what the skirt needs, a row a material
  await openTab(page, 'materials');
  await page.waitForFunction(() => {
    const cells = document.querySelectorAll('.needs-table tbody tr:first-child td');
    return cells.length === 4 && cells[0]?.textContent !== '' && cells[0]?.textContent !== 'No pieces';
  });

  // The Info tab: each change one step
  await openTab(page, 'info');
  await page.waitForSelector('.info input[name="field:date"]:checked');
  await page.click('.info input[name="field:date"]');
  await waitForUndo(page, 'Change title block');
  await page.waitForSelector('.info input[name="field:date"]:not(:checked)');
  await page.click('.info input[name="field:date"]');
  await page.waitForSelector('.info input[name="field:date"]:checked');
  await page.select('.info select[name="corner"]', 'topRight');
  await page.click('.info input[name="enabled"]');
  await page.waitForSelector('.info input[name="field:date"]:disabled');
  await page.click('.info input[name="enabled"]');
  await page.waitForSelector('.info input[name="field:date"]:enabled');

  // Saved as a download, counted saved; then exported
  await command(page, 'Save');
  await waitForStatus(page, 'Downloaded skirt-darts.slayout');
  const saved = (await download(downloads, 'skirt-darts.slayout')).toString();
  assert.match(saved, /"placements"/u);
  await page.waitForFunction(() => document.title === 'skirt-darts — OpenSloper Publish');
  await command(page, 'Export PDF');
  assert.equal((await download(downloads, 'skirt-darts.pdf')).subarray(0, 5).toString(), '%PDF-');
  await command(page, 'Export SVG');
  assert.match((await download(downloads, 'skirt-darts.svg')).toString(), /<svg/u);
  await command(page, 'Export DXF');
  assert.match((await download(downloads, 'skirt-darts.dxf')).toString(), /SECTION/u);

  // The saved layout opens again as it was
  await input.uploadFile(join(downloads, 'skirt-darts.slayout'), PATTERN, MEASUREMENTS);
  await waitForStatus(page, 'Opened skirt-darts.slayout');
  assert.equal(await page.title(), 'skirt-darts — OpenSloper Publish');

  await input.uploadFile(layoutFile, PATTERN, MEASUREMENTS);
  await waitForStatus(page, 'Opened skirt.slayout');
  assert.equal(await page.title(), 'Skirt for cutting — OpenSloper Publish');
  // Every file was found; its pieces wait in the tray, so nothing would print
  assert.doesNotMatch(await status(page), /needs/u);
  assert.match(await page.$eval('#problem-count', (count) => count.textContent), /stop printing/u);
  // The count opens the Problems tab, the one that stops printing in red
  await page.click('#problem-count');
  await page.waitForSelector('.problems-list li.blocking', { visible: true });
  assert.match(await page.$eval('.side-title', (title) => title.textContent), /^Problems \(\d+\)$/u);
  // Its tray lists them until they are placed
  assert.ok((await page.$$('.tray-list li[data-index]')).length > 0);
  await piecesButton(page, 'Place new pieces');
  await waitForStatus(page, 'Placed');
  assert.doesNotMatch(await status(page), /stop printing/u);

  await input.uploadFile(MEASUREMENTS);
  await waitForStatus(page, 'skirt.slm is not a layout');

  assert.deepEqual(problems, []);
  console.log('Publish app passed');
} finally {
  await browser.close();
  app.close();
  await rm(folder, { recursive: true, force: true });
}
