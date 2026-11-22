// Runs the web engine under Node's WASI: stdin and stdout are the process's,
// and /data is the folder given as the first argument
import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import { argv, env } from 'node:process';

const wasi = new WASI({ version: 'preview1', args: ['engine'], env: { HOME: '/data' }, preopens: { '/data': argv[2] } });
const module = await WebAssembly.compile(await readFile(new URL('./out/engine_serve.wasm', import.meta.url)));
const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
const start = performance.now();
wasi.start(instance);
console.error(`ran in ${(performance.now() - start).toFixed(0)} ms`);
