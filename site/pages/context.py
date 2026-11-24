"""What every page is given: the release it describes and the addresses it links to."""
from functools import cache

from django.conf import settings


@cache
def version():
    """The release import_opensloper copied from the checkout's sloper.core.version.pas."""
    try:
        return (settings.IMPORTED_DIR / "version.txt").read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return ""


def site(request):
    return {
        "version": version(),
        "repo": settings.REPO_URL,
        "docs": settings.DOCS_URL,
        "site_url": settings.SITE_URL,
    }
