from django.conf import settings
from django.http import FileResponse, Http404


def favicon(request):
    """The app icon, at the address browsers look for it."""
    path = settings.IMPORTED_DIR / "favicon.svg"
    if not path.is_file():
        raise Http404("run manage.py import_opensloper first")
    return FileResponse(path.open("rb"), content_type="image/svg+xml")
