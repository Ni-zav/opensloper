// What the browser tests share: the built app (out/design) served on a free
// port, headless Chromium (CHROMIUM names it, /usr/bin/chromium by
// default), and waiting for the body data the app sets for tests.
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';
import { extname, join, normalize, relative } from 'node:path';
import { launch, type Browser, type Page } from 'puppeteer-core';

export const TIMEOUT_MS = 30000;

const TYPES: Record<string, string> = {
  '.html': 'text/html',
  '.js': 'text/javascript',
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
  root?: string;
  // Changes a file as it is served, by its path under out/design, as a new build would
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
  return launch({
    executablePath: process.env.CHROMIUM ?? '/usr/bin/chromium',
    args: ['--no-sandbox', '--disable-gpu'],
  });
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
