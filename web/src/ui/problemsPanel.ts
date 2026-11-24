// The Problems tab, at the foot of the side panel, as Sloper.UI.ProblemsPanel:
// every problem the pattern has, in full (editor_problems), with their count
// on the tab's icon. Choosing one shows what it is about, pointing at one
// highlights it on the canvas, and a double-click zooms to it. It follows
// every change while hidden too, as its count shows on the icon.
import type { DocumentChange, PatternDocument } from '../document/patternDocument.ts';
import { numberField, recordsField, stringField } from '../engine/replies.ts';
import { LatestOnly } from './latestOnly.ts';
import type { SideTabContent } from './sideTabs.ts';
import { STRINGS } from './strings.ts';

// What a problem is about: an object on the canvas (or a seam) or a variable
// by ID, a measurement by key, or nothing
export type ProblemSubject =
  { kind: 'object' | 'variable'; id: string } | { kind: 'measurement'; key: string } | { kind: 'none' };

export interface Problem {
  text: string;
  subject: ProblemSubject;
}

export interface ProblemsPanelEvents {
  // How many problems there are, for the tab's icon and caption
  counted(count: number): void;
  // The user chose a problem, by clicking it or moving to it with the keys
  choose(subject: ProblemSubject): void;
  // The pointer moved onto a problem, or off them all
  hover(subject: ProblemSubject): void;
  // A double-click on a problem
  zoom(subject: ProblemSubject): void;
  failed(error: unknown): void;
}

const NONE: ProblemSubject = { kind: 'none' };

function parseSubject(problem: Record<string, unknown>): ProblemSubject {
  const kind = stringField(problem, 'kind');
  const id = numberField(problem, 'id');
  if ((kind === 'object' || kind === 'variable') && id !== undefined) {
    return { kind, id: String(id) };
  }
  const key = stringField(problem, 'key');
  if (kind === 'measurement' && key !== undefined) {
    return { kind, key };
  }
  return NONE;
}

// So a chosen problem stays chosen when the list is built again
function problemKey(problem: Problem): string {
  return `${JSON.stringify(problem.subject)} ${problem.text}`;
}

export class ProblemsPanel implements SideTabContent {
  readonly element: HTMLElement;
  private readonly events: ProblemsPanelEvents;
  private readonly document: PatternDocument;
  private readonly empty: HTMLElement;
  private readonly list: HTMLElement;
  private readonly loads: LatestOnly<number>;
  private problems: Problem[] = [];
  private chosenKey = '';
  private hovered = -1;
  private readonly listener = (_document: PatternDocument, changes: ReadonlySet<DocumentChange>): void => {
    if (changes.has('pattern') || changes.has('objectsReplaced') || changes.has('measurements')) {
      this.loads.push(0);
    }
  };

  constructor(document: PatternDocument, events: ProblemsPanelEvents) {
    this.document = document;
    this.events = events;
    const make = window.document.createElement.bind(window.document);
    this.element = make('div');
    this.element.className = 'problems';
    this.empty = make('div');
    this.empty.className = 'problems-none';
    this.empty.textContent = STRINGS.problemsNone;
    this.list = make('ul');
    this.list.className = 'problems-list';
    this.list.setAttribute('role', 'listbox');
    this.list.tabIndex = 0;
    this.element.append(this.empty, this.list);
    this.list.addEventListener('click', (event) => {
      const index = this.indexAt(event);
      if (index >= 0) {
        this.choose(index);
      }
    });
    this.list.addEventListener('dblclick', (event) => {
      const index = this.indexAt(event);
      const problem = this.problems[index];
      if (problem !== undefined) {
        events.zoom(problem.subject);
      }
    });
    this.list.addEventListener('mousemove', (event) => {
      this.setHovered(this.indexAt(event));
    });
    this.list.addEventListener('mouseleave', () => {
      this.setHovered(-1);
    });
    this.list.addEventListener('keydown', (event) => {
      this.key(event);
    });
    this.loads = new LatestOnly(
      async () => this.load(),
      (error) => {
        events.failed(error);
      },
    );
    document.addListener(this.listener);
    this.loads.push(0);
  }

  // The list follows every change, shown or not, so there is nothing to catch up on
  setShown(shown: boolean): void {
    if (!shown) {
      this.setHovered(-1);
    }
  }

  dispose(): void {
    this.document.removeListener(this.listener);
    this.element.remove();
  }

  get count(): number {
    return this.problems.length;
  }

  private async load(): Promise<void> {
    const answer = await this.document.read('editor_problems');
    this.problems = recordsField(answer, 'problems').map((problem) => ({
      text: stringField(problem, 'text') ?? '',
      subject: parseSubject(problem),
    }));
    this.hovered = -1;
    this.show();
    this.events.counted(this.problems.length);
  }

  private show(): void {
    const make = window.document.createElement.bind(window.document);
    const rows = this.problems.map((problem, index) => {
      const row = make('li');
      row.setAttribute('role', 'option');
      row.dataset.index = String(index);
      row.textContent = problem.text;
      const chosen = problemKey(problem) === this.chosenKey;
      row.classList.toggle('chosen', chosen);
      row.setAttribute('aria-selected', String(chosen));
      return row;
    });
    this.list.replaceChildren(...rows);
    this.empty.hidden = this.problems.length > 0;
    this.list.hidden = this.problems.length === 0;
  }

  private indexAt(event: MouseEvent): number {
    const row = event.target instanceof Element ? event.target.closest('li') : null;
    return row === null ? -1 : Number(row.dataset.index ?? -1);
  }

  private choose(index: number): void {
    const problem = this.problems[index];
    if (problem === undefined) {
      return;
    }
    this.chosenKey = problemKey(problem);
    for (const row of this.list.children) {
      const chosen = row instanceof HTMLElement && row.dataset.index === String(index);
      row.classList.toggle('chosen', chosen);
      row.setAttribute('aria-selected', String(chosen));
      if (chosen) {
        row.scrollIntoView({ block: 'nearest' });
      }
    }
    this.events.choose(problem.subject);
  }

  private setHovered(index: number): void {
    if (index === this.hovered) {
      return;
    }
    this.hovered = index;
    this.events.hover(this.problems[index]?.subject ?? NONE);
  }

  // Up and Down choose the next problem, as clicking it does
  private key(event: KeyboardEvent): void {
    const step = event.key === 'ArrowDown' ? 1 : event.key === 'ArrowUp' ? -1 : 0;
    if (step === 0 || this.problems.length === 0) {
      return;
    }
    event.preventDefault();
    const current = this.problems.findIndex((problem) => problemKey(problem) === this.chosenKey);
    const next = current < 0 ? (step > 0 ? 0 : this.problems.length - 1) : current + step;
    if (next >= 0 && next < this.problems.length) {
      this.choose(next);
    }
  }
}
