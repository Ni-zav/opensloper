"""The site's addresses. The web apps live under /design/ (and later
/measurements/ and /publish/); Apache serves them in production, and Django
only while developing, as it does the static files."""
from django.conf import settings
from django.urls import include, path, re_path
from django.views.generic import RedirectView
from django.views.static import serve

urlpatterns = [
    path("", include("pages.urls")),
    # The app's files are relative to its folder, so it needs the slash
    path("design", RedirectView.as_view(url="/design/", permanent=True)),
]

if settings.DEBUG:
    urlpatterns += [
        re_path(
            r"^design/(?P<path>.*)$",
            lambda request, path: serve(request, path or "index.html", document_root=settings.APPS_DIR / "design"),
        ),
    ]
