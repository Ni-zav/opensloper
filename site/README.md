# opensloper.com

`template.html` is the page; `build.py` fills it with the logo, app icons and
tutorial drawings from an OpenSloper checkout, inlined, so the site is one file.

    python3 build.py ~/src/opensloper dist

Upload the contents of `dist/` (index.html, favicon.svg, og-image.jpg,
robots.txt, sitemap.xml and the hidden .htaccess) to the site's `web` folder,
replacing ISPConfig's index.html. The .htaccess 301-redirects http and the bare
domain to https://www.opensloper.com/, the canonical address.

Rebuild after the logo, icons or tutorial drawings change, or when the
version in `src/core/sloper.core.version.pas` moves on. The docs and repo
addresses are at the top of `build.py`.

The screenshots in `images/` are inlined as data URIs: the hero,
`design-app.webp`, and one per app in The apps section (`measurements-app`,
`design-features`, `publish-app`, `drape-app`). Retake them when the windows
change. `og-image.jpg` is the link-preview picture, cut from the hero:
`magick images/design-app.webp -resize 1200x -gravity north -crop 1200x630+0+0
+repage -strip -quality 85 images/og-image.jpg`. They were taken at 1280x800 in Xvfb with no window manager
(`Xvfb :78 -screen 0 1280x800x24`), the light Qt style
(`env -u QT_QPA_PLATFORMTHEME`), a throwaway `HOME` so your own preferences
are untouched, View → Labels → Contextual, the window moved to 0,0 and
sized 1280x800 with `xdotool`, and
`import -window root`, then `magick shot.png -quality 82 x.webp`:

- design-app: `docs/examples/bodice-block/bodice-block.sloper`, View → Piece
  Fills on, zoom to fit, Garment tab open.
- design-features: the same, Features tab open with Zip chosen, centre back
  edge selected.
- measurements-app: `docs/examples/measurements/size-table.slm`.
- publish-app: `docs/examples/circle-skirt/circle-skirt.sloper`, Pieces tab,
  Pack pieces, zoom to fit.
- drape-app: `docs/examples/bodice-block/bodice-block.sdrape`, the view
  turned a little by dragging so the back piece shows.
