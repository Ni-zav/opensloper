"""The site's addresses. The web apps live under /design/ (and later
/measurements/ and /publish/); Apache serves them in production, and Django
only while developing, as it does the static files."""
from django.conf import settings
from django.http import Http404
from django.urls import include, path, re_path
from django.views.generic import RedirectView
from django.views.static import serve


def app_file(request, path):
    """A file of the web Design app, while developing; Apache serves them in production."""
    if not settings.DEBUG:
        raise Http404("Apache serves the app")
    return serve(request, path or "index.html", document_root=settings.APPS_DIR / "design")


urlpatterns = [
    path("", include("pages.urls")),
    # The app's files are relative to its folder, so it needs the slash
    path("design", RedirectView.as_view(url="/design/", permanent=True)),
    re_path(r"^design/(?P<path>.*)$", app_file),
]
