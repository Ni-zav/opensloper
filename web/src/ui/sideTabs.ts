// The side panel's tabs, as Sloper.UI.SideTabs: one open at a time, a column
// of icons down the left and the open tab beside it under a title with its
// icon and name. Clicking the open tab's icon folds the panel down to the
// column, giving the canvas the room; clicking any icon opens it again.

// What a tab holds: told when it shows and hides, so a hidden list need not
// follow every change
export interface SideTabContent {
  readonly element: HTMLElement;
  setShown(shown: boolean): void;
}

interface Section {
  key: string;
  caption: string;
  icon: string;
  button: HTMLButtonElement;
  content: SideTabContent;
}

export class SideTabs {
  readonly element: HTMLElement;
  private readonly column: HTMLElement;
  private readonly page: HTMLElement;
  private readonly titleIcon: HTMLImageElement;
  private readonly titleText: HTMLElement;
  private readonly body: HTMLElement;
  private readonly sections: Section[] = [];
  private openKey = '';
  private folded = false;

  constructor(element: HTMLElement) {
    this.element = element;
    this.element.classList.add('side-tabs');
    this.column = document.createElement('div');
    this.column.className = 'side-column';
    this.column.setAttribute('role', 'tablist');
    this.column.setAttribute('aria-orientation', 'vertical');
    this.page = document.createElement('div');
    this.page.className = 'side-page';
    const title = document.createElement('div');
    title.className = 'side-title';
    this.titleIcon = document.createElement('img');
    this.titleIcon.alt = '';
    this.titleText = document.createElement('span');
    title.append(this.titleIcon, this.titleText);
    this.body = document.createElement('div');
    this.body.className = 'side-body';
    this.page.append(title, this.body);
    this.element.append(this.column, this.page);
    this.column.addEventListener('keydown', (event) => {
      this.columnKey(event);
    });
  }

  addSection(key: string, caption: string, icon: string, content: SideTabContent): void {
    const button = document.createElement('button');
    button.type = 'button';
    button.title = caption;
    button.setAttribute('role', 'tab');
    button.dataset.tab = key;
    const image = document.createElement('img');
    image.src = `icons/${icon}.svg`;
    image.alt = caption;
    button.append(image);
    button.addEventListener('click', () => {
      // The open tab's icon folds the panel; any other opens its tab
      if (key === this.openKey && !this.folded) {
        this.setFolded(true);
      } else {
        this.open(key);
      }
    });
    this.column.append(button);
    content.element.hidden = true;
    this.body.append(content.element);
    this.sections.push({ key, caption, icon, button, content });
    if (this.openKey === '') {
      this.open(key);
    }
  }

  open(key: string): void {
    const section = this.sections.find((each) => each.key === key);
    if (section === undefined) {
      return;
    }
    this.openKey = key;
    this.titleIcon.src = `icons/${section.icon}.svg`;
    this.titleText.textContent = section.caption;
    this.setFolded(false);
  }

  get openTab(): string {
    return this.openKey;
  }

  private setFolded(folded: boolean): void {
    this.folded = folded;
    this.page.hidden = folded;
    this.element.classList.toggle('folded', folded);
    for (const section of this.sections) {
      const shown = !folded && section.key === this.openKey;
      section.button.classList.toggle('chosen', section.key === this.openKey);
      section.button.setAttribute('aria-selected', String(shown));
      section.content.element.hidden = !shown;
      section.content.setShown(shown);
    }
  }

  // Up and Down move along the icons, Enter and Space open the one focused, as the button does
  private columnKey(event: KeyboardEvent): void {
    const step = event.key === 'ArrowDown' ? 1 : event.key === 'ArrowUp' ? -1 : 0;
    if (step === 0) {
      return;
    }
    const buttons = this.sections.map((section) => section.button);
    const index = buttons.findIndex((button) => button === document.activeElement);
    buttons[(index + step + buttons.length) % buttons.length]?.focus();
    event.preventDefault();
  }
}
