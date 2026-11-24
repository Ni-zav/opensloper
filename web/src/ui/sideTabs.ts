// The side panel's tabs, as Sloper.UI.SideTabs: one open at a time, a column
// of icons down the left and the open tab beside it under a title with its
// icon and name. Clicking the open tab's icon folds the panel down to the
// column, giving the canvas the room; clicking any icon opens it again. A
// tab can sit at the foot of the column, as the Problems tab does in every
// app, and show a count on its icon.

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
  badge: HTMLElement;
  content: SideTabContent;
}

export class SideTabs {
  readonly element: HTMLElement;
  private readonly column: HTMLElement;
  // The tabs kept at the foot of the column
  private readonly foot: HTMLElement;
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
    this.foot = document.createElement('div');
    this.foot.className = 'side-foot';
    this.column.append(this.foot);
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

  // A new tab, after the others or, atFoot, at the foot of the column
  addSection(key: string, caption: string, icon: string, content: SideTabContent, atFoot = false): void {
    const button = document.createElement('button');
    button.type = 'button';
    button.title = caption;
    button.setAttribute('role', 'tab');
    button.dataset.tab = key;
    const image = document.createElement('img');
    image.src = `icons/${icon}.svg`;
    image.alt = caption;
    const badge = document.createElement('span');
    badge.className = 'side-badge';
    badge.hidden = true;
    button.append(image, badge);
    button.addEventListener('click', () => {
      // The open tab's icon folds the panel; any other opens its tab
      if (key === this.openKey && !this.folded) {
        this.setFolded(true);
      } else {
        this.open(key);
      }
    });
    if (atFoot) {
      this.foot.append(button);
    } else {
      this.column.insertBefore(button, this.foot);
    }
    content.element.hidden = true;
    this.body.append(content.element);
    this.sections.push({ key, caption, icon, button, badge, content });
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

  // The tab's name, on its icon's tooltip and its title while open
  setCaption(key: string, caption: string): void {
    const section = this.sections.find((each) => each.key === key);
    if (section === undefined) {
      return;
    }
    section.caption = caption;
    section.button.title = caption;
    if (key === this.openKey) {
      this.titleText.textContent = caption;
    }
  }

  // A count on the tab's icon, such as how many problems there are; none at 0
  setCount(key: string, count: number): void {
    const section = this.sections.find((each) => each.key === key);
    if (section === undefined) {
      return;
    }
    section.badge.textContent = String(count);
    section.badge.hidden = count <= 0;
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
    const buttons = [...this.column.querySelectorAll('button')];
    const index = buttons.findIndex((button) => button === document.activeElement);
    buttons[(index + step + buttons.length) % buttons.length]?.focus();
    event.preventDefault();
  }
}
