"""The WSGI application gunicorn runs (see deploy/opensloper-web.service)."""
import os

from django.core.wsgi import get_wsgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "opensloper_site.settings")

application = get_wsgi_application()
