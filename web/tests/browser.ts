// What the browser tests share: the built app (out/design) served on a free
// port, a headless browser (CHROMIUM overrides its path), and waiting
// for the body data the app sets for tests.
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';
import { extname, join, normalize, relative } from 'node:path';
import { launch, type Browser, type KeyInput, type Page } from 'puppeteer-core';
import { isMac } from '../src/ui/shortcuts.ts';

export const TIMEOUT_MS = 30000;

const TYPES: Record<string, string> = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.wasm': 'application/wasm',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.webmanifest': 'application/manifest+json',
  '.sloper': 'application/json',
  '.slm': 'application/json',
};

export interface ServeOptions {
  // The port to listen on, as when serving again after going offline; a free one by default
  port?: number;
  // The app's built folder; out/design by default
  root?: string;
  // Changes a file as it is served, by its path under the root, as a new build would
  alter?: (file: string, data: Buffer) => Buffer;
}

// Serves the app until close is called, which drops every connection, so
// the page is offline until it is served again
export async function serveApp(options: ServeOptions = {}): Promise<{ port: number; close: () => void }> {
  const root = options.root ?? 'out/design';
  const server = createServer((request, response) => {
    const path = normalize(join(root, decodeURIComponent(new URL(request.url ?? '/', 'http://x').pathname)));
    const file = path.endsWith('/') || path === root ? join(path, 'index.html') : path;
    readFile(file)
      .then((data) => {
        response.writeHead(200, { 'Content-Type': TYPES[extname(file)] ?? 'application/octet-stream' });
        response.end(options.alter === undefined ? data : options.alter(relative(root, file), data));
        return undefined;
      })
      .catch(() => {
        response.writeHead(404);
        response.end();
      });
  });
  await new Promise<void>((resolve) => server.listen(options.port ?? 0, '127.0.0.1', resolve));
  const address: string | AddressInfo | null = server.address();
  if (address === null || typeof address === 'string') {
    throw new Error('the server has no port');
  }
  return {
    port: address.port,
    close: () => {
      server.close();
      server.closeAllConnections();
    },
  };
}

export async function launchBrowser(): Promise<Browser> {
  const executable =
    process.platform === 'darwin'
      ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
      : '/usr/bin/chromium';
  return launch({
    executablePath: process.env.CHROMIUM ?? executable,
    args: ['--no-sandbox', '--disable-gpu'],
  });
}

// Mod is Command on macOS and Control elsewhere, as the editor sees it.
export async function pressWithMod(page: Page, key: KeyInput): Promise<void> {
  const modifier = (await page.evaluate(isMac)) ? 'Meta' : 'Control';
  await page.keyboard.down(modifier);
  try {
    await page.keyboard.press(key);
  } finally {
    await page.keyboard.up(modifier);
  }
}

// Errors on the page and in its console, gathered for the end
export function watchProblems(page: Page): string[] {
  const problems: string[] = [];
  page.on('pageerror', (error: unknown) => {
    problems.push(`page error: ${String(error)}`);
  });
  page.on('console', (message) => {
    if (message.type() === 'error') {
      problems.push(`console: ${message.text()}`);
    }
  });
  return problems;
}

export async function bodyData(page: Page, name: string): Promise<string> {
  return page.$eval('body', (body, key) => body.dataset[key] ?? '', name);
}

// Waits for a body data value; on a timeout, says what the page showed instead
export async function waitForData(page: Page, name: string, value: string): Promise<void> {
  try {
    await page.waitForFunction(
      (key, expected) => document.body.dataset[key] === expected,
      { timeout: TIMEOUT_MS },
      name,
      value,
    );
  } catch (error: unknown) {
    const shown = await page.evaluate(() => ({
      data: Object.fromEntries(Object.entries(document.body.dataset)),
      status: document.querySelector('#status')?.textContent,
    }));
    throw new Error(`waiting for ${name} "${value}": ${JSON.stringify(shown)}`, { cause: error });
  }
}

// Waits for the status bar to start with the text
export async function waitForStatus(page: Page, start: string): Promise<void> {
  try {
    await page.waitForFunction(
      (text) => document.querySelector('#status')?.textContent.startsWith(text),
      {
        timeout: TIMEOUT_MS,
      },
      start,
    );
  } catch (error: unknown) {
    throw new Error(`waiting for the status "${start}": "${await status(page)}"`, { cause: error });
  }
}

export async function status(page: Page): Promise<string> {
  return page.$eval('#status', (element) => element.textContent);
}

// File System Access in headless Chromium, whose pickers cannot be clicked
// through: they are stood in for by ones over the page's private file system
// The pickers, over OPFS: each takes the next path the test has queued in
// window.testPicks ('' is the top folder)
export function standInPickers(): void {
  const picks: (string | string[])[] = [];
  Reflect.set(window, 'testPicks', picks);
  const next = (): string[] => {
    const pick = picks.shift();
    if (pick === undefined) {
      throw new DOMException('no pick queued', 'AbortError');
    }
    return typeof pick === 'string' ? [pick] : pick;
  };
  // Inside, as the page is sent this function alone
  // oxlint-disable-next-line unicorn/consistent-function-scoping
  const folderAt = async (parts: string[], create: boolean): Promise<FileSystemDirectoryHandle> => {
    let folder = await navigator.storage.getDirectory();
    for (const part of parts) {
      // oxlint-disable-next-line no-await-in-loop
      folder = await folder.getDirectoryHandle(part, { create });
    }
    return folder;
  };
  const fileAt = async (path: string, create: boolean): Promise<FileSystemFileHandle> => {
    const parts = path.split('/');
    const name = parts.pop() ?? '';
    return (await folderAt(parts, create)).getFileHandle(name, { create });
  };
  Object.defineProperty(window, 'showOpenFilePicker', {
    value: async () => Promise.all(next().map(async (path) => fileAt(path, false))),
  });
  Object.defineProperty(window, 'showSaveFilePicker', {
    value: async () => fileAt(next()[0] ?? '', true),
  });
  Object.defineProperty(window, 'showDirectoryPicker', {
    value: async () =>
      folderAt(
        (next()[0] ?? '').split('/').filter((part) => part !== ''),
        false,
      ),
  });
}

export async function queuePicks(page: Page, ...picks: (string | string[])[]): Promise<void> {
  await page.evaluate((queued) => {
    const list: unknown = Reflect.get(window, 'testPicks');
    if (Array.isArray(list)) {
      list.push(...queued);
    }
  }, picks);
}

export async function writeOpfs(page: Page, path: string, text: string): Promise<void> {
  await page.evaluate(
    async (where, contents) => {
      const parts = where.split('/');
      const name = parts.pop() ?? '';
      let folder = await navigator.storage.getDirectory();
      for (const part of parts) {
        // oxlint-disable-next-line no-await-in-loop
        folder = await folder.getDirectoryHandle(part, { create: true });
      }
      const stream = await (await folder.getFileHandle(name, { create: true })).createWritable();
      await stream.write(contents);
      await stream.close();
    },
    path,
    text,
  );
}

export async function readOpfs(page: Page, path: string): Promise<string> {
  return page.evaluate(async (where) => {
    const parts = where.split('/');
    const name = parts.pop() ?? '';
    let folder = await navigator.storage.getDirectory();
    for (const part of parts) {
      // oxlint-disable-next-line no-await-in-loop
      folder = await folder.getDirectoryHandle(part);
    }
    return (await (await folder.getFileHandle(name)).getFile()).text();
  }, path);
}
