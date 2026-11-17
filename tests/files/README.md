# Files of older format versions

A file of every older version of the pattern, measurement and layout formats, one folder for each version (`v1`, `v2` ...). `Sloper.Tests.FileVersions` loads each one, which brings it up to the current version through the upgrade steps, saves it, and checks that it is saved at the current version and saves the same again.

While a format is still at the version of a folder, its file there is simply a current file. When a format's version goes up (see File format and storage in the design document):

1. Copy a file of the old version here, into the folder of that version, before changing anything, if it has none yet.
2. Raise the version constant (`PATTERN_VERSION`, `MEASUREMENT_VERSION` or `LAYOUT_VERSION`) and add the upgrade step from the old version to the format's `...FileVersions` function.
3. Write a test that the old file loads to what was meant.

`check-schemas.py` checks only files at the current version, since a schema describes that version, so the files here of older versions are left out.

The files in `v1` are copies of `docs/examples/skirt-block/skirt-block.sloper`, `docs/examples/measurements/size-table.slm` and the layout example on the File formats page.
