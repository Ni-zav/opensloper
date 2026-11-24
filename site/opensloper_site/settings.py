"""Settings for the opensloper.com site.

Development needs nothing set. In production the environment gives
DJANGO_SECRET_KEY and sets DJANGO_DEBUG=0 (see deploy/opensloper-web.env).
The site keeps no data, so there is no database: no accounts yet, and no
patterns or measurements ever (the web apps keep those on the user's machine).
"""
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

DEBUG = os.environ.get("DJANGO_DEBUG", "1") == "1"

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "")
if not SECRET_KEY:
    if not DEBUG:
        raise RuntimeError("DJANGO_SECRET_KEY must be set when DJANGO_DEBUG is 0")
    SECRET_KEY = "development-only-not-secret"

ALLOWED_HOSTS = os.environ.get(
    "DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1" if DEBUG else "www.opensloper.com,opensloper.com"
).split(",")

INSTALLED_APPS = [
    "django.contrib.staticfiles",
    "pages",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "opensloper_site.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        # The logo, icons and drawings import_opensloper copies from a checkout
        "DIRS": [BASE_DIR / "imported" / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "pages.context.site",
            ],
        },
    },
]

WSGI_APPLICATION = "opensloper_site.wsgi.application"

DATABASES = {}

LANGUAGE_CODE = "en"
USE_I18N = False
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = Path(os.environ.get("DJANGO_STATIC_ROOT", BASE_DIR / "static_root"))

# What import_opensloper copied: the version and the built web apps, which
# Apache serves in production and Django while developing
IMPORTED_DIR = BASE_DIR / "imported"
APPS_DIR = IMPORTED_DIR / "apps"

# The addresses the pages link to
REPO_URL = "https://github.com/opensloper/opensloper"
DOCS_URL = "https://docs.opensloper.com/"
SITE_URL = "https://www.opensloper.com"

if not DEBUG:
    # Apache ends TLS and passes requests on over plain HTTP
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
    SECURE_SSL_REDIRECT = True
    # One address for search engines: opensloper.com goes to www.
    PREPEND_WWW = True
    SECURE_HSTS_SECONDS = 60 * 60 * 24 * 30
    SECURE_CONTENT_TYPE_NOSNIFF = True
    SECURE_REFERRER_POLICY = "strict-origin-when-cross-origin"
