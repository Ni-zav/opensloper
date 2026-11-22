// Keys as Sloper.Core.Shortcuts writes them (Mod+Shift+Z, where Mod is Ctrl,
// or Cmd on macOS), matched against key presses. The keys themselves come
// from the engine's tables, so the two editors cannot drift.

export interface Shortcut {
  key: string;
  mod: boolean;
  ctrl: boolean;
  shift: boolean;
  alt: boolean;
}

// The keys known by name, as KeyboardEvent.key gives them
const KEY_NAMES: Record<string, string> = {
  Comma: ',',
  Plus: '+',
  Minus: '-',
  Delete: 'Delete',
  Escape: 'Escape',
  Enter: 'Enter',
  Tab: 'Tab',
  Space: ' ',
  Left: 'ArrowLeft',
  Right: 'ArrowRight',
  Up: 'ArrowUp',
  Down: 'ArrowDown',
  F2: 'F2',
};

// One key press, or undefined for what is not one, such as Arrows
export function parseShortcut(keys: string): Shortcut | undefined {
  const shortcut: Shortcut = { key: '', mod: false, ctrl: false, shift: false, alt: false };
  for (const part of keys.split('+')) {
    if (part === 'Mod') {
      shortcut.mod = true;
    } else if (part === 'Ctrl') {
      shortcut.ctrl = true;
    } else if (part === 'Shift') {
      shortcut.shift = true;
    } else if (part === 'Alt') {
      shortcut.alt = true;
    } else if (shortcut.key === '' && /^[A-Z0-9]$/.test(part)) {
      shortcut.key = part;
    } else if (shortcut.key === '' && part in KEY_NAMES) {
      shortcut.key = KEY_NAMES[part] ?? '';
    } else {
      return undefined;
    }
  }
  return shortcut.key === '' ? undefined : shortcut;
}

export function isMac(): boolean {
  return /Mac|iPhone|iPad/.test(navigator.platform);
}

export function matchesShortcut(event: KeyboardEvent, shortcut: Shortcut): boolean {
  const mod = isMac() ? event.metaKey : event.ctrlKey;
  // On macOS, Ctrl is a key of its own; elsewhere it is Mod
  const ctrl = isMac() ? event.ctrlKey : false;
  const key = event.key.length === 1 ? event.key.toUpperCase() : event.key;
  return (
    key === shortcut.key &&
    mod === (shortcut.mod || (!isMac() && shortcut.ctrl)) &&
    ctrl === (isMac() && shortcut.ctrl) &&
    event.shiftKey === shortcut.shift &&
    event.altKey === shortcut.alt
  );
}
