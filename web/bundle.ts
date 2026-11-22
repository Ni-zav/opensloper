// Bundles the web pages with esbuild, each with the engine's worker, and
// copies what they load beside them: the design app into out/design, with the
// toolbar icons, and the spike's page into engine/out/browser. The engine
// (engine_lib.wasm) is built first by ./opensloper-make.sh web. Node runs this
// TypeScript as it is.
import { access, copyFile, cp, mkdir } from 'node:fs/promises';
import { build } from 'esbuild';

const ENGINE = 'engine/out/browser/engine_lib.wasm';

async function bundle(entries: string[], outdir: string): Promise<void> {
  await build({
    entryPoints: entries,
    bundle: true,
    format: 'esm',
    target: 'es2022',
    outdir,
    entryNames: '[name]',
    logLevel: 'warning',
  });
}

try {
  await access(ENGINE);
} catch {
  console.error(`No ${ENGINE}: build the engine first with ./opensloper-make.sh web`);
  process.exit(2);
}

await mkdir('out/design', { recursive: true });
await bundle(['src/design/main.ts', 'src/engine/worker.ts'], 'out/design');
await copyFile('src/design/index.html', 'out/design/index.html');
await copyFile(ENGINE, 'out/design/engine_lib.wasm');
await cp('../data/icons', 'out/design/icons', { recursive: true });
await copyFile('../resources/opensloper-design.svg', 'out/design/opensloper-design.svg');

await bundle(['engine/browser/main.ts', 'src/engine/worker.ts'], 'engine/out/browser');
await copyFile('engine/browser/index.html', 'engine/out/browser/index.html');
console.log('Bundled out/design and engine/out/browser');
