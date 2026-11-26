// The Problems tab every app's side panel ends with, as Sloper.UI.ProblemsPanel:
// each problem in full, those that stop printing in red. Pointing at one or
// choosing it tells the app what it is about, by a key the app gave it, so
// the app can show it. It knows nothing of documents, so each app fills it
// its own way.
import type { SideTabContent } from './sideTabs.ts';
import { STRINGS } from './strings.ts';

export interface ListedProblem {
  // What the problem is about, in the app's own terms; '' for none
  key: string;
  text: string;
  // It stops printing or exporting, rather than only warning
  blocking: boolean;
}

export interface ProblemsPanelEvents {
  // The user chose a problem, by clicking it or moving to it with the keys
  choose(key: string): void;
  // The pointer moved onto a problem, or off them all ('')
  hover(key: string): void;
  // A double-click on a problem
  zoom(key: string): void;
}

// So a chosen problem stays chosen when the list is filled again
function rowKey(problem: ListedProblem): string {
  return `${problem.key} ${problem.text}`;
}

export class ProblemsPanel implements SideTabContent {
  readonly element: HTMLElement;
  private readonly events: ProblemsPanelEvents;
  private readonly empty: HTMLElement;
  private readonly list: HTMLElement;
  private problems: ListedProblem[] = [];
  private chosenKey = '';
  private hovered = -1;

  constructor(events: ProblemsPanelEvents) {
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
      const problem = this.problems[this.indexAt(event)];
      if (problem !== undefined) {
        events.zoom(problem.key);
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
    this.show();
  }

  // The app fills it on every change, shown or not, so there is nothing to catch up on
  setShown(shown: boolean): void {
    if (!shown) {
      this.setHovered(-1);
    }
  }

  dispose(): void {
    this.element.remove();
  }

  get count(): number {
    return this.problems.length;
  }

  // Lists these, keeping the chosen one chosen if it is still listed
  setProblems(problems: ListedProblem[]): void {
    this.problems = problems;
    this.hovered = -1;
    this.show();
  }

  private show(): void {
    const make = window.document.createElement.bind(window.document);
    const rows = this.problems.map((problem, index) => {
      const row = make('li');
      row.setAttribute('role', 'option');
      row.dataset.index = String(index);
      row.textContent = problem.text;
      row.classList.toggle('blocking', problem.blocking);
      const chosen = rowKey(problem) === this.chosenKey;
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
    this.chosenKey = rowKey(problem);
    for (const row of this.list.children) {
      const chosen = row instanceof HTMLElement && row.dataset.index === String(index);
      row.classList.toggle('chosen', chosen);
      row.setAttribute('aria-selected', String(chosen));
      if (chosen) {
        row.scrollIntoView({ block: 'nearest' });
      }
    }
    this.events.choose(problem.key);
  }

  private setHovered(index: number): void {
    if (index === this.hovered) {
      return;
    }
    this.hovered = index;
    this.events.hover(this.problems[index]?.key ?? '');
  }

  // Up and Down choose the next problem, as clicking it does
  private key(event: KeyboardEvent): void {
    const step = event.key === 'ArrowDown' ? 1 : event.key === 'ArrowUp' ? -1 : 0;
    if (step === 0 || this.problems.length === 0) {
      return;
    }
    event.preventDefault();
    const current = this.problems.findIndex((problem) => rowKey(problem) === this.chosenKey);
    const next = current < 0 ? (step > 0 ? 0 : this.problems.length - 1) : current + step;
    if (next >= 0 && next < this.problems.length) {
      this.choose(next);
    }
  }
}
