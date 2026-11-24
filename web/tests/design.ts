// Drives the built design app (out/design, from npm run build) in headless
// Chromium as a user would: adds a point to the empty pattern it starts with
// and checks it stays where it was clicked, opens a regression pattern with its measurements,
// checks the canvas drew it and its rulers, hides and shows them, adds a point with the Point tool, drags it with
// the Select tool and undoes, edits it in the Properties tab, then uses each
// drawing tool and drags a curve's handle, a note and a callout's tip. It edits a measurement and saves the
// set, whose download it reads, and tries the test size. Serves the app itself on a free port. Node runs
// this TypeScript as it is; CHROMIUM names the browser, /usr/bin/chromium by
// default, and SCREENSHOT, a file name without .png, keeps a picture of the end. It opens and saves
// through uploads and downloads, as where the browser has no File System Access.
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { KeyInput, Page } from 'puppeteer-core';
import {
  bodyData,
  launchBrowser,
  serveApp,
  status,
  TIMEOUT_MS,
  waitForData,
  waitForStatus,
  watchProblems,
} from './browser.ts';

const PATTERNS = '../tests/patterns';
// The canvas's paper colour, which an empty canvas is all of but the grid
const PAPER = [252, 251, 248];
// Pixels of the pattern's ink an opened skirt draws at the least
const MIN_INKED_PIXELS = 500;
const DRAG_PIXELS = 40;
// How long the page is watched while idle, in ms
const IDLE_MS = 1000;

const { port, close } = await serveApp();

// A row's field or box in the Properties tab
function field(row: string): string {
  return `.property-value[data-row="${row}"] input`;
}

// Chooses a tool by its button, whose hint is its caption and keys
async function chooseTool(page: Page, caption: string): Promise<void> {
  await page.click(`#tools button[title^="${caption} ("]`);
}

// Clicks the canvas at a place relative to its top left
async function clickAt(page: Page, origin: { x: number; y: number }, x: number, y: number): Promise<void> {
  await page.mouse.move(origin.x + x, origin.y + y);
  // The snap shown is the one clicked: let it catch up, as a user's hand does
  await new Promise((resolve) => setTimeout(resolve, 100));
  await page.mouse.click(origin.x + x, origin.y + y);
}

// The Measurements tab's button, by its caption
function measurementButton(caption: 'Add' | 'Save' | 'Revert'): string {
  return `.list-panel:not([hidden]) .list-buttons button:nth-child(${String(['Add', 'Save', 'Revert'].indexOf(caption) + 1)})`;
}

// Whether the control is disabled
async function isDisabled(page: Page, selector: string): Promise<boolean> {
  return page.$eval(selector, (control) =>
    control instanceof HTMLInputElement || control instanceof HTMLButtonElement || control instanceof HTMLSelectElement
      ? control.disabled
      : false,
  );
}

// Pixels of the canvas that are neither paper nor the grid's light lines
async function inkedPixels(page: Page): Promise<number> {
  return page.$eval(
    '#canvas',
    (canvas, paper) => {
      if (!(canvas instanceof HTMLCanvasElement)) {
        return 0;
      }
      const data = canvas.getContext('2d')?.getImageData(0, 0, canvas.width, canvas.height).data ?? [];
      let count = 0;
      for (let index = 0; index < data.length; index += 4) {
        const red = data[index] ?? 0;
        const green = data[index + 1] ?? 0;
        const blue = data[index + 2] ?? 0;
        // The grid is within 40 of the paper; ink is darker or coloured
        if (
          Math.abs(red - (paper[0] ?? 0)) + Math.abs(green - (paper[1] ?? 0)) + Math.abs(blue - (paper[2] ?? 0)) >
          120
        ) {
          count++;
        }
      }
      return count;
    },
    PAPER,
  );
}

// Whether the canvas has ink within a few pixels of a place relative to its top left
async function inkedNear(page: Page, x: number, y: number): Promise<boolean> {
  return page.$eval(
    '#canvas',
    (canvas, place, paper) => {
      if (!(canvas instanceof HTMLCanvasElement)) {
        return false;
      }
      const ratio = window.devicePixelRatio;
      const reach = Math.round(3 * ratio);
      const data =
        canvas
          .getContext('2d')
          ?.getImageData(Math.round(place.x * ratio) - reach, Math.round(place.y * ratio) - reach, 2 * reach, 2 * reach)
          .data ?? [];
      for (let index = 0; index < data.length; index += 4) {
        const difference =
          Math.abs((data[index] ?? 0) - (paper[0] ?? 0)) +
          Math.abs((data[index + 1] ?? 0) - (paper[1] ?? 0)) +
          Math.abs((data[index + 2] ?? 0) - (paper[2] ?? 0));
        if (difference > 120) {
          return true;
        }
      }
      return false;
    },
    { x, y },
    PAPER,
  );
}

