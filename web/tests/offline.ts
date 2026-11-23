// Drives the built design app's service worker in headless Chromium: once
// the app has been opened, it loads and opens an example with the server
// gone, as an installed app does offline; then a new build, served when the
// server is back, waits until the Update button reloads into it, keeping the
// work not saved, and the old build's cache goes.
import assert from 'node:assert/strict';
import type { Page } from 'puppeteer-core';
import { launchBrowser, serveApp, status, TIMEOUT_MS, waitForData, waitForStatus, watchProblems } from './browser.ts';

// What a new build changes in the service worker: its version
const NEXT_VERSION = 'nextbuild0000000';

async function cacheNames(page: Page): Promise<string[]> {
  return page.evaluate(async () => caches.keys());
}

const first = await serveApp();
const browser = await launchBrowser();
let next: { close: () => void } | undefined;
try {
  const page = await browser.newPage();
  await page.setViewport({ width: 1200, height: 800 });
  const problems = watchProblems(page);
  const address = `http://127.0.0.1:${String(first.port)}/`;
  await page.goto(address);
  await waitForData(page, 'ready', 'true');
  // The first worker takes the page over once it has kept every file
  await waitForData(page, 'offline', 'true');
  const [cache] = await cacheNames(page);
  assert.ok(cache?.startsWith('opensloper-design-') === true, `the build's cache: ${String(cache)}`);
  const manifest = await page.$eval('link[rel="manifest"]', (link) => link.href);
  assert.ok(manifest.endsWith('manifest.webmanifest'), 'a manifest to install it by');

  // No server: the app and an example still come
  first.close();
  await page.reload();
  await waitForData(page, 'ready', 'true');
  await page.select('#examples', 'tote-bag/tote-bag.sloper');
  await waitForStatus(page, 'Opened tote-bag.sloper');

  // A change not yet saved, then a new build: it waits, and Update reloads into it
  await page.keyboard.press('p');
  await page.mouse.click(300, 300);
  await waitForData(page, 'undo', 'Add point');
  next = await serveApp({
    port: first.port,
    alter: (file, data) =>
      file === 'sw.js' ? Buffer.from(data.toString().replace(/"[0-9a-f]{16}"/, `"${NEXT_VERSION}"`)) : data,
  });
  await page.evaluate(async () => {
    await (await navigator.serviceWorker.getRegistration())?.update();
  });
  await page.waitForSelector('#update:not([hidden])', { timeout: TIMEOUT_MS });
  await page.click('#update');
  // The reloaded page offers the work it kept
  await page.waitForFunction(() => document.body.dataset.ready === undefined, { timeout: TIMEOUT_MS });
  await waitForData(page, 'ready', 'true');
  await waitForStatus(page, 'Unsaved work on tote-bag.sloper');
  assert.deepEqual(await cacheNames(page), [`opensloper-design-${NEXT_VERSION}`], 'only the new build kept');
  assert.equal(
    await page.$eval('#update', (button) => button instanceof HTMLElement && button.hidden),
    true,
    'up to date',
  );

  assert.deepEqual(problems, [], 'no errors on the page');
  console.log(
    'Offline: kept the app, loaded it and opened an example with no server; a new build waited until Update ' +
      `reloaded into it, keeping the unsaved work, and the old cache went. ${await status(page)}`,
  );
} finally {
  await browser.close();
  first.close();
  next?.close();
}
