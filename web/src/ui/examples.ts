import { baseName } from './download.ts';

// A file from the site, named as its address ends.
export async function fetchExampleFile(address: URL): Promise<File | undefined> {
  const response = await fetch(address);
  if (!response.ok) {
    return undefined;
  }
  return new File([await response.text()], baseName(address.pathname));
}