const browser = await launchBrowser();
// Where the page's downloads go, removed at the end
const downloads = await mkdtemp(join(tmpdir(), 'opensloper-design-'));
try {
  // Copy and Paste use the clipboard, which a user's browser would offer
  await browser
    .defaultBrowserContext()
    .overridePermissions(`http://127.0.0.1:${String(port)}`, ['clipboard-read', 'clipboard-sanitized-write']);
  const page = await browser.newPage();
  const session = await page.createCDPSession();
  await session.send('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: downloads });
  await page.setViewport({ width: 1200, height: 800 });
  const problems = watchProblems(page);
  // Opening an example over unsaved changes asks first
  const dialogs: string[] = [];
  page.on('dialog', (dialog) => {
    dialogs.push(dialog.message());
    void dialog.accept();
  });
  // Opening and saving through uploads and downloads, as where the browser
  // has no File System Access (files.ts drives that)
  await page.evaluateOnNewDocument(() => {
    for (const name of ['showOpenFilePicker', 'showSaveFilePicker', 'showDirectoryPicker']) {
      Object.defineProperty(window, name, { value: undefined });
    }
  });
  // Counts the scenes asked of the engine, in body data, to check an idle page asks nothing
  await page.evaluateOnNewDocument(() => {
    // Kept to be called with each worker as this, through Reflect.apply
    // oxlint-disable-next-line typescript/unbound-method
    const original = Worker.prototype.postMessage;
    Object.defineProperty(Worker.prototype, 'postMessage', {
      value: function (this: Worker, ...args: unknown[]): unknown {
        const request = JSON.stringify(args[0]);
        if (request.includes('editor_drag_to')) {
          document.body.dataset.dragMoved = 'true';
        } else if (request.includes('editor_drag_cancel')) {
          document.body.dataset.dragCancelled = 'true';
        }
        if (request.includes('editor_scene')) {
          document.body.dataset.sceneCalls = String(Number(document.body.dataset.sceneCalls ?? '0') + 1);
        }
        return Reflect.apply(original, this, args);
      },
    });
  });
  await page.goto(`http://127.0.0.1:${String(port)}/`);
  await waitForData(page, 'ready', 'true');

  // The first point added to the empty pattern stays where it was clicked:
  // the view once fitted itself round it, as if a pattern had been opened (#83)
  const emptyCanvas = await (await page.$('#canvas'))?.boundingBox();
  assert.ok(emptyCanvas !== null && emptyCanvas !== undefined, 'the canvas has a place');
  await page.keyboard.press('p');
  await clickAt(page, emptyCanvas, 60, 60);
  await waitForData(page, 'undo', 'Add point');
  await page.waitForFunction(() => new Promise((resolve) => requestAnimationFrame(() => resolve(true))));
  await new Promise((resolve) => setTimeout(resolve, 500));
  assert.ok(await inkedNear(page, 60, 60), 'the first point is drawn where it was clicked');
  await page.keyboard.press('s');
  const touchPoint = { x: Math.round(emptyCanvas.x + 60), y: Math.round(emptyCanvas.y + 60) };
  const draggedPoint = { x: touchPoint.x + DRAG_PIXELS, y: touchPoint.y + DRAG_PIXELS };
  await session.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [touchPoint] });
  await session.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [draggedPoint] });
  await waitForData(page, 'dragMoved', 'true');
  await session.send('Input.dispatchTouchEvent', { type: 'touchCancel', touchPoints: [] });
  await waitForData(page, 'dragCancelled', 'true');
  await page.waitForSelector('button[title="Undo Add point"]:enabled', { timeout: TIMEOUT_MS });
  await clickAt(page, emptyCanvas, 150, 150);
  assert.equal(await bodyData(page, 'undo'), 'Add point', 'a later click does not commit the cancelled drag');
  assert.ok(await inkedNear(page, 60, 60), 'the cancelled drag put the point back');
  await page.keyboard.down('Control');
  await page.keyboard.press('z');
  await page.keyboard.up('Control');
  await waitForData(page, 'undo', '');
  await page.keyboard.press('s');

  // Import… on the Variables tab adds another pattern's variables, chosen in
  // the tab, as one undo step; one in another unit is refused in a dialog
  await page.click('.side-column [data-tab="variables"]');
  const importFrom = async (file: string): Promise<void> => {
    const [chooser] = await Promise.all([
      page.waitForFileChooser({ timeout: TIMEOUT_MS }),
      page.click('.list-panel:not([hidden]) .list-buttons button:nth-child(3)'),
    ]);
    await chooser.accept([join(PATTERNS, file)]);
  };
  await importFrom('skirt-block.sloper');
  await waitForData(page, 'undo', 'Import variables');
  await waitForStatus(page, 'Imported 6 variables from skirt-block.sloper');
  await page.waitForFunction(
    () => document.querySelectorAll('.list-panel:not([hidden]) tbody tr.selected').length === 6,
    { timeout: TIMEOUT_MS },
  );
  const dialogsBeforeImport = dialogs.length;
  await importFrom('bodice-block.sloper');
  await page.waitForFunction(() => document.querySelector('#status')?.textContent.includes('convert') === true, {
    timeout: TIMEOUT_MS,
  });
  assert.equal(dialogs.length, dialogsBeforeImport + 1, 'a refused import says so in a dialog');
  assert.equal(await bodyData(page, 'undo'), 'Import variables', 'a refused import changes nothing');
  await page.keyboard.down('Control');
  await page.keyboard.press('z');
  await page.keyboard.up('Control');
  await waitForData(page, 'undo', '');

  const input = await page.$('input#open-input');
  assert.ok(input !== null, 'the open input');
  await input.uploadFile(join(PATTERNS, 'skirt-pieces.sloper'), join(PATTERNS, 'skirt-small.slm'));
  await page.waitForFunction(() => document.querySelector('#status')?.textContent.startsWith('Measurements from'), {
    timeout: TIMEOUT_MS,
  });
  assert.equal(await page.title(), 'skirt-pieces.sloper — OpenSloper', 'the title');
  // The scene comes after the change, and is drawn on the next frame
  await page.waitForFunction(() => new Promise((resolve) => requestAnimationFrame(() => resolve(true))));
  await new Promise((resolve) => setTimeout(resolve, 500));
  const inked = await inkedPixels(page);
  assert.ok(inked > MIN_INKED_PIXELS, `the pattern is drawn: ${String(inked)} pixels`);
  // Opening fitted all of it, measurements and all, so Fit changes nothing
  await page.click('#toolbar button[title="Fit everything in the window"]');
  await new Promise((resolve) => setTimeout(resolve, 500));
  assert.equal(await inkedPixels(page), inked, 'opened fitted to the window');
  // The rulers count in the pattern's unit, and the Rulers key hides and shows them
  const rulersShown = async (): Promise<boolean> =>
    page.$eval('.ruler-top', (ruler) => ruler.getBoundingClientRect().height > 0);
  assert.equal(await page.$eval('.ruler-corner', (corner) => corner.textContent), 'mm', 'the rulers count in mm');
  assert.ok(await rulersShown(), 'the rulers show');
  await page.keyboard.down('Control');
  await page.keyboard.press('r');
  await page.keyboard.up('Control');
  assert.ok(!(await rulersShown()), 'the Rulers key hides them');
  await page.click('#toolbar button[title^="Show or hide the rulers"]');
  assert.ok(await rulersShown(), 'the Rulers button shows them');
  // Fitting after each scene once led to a new scene after each fit, forever
  const calls = async (): Promise<number> => Number(await bodyData(page, 'sceneCalls'));
  const callsBefore = await calls();
  await new Promise((resolve) => setTimeout(resolve, IDLE_MS));
  assert.equal((await calls()) - callsBefore, 0, 'an idle page asks the engine for nothing');

  // The side panel's lists: choosing an object selects it on the canvas, search narrows them
  await page.click('.side-column [data-tab="objects"]');
  const shownRows = async (): Promise<number> => (await page.$$('.list-panel:not([hidden]) tbody tr')).length;
  await page.waitForFunction(() => document.querySelectorAll('.list-panel:not([hidden]) tbody tr').length > 0);
  const allRows = await shownRows();
  const firstKey = await page.$eval('.list-panel:not([hidden]) tbody tr', (row) => (row as HTMLElement).dataset.key);
  await page.click('.list-panel:not([hidden]) tbody tr');
  await waitForData(page, 'selection', firstKey ?? '');
  await page.type('.list-panel:not([hidden]) input[type=search]', 'curve');
  await page.waitForFunction(
    (before) => document.querySelectorAll('.list-panel:not([hidden]) tbody tr').length < before,
    {},
    allRows,
  );
  // A variable added, named and given a formula in the Variables tab, each one undo step
  await page.click('.side-column [data-tab="variables"]');
  await page.click('.list-panel:not([hidden]) .list-buttons button:first-child');
  await waitForData(page, 'undo', 'Add variable');
  await page.waitForSelector('input.cell-editor', { timeout: TIMEOUT_MS });
  await page.keyboard.type('ease');
  await page.keyboard.press('Enter');
  await waitForData(page, 'undo', 'Rename variable');
  await page.keyboard.press('ArrowRight');
  await page.keyboard.type('12 +');
  await page.keyboard.press('Enter');
  await page.waitForSelector('.list-panel:not([hidden]) td.refused', { timeout: TIMEOUT_MS });
  assert.notEqual(await status(page), '', 'says why the formula was refused');
  await page.keyboard.press('Enter');
  await page.keyboard.press('Backspace');
  await page.keyboard.type('12 * 2');
  await page.keyboard.press('Enter');
  await waitForData(page, 'undo', 'Edit variable formula');
  // The refusal clears once the rows come back
  await page.waitForFunction(() => document.querySelector('.list-panel:not([hidden]) td.refused') === null, {
    timeout: TIMEOUT_MS,
  });
  // Ctrl+Space offers every name; Escape closes the list, then the cell
  await page.keyboard.press('Enter');
  await page.keyboard.press('Backspace');
  await page.keyboard.down('Control');
  await page.keyboard.press('Space');
  await page.keyboard.up('Control');
  await page.waitForSelector('.completer:not([hidden]) li', { timeout: TIMEOUT_MS });
  await page.keyboard.press('Escape');
  await page.keyboard.press('Escape');
  await page.waitForFunction(() => document.querySelector('input.cell-editor') === null, { timeout: 3000 });
  await page.click('.list-panel:not([hidden]) .list-buttons button:nth-child(2)');
  await waitForData(page, 'undo', 'Delete variable');
  // A measurement's value edited is kept in bold until Save makes it and downloads the set
  await page.click('.side-column [data-tab="measurements"]');
  await page.waitForFunction(() => document.querySelectorAll('.list-panel:not([hidden]) tbody tr').length > 0);
  assert.equal(await page.$eval('#measurement-file', (label) => label.textContent), 'skirt-small.slm', 'the set');
  await page.click('.list-panel:not([hidden]) tbody tr:first-child td:nth-child(2)');
  await page.keyboard.type('eight');
  await page.keyboard.press('Enter');
  await page.waitForSelector('.list-panel:not([hidden]) td.refused', { timeout: TIMEOUT_MS });
  await page.keyboard.press('Enter');
  await page.keyboard.press('Backspace');
  await page.keyboard.type('777.5');
  await page.keyboard.press('Enter');
  await page.waitForSelector('.list-panel:not([hidden]) tr.marked', { timeout: TIMEOUT_MS });
  assert.ok(await isDisabled(page, '#measurement-test'), 'no test sizes while edits wait');
  await page.click(measurementButton('Save'));
  await page.waitForFunction(() => document.querySelector('.list-panel:not([hidden]) tr.marked') === null, {
    timeout: TIMEOUT_MS,
  });
  let saved = '';
  for (let tries = 0; tries < 50 && !saved.includes('777.5'); tries++) {
    // oxlint-disable-next-line no-await-in-loop
    saved = await readFile(join(downloads, 'skirt-small.slm'), 'utf8').catch(() => '');
    // oxlint-disable-next-line no-await-in-loop
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  assert.ok(saved.includes('777.5'), 'the set downloaded with the edit');
  // Add gives a new key to name; Revert drops it
  await page.click(measurementButton('Add'));
  await page.waitForSelector('input.cell-editor', { timeout: TIMEOUT_MS });
  await page.keyboard.type('seat');
  await page.keyboard.press('Enter');
  await page.waitForSelector('.list-panel:not([hidden]) tr.marked[data-key="seat"]', { timeout: TIMEOUT_MS });
  await page.click(measurementButton('Revert'));
  await page.waitForFunction(() => document.querySelector('.list-panel:not([hidden]) tr.marked') === null, {
    timeout: TIMEOUT_MS,
  });
  // A test size pauses editing until it is reset
  await page.$eval('#measurement-test', (slider) => {
    if (slider instanceof HTMLInputElement) {
      slider.value = '5';
      slider.dispatchEvent(new Event('input'));
    }
  });
  const addDisabled = async (disabled: boolean): Promise<void> => {
    await page.waitForFunction(
      (add, wanted) => {
        const button = document.querySelector(add);
        return button instanceof HTMLButtonElement && button.disabled === wanted;
      },
      { timeout: TIMEOUT_MS },
      measurementButton('Add'),
      disabled,
    );
  };
  await addDisabled(true);
  await page.click('.measurement-test button');
  await addDisabled(false);
  await page.click('.side-column [data-tab="objects"]');
  await page.keyboard.press('Escape');
  await waitForData(page, 'selection', '');

  const canvas = await page.$('#canvas');
  const box = await canvas?.boundingBox();
  assert.ok(box !== null && box !== undefined, 'the canvas has a place');
  // Near the top left, clear of the fitted pattern
  const at = { x: box.x + 30, y: box.y + 30 };
  await page.keyboard.press('p');
  await page.mouse.move(at.x, at.y);
  await page.mouse.click(at.x, at.y);
  await waitForData(page, 'undo', 'Add point');
  assert.equal(await bodyData(page, 'modified'), 'true', 'modified');
  const added = await bodyData(page, 'selection');
  assert.ok(added !== '', 'the new point is selected');

  await page.keyboard.press('s');
  await page.mouse.move(at.x, at.y);
  await page.mouse.down();
  for (let step = 1; step <= 4; step++) {
    // oxlint-disable-next-line no-await-in-loop
    await page.mouse.move(at.x + (DRAG_PIXELS * step) / 4, at.y + (DRAG_PIXELS * step) / 4);
  }
  await page.mouse.up();
  await waitForData(page, 'undo', 'Move point');
  assert.equal(await bodyData(page, 'selection'), added, 'the dragged point stays selected');

  await page.keyboard.down('Control');
  await page.keyboard.press('z');
  await page.keyboard.up('Control');
  await waitForData(page, 'undo', 'Add point');

  // The Delete key deletes what is selected, as one undo step, and so does
  // the Delete button, which is disabled while nothing is selected
  const deleteButton = '#toolbar button[title^="Delete the selected objects"]';
  assert.equal(await bodyData(page, 'selection'), added, 'the point is still selected');
  await page.keyboard.press('Delete');
  await waitForData(page, 'undo', 'Delete');
  await waitForData(page, 'selection', '');
  assert.ok(await isDisabled(page, deleteButton), 'nothing selected, nothing to delete');
  await page.keyboard.down('Control');
  await page.keyboard.press('z');
  await page.keyboard.up('Control');
  await waitForData(page, 'undo', 'Add point');
  await page.mouse.click(at.x, at.y);
  await waitForData(page, 'selection', added);
  assert.ok(!(await isDisabled(page, deleteButton)), 'something to delete');
  await page.click(deleteButton);
  await waitForData(page, 'undo', 'Delete');
  await waitForData(page, 'selection', '');
  await page.keyboard.down('Control');
  await page.keyboard.press('z');
  await page.keyboard.up('Control');
  await waitForData(page, 'undo', 'Add point');
  await page.mouse.click(at.x, at.y);
  await waitForData(page, 'selection', added);

  // Change point to… needs a selection; the point is free already, so making
  // it free is refused with the reason, and the box goes back to its caption
  assert.ok(!(await isDisabled(page, '#point-type')), 'a point to change');
  await page.select('#point-type', 'freePoint');
  await page.waitForFunction(
    () => document.querySelector('#status')?.textContent.endsWith('is already placed that way'),
    { timeout: TIMEOUT_MS },
  );
  assert.equal(
    await page.$eval('#point-type', (select) => (select instanceof HTMLSelectElement ? select.value : undefined)),
    '',
    'back to its caption',
  );
  assert.equal(await bodyData(page, 'undo'), 'Add point', 'nothing changed');

  // Copy puts the point's fragment on the clipboard; Paste, the button or the
  // paste key, makes a selected copy of it, and Cut copies and deletes, each one undo step
  const pressWithControl = async (key: KeyInput): Promise<void> => {
    await page.keyboard.down('Control');
    await page.keyboard.press(key);
    await page.keyboard.up('Control');
  };
  await pressWithControl('c');
  await waitForStatus(page, 'Copied');
  const fragment = await page.evaluate(async () => navigator.clipboard.readText());
  assert.ok(fragment.length > 0, 'the fragment is on the clipboard');
  await page.click('#toolbar button[title^="Paste copies"]');
  await waitForData(page, 'undo', 'Paste');
  const copy = await bodyData(page, 'selection');
  assert.ok(copy !== '' && copy !== added, 'the copy is selected');
  await pressWithControl('x');
  await waitForData(page, 'undo', 'Cut');
  await waitForData(page, 'selection', '');
  // As the paste key gives it
  await page.evaluate((text) => {
    const data = new DataTransfer();
    data.setData('text/plain', text);
    document.body.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true }));
  }, fragment);
  await page.waitForFunction(() => document.body.dataset.selection !== '', { timeout: TIMEOUT_MS });
  assert.equal(await bodyData(page, 'undo'), 'Paste', 'pasted from the paste key');
  for (const step of ['Cut', 'Paste', 'Add point']) {
    // oxlint-disable-next-line no-await-in-loop
    await pressWithControl('z');
    // oxlint-disable-next-line no-await-in-loop
    await waitForData(page, 'undo', step);
  }
  await page.mouse.click(at.x, at.y);
  await waitForData(page, 'selection', added);

  // The Properties tab shows the point: renamed, a formula refused and put back, then one taken,
  // a marker chosen, which adds the marker's size, the point locked and unlocked, and its name put
  // back, as the rectangle's corners are named after the points before them
  await page.click('.side-column [data-tab="properties"]');
  const fieldText = async (row: string): Promise<string> =>
    page.$eval(field(row), (shown) => (shown instanceof HTMLInputElement ? shown.value : ''));
  const retype = async (row: string, text: string): Promise<void> => {
    await page.$eval(field(row), (shown) => {
      if (shown instanceof HTMLInputElement) {
        shown.focus();
        shown.select();
      }
    });
    await page.keyboard.type(text);
    await page.keyboard.press('Enter');
  };
  await page.waitForSelector(field('name'), { timeout: TIMEOUT_MS });
  const pointName = await fieldText('name');
  await retype('name', 'Spot');
  await waitForData(page, 'undo', 'Rename');
  await retype('x', '12 +');
  await page.waitForSelector('[data-row="x"] .property-refusal:not([hidden])', { timeout: TIMEOUT_MS });
  assert.equal(await fieldText('x'), '12 +', 'kept to fix');
  await page.keyboard.press('Escape');
  await page.waitForSelector('[data-row="x"] .property-refusal[hidden]', { timeout: TIMEOUT_MS });
  await retype('y', `${await fieldText('y')} + 0`);
  await waitForData(page, 'undo', 'Change Y');
  await page.select('.property-value[data-row="marker"] select', '1');
  await waitForData(page, 'undo', 'Change marker');
  await page.waitForSelector(field('markerSize'), { timeout: TIMEOUT_MS });
  await page.click(field('locked'));
  await waitForData(page, 'undo', 'Lock');
  await page.waitForSelector(`${field('x')}[readonly]`, { timeout: TIMEOUT_MS });
  await page.click(field('locked'));
  await waitForData(page, 'undo', 'Unlock');
  await page.waitForSelector(`${field('x')}:not([readonly])`, { timeout: TIMEOUT_MS });
  // Its x's formula suggestions: the wand opens and closes them, hovering one previews it,
  // and Alt+Down, Down and Enter take the first
  const suggestion = '.suggest-list li[role="option"]';
  await page.click('[data-row="x"] .property-wand');
  await page.waitForSelector(suggestion, { timeout: TIMEOUT_MS });
  await page.hover(suggestion);
  await page.click('[data-row="x"] .property-wand');
  await page.waitForFunction(() => document.querySelector('.suggest-list') === null, { timeout: TIMEOUT_MS });
  await page.$eval(field('x'), (shown) => {
    if (shown instanceof HTMLInputElement) {
      shown.focus();
    }
  });
  await page.keyboard.down('Alt');
  await page.keyboard.press('ArrowDown');
  await page.keyboard.up('Alt');
  await page.waitForSelector(suggestion, { timeout: TIMEOUT_MS });
  const taken = await page.$eval(`${suggestion} .suggest-formula`, (shown) => shown.textContent);
  await page.keyboard.press('ArrowDown');
  await page.keyboard.press('Enter');
  await waitForData(page, 'undo', 'Change X');
  assert.equal(await fieldText('x'), taken, 'the suggestion taken');
  await retype('name', pointName);
  await waitForData(page, 'undo', 'Rename');

  // The drawing tools, in the empty space left of the pattern
  await chooseTool(page, 'Line');
  await clickAt(page, box, 60, 120);
  await clickAt(page, box, 200, 120);
  await waitForData(page, 'undo', 'Add line');
  await page.keyboard.press('Escape');

  // A curve, whose handles lie a third along it: selected, the first is dragged down
  await chooseTool(page, 'Curve');
  await clickAt(page, box, 60, 220);
  await clickAt(page, box, 210, 220);
  await waitForData(page, 'undo', 'Add curve');
  await page.keyboard.press('Escape');
  await chooseTool(page, 'Select');
  await clickAt(page, box, 135, 220);
  await page.waitForFunction(() => /^\d+$/.test(document.body.dataset.selection ?? ''));
  await new Promise((resolve) => setTimeout(resolve, 200));
  await page.mouse.move(box.x + 110, box.y + 220);
  await page.mouse.down();
  for (let step = 1; step <= 4; step++) {
    // oxlint-disable-next-line no-await-in-loop
    await page.mouse.move(box.x + 110, box.y + 220 + step * 10);
  }
  await page.mouse.up();
  await waitForData(page, 'undo', 'Move curve handle');

  await chooseTool(page, 'Rectangle');
  await clickAt(page, box, 60, 300);
  assert.match(await status(page), /opposite corner/, 'the rectangle asks for its other corner');
  await clickAt(page, box, 200, 450);
  await waitForData(page, 'undo', 'Add rectangle');
  assert.equal((await bodyData(page, 'selection')).split(' ').length, 4, 'its four edges selected');

  await chooseTool(page, 'Piece');
  await clickAt(page, box, 130, 375);
  await waitForData(page, 'undo', 'Add piece');
  // The new piece's rows: cut twice, folded on an edge and given its own colour
  await page.waitForSelector(field('cut'), { timeout: TIMEOUT_MS });
  await page.$eval(field('cut'), (shown) => {
    if (shown instanceof HTMLInputElement) {
      shown.value = '2';
      shown.dispatchEvent(new Event('change'));
    }
  });
  await waitForData(page, 'undo', 'Change cut');
  await page.select('.property-value[data-row="fold"] select', '1');
  await waitForData(page, 'undo', 'Change fold');
  await page.select('.property-value[data-row="fillColor"] select', '1');
  await waitForData(page, 'undo', 'Change fill');
  // An edge given its own allowance: its new row takes the cursor
  await page.select('.property-value[data-row="ownAllowance"] select', '1');
  await waitForData(page, 'undo', 'Add edge allowance');
  await page.waitForFunction(
    () => document.activeElement?.closest('.property-value')?.getAttribute('data-row')?.endsWith('.allowance') === true,
    { timeout: TIMEOUT_MS },
  );
  await chooseTool(page, 'Notch');
  await clickAt(page, box, 130, 300);
  await waitForData(page, 'undo', 'Add notch');

  await chooseTool(page, 'Circle');
  await clickAt(page, box, 130, 560);
  await clickAt(page, box, 170, 560);
  await waitForData(page, 'undo', 'Add circle or arc');

  // A seam from the rectangle piece's top edge to its bottom one
  await chooseTool(page, 'Seam');
  await clickAt(page, box, 100, 300);
  assert.match(await status(page), /^Side A/, 'side A picked');
  await page.keyboard.press('Tab');
  await page.waitForFunction(() => document.querySelector('#status')?.textContent.startsWith('Side B'));
  await clickAt(page, box, 100, 450);
  await page.keyboard.press('Enter');
  await waitForData(page, 'undo', 'Add seam');

  // A note: the Text tool adds it and opens its text to type
  await chooseTool(page, 'Text');
  await clickAt(page, box, 60, 650);
  await waitForData(page, 'undo', 'Add note');
  await page.waitForSelector('textarea.note-editor', { timeout: TIMEOUT_MS });
  await page.keyboard.type('Cut 2 on fold');
  await page.keyboard.down('Control');
  await page.keyboard.press('Enter');
  await page.keyboard.up('Control');
  await waitForData(page, 'undo', 'Change note');
  assert.equal(await page.$('textarea.note-editor'), null, 'the text field closed');

  // A callout from the circle's centre, its text to the right
  await chooseTool(page, 'Callout');
  await clickAt(page, box, 130, 560);
  assert.match(await status(page), /text goes/, 'asks where its text goes');
  await clickAt(page, box, 240, 600);
  await waitForData(page, 'undo', 'Add callout');
  const calloutId = await bodyData(page, 'selection');
  await page.waitForSelector('textarea.note-editor', { timeout: TIMEOUT_MS });
  await page.keyboard.press('Escape');

  // Dragging the note by its text
  await chooseTool(page, 'Select');
  await page.mouse.move(box.x + 64, box.y + 653);
  await page.mouse.down();
  for (let step = 1; step <= 4; step++) {
    // oxlint-disable-next-line no-await-in-loop
    await page.mouse.move(box.x + 64 + step * 10, box.y + 653 + step * 5);
  }
  await page.mouse.up();
  await waitForData(page, 'undo', 'Move note');
  // Its text retyped in the Properties tab, drawn on the canvas as it is typed, then on two
  // lines, and made bold
  await page.waitForSelector('.property-value[data-row="noteText"] textarea', { timeout: TIMEOUT_MS });
  const inkBefore = await inkedPixels(page);
  await page.$eval('.property-value[data-row="noteText"] textarea', (shown) => {
    if (shown instanceof HTMLTextAreaElement) {
      shown.focus();
      shown.select();
    }
  });
  await page.keyboard.type('Cut 2 on fold WWWWWWWWWWWWWWWW');
  await new Promise((resolve) => setTimeout(resolve, 300));
  assert.ok((await inkedPixels(page)) > inkBefore, 'the text typed shows on the canvas');
  await page.keyboard.down('Control');
  await page.keyboard.press('a');
  await page.keyboard.up('Control');
  await page.keyboard.type('Cut 2');
  await page.keyboard.press('Enter');
  await page.keyboard.type('on fold');
  await page.keyboard.down('Control');
  await page.keyboard.press('Enter');
  await page.keyboard.up('Control');
  await waitForData(page, 'undo', 'Change note text');
  await page.click(field('noteBold'));
  await waitForData(page, 'undo', 'Change note');

  // The callout, selected by its text, has its tip dragged from the circle's centre to the rectangle's corner
  await clickAt(page, box, 243, 602);
  await waitForData(page, 'selection', calloutId);
  await new Promise((resolve) => setTimeout(resolve, 200));
  await page.mouse.move(box.x + 130, box.y + 560);
  await page.mouse.down();
  for (let step = 1; step <= 4; step++) {
    // oxlint-disable-next-line no-await-in-loop
    await page.mouse.move(box.x + 130 + step * 17.5, box.y + 560 - step * 27.5);
  }
  try {
    await page.waitForFunction(() => document.querySelector('#status')?.textContent.includes('AD'), { timeout: 3000 });
  } catch (error: unknown) {
    throw new Error(`the tip: ${await status(page)} ${await bodyData(page, 'selection')}`, { cause: error });
  }
  await page.mouse.up();
  await waitForData(page, 'undo', 'Move callout tip');

  // Every label drawn adds ink
  await page.select('#labels', 'none');
  await new Promise((resolve) => setTimeout(resolve, 300));
  const unlabelled = await inkedPixels(page);
  await page.select('#labels', 'all');
  await new Promise((resolve) => setTimeout(resolve, 300));
  assert.ok((await inkedPixels(page)) > unlabelled + MIN_INKED_PIXELS, 'labels drawn');

  // Export SVG downloads the draft; Print… downloads the tiled PDF on the paper chosen, and opens it
  // in a tab of its own for the browser's viewer to print
  const downloaded = async (name: string, start: string): Promise<string> => {
    let text = '';
    for (let tries = 0; tries < 100 && !text.startsWith(start); tries++) {
      // oxlint-disable-next-line no-await-in-loop
      text = await readFile(join(downloads, name), 'latin1').catch(() => '');
      // oxlint-disable-next-line no-await-in-loop
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    return text;
  };
  await page.click('#toolbar button[title="Download the draft as SVG, as the canvas shows it"]');
  assert.ok((await downloaded('skirt-pieces.svg', '<')).includes('<svg'), 'the draft downloaded');
  await page.click('#toolbar button[title="Print the pieces at full size, tiled on pages"]');
  await page.waitForSelector('.print-dialog[open]', { timeout: TIMEOUT_MS });
  await page.select('#print-paper', 'Letter');
  await page.click('.print-buttons button:nth-child(2)');
  assert.ok((await downloaded('skirt-pieces.pdf', '%PDF')).startsWith('%PDF'), 'the PDF downloaded');
  assert.equal(await status(page), 'Downloaded skirt-pieces.pdf: print it at 100% (actual size)', 'said so');
  const viewer = browser.waitForTarget((target) => target.url().startsWith('blob:'), { timeout: TIMEOUT_MS });
  await page.click('.print-buttons button:nth-child(1)');
  // The viewer's tab is closed again, and the editor brought back to the front
  await (await (await viewer).page())?.close();
  await page.bringToFront();
  await page.click('.print-buttons button:nth-child(3)');
  await page.waitForFunction(() => document.querySelector('.print-dialog[open]') === null, { timeout: TIMEOUT_MS });

  // The Materials tab and dialog: a material added and named, a size refused and put back, the
  // name undone in the dialog, then the material deleted
  await page.click('.side-column [data-tab="materials"]');
  const materialRows = '.materials .material-grid tbody tr';
  await page.waitForSelector(materialRows, { timeout: TIMEOUT_MS });
  const materialCount = (await page.$$(materialRows)).length;
  await page.click('.materials .material-edit');
  await page.waitForSelector('.materials-dialog[open]', { timeout: TIMEOUT_MS });
  await page.click('.materials-left .list-buttons button:first-child');
  await waitForData(page, 'undo', 'Add material');
  await page.waitForFunction(() => document.activeElement?.id === 'material-name', { timeout: TIMEOUT_MS });
  await page.keyboard.type('Lining');
  await page.keyboard.press('Enter');
  await waitForData(page, 'undo', 'Rename material');
  await page.waitForSelector('.materials-dialog tr.selected[data-name="Lining"]', { timeout: TIMEOUT_MS });
  await page.click('#material-width');
  await page.keyboard.type('wide');
  await page.keyboard.press('Enter');
  await page.waitForSelector('#material-width.refused', { timeout: TIMEOUT_MS });
  await page.keyboard.press('Escape');
  await page.waitForSelector('#material-width:not(.refused)', { timeout: TIMEOUT_MS });
  assert.ok(await page.$('.materials-dialog[open]'), 'Escape put the field back, leaving the dialog open');
  await page.focus('.materials-dialog .material-grid');
  await page.keyboard.down('Control');
  await page.keyboard.press('z');
  await page.keyboard.up('Control');
  await waitForData(page, 'undo', 'Add material');
  await page.click('.materials-left .list-buttons button:last-child');
  await waitForData(page, 'undo', 'Delete material');
  await page.click('.materials-bottom button');
  await page.waitForFunction(() => document.querySelector('.materials-dialog[open]') === null, { timeout: TIMEOUT_MS });
  assert.equal((await page.$$(materialRows)).length, materialCount, 'the tab lists them as before');

  // The Garment tab: the pieces as sewn; a click selects one on the canvas,
  // which outlines it here, and Export… downloads the view as SVG and PNG
  await page.click('.side-column [data-tab="garment"]');
  await page.waitForFunction(
    () =>
      (document.querySelector('.garment-drawing')?.shadowRoot?.querySelectorAll('polygon[data-id]').length ?? 0) >= 2,
    { timeout: TIMEOUT_MS },
  );
  const garmentPiece = await page.evaluate(() => {
    const shape = document.querySelector('.garment-drawing')?.shadowRoot?.querySelector('polygon[data-id]');
    if (!(shape instanceof SVGPolygonElement)) {
      return undefined;
    }
    const shapeBox = shape.getBoundingClientRect();
    return { id: shape.dataset.id ?? '', x: shapeBox.left + shapeBox.width / 2, y: shapeBox.top + shapeBox.height / 2 };
  });
  assert.ok(garmentPiece !== undefined, 'a piece drawn');
  await page.mouse.click(garmentPiece.x, garmentPiece.y);
  await waitForData(page, 'selection', garmentPiece.id);
  await page.waitForFunction(
    () =>
      document
        .querySelector('.garment-drawing')
        ?.shadowRoot?.querySelector('polygon[stroke="rgb(30, 120, 220)"]') instanceof SVGPolygonElement,
    { timeout: TIMEOUT_MS },
  );
  await page.click('.garment-toolbar button');
  await page.waitForSelector('.garment-export[open]', { timeout: TIMEOUT_MS });
  await page.click('.garment-export-buttons button.default');
  assert.ok((await downloaded('skirt-pieces-garment.svg', '<')).includes('<svg'), 'the SVG downloaded');
  await page.click('.garment-toolbar button');
  await page.waitForSelector('.garment-export[open]', { timeout: TIMEOUT_MS });
  await page.click('.garment-export label:nth-of-type(2) input');
  await page.click('.garment-export-width input', { count: 3 });
  await page.type('.garment-export-width input', '200');
  await page.click('.garment-export-buttons button.default');
  assert.ok((await downloaded('skirt-pieces-garment.png', '\x89PNG')).startsWith('\x89PNG'), 'the PNG downloaded');

  // The Problems tab, at the foot of the column with the count on its icon:
  // choosing one selects what it is about on the canvas
  assert.ok((await page.$('.side-foot [data-tab="problems"]')) !== null, 'at the foot of the column');
  await page.click('.side-column [data-tab="problems"]');
  await page.waitForSelector('.problems-list li', { timeout: TIMEOUT_MS });
  const problemRows = await page.$$eval('.problems-list li', (rows) => rows.map((row) => row.textContent));
  assert.equal(
    await page.$eval('[data-tab="problems"] .side-badge', (badge) => badge.textContent),
    String(problemRows.length),
    'counted on the icon',
  );
  assert.equal(
    await page.$eval('.side-title span', (title) => title.textContent),
    `Problems (${String(problemRows.length)})`,
    'and in the title',
  );
  const edgeProblem = problemRows.findIndex((text) => text.includes('is an outline edge in no piece'));
  assert.ok(edgeProblem >= 0, 'an edge in no piece listed');
  await page.click(`.problems-list li:nth-child(${String(edgeProblem + 1)})`);
  await page.waitForFunction(
    (piece) => document.body.dataset.selection !== '' && document.body.dataset.selection !== piece,
    { timeout: TIMEOUT_MS },
    garmentPiece.id,
  );
  assert.ok(
    await page.$eval('.problems-list li.chosen', (row) => row.textContent.includes('is an outline edge in no piece')),
    'the problem stays chosen',
  );

  // The Features tab: a double hem along the back's bottom edge, chosen in the Objects tab, then undone
  const undoBefore = await bodyData(page, 'undo');
  await page.click('.side-column [data-tab="objects"]');
  const search = '.list-panel:not([hidden]) input[type=search]';
  await page.click(search, { count: 3 });
  await page.type(search, 'Line_C_J');
  // The list is refilled as the search narrows: the row is clicked once it is the only one
  await page.waitForFunction(
    () => {
      const rows = document.querySelectorAll('.list-panel:not([hidden]) tbody tr');
      return rows.length === 1 && rows[0]?.textContent.includes('Line_C_J') === true;
    },
    { timeout: TIMEOUT_MS },
  );
  await page.click('.list-panel:not([hidden]) tbody tr');
  await page.waitForFunction(() => document.body.dataset.selection !== '', { timeout: TIMEOUT_MS });
  await page.click('.side-column [data-tab="features"]');
  await page.waitForSelector('.feature-kinds option', { timeout: TIMEOUT_MS });
  await page.select('.feature-kinds', 'hem');
  await page.waitForFunction(() => document.querySelector('.feature-header')?.textContent === 'Along Line_C_J', {
    timeout: TIMEOUT_MS,
  });
  assert.ok(await isDisabled(page, '#feature-turnUnder'), 'no turn under for a single hem');
  await page.select('#feature-style', '1');
  await page.waitForFunction(
    () => {
      const turnUnder = document.querySelector('#feature-turnUnder');
      return turnUnder instanceof HTMLInputElement && !turnUnder.disabled;
    },
    { timeout: TIMEOUT_MS },
  );
  await page.click('.feature-apply');
  await waitForData(page, 'undo', 'Insert Hem');
  assert.equal(await status(page), 'Hem added along Line_C_J', 'said so');
  await page.keyboard.down('Control');
  await page.keyboard.press('z');
  await page.keyboard.up('Control');
  await waitForData(page, 'undo', undoBefore);

  // Every example listed is on the site, and one opens with the measurement file it names beside it
  const examples = await page.$$eval('#examples option', (options) =>
    options.map((option) => option.value).filter((value) => value !== ''),
  );
  for (const example of examples) {
    // oxlint-disable-next-line no-await-in-loop
    const found = await page.evaluate(async (path) => (await fetch(`examples/${path}`)).ok, example);
    assert.ok(found, `the example ${example} is on the site`);
  }
  const dialogsBefore = dialogs.length;
  await page.select('#examples', 'circle-skirt/circle-skirt.sloper');
  await page.waitForFunction(
    () => document.querySelector('#status')?.textContent === 'Measurements from size-table.slm',
    {
      timeout: TIMEOUT_MS,
    },
  );
  assert.equal(await page.title(), 'circle-skirt.sloper — OpenSloper', 'the example opened');
  assert.deepEqual(
    dialogs.slice(dialogsBefore),
    ['The pattern has changes not saved. Drop them?'],
    'asked before dropping the changes',
  );

  // SCREENSHOT names a PNG file to keep what the canvas shows at the end
  if ((process.env.SCREENSHOT ?? '') !== '') {
    await page.mouse.move(box.x + box.width / 2, box.y + box.height - 20);
    await new Promise((resolve) => setTimeout(resolve, 300));
    await page.screenshot({ path: `${process.env.SCREENSHOT ?? ''}.png` });
  }
  assert.deepEqual(problems, [], 'no errors on the page');
  console.log(
    `Design app: opened, drew ${String(inked)} pixels; chose from the lists, added, edited and deleted a variable; added, dragged and undid a point and edited it in the Properties tab, taking a formula suggestion, as a piece (an edge's own allowance focused) and a note, its text drawn as typed; drew a line, a curve, ` +
      `dragged its handle, a rectangle, a piece, a notch, a circle and a seam; wrote a note and a callout, moved the note and the callout's tip; labelled everything; exported the draft and printed it to PDF; added, renamed and deleted a material; selected a piece in the Garment tab and exported it; chose a problem; added a hem from the Features tab; ` +
      `edited and saved a measurement, added and reverted one and tried a test size; opened an example. ` +
      (await status(page)),
  );
} finally {
  await browser.close();
  close();
  await rm(downloads, { recursive: true, force: true });
}
