"""The site's addresses. The web apps live under /design/ and /publish/ (and
later /measurements/); Apache serves them in production, and Django only
while developing, as it does the static files."""
from django.conf import settings
from django.http import Http404
from django.urls import include, path, re_path
from django.views.generic import RedirectView
from django.views.static import serve


def app_file(request, path, app):
    """A file of a web app, while developing; Apache serves them in production."""
    if not settings.DEBUG:
        raise Http404("Apache serves the app")
    return serve(request, path or "index.html", document_root=settings.APPS_DIR / app)


urlpatterns = [path("", include("pages.urls"))]
for app in ("design", "publish"):
    urlpatterns += [
        # The app's files are relative to its folder, so it needs the slash
        path(app, RedirectView.as_view(url=f"/{app}/", permanent=True)),
        re_path(rf"^{app}/(?P<path>.*)$", app_file, {"app": app}),
    ]
