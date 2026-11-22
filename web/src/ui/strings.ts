// The editor's own user-visible text, in one place as the desktop's
// resourcestring sections are. Text the engine gives (tool captions and hints,
// snap descriptions, reasons) comes already in words.

export const STRINGS = {
  appName: 'OpenSloper',
  loading: 'Loading the engine…',
  untitled: 'Untitled',
  open: 'Open…',
  openHint: 'Open a pattern, with its measurement file if you have it',
  measurements: 'Measurements…',
  measurementsHint: 'Choose the measurement file for the pattern',
  save: 'Save',
  saveHint: 'Download the pattern file',
  undo: 'Undo',
  redo: 'Redo',
  undoStep: (step: string): string => `Undo ${step}`,
  redoStep: (step: string): string => `Redo ${step}`,
  fit: 'Fit',
  fitHint: 'Fit everything in the window',
  drawRoleHint: 'The role of the lines and shapes drawn next',
  labelsHint: 'Which objects are labelled',
  labelsContextual: 'Labels: contextual',
  labelsAll: (holdKeys: string): string => `Labels: all (hold ${holdKeys})`,
  labelsNone: 'Labels: none',
  opened: (name: string, objects: number): string => `Opened ${name}: ${String(objects)} objects`,
  needsMeasurements: (file: string): string =>
    `The pattern uses the measurement file ${file}: choose it with Measurements…`,
  measurementsUsed: (name: string): string => `Measurements from ${name}`,
  notAPattern: (name: string): string => `${name} is not a pattern file (.sloper)`,
  failed: (reason: string): string => `Something went wrong: ${reason}`,
  // Shown in the title while the pattern has changes not saved
  modifiedMark: '•',
} as const;
