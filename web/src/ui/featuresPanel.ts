// The Features tab of the side panel, as Sloper.UI.FeaturesPanel: sewing
// details applied to the pattern in one step, a zip, a dart, a hem, a facing
// or buttons, chosen from a list. The engine gives the chosen feature's form
// for the canvas's selection (editor_features): what it goes along, its
// fields and what Apply adds. The panel keeps each feature's values as they
// are typed or chosen; a change to a choice or a box, or a field left after
// typing, asks the engine again, as another style starts at its own widths.
// Apply adds ordinary objects as one undo step (editor_feature_apply).
import type { DocumentChange, PatternDocument } from '../document/patternDocument.ts';
import { booleanField, recordsField, stringField, stringsField, type JsonRecord } from '../engine/replies.ts';
import { LatestOnly } from './latestOnly.ts';
import type { SideTabContent } from './sideTabs.ts';
import { STRINGS } from './strings.ts';

// As TFeatureFieldKind
type FieldKind = 'text' | 'choice' | 'check' | 'combo';
const FIELD_KINDS: readonly FieldKind[] = ['text', 'choice', 'check', 'combo'];
const CHECKED = '1';
const UNCHECKED = '0';
const FIRST_FEATURE = 'zip';

interface FeatureField {
  id: string;
  kind: FieldKind;
  caption: string;
  text: string;
  choices: string[];
  enabled: boolean;
}

interface FeatureValue {
  id: string;
  text: string;
}

interface FeatureForm {
  features: { name: string; caption: string }[];
  header: string;
  note: string;
  canApply: boolean;
  values: FeatureValue[];
  fields: FeatureField[];
}

function isFieldKind(name: string): name is FieldKind {
  return (FIELD_KINDS as readonly string[]).includes(name);
}

function parseForm(answer: JsonRecord): FeatureForm {
  return {
    features: recordsField(answer, 'features').map((feature) => ({
      name: stringField(feature, 'name') ?? '',
      caption: stringField(feature, 'caption') ?? '',
    })),
    header: stringField(answer, 'header') ?? '',
    note: stringField(answer, 'note') ?? '',
    canApply: booleanField(answer, 'canApply') ?? false,
    values: recordsField(answer, 'values').map((value) => ({
      id: stringField(value, 'id') ?? '',
      text: stringField(value, 'text') ?? '',
    })),
    fields: recordsField(answer, 'fields').map((field) => {
      const kind = stringField(field, 'kind') ?? '';
      return {
        id: stringField(field, 'id') ?? '',
        kind: isFieldKind(kind) ? kind : 'text',
        caption: stringField(field, 'caption') ?? '',
        text: stringField(field, 'text') ?? '',
        choices: stringsField(field, 'choices') ?? [],
        enabled: booleanField(field, 'enabled') ?? true,
      };
    }),
  };
}

// What a field's control reads and writes
interface FieldControl {
  id: string;
  kind: FieldKind;
  caption: HTMLLabelElement | undefined;
  control: HTMLInputElement | HTMLSelectElement;
  // A combo's choices, offered as the field is typed in
  list: HTMLDataListElement | undefined;
}

// A reload: the field changed, with what it held before, if one did
interface Reload {
  changed: string;
  previous: string;
}

export interface FeaturesEvents {
  // What Apply did, or why it did nothing
  message(text: string): void;
  failed(error: unknown): void;
}

export class FeaturesPanel implements SideTabContent {
  readonly element: HTMLElement;
  private readonly document: PatternDocument;
  private readonly events: FeaturesEvents;
  private readonly kinds: HTMLSelectElement;
  private readonly header: HTMLElement;
  private readonly fieldsArea: HTMLElement;
  private readonly applyButton: HTMLButtonElement;
  private readonly note: HTMLElement;
  private readonly loads: LatestOnly<Reload | undefined>;
  private feature = FIRST_FEATURE;
  // Each feature's values so far, kept while another is shown
  private readonly values = new Map<string, FeatureValue[]>();
  // The pattern they were started for
  private generation = -1;
  private selection: string[] = [];
  private shown = false;
  private stale = true;
  private layout = '';
  private controls: FieldControl[] = [];
  private readonly listener = (_document: PatternDocument, changes: ReadonlySet<DocumentChange>): void => {
    if (changes.has('pattern') || changes.has('objectsReplaced') || changes.has('measurements')) {
      this.reload();
    }
  };

