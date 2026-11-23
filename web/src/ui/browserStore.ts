// The app's IndexedDB database, for what files cannot hold: the folders the
// user granted (fileAccess.ts) and, beside each tab's work in progress, the
// handles of the files it came from (autosave.ts). Each store keeps records
// by a key; nothing in it leaves the machine.

const DATABASE = 'opensloper-files';
// Each version adds the stores it names
const VERSION = 2;
export const FOLDERS_STORE = 'folders';
export const WORK_STORE = 'work';
const STORES = [FOLDERS_STORE, WORK_STORE];

async function openDatabase(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE, VERSION);
    request.addEventListener('upgradeneeded', () => {
      for (const store of STORES) {
        if (!request.result.objectStoreNames.contains(store)) {
          request.result.createObjectStore(store, { autoIncrement: true });
        }
      }
    });
    request.addEventListener('success', () => {
      resolve(request.result);
    });
    request.addEventListener('error', () => {
      reject(request.error ?? new Error(`cannot open ${DATABASE}`));
    });
  });
}

// Runs a request on a store, resolving with its result once the transaction completes
async function inStore<T>(
  store: string,
  mode: IDBTransactionMode,
  makeRequest: (objects: IDBObjectStore) => IDBRequest<T>,
): Promise<T> {
  const database = await openDatabase();
  try {
    return await new Promise((resolve, reject) => {
      const transaction = database.transaction(store, mode);
      const request = makeRequest(transaction.objectStore(store));
      transaction.addEventListener('complete', () => {
        resolve(request.result);
      });
      transaction.addEventListener('error', () => {
        reject(transaction.error ?? new Error(`cannot use ${store}`));
      });
    });
  } finally {
    database.close();
  }
}

export async function allRecords(store: string): Promise<unknown[]> {
  return inStore(store, 'readonly', (objects) => objects.getAll());
}

// A record under a key, or with the next key when none is given
export async function putRecord(store: string, value: unknown, key?: string): Promise<void> {
  await inStore(store, 'readwrite', (objects) => objects.put(value, key));
}

export async function getRecord(store: string, key: string): Promise<unknown> {
  return inStore(store, 'readonly', (objects) => objects.get(key));
}

export async function deleteRecord(store: string, key: string): Promise<void> {
  await inStore(store, 'readwrite', (objects) => objects.delete(key));
}
