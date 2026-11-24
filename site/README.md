# opensloper.com

The project's website: the home page and, under `/design/`, the web Design
app (a beta, `web/`). A Django 5.2 site with no database: it keeps no
accounts, patterns or measurements (`documents/design/web-version.md`,
Server). Its own packages are pinned in `requirements.txt`.

| Path | What it is |
| --- | --- |
| `opensloper_site/` | Settings (from the environment in production), addresses, WSGI |
| `pages/` | The pages' templates, CSS and pictures, their tests, and `import_opensloper` |
| `deploy/` | The gunicorn service, its environment file and the Apache directives |
| `imported/` | What `import_opensloper` copied from the checkout (not in git) |

## Developing

```
./opensloper-make.sh web            # build the web Design app, with FPC trunk (web/README.md)
./opensloper-make.sh site --serve   # import it into the site, check, test, and serve at 127.0.0.1:8000
```

`site` installs Django into the repository's `venv`, then runs
`manage.py import_opensloper`, which copies the logo, app icons, tutorial
drawings and version from the checkout, and `web/out/design`, into
`imported/`. Run it again after any of those change. While developing,
Django serves the app and the static files; in production Apache does.

The screenshots in `pages/static/pages/images/` are 1280x800 WebP:

- `web-design`, the hero: the web Design app in headless Chromium with the
  bodice block example opened from the Examples box, point SB chosen in the
  Objects tab, then the Properties tab shown.
- One per desktop app in The apps section (`measurements-app`,
  `design-features`, `publish-app`, `drape-app`), and `design-app`, taken in
  Xvfb (`Xvfb :78 -screen 0 1280x800x24`) with no window manager, the light
  Qt style (`env -u QT_QPA_PLATFORMTHEME`), a throwaway `HOME`, View → Labels
  → Contextual, the window moved to 0,0 and sized 1280x800 with `xdotool`,
  and `import -window root`, then `magick shot.png -quality 82 x.webp`:
  - design-app: `docs/examples/bodice-block/bodice-block.sloper`, View →
    Piece Fills on, zoom to fit, Garment tab open.
  - design-features: the same, Features tab open with Zip chosen, centre
    back edge selected.
  - measurements-app: `docs/examples/measurements/size-table.slm`.
  - publish-app: `docs/examples/circle-skirt/circle-skirt.sloper`, Pieces
    tab, Pack pieces, zoom to fit.
  - drape-app: `docs/examples/bodice-block/bodice-block.sdrape`, the view
    turned a little by dragging so the back piece shows.

`og-image.jpg` is the link-preview picture, cut from `design-app`:
`magick design-app.webp -resize 1200x -gravity north -crop 1200x630+0+0 +repage -strip -quality 85 og-image.jpg`.

## Deploying

The site runs under gunicorn as a systemd service on the ISPConfig server,
with Apache in front. The web app's Wasm engine needs the FPC trunk
cross-compiler, so the site is built here and copied over, `imported/`
included.

First time, on the server:

1. Make `/srv/opensloper-site` owned by the ISPConfig site's web user, and a
   venv in it: `python3 -m venv /srv/opensloper-site/venv`.
2. Copy `deploy/opensloper-site.env.example` to `/etc/opensloper-site.env`
   (`chmod 600`), with a new secret key.
3. Copy `deploy/opensloper-site.service` to `/etc/systemd/system/`, with
   `User` and `Group` set to the site's web user and group.
4. Paste `deploy/apache-directives.conf` into the site's Apache Directives
   in ISPConfig, and turn on its Let's Encrypt certificate.

Each release, here and then on the server:

```
./opensloper-make.sh web && ./opensloper-make.sh site
rsync -a --delete --exclude venv --exclude static_root --exclude __pycache__ site/ SERVER:/srv/opensloper-site/
ssh SERVER 'cd /srv/opensloper-site && venv/bin/pip install -r requirements.txt \
  && set -a && . /etc/opensloper-site.env && venv/bin/python manage.py collectstatic --noinput \
  && sudo systemctl restart opensloper-site'
```

The old static page's files in the site's `web` folder (`index.html`,
`.htaccess` and the rest) are no longer used once the directives are in
place, and can be removed.