  constructor(document: PatternDocument, events: FeaturesEvents) {
    this.document = document;
    this.events = events;
    const make = window.document.createElement.bind(window.document);
    this.element = make('div');
    this.element.className = 'features';
    this.kinds = make('select');
    this.kinds.className = 'feature-kinds';
    this.kinds.size = 5;
    this.kinds.setAttribute('aria-label', STRINGS.tabFeatures);
    this.kinds.addEventListener('change', () => {
      this.feature = this.kinds.value;
      this.reload();
    });
    this.header = make('div');
    this.header.className = 'feature-header';
    this.fieldsArea = make('div');
    this.fieldsArea.className = 'feature-fields';
    this.applyButton = make('button');
    this.applyButton.type = 'button';
    this.applyButton.className = 'feature-apply';
    this.applyButton.textContent = STRINGS.featuresApply;
    this.applyButton.addEventListener('click', () => {
      this.apply();
    });
    this.note = make('p');
    this.note.className = 'feature-note';
    this.element.append(this.kinds, this.header, this.fieldsArea, this.applyButton, this.note);
    this.loads = new LatestOnly(
      async (change) => this.load(change),
      (error) => {
        events.failed(error);
      },
    );
    document.addListener(this.listener);
  }

  setShown(shown: boolean): void {
    this.shown = shown;
    if (shown && this.stale) {
      this.reload();
    }
  }

  // A zip goes along one selected edge, a dart into one, to a selected point
  // if there is one, and a hem or a facing along all
  showSelection(ids: readonly string[]): void {
    this.selection = [...ids];
    this.reload();
  }

  dispose(): void {
    this.document.removeListener(this.listener);
    this.element.remove();
  }

  private reload(change?: Reload): void {
    if (!this.shown) {
      this.stale = true;
      return;
    }
    this.stale = false;
    this.loads.push(change);
  }

  private async load(change: Reload | undefined): Promise<void> {
    // Another pattern starts every feature again at its own values
    if (this.generation !== this.document.state.generation) {
      this.values.clear();
      this.generation = this.document.state.generation;
    }
    const feature = this.feature;
    const params: Record<string, unknown> = { feature, selection: this.selection };
    const values = this.values.get(feature);
    if (values !== undefined) {
      params.values = values;
    }
    if (change !== undefined) {
      params.changed = change.changed;
      params.previous = change.previous;
    }
    const form = parseForm(await this.document.read('editor_features', params));
    if (feature !== this.feature) {
      return;
    }
    this.values.set(feature, form.values);
    this.show(form);
  }

  private show(form: FeatureForm): void {
    if (this.kinds.options.length === 0) {
      for (const each of form.features) {
        this.kinds.add(new Option(each.caption, each.name));
      }
      this.kinds.value = this.feature;
    }
    this.header.textContent = form.header;
    this.note.textContent = form.note;
    this.applyButton.disabled = !form.canApply;
    const layout = JSON.stringify([this.feature, form.fields.map((field) => [field.id, field.kind])]);
    if (layout !== this.layout) {
      this.layout = layout;
      this.build(form.fields);
    }
    for (const [index, control] of this.controls.entries()) {
      const field = form.fields[index];
      if (field !== undefined) {
        this.fill(control, field);
      }
    }
  }

