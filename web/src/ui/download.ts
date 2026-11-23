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
