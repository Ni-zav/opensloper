// Saving on the web: a file the engine wrote is handed to the browser as a
// download, which asks where to put it or puts it in Downloads. Nothing
// leaves the machine.

export function downloadText(fileName: string, text: string, type = 'application/json'): void {
  downloadBlob(fileName, new Blob([text], { type }));
}

export function downloadBlob(fileName: string, blob: Blob): void {
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = fileName;
  link.click();
  URL.revokeObjectURL(link.href);
}

// The last part of a path with /, as patterns record their measurement files
export function baseName(path: string): string {
  return path.slice(path.lastIndexOf('/') + 1);
}

// A PDF the engine wrote, from its Base64
export function pdfBlob(base64: string): Blob {
  return new Blob([Uint8Array.from(atob(base64), (character) => character.charCodeAt(0))], {
    type: 'application/pdf',
  });
}

// How long an opened PDF's address is kept for the viewer to read it, in ms
const OPENED_PDF_MS = 60000;

// Opens a PDF in the tab opened for it while the click counted, or
// downloads it: when no tab was asked for (undefined), or the browser
// would not open one (null). Says which it did.
export function deliverPdf(
  tab: Window | null | undefined,
  name: string,
  blob: Blob,
): 'opened' | 'downloaded' | 'blocked' {
  if (tab === undefined || tab === null) {
    downloadBlob(name, blob);
    return tab === undefined ? 'downloaded' : 'blocked';
  }
  const address = URL.createObjectURL(blob);
  tab.location.href = address;
  setTimeout(() => {
    URL.revokeObjectURL(address);
  }, OPENED_PDF_MS);
  return 'opened';
}