  private build(fields: FeatureField[]): void {
    const make = window.document.createElement.bind(window.document);
    this.controls = [];
    this.fieldsArea.replaceChildren();
    for (const field of fields) {
      const row = make('div');
      row.className = 'feature-field';
      row.dataset.field = field.id;
      const controlId = `feature-${field.id}`;
      let caption: HTMLLabelElement | undefined;
      let control: HTMLInputElement | HTMLSelectElement;
      let list: HTMLDataListElement | undefined;
      if (field.kind === 'choice') {
        control = make('select');
      } else {
        control = make('input');
        control.type = field.kind === 'check' ? 'checkbox' : 'text';
        control.autocomplete = 'off';
        control.spellcheck = false;
      }
      control.id = controlId;
      if (field.kind === 'check') {
        caption = make('label');
        caption.className = 'feature-check';
        caption.append(control, '');
        row.append(caption);
      } else {
        if (field.caption !== '') {
          caption = make('label');
          caption.htmlFor = controlId;
          row.append(caption);
        }
        row.append(control);
      }
      if (field.kind === 'combo' && control instanceof HTMLInputElement) {
        list = make('datalist');
        list.id = `${controlId}-choices`;
        control.setAttribute('list', list.id);
        row.append(list);
      }
      const item: FieldControl = { id: field.id, kind: field.kind, caption, control, list };
      this.listen(item);
      this.controls.push(item);
      this.fieldsArea.append(row);
    }
  }

  // Typing keeps the value; a choice, a box, or leaving a typed field asks the engine again
  private listen(item: FieldControl): void {
    const { control } = item;
    if (control instanceof HTMLInputElement && item.kind !== 'check') {
      control.addEventListener('input', () => {
        this.setValue(item.id, control.value);
      });
    }
    control.addEventListener('change', () => {
      const previous = this.valueOf(item.id);
      this.setValue(item.id, this.controlValue(item));
      this.reload({ changed: item.id, previous });
    });
  }

  private controlValue(item: FieldControl): string {
    const { control } = item;
    if (control instanceof HTMLInputElement && item.kind === 'check') {
      return control.checked ? CHECKED : UNCHECKED;
    }
    return control.value;
  }

  private fill(item: FieldControl, field: FeatureField): void {
    const { control } = item;
    if (item.caption !== undefined) {
      const text = item.caption.lastChild;
      if (item.kind === 'check' && text !== null) {
        text.textContent = field.caption;
      } else if (item.kind !== 'check') {
        item.caption.textContent = field.caption;
      }
      item.caption.classList.toggle('disabled', !field.enabled);
    }
    control.disabled = !field.enabled;
    if (control instanceof HTMLSelectElement) {
      const choices = [...control.options].map((option) => option.text);
      if (JSON.stringify(choices) !== JSON.stringify(field.choices)) {
        control.replaceChildren(...field.choices.map((choice, index) => new Option(choice, String(index))));
      }
      control.value = field.text;
      if (control.selectedIndex < 0 && control.options.length > 0) {
        control.selectedIndex = 0;
      }
    } else if (item.kind === 'check') {
      control.checked = field.text === CHECKED;
    } else if (window.document.activeElement !== control) {
      // A field being typed in keeps what is typed
      control.value = field.text;
    }
    if (item.list !== undefined) {
      item.list.replaceChildren(...field.choices.map((choice) => new Option(choice)));
    }
  }

  private valueOf(id: string): string {
    return this.values.get(this.feature)?.find((value) => value.id === id)?.text ?? '';
  }

  private setValue(id: string, text: string): void {
    const values = this.values.get(this.feature) ?? [];
    const found = values.find((value) => value.id === id);
    if (found === undefined) {
      values.push({ id, text });
    } else {
      found.text = text;
    }
    this.values.set(this.feature, values);
  }

  private apply(): void {
    const feature = this.feature;
    this.document
      .call('editor_feature_apply', {
        feature,
        selection: this.selection,
        values: this.values.get(feature) ?? [],
      })
      .then((answer) => {
        this.events.message(stringField(answer, 'message') ?? '');
        return undefined;
      })
      .catch((error: unknown) => {
        this.events.failed(error);
      });
  }
}
