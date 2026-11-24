#!/usr/bin/env bash
# Deploy the opensloper.com site: copy site/ to the server and set it up.
#
# Run from anywhere in the checkout, after ./opensloper-make.sh web:
#   site/deploy/deploy.sh [--no-build]
# It runs ./opensloper-make.sh site (import, check, test) unless --no-build,
# copies site/ (imported/ included) to the server with rsync, then on the
# server makes the venv if need be, installs requirements.txt, writes the
# environment file with a new secret key the first time, fills in the
# service and Apache directives for this server, collects the static files
# and reloads gunicorn (opensloper-site.service) if it is running.
# Nothing needs root: the service runs as the SSH account's user, so a HUP
# to gunicorn loads the new code.
#
# The server goes in site/deploy/deploy.local.sh (not in git; copy
# deploy.local.sh.example): SITE_HOST, an ~/.ssh/config entry, and SITE_DIR,
# the folder the site goes in. The environment file is SITE_DIR.env, beside
# it, so rsync --delete leaves it.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
build=1

while [ $# -gt 0 ]; do
  case "$1" in
    --no-build) build=0 ;;
    -h | --help)
      sed -n '2,/^set -euo/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "deploy: unknown option $1" >&2
      exit 2
      ;;
  esac
  shift
done

if [ -f "$here/deploy.local.sh" ]; then
  . "$here/deploy.local.sh"
fi
host="${SITE_HOST:-}"
dir="${SITE_DIR:-}"
if [ -z "$host" ] || [ -z "$dir" ]; then
  echo "deploy: set SITE_HOST and SITE_DIR in site/deploy/deploy.local.sh" \
    "(see deploy.local.sh.example)" >&2
  exit 2
fi

cd "$root"
if [ "$build" -eq 1 ]; then
  ./opensloper-make.sh site
fi
if [ ! -f site/imported/apps/design/index.html ]; then
  echo "deploy: no web Design app in site/imported; run ./opensloper-make.sh web" \
    "then ./opensloper-make.sh site" >&2
  exit 1
fi

echo "Copying site/ to $host:$dir"
ssh "$host" "mkdir -p '$dir'"
# Readable by Apache, whose user is in the site's group, for /static/ and /design/
rsync -az --delete --chmod=Du=rwx,go=rx,Fu=rw,go=r \
  --exclude /venv/ --exclude /static_root/ --exclude /dist/ \
  --exclude /deploy/deploy.local.sh \
  --exclude __pycache__/ --exclude '*.pyc' \
  site/ "$host:$dir/"

echo "Setting up on $host"
ssh "$host" bash -s -- "$dir" <<'REMOTE'
set -euo pipefail
dir="$1"
env_file="$dir.env"
cd "$dir"

[ -x venv/bin/python ] || python3 -m venv venv
venv/bin/pip install --quiet --disable-pip-version-check -r requirements.txt

if [ ! -f "$env_file" ]; then
  echo "Writing $env_file with a new secret key"
  (
    umask 077
    {
      echo "# opensloper.com site settings (site/deploy/opensloper-site.env.example)"
      echo "DJANGO_SECRET_KEY=$(python3 -c 'import secrets; print(secrets.token_urlsafe(50))')"
      echo "DJANGO_DEBUG=0"
      echo "DJANGO_ALLOWED_HOSTS=www.opensloper.com,opensloper.com"
      echo "DJANGO_STATIC_ROOT=$dir/static_root"
    } >"$env_file"
  )
fi

# The service and directives filled in, in place, with this server's folder,
# user and group (rsync brings the templates back each time)
sed -i -e "s|@SITE_DIR@|$dir|g" -e "s|@SITE_USER@|$(id -un)|g" \
  -e "s|@SITE_GROUP@|$(id -gn)|g" deploy/opensloper-site.service deploy/apache-directives.conf

set -a
. "$env_file"
set +a
venv/bin/python manage.py check
venv/bin/python manage.py collectstatic --noinput --verbosity 0

pid="$(systemctl show -p MainPID --value opensloper-site 2>/dev/null || echo 0)"
if [ "${pid:-0}" -gt 0 ]; then
  kill -HUP "$pid"
  echo "Reloaded opensloper-site (gunicorn $pid)"
else
  echo "opensloper-site is not running. As root, once:"
  echo "  cp $dir/deploy/opensloper-site.service /etc/systemd/system/"
  echo "  systemctl daemon-reload && systemctl enable --now opensloper-site"
  echo "and paste $dir/deploy/apache-directives.conf into the site's Apache Directives."
fi
REMOTE
