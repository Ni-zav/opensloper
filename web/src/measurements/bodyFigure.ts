// The measurements page's body figure, as Sloper.Measurements.BodyFigure: the
// engine draws it as SVG at the panel's size, with the set's measurements on
// it and one highlighted, and says which measurement a point picks. This
// shows the drawing and passes on hovers and clicks.
import type { MeasurementDocument } from '../document/measurementDocument.ts';
import { stringField } from '../engine/replies.ts';

export interface BodyFigureEvents {
  // The set's measurement under the pointer, '' when it leaves one
  hover(key: string): void;
  // A measurement was clicked
  pick(key: string): void;
  failed(error: unknown): void;
}

export class BodyFigure {
  readonly element: HTMLElement;
  private readonly document: MeasurementDocument;
  private readonly events: BodyFigureEvents;
  private readonly image: HTMLImageElement;
  private highlighted = '';
  private hovered = '';
  private shownUrl = '';
  // Only the latest drawing and point asked for count
  private drawRequest = 0;
  private pointRequest = 0;

  constructor(document: MeasurementDocument, events: BodyFigureEvents) {
    this.document = document;
    this.events = events;
    this.element = window.document.createElement('div');
    this.element.className = 'body-figure';
    this.image = window.document.createElement('img');
    this.image.alt = '';
    this.image.draggable = false;
    this.element.append(this.image);
    this.element.addEventListener('mousemove', (event) => {
      this.run(this.pointMoved(event.offsetX, event.offsetY));
    });
    this.element.addEventListener('mouseleave', () => {
      this.pointRequest++;
      this.setHovered('');
    });
    this.element.addEventListener('click', (event) => {
      this.run(this.clicked(event.offsetX, event.offsetY));
    });
    new ResizeObserver(() => {
      this.refresh();
    }).observe(this.element);
  }

  // The measurement drawn in the highlight's colour; '' for none
  set highlight(key: string) {
    if (key !== this.highlighted) {
      this.highlighted = key;
      this.refresh();
    }
  }

  // The set or the catalogue changed: the figure is drawn again
  refresh(): void {
    this.run(this.draw());
  }

  private get size(): { width: number; height: number } {
    return { width: this.element.clientWidth, height: this.element.clientHeight };
  }

  private run(pending: Promise<void>): void {
    pending.catch((error: unknown) => {
      this.events.failed(error);
    });
  }

  private async draw(): Promise<void> {
    const { width, height } = this.size;
    if (width === 0 || height === 0) {
      return;
    }
    const request = ++this.drawRequest;
    const highlight = this.highlighted;
    const svg = stringField(await this.document.read('measurements_figure', { width, height, highlight }), 'svg') ?? '';
    if (request !== this.drawRequest) {
      return;
    }
    const url = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' }));
    this.image.src = url;
    if (this.shownUrl !== '') {
      URL.revokeObjectURL(this.shownUrl);
    }
    this.shownUrl = url;
    // The measurement drawn highlighted, for whoever looks, such as a test
    this.element.dataset.highlight = highlight;
  }

  private async keyAt(x: number, y: number): Promise<string | undefined> {
    const request = ++this.pointRequest;
    const answer = await this.document.read('measurements_figure_at', { ...this.size, x, y });
    return request === this.pointRequest ? (stringField(answer, 'key') ?? '') : undefined;
  }

  private async pointMoved(x: number, y: number): Promise<void> {
    const key = await this.keyAt(x, y);
    if (key !== undefined) {
      this.setHovered(key);
    }
  }

  private async clicked(x: number, y: number): Promise<void> {
    const key = await this.keyAt(x, y);
    if (key !== undefined && key !== '') {
      this.events.pick(key);
    }
  }

  private setHovered(key: string): void {
    if (key === this.hovered) {
      return;
    }
    this.hovered = key;
    this.element.classList.toggle('over-measurement', key !== '');
    this.events.hover(key);
  }
}
