// What the browser tests share: the built app (out/design) served on a free
// port, headless Chromium (CHROMIUM names it, /usr/bin/chromium by
// default), and waiting for the body data the app sets for tests.
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';
import { extname, join, normalize } from 'node:path';
import { launch, type Browser, type Page } from 'puppeteer-core';

const ROOT = 'out/design';
export const TIMEOUT_MS = 30000;

const TYPES: Record<string, string> = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.wasm': 'application/wasm',
  '.svg': 'image/svg+xml',
};

// Serves the app until close is called
export async function serveApp(): Promise<{ port: number; close: () => void }> {
  const server = createServer((request, response) => {
    const path = normalize(join(ROOT, decodeURIComponent(new URL(request.url ?? '/', 'http://x').pathname)));
    const file = path.endsWith('/') || path === ROOT ? join(path, 'index.html') : path;
    readFile(file)
      .then((data) => {
        response.writeHead(200, { 'Content-Type': TYPES[extname(file)] ?? 'application/octet-stream' });
        response.end(data);
        return undefined;
      })
      .catch(() => {
        response.writeHead(404);
        response.end();
      });
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address: string | AddressInfo | null = server.address();
  if (address === null || typeof address === 'string') {
    throw new Error('the server has no port');
  }
  return {
    port: address.port,
    close: () => {
      server.close();
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
