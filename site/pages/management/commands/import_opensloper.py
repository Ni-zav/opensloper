"""Copies what the site shows from an OpenSloper checkout into imported/:
the logo, app icons and tutorial drawings as template snippets to inline,
the favicon, the release version, and the built web apps (web/out/design,
from ./opensloper-make.sh web). Run it again after any of those change."""
import re
import shutil
from pathlib import Path

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

# Snippet name: (file in the checkout, label for screen readers or None to hide it)
SVGS = {
    "logo": ("resources/opensloper-logo-horizontal.svg", None),
    "logo-dark": ("resources/opensloper-logo-horizontal-dark.svg", None),
    "icon-measure": ("resources/opensloper-measure.svg", None),
    "icon-design": ("resources/opensloper-design.svg", None),
    "icon-publish": ("resources/opensloper-publish.svg", None),
    "icon-drape": ("resources/opensloper-drape.svg", None),
    "icon-cli": ("resources/opensloper-api.svg", None),
    "skirt-1": ("docs/tutorials/images/skirt-1-frame.svg", "Skirt block frame"),
    "skirt-2": ("docs/tutorials/images/skirt-2-side.svg", "Skirt block with the side seam"),
    "skirt-3": ("docs/tutorials/images/skirt-3-darts.svg", "Skirt block with waist darts"),
    "skirt-4": ("docs/tutorials/images/skirt-4-pieces.svg", "Finished front and back skirt pieces"),
}

# Web app folder under imported/apps: its build in the checkout
APPS = {
    "design": "web/out/design",
}


def inline(svg, label):
    """An SVG file as inline markup: no XML prolog, no fixed size, labelled
    or hidden from screen readers."""
    svg = re.sub(r"<\?xml[^>]*\?>\s*", "", svg)
    head, rest = svg.split(">", 1)
    head = re.sub(r'\s(width|height|role|aria-label)="[^"]*"', "", head)
    if label:
        head += f' role="img" aria-label="{label}"'
    else:
        head += ' aria-hidden="true" focusable="false"'
    return head + ">" + rest.strip()


class Command(BaseCommand):
    help = "Copy the logo, icons, drawings, version and built web apps from an OpenSloper checkout."

    def add_arguments(self, parser):
        parser.add_argument(
            "repo",
            type=Path,
            nargs="?",
            default=settings.BASE_DIR.parent,
            help="path to an OpenSloper checkout, with the web app built; by default the one the site is in",
        )

    def handle(self, *args, **options):
        repo = options["repo"].expanduser().resolve()
        version_file = repo / "src/core/sloper.core.version.pas"
        if not version_file.is_file():
            raise CommandError(f"{repo} does not look like an OpenSloper checkout")
        found = re.search(r"APP_VERSION\s*=\s*'([^']+)'", version_file.read_text(encoding="utf-8"))
        if found is None:
            raise CommandError(f"no APP_VERSION in {version_file}")
        for name, build in APPS.items():
            if not (repo / build / "index.html").is_file():
                raise CommandError(f"{repo / build} is not built: run ./opensloper-make.sh web in the checkout")

        out = settings.IMPORTED_DIR
        snippets = out / "templates" / "imported"
        snippets.mkdir(parents=True, exist_ok=True)
        for name, (path, label) in SVGS.items():
            svg = (repo / path).read_text(encoding="utf-8")
            (snippets / f"{name}.svg").write_text(inline(svg, label), encoding="utf-8")
        shutil.copy(repo / "resources/opensloper-icon.svg", out / "favicon.svg")
        (out / "version.txt").write_text(found.group(1) + "\n", encoding="utf-8")
        for name, build in APPS.items():
            # Replaced whole, so files a new build dropped go too
            target = settings.APPS_DIR / name
            if target.exists():
                shutil.rmtree(target)
            shutil.copytree(repo / build, target)
        self.stdout.write(f"Imported {found.group(1)} from {repo} into {out}")
