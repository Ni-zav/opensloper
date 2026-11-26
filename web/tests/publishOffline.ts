// Drives the built Publish app's service worker and work in progress in
// headless Chromium. Once opened, the app is kept in a cache of its own and
// loads with the server gone, as an installed app does offline. A layout
// opened and changed there is kept, and another tab offers it only once the
// tab that kept it has closed: opened again, it is as it was, not saved.
import assert from 'node:assert/strict';
import type { Browser, Page } from 'puppeteer-core';
import { launchBrowser, serveApp, status, waitForData, waitForStatus, watchProblems } from './browser.ts';

const PATTERN = '../docs/examples/skirt-block/skirt-darts.sloper';
const MEASUREMENTS = '../docs/examples/skirt-block/skirt.slm';

// Opening and saving through uploads and downloads, so no picker is needed
function withoutFileAccess(): void {
  for (const name of ['showOpenFilePicker', 'showSaveFilePicker', 'showDirectoryPicker']) {
    Object.defineProperty(window, name, { value: undefined });
  }
}

async function newTab(browser: Browser): Promise<Page> {
  const tab = await browser.newPage();
  await tab.setViewport({ width: 1200, height: 800 });
  await tab.evaluateOnNewDocument(withoutFileAccess);
  return tab;
}

const app = await serveApp({ root: 'out/publish' });
const browser = await launchBrowser();
try {
  const page = await newTab(browser);
  const problems = watchProblems(page);
  const address = `http://127.0.0.1:${String(app.port)}/`;
  await page.goto(address);
  await waitForData(page, 'ready', 'true');
  // The first worker takes the page over once it has kept every file
  await waitForData(page, 'offline', 'true');
  const caches = await page.evaluate(async () => globalThis.caches.keys());
  assert.ok(
    caches.some((name) => name.startsWith('opensloper-publish-')),
    `the app's own cache: ${caches.join(', ')}`,
  );
  const manifest = await page.$eval('link[rel="manifest"]', (link) => link.href);
  assert.ok(manifest.endsWith('manifest.webmanifest'), 'a manifest to install it by');

  // No server: the app still comes, and opens a layout from the files chosen
  app.close();
  await page.reload();
  await waitForData(page, 'ready', 'true');
  const input = await page.$('input#open-input');
  assert.ok(input);
  await input.uploadFile(PATTERN, MEASUREMENTS);
  await waitForStatus(page, 'Started a layout for skirt-darts.sloper');

  // Changed, so kept; another tab leaves it alone while this one is open
  await page.evaluate(() => {
    [...document.querySelectorAll('.pieces button')]
      .find((each) => each.textContent === 'Pack pieces')
      ?.dispatchEvent(new MouseEvent('click'));
  });
  await waitForData(page, 'workKept', 'true');
  const other = await newTab(browser);
  await other.goto(address);
  await waitForData(other, 'ready', 'true');
  await new Promise((resolve) => {
    setTimeout(resolve, 1000);
  });
  assert.ok(!(await status(other)).startsWith('Unsaved work'), 'not while its tab is open');

  // Once that tab has closed, offered, and opened as it was, not saved
  await page.close();
  await other.reload();
  await waitForData(other, 'ready', 'true');
  await waitForStatus(other, 'Unsaved work on skirt-darts.slayout');
  await other.click('#message button');
  await waitForStatus(other, 'Opened the unsaved work on skirt-darts.slayout');
  assert.equal(await other.title(), '• skirt-darts — OpenSloper Publish', 'not saved');
  assert.match(await status(other), /No problems$/u, 'its files with it');

  assert.deepEqual(problems, []);
  console.log('Publish offline passed');
} finally {
  await browser.close();
  app.close();
}
