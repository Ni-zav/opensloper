#!/usr/bin/env bash
# Build, test, check, format, package and document OpenSloper.
#
#   ./opensloper-make.sh COMMAND [OPTIONS]
#
# Run ./opensloper-make.sh help for the commands. Toolchain overrides
# (LAZBUILD, LAZARUS_PCP, LCL_WIDGETSET, JCF_SOURCE) can go in build.local.sh;
# see build.local.sh.example. File arguments are relative to the repository
# root, where every command runs.
set -euo pipefail
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$SELF")"

if [ -f build.local.sh ]; then
  . ./build.local.sh
fi
LAZBUILD="${LAZBUILD:-lazbuild}"
PCP_ARGS=()
if [ -n "${LAZARUS_PCP:-}" ]; then
  PCP_ARGS=(--pcp="$LAZARUS_PCP")
fi

usage() {
  cat <<'EOF'
Usage: ./opensloper-make.sh COMMAND [OPTIONS]

Commands:
  test [RUNNER OPTIONS]  build and run the tests, with the heaptrc leak check
                         (run before every commit)
  build [LAZBUILD OPTIONS]
                         build the GUI apps and the CLI into release/,
                         e.g. build --build-mode=Release
  check [FILE...]        check the coding standards the formatter cannot
                         (errors fail, warnings advise; run before every commit)
  format [--check] [FILE...]
                         format the sources with jcfsettings.cfg; --check lists
                         the files that need it and changes nothing
  pr-check               format, check, test and build, as before a pull
                         request; stops at the first that fails, and lists
                         the files format changed, to commit
  docs [--serve] [--offline] [--reinstall]
                         regenerate docs/reference/ and build the site into
                         release/site_docs; --serve previews it, --offline
                         also builds the copy the downloads ship into
                         release/site_offline, --reinstall makes the Python
                         venv again
  package                pack the built apps for this platform into release/dist:
                         the archive and the installer (.deb, .dmg or setup.exe)
  release [VERSION]      print a release's notes: its CHANGELOG.md section, else
                         its commits since the last release
  version                print the current version
  bump major|minor|patch|VERSION
                         set APP_VERSION to the next version and start its
                         section in CHANGELOG.md; commits nothing (the release
                         workflow tags the release)
  help                   show this help
EOF
}

# APP_VERSION in Sloper.Core.Version
app_version() {
  local version
  version=$(sed -n "s/^ *APP_VERSION = '\(.*\)';.*/\1/p" src/core/sloper.core.version.pas)
  if [ -z "$version" ]; then
    echo "APP_VERSION not found in src/core/sloper.core.version.pas" >&2
    exit 1
  fi
  echo "$version"
}

cmd_version() {
  app_version;
}

# bump: set APP_VERSION to the next major, minor or patch version, or to the
# version given, and add an empty "## VERSION" section at the top of
# CHANGELOG.md for the changes to come. Leaves the commit to you.
cmd_bump() {
  local current next major minor patch
  if [ $# -ne 1 ]; then
    echo "Usage: ./opensloper-make.sh bump major|minor|patch|VERSION" >&2
    exit 2
  fi
  if ! git diff-index --quiet HEAD --; then
    echo "There are uncommitted changes: commit or stash them before bumping the version" >&2
    exit 1
  fi
  current=$(app_version)
  if ! [[ $current =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "APP_VERSION $current is not MAJOR.MINOR.PATCH" >&2
    exit 1
  fi
  major=${BASH_REMATCH[1]}
  minor=${BASH_REMATCH[2]}
  patch=${BASH_REMATCH[3]}
  case "$1" in
    major) next="$((major + 1)).0.0" ;;
    minor) next="$major.$((minor + 1)).0" ;;
    patch) next="$major.$minor.$((patch + 1))" ;;
    *)
      if ! [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Not major, minor, patch or a MAJOR.MINOR.PATCH version: $1" >&2
        exit 2
      fi
      next="$1"
      ;;
  esac
  if [ "$next" = "$current" ]; then
    echo "The version is already $current" >&2
    exit 1
  fi
  if awk -v version="$next" '/^## / && $2 == version { found = 1 } END { exit !found }' CHANGELOG.md; then
    echo "CHANGELOG.md already has a section for $next" >&2
    exit 1
  fi

  sed -i.bak "s/^\( *APP_VERSION = '\)$current\(';.*\)/\1$next\2/" src/core/sloper.core.version.pas
  rm -f src/core/sloper.core.version.pas.bak
  # The new section goes before the first version heading
  awk -v version="$next" '
    !done && /^## / { print "## " version "\n"; done = 1 }
    { print }
  ' CHANGELOG.md > CHANGELOG.md.new
  mv CHANGELOG.md.new CHANGELOG.md

  if [ "$(app_version)" != "$next" ]; then
    echo "APP_VERSION was not changed" >&2
    exit 1
  fi
  echo "Version $current -> $next: src/core/sloper.core.version.pas and CHANGELOG.md changed, not committed"
}

# The Pascal sources the formatter and the standards check look at:
# src/packages/ and the Lazarus-generated package unit osclipper2.pas are left alone
source_files() {
  git ls-files --cached --others --exclude-standard '*.pas' '*.lpr' '*.pp' |
    grep -v '^src/packages/' | grep -v '^src/core/clipper2/osclipper2.pas$'
}

# test: build and run the test suite
cmd_test() {
  git submodule update --init --recursive

  # -B: lazbuild compares file times to the second, so an edit made in the
  # same second as the last build could otherwise be skipped
  "$LAZBUILD" "${PCP_ARGS[@]}" -q -B tests/opensloper_tests.lpi

  HEAPLOG="$(mktemp)"
  RESULTS="$(mktemp)"
  trap 'rm -f "$HEAPLOG" "$RESULTS"' EXIT
  rm -f "$HEAPLOG"
  local status
  set +e
  HEAPTRC="log=$HEAPLOG" ./tests/opensloper_tests --all --format=plain "$@" 2>&1 | tee "$RESULTS"
  status=${PIPESTATUS[0]}
  set -e

  if [ "$status" -ne 0 ]; then
    echo "Tests failed (exit $status)" >&2
    exit "$status"
  fi
  # The runner can stop early (an exception outside a test) and still exit 0,
  # so require its summary too
  if ! grep -q '^Number of errors: *0$' "$RESULTS" || ! grep -q '^Number of failures: *0$' "$RESULTS"; then
    echo "Tests did not finish or did not pass" >&2
    exit 1
  fi
  if ! grep -q '^0 unfreed memory blocks' "$HEAPLOG" 2>/dev/null; then
    cat "$HEAPLOG" >&2 2>/dev/null || echo "No heaptrc report was written" >&2
    echo "heaptrc reported memory leaks" >&2
    exit 1
  fi
  echo "All tests passed, no leaks."
}

# Qt6 needs its Pascal bindings (libQt6Pas), not just Qt6 itself
has_qt6pas() {
  if command -v ldconfig >/dev/null 2>&1 || [ -x /sbin/ldconfig ]; then
    "$(command -v ldconfig || echo /sbin/ldconfig)" -p 2>/dev/null | grep -q 'libQt6Pas\.so' && return 0
  fi
  compgen -G '/usr/lib*/libQt6Pas.so*' >/dev/null || compgen -G '/usr/lib/*/libQt6Pas.so*' >/dev/null ||
    compgen -G '/usr/local/lib*/libQt6Pas.so*' >/dev/null
}

# build: the GUI apps and the command-line tool. On Linux the widgetset is qt6
# when libQt6Pas is installed, else qt5; it is cocoa on macOS and win32 on
# Windows (run from Git Bash). LCL_WIDGETSET chooses another.
cmd_build() {
  local ws
  case "$(uname -s)" in
    Darwin) ws="${LCL_WIDGETSET:-cocoa}" ;;
    MINGW* | MSYS* | CYGWIN*) ws="${LCL_WIDGETSET:-win32}" ;;
    *)
      if [ -n "${LCL_WIDGETSET:-}" ]; then
        ws="$LCL_WIDGETSET"
      elif has_qt6pas; then
        ws=qt6
      else
        ws=qt5
      fi
      ;;
  esac
  echo "Building GUI apps with the $ws widgetset"

  git submodule update --init --recursive

  "$LAZBUILD" "${PCP_ARGS[@]}" -q src/cli/opensloper_cli.lpi "$@"
  "$LAZBUILD" "${PCP_ARGS[@]}" -q --ws="$ws" src/design/opensloper_design.lpi "$@"
  "$LAZBUILD" "${PCP_ARGS[@]}" -q --ws="$ws" src/publish/opensloper_publish.lpi "$@"
  "$LAZBUILD" "${PCP_ARGS[@]}" -q --ws="$ws" src/measurements/opensloper_measurements.lpi "$@"
}

# check: the coding standards that the formatter cannot enforce (see
# documents/coding-standards.md and CLAUDE.md), by the Perl program at the end
# of this file. CI runs it on every pull request. Errors fail the check (exit
# 1). Warnings are reported but do not fail it: they are heuristics a reviewer
# should look at. Under GitHub Actions both are also written as annotations,
# so they show on the pull request's diff.
cmd_check() {
  local files=("$@")
  if [ ${#files[@]} -eq 0 ]; then
    mapfile -t files < <(source_files)
  fi
  exec perl -x "$SELF" "${files[@]}"
}

# The command-line formatter, JEDI Code Format, is built into lib/jcf on first
# use, from the Lazarus source in JCF_SOURCE (default: the Lazarus that
# LAZBUILD belongs to). CI uses the release Lazarus in .github/workflows/ci.yml;
# format with the same release so your files pass its check.
build_jcf() {
  local src
  echo "Building the formatter from $JCF_SOURCE" >&2
  src=lib/jcf-src
  rm -rf "$src" lib/jcf-pcp
  mkdir -p lib/jcf
  cp -r "$JCF_SOURCE" "$src"
  rm -rf "$src/lib"
  # Build against this copy's own jcfbase package, not the one installed in
  # the Lazarus that does the building
  sed -i 's|<PackageName Value="jcfbase"/>|&\n        <DefaultFilename Value="../../jcfbase.lpk" Prefer="True"/>|' \
    "$src/CommandLine/Lazarus/jcf.lpi"
  "$LAZBUILD" --pcp="$PWD/lib/jcf-pcp" --lazarusdir="$LAZARUS_DIR" -q \
    "$src/CommandLine/Lazarus/jcf.lpi" > lib/jcf/build.log 2>&1 ||
    { cat lib/jcf/build.log >&2; exit 1; }
  cp "$src"/lib/CommandLine-*/jcf "$JCF"
}

format_file() {
  local log
  log="$(mktemp)"
  if ! "$JCF" -clarify -inplace -y -config="$CONFIG" -F "$1" > "$log" 2>&1 ||
    grep -qiE 'exception|parse error' "$log"; then
    echo "Could not format $1:" >&2
    cat "$log" >&2
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
}

# format: the Pascal sources, with the project settings in jcfsettings.cfg
# (see documents/coding-standards.md)
cmd_format() {
  JCF="${JCF:-lib/jcf/jcf}"
  LAZARUS_DIR="$(dirname "$(realpath "$(command -v "$LAZBUILD")")")"
  JCF_SOURCE="${JCF_SOURCE:-$LAZARUS_DIR/components/jcf2}"
  CONFIG="$PWD/jcfsettings.cfg"

  [ -x "$JCF" ] || build_jcf

  local check=0 files f needed
  if [ "${1:-}" = "--check" ]; then
    check=1
    shift
  fi
  files=("$@")
  if [ ${#files[@]} -eq 0 ]; then
    mapfile -t files < <(source_files)
  fi

  if [ "$check" -eq 1 ]; then
    CHECK_DIR="$(mktemp -d)"
    trap 'rm -rf "$CHECK_DIR"' EXIT
    needed=0
    for f in "${files[@]}"; do
      cp "$f" "$CHECK_DIR/check.pas"
      format_file "$CHECK_DIR/check.pas"
      if ! cmp -s "$f" "$CHECK_DIR/check.pas"; then
        echo "$f"
        needed=1
      fi
    done
    exit "$needed"
  fi

  for f in "${files[@]}"; do
    format_file "$f"
  done
  echo "Formatted ${#files[@]} files."
}

# Each source file's content hash and path, to see what formatting changed;
# git's hash works the same on every platform
source_hashes() {
  local list
  list="$(source_files | sort)"
  [ -n "$list" ] || return 0
  paste -d ' ' <(printf '%s\n' "$list" | git hash-object --stdin-paths) <(printf '%s\n' "$list")
}

# pr-check: what a pull request needs (CONTRIBUTING.md), in one go: format,
# check, test and build, each run as its own command, since several of them
# end the shell they run in. The first that fails stops it with its exit
# status. Formatting changes files in place, so the files it changed are
# listed at the end: they need committing, or CI's formatting check fails.
cmd_pr_check() {
  local step status before after changed
  if [ $# -gt 0 ]; then
    echo "pr-check takes no options" >&2
    exit 2
  fi
  before="$(mktemp)"
  after="$(mktemp)"
  # Expanded now: the trap runs after this function's locals are gone
  trap "rm -f '$before' '$after'" EXIT
  source_hashes > "$before"
  for step in format check test build; do
    echo "== pr-check: $step"
    set +e
    "$SELF" "$step"
    status=$?
    set -e
    if [ "$status" -ne 0 ]; then
      echo "pr-check: $step failed (exit $status)" >&2
      exit "$status"
    fi
  done
  source_hashes > "$after"
  # diff exits 1 when they differ, which pipefail would take as a failure
  changed="$({ diff "$before" "$after" || true; } | sed -n 's/^> [0-9a-f]* //p')"
  echo "== pr-check: format, check, test and build all passed"
  if [ -n "$changed" ]; then
    echo "Formatting changed these files; review and commit them:"
    echo "$changed" | sed 's/^/  /'
  fi
}

# docs: the user documentation, into release/site_docs.
#
# The reference pages in docs/reference/ and the file format schemas in
# docs/reference/schemas/ are generated by opensloper-cli doc from the program
# itself, as is the Python client docs/reference/opensloper.py, and the
# tutorial pictures in docs/tutorials/images/ are drawn from the example
# patterns. They are committed, so the site builds without a Pascal toolchain
# (as the GitHub Pages workflow does); this command writes them again first
# when release/opensloper-cli has been built.
#
# --offline also builds the copy of the site that package puts in each
# download as data/help, read from disk: pages are linked as .../index.html,
# search works without a server, and the web fonts give way to the system's.
cmd_docs() {
  local cli=release/opensloper-cli serve=0 offline=0 reinstall=0 arg topic
  for arg in "$@"; do
    case "$arg" in
      --serve) serve=1 ;;
      --offline) offline=1 ;;
      --reinstall) reinstall=1 ;;
      *)
        echo "docs: unknown option $arg" >&2
        exit 2
        ;;
    esac
  done

  if [ "$reinstall" -eq 1 ]; then
    echo "Reinstalling virtual environment..."
    rm -rf venv
  fi
  if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
    # Upgrade pip inside the environment first to prevent installation issues
    ./venv/bin/pip install --upgrade pip
    ./venv/bin/pip install -r requirements.txt
  fi
  # A venv made before a requirement was added
  ./venv/bin/python -c "import jsonschema" 2>/dev/null || ./venv/bin/pip install -r requirements.txt

  if [ -x "$cli" ]; then
    # A topic ending in .schema.json is a file format's JSON Schema, as
    # DocTopicPath in Sloper.Docs.Reference says
    mkdir -p docs/reference/schemas
    for topic in $("$cli" doc); do
      case "$topic" in
        *.schema.json) "$cli" doc "$topic" -o "docs/reference/schemas/$topic" ;;
        *.py) "$cli" doc "$topic" -o "docs/reference/$topic" ;;
        *) "$cli" doc "$topic" -o "docs/reference/$topic.md" ;;
      esac
    done
    # Tutorial pictures, as listed in docs/tutorials/images.list
    mkdir -p docs/tutorials/images
    grep -v '^#' docs/tutorials/images.list | while read -r image pattern upto; do
      [ -z "$image" ] && continue
      local args=(export-draft "docs/$pattern" --labels -o "docs/tutorials/images/$image")
      [ "$upto" != "-" ] && args+=("--upto=$upto")
      "$cli" "${args[@]}" > /dev/null
    done
  else
    echo "Note: $cli is not built, so docs/reference/ and the tutorial pictures are left as they are" \
      "(run ./opensloper-make.sh build first)"
  fi

  # The Python client must at least read as Python
  ./venv/bin/python -I -c "import ast, sys; ast.parse(open(sys.argv[1], encoding='utf-8').read(), sys.argv[1])" \
    docs/reference/opensloper.py

  # The examples and regression files against the file format schemas
  ./venv/bin/python -I check-schemas.py docs tests

  if [ "$serve" -eq 1 ]; then
    ./venv/bin/zensical serve
  else
    ./venv/bin/zensical build --clean --strict
  fi

  if [ "$offline" -eq 1 ]; then
    # Zensical takes the project root from the configuration's folder, so the
    # offline configuration is written beside zensical.toml for the build
    sed -e 's|^site_dir = .*|site_dir = "release/site_offline"\nuse_directory_urls = false|' \
      -e 's|^\[project.theme\]$|&\nfont = false|' \
      -e '$a\\n[project.plugins.offline]' zensical.toml > .zensical-offline.toml
    trap 'rm -f .zensical-offline.toml' EXIT
    ./venv/bin/zensical build --clean --strict -f .zensical-offline.toml
    rm -f .zensical-offline.toml
    echo "Offline copy in release/site_offline"
  fi
}

# package: the apps that build put in release/ for this platform, as
#   release/dist/opensloper-VERSION-linux-x86_64.tar.gz    (Linux)
#   release/dist/opensloper_VERSION_amd64.deb              (Linux, with dpkg-deb)
#   release/dist/opensloper-VERSION-macos-arm64.dmg        (macOS: OpenSloper.app)
#   release/dist/opensloper-VERSION-windows-x86_64.zip     (Windows, from Git Bash)
#   release/dist/opensloper-VERSION-windows-x86_64-setup.exe  (Windows, with Inno Setup)
# VERSION is APP_VERSION in Sloper.Core.Version. Each has the offline user
# guide in data/help when docs --offline has built it into release/site_offline.
# STRIP names the strip program when it is not on PATH (as on Windows), and
# ISCC the Inno Setup compiler when it is not in its usual place.
# On Linux, BUNDLE_LIBS lists libraries to ship in lib/ beside the programs
# (the release workflow ships the Qt6 Pascal bindings, libQt6Pas.so.6, which
# few distributions package); the GUI programs then look there first.
# The Windows and macOS downloads ship OpenSSL 3 for the Claude assistant,
# with Mozilla's root certificates from curl.se, which OpenSSL there cannot
# read from the system: on Windows the DLLs in OPENSSL_DLL_DIR (default the
# first of /mingw64/bin, the openssl on PATH and C:/Program Files/OpenSSL*
# that has them), on macOS the dylibs of OPENSSL_PREFIX
# (default Homebrew's openssl@3). Linux uses the system's OpenSSL.

# The bundle's file types: the design app opens them all, and hands
# measurement files and layouts to the apps beside it
plist_document_type() {
  cat <<EOF
    <dict>
      <key>CFBundleTypeName</key><string>$1</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Owner</string>
      <key>CFBundleTypeIconFile</key><string>OpenSloper</string>
      <key>LSItemContentTypes</key><array><string>io.github.billbsing.opensloper.$2</string></array>
    </dict>
EOF
}

plist_exported_type() {
  cat <<EOF
    <dict>
      <key>UTTypeIdentifier</key><string>io.github.billbsing.opensloper.$2</string>
      <key>UTTypeDescription</key><string>$1</string>
      <key>UTTypeConformsTo</key><array><string>public.json</string></array>
      <key>UTTypeIconFile</key><string>OpenSloper</string>
      <key>UTTypeTagSpecification</key>
      <dict><key>public.filename-extension</key><array><string>$3</string></array></dict>
    </dict>
EOF
}

# The programs lose their debug information; the build keeps it for debugging
strip_programs() {
  local strip="${STRIP:-strip}" program
  if ! command -v "$strip" >/dev/null 2>&1; then
    echo "No $strip found, so the programs keep their debug information" >&2
    return
  fi
  for program in "$@"; do
    "$strip" "$program"
  done
}

# What the download says about running it, beside the programs
write_readme() {
  local file=$1 platform=$2
  {
    echo "OpenSloper $VERSION for $platform"
    echo
    echo "Parametric sewing pattern drafting. https://github.com/billbsing/opensloper"
    echo "Free software under the GNU General Public License version 3 or later (LICENSE)."
    echo
    case "$platform" in
      Linux)
        echo "Run opensloper-design (the pattern editor), opensloper-measurements or"
        echo "opensloper-publish from this folder; keep the data folder beside them."
        echo "opensloper-cli is the command-line tool."
        echo
        if [ -n "${BUNDLE_LIBS:-}" ]; then
          echo "The apps use Qt 6.4 or later, which most desktops have; its Pascal"
          echo "bindings are in the lib folder. Should Qt 6 be missing:"
          echo "  Debian, Ubuntu: sudo apt install libqt6printsupport6 qt6-qpa-plugins"
          echo "  Fedora: sudo dnf install qt6-qtbase-gui"
          echo "  Arch: sudo pacman -S qt6-base"
        else
          echo "The apps use Qt and need its Pascal bindings, libQt5Pas or libQt6Pas,"
          echo "from your distribution (libqt5pas1 or libqt6pas6 on Debian and Ubuntu)."
        fi
        echo
        echo "share/applications holds menu entries, share/icons the icons and share/mime"
        echo "the file types; copy them to ~/.local/share/applications,"
        echo "~/.local/share/icons/hicolor/scalable/apps and ~/.local/share/mime/packages"
        echo "(then run update-mime-database ~/.local/share/mime), with the programs on"
        echo "your PATH, to start OpenSloper from the desktop menu and open its files."
        echo "On Debian and Ubuntu the .deb download does all this."
        echo
        echo "To keep settings and recent files in this folder rather than your home"
        echo "folder, to run from a USB stick, put an empty file named portable.ini here."
        echo
        echo "The Claude assistant needs OpenSSL 3 (libssl3), which most systems have;"
        echo "opensloper-cli check-connection says whether it can reach the API."
        ;;
      macOS)
        echo "Drag OpenSloper.app to Applications and open it: it is the pattern editor,"
        echo "and its File menu opens the measurements editor and the publish window."
        echo "It is not signed by Apple. If macOS says it cannot be opened or is damaged,"
        echo "run this once in Terminal:"
        echo "  xattr -cr /Applications/OpenSloper.app"
        echo "The command-line tool is OpenSloper.app/Contents/MacOS/opensloper-cli."
        echo "Built for Apple silicon (arm64)."
        ;;
      Windows)
        echo "Run opensloper-design.exe (the pattern editor), opensloper-measurements.exe"
        echo "or opensloper-publish.exe from this folder; keep the data folder beside"
        echo "them. opensloper-cli.exe is the command-line tool. The setup.exe download"
        echo "installs the same programs, with Start menu entries and file types."
        echo
        echo "To keep settings and recent files in this folder rather than in AppData,"
        echo "to run from a USB stick, put an empty file named portable.ini here."
        echo
        echo "opensloper-cli.exe check-connection says whether the Claude assistant can"
        echo "reach the API. THIRD-PARTY.txt lists the parts that are not OpenSloper's."
        echo
        echo "The programs are not signed, so Windows SmartScreen may ask before the"
        echo "first run: choose More info, then Run anyway."
        ;;
    esac
  } > "$file"
}

CA_BUNDLE_URL=https://curl.se/ca/cacert.pem

# Mozilla's root certificates as curl publishes them, checked against the
# checksum published beside them, into a download's data folder
fetch_ca_bundle() {
  local data=$1 expected actual
  curl -sfL "$CA_BUNDLE_URL" -o "$data/cacert.pem"
  expected=$(curl -sfL "$CA_BUNDLE_URL.sha256" | cut -d' ' -f1)
  if command -v sha256sum >/dev/null; then
    actual=$(sha256sum "$data/cacert.pem" | cut -d' ' -f1)
  else
    actual=$(shasum -a 256 "$data/cacert.pem" | cut -d' ' -f1)
  fi
  if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    echo "The certificates from $CA_BUNDLE_URL do not match their checksum" >&2
    exit 1
  fi
}

# What a Windows or macOS download ships that is not OpenSloper's, with the
# licence OpenSSL asks to go with it
write_third_party() {
  local folder=$1 where=$2
  cp resources/licenses/Apache-2.0.txt "$folder/OpenSSL-LICENSE.txt"
  {
    echo "Besides OpenSloper itself, this download contains:"
    echo
    echo "OpenSSL 3 ($where), which the Claude assistant reaches the API with."
    echo "  Copyright the OpenSSL Project Authors. Apache License 2.0, in"
    echo "  OpenSSL-LICENSE.txt. https://www.openssl.org"
    echo
    echo "Mozilla's root certificates (data/cacert.pem), as published by the curl"
    echo "  project, which the assistant trusts in place of the system's. Mozilla"
    echo "  Public License 2.0. https://curl.se/docs/caextract.html"
  } > "$folder/THIRD-PARTY.txt"
}

# The OpenSSL 3 DLLs, beside the programs: from OPENSSL_DLL_DIR when it is
# set, else the first of Git for Windows' MinGW folder, the folder of the
# openssl on PATH and the usual install folders that has both
copy_openssl_windows() {
  local root=$1 dir found= openssl_bin candidates=()
  if [ -n "${OPENSSL_DLL_DIR:-}" ]; then
    candidates=("$OPENSSL_DLL_DIR")
  else
    candidates=(/mingw64/bin)
    openssl_bin=$(command -v openssl 2>/dev/null || true)
    [ -n "$openssl_bin" ] && candidates+=("$(dirname "$openssl_bin")")
    candidates+=("/c/Program Files/OpenSSL/bin" "/c/Program Files/OpenSSL-Win64/bin"
      "/c/Program Files/OpenSSL" "/c/Program Files/OpenSSL-Win64")
  fi
  for dir in "${candidates[@]}"; do
    if [ -f "$dir/libssl-3-x64.dll" ] && [ -f "$dir/libcrypto-3-x64.dll" ]; then
      found=$dir
      break
    fi
  done
  if [ -z "$found" ]; then
    echo "No libssl-3-x64.dll and libcrypto-3-x64.dll in any of:" >&2
    printf '  %s\n' "${candidates[@]}" >&2
    echo "Set OPENSSL_DLL_DIR to the folder of the OpenSSL 3 DLLs" >&2
    exit 1
  fi
  echo "OpenSSL DLLs from $found"
  cp "$found/libssl-3-x64.dll" "$found/libcrypto-3-x64.dll" "$root/"
}

# The OpenSSL 3 dylibs, in the bundle's Frameworks, finding each other there
# rather than where Homebrew put them; the bundle is signed after
copy_openssl_macos() {
  local bundle=$1 prefix=${OPENSSL_PREFIX:-} frameworks crypto
  [ -n "$prefix" ] || prefix=$(brew --prefix openssl@3 2>/dev/null || true)
  if [ ! -f "$prefix/lib/libssl.3.dylib" ]; then
    echo "No OpenSSL 3 in ${prefix:-Homebrew}; run brew install openssl@3, or set OPENSSL_PREFIX" >&2
    exit 1
  fi
  frameworks="$bundle/Contents/Frameworks"
  mkdir -p "$frameworks"
  cp -L "$prefix/lib/libssl.3.dylib" "$prefix/lib/libcrypto.3.dylib" "$frameworks/"
  chmod u+w "$frameworks"/*.dylib
  install_name_tool -id @loader_path/libcrypto.3.dylib "$frameworks/libcrypto.3.dylib"
  install_name_tool -id @loader_path/libssl.3.dylib "$frameworks/libssl.3.dylib"
  crypto=$(otool -L "$frameworks/libssl.3.dylib" | awk 'NR > 1 && /libcrypto/ {print $1; exit}')
  install_name_tool -change "$crypto" @loader_path/libcrypto.3.dylib "$frameworks/libssl.3.dylib"
  if otool -L "$frameworks"/*.dylib | grep -E '/opt/homebrew|/usr/local/(opt|Cellar)'; then
    echo "The bundled OpenSSL still names libraries outside the bundle" >&2
    exit 1
  fi
  # Homebrew builds for the runner's macOS, which may be later than the bundle's minimum
  echo "Bundled OpenSSL needs macOS $(otool -l "$frameworks/libssl.3.dylib" | awk '/minos/ {print $2; exit}')"
}

# The offline user guide, into a download's data folder
copy_user_guide() {
  local data=$1
  if [ -f release/site_offline/index.html ]; then
    cp -R release/site_offline "$data/help"
  else
    echo "No offline user guide in release/site_offline (run docs --offline), so" \
      "the apps' Help menu opens the website" >&2
  fi
}

# The .deb: the programs and data in /usr/lib/opensloper, linked from
# /usr/bin (the programs find their data from their real path), with the menu
# entries, icons and file types under /usr/share, which dpkg's triggers
# register. It needs the Qt6 Pascal bindings bundled (BUNDLE_LIBS), which
# Debian and Ubuntu package only from 2026, and Qt 6 itself from the system.
package_deb() {
  local root=$1 arch=$2 deb=release/stage/deb app size
  case "$arch" in
    x86_64) arch=amd64 ;;
  esac
  if ! command -v dpkg-deb >/dev/null; then
    echo "No dpkg-deb, so no .deb" >&2
    return
  fi
  if [ -z "${BUNDLE_LIBS:-}" ]; then
    echo "No .deb without the Qt6 Pascal bindings in BUNDLE_LIBS" >&2
    return
  fi
  rm -rf "$deb"
  mkdir -p "$deb/DEBIAN" "$deb/usr/lib/opensloper" "$deb/usr/bin" "$deb/usr/share/applications" \
    "$deb/usr/share/icons/hicolor/scalable/apps" "$deb/usr/share/mime/packages" "$deb/usr/share/doc/opensloper"
  for app in opensloper-design opensloper-publish opensloper-measurements opensloper-cli; do
    cp -p "$root/$app" "$deb/usr/lib/opensloper/"
    ln -s "../lib/opensloper/$app" "$deb/usr/bin/$app"
  done
  cp -R "$root/lib" "$root/data" "$deb/usr/lib/opensloper/"
  cp "$root"/share/applications/*.desktop "$deb/usr/share/applications/"
  cp "$root"/share/icons/*.svg "$deb/usr/share/icons/hicolor/scalable/apps/"
  cp "$root"/share/mime/packages/opensloper.xml "$deb/usr/share/mime/packages/"
  {
    echo "Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/"
    echo "Upstream-Name: OpenSloper"
    echo "Source: https://github.com/opensloper/opensloper"
    echo
    echo "Files: *"
    echo "Copyright: 2026 The OpenSloper authors"
    echo "License: GPL-3.0-or-later"
    echo " On Debian systems the licence is in /usr/share/common-licenses/GPL-3."
  } > "$deb/usr/share/doc/opensloper/copyright"
  gzip -9n < CHANGELOG.md > "$deb/usr/share/doc/opensloper/changelog.gz"
  size=$(du -sk "$deb/usr" | cut -f1)
  # Ubuntu 24.04 and Debian 13 name the Qt 6 libraries with t64
  cat > "$deb/DEBIAN/control" <<EOF
Package: opensloper
Version: $VERSION
Architecture: $arch
Maintainer: The OpenSloper authors <contact@opensloper.com>
Installed-Size: $size
Depends: libc6, libssl3t64 | libssl3, libqt6core6t64 (>= 6.4) | libqt6core6 (>= 6.4), libqt6gui6t64 | libqt6gui6, libqt6widgets6t64 | libqt6widgets6, libqt6printsupport6t64 | libqt6printsupport6, qt6-qpa-plugins
Section: graphics
Priority: optional
Homepage: https://github.com/opensloper/opensloper
Description: parametric sewing pattern drafting
 OpenSloper drafts sewing patterns from body measurements and formulas, so
 a pattern redrafts itself for every size. It has three apps: the pattern
 editor, a measurements editor and a publish app that lays out, tiles and
 prints the pieces, with opensloper-cli for the command line.
EOF
  dpkg-deb --root-owner-group --build "$deb" "release/dist/opensloper_${VERSION}_$arch.deb" >/dev/null
  echo "release/dist/opensloper_${VERSION}_$arch.deb"
}

# The macOS disk image: the bundle beside a link to Applications to drag it to
package_dmg() {
  local folder=$1 name=$2
  ln -s /Applications "$folder/Applications"
  rm -f "release/dist/$name.dmg"
  hdiutil create -quiet -volname "OpenSloper $VERSION" -srcfolder "$folder" -fs HFS+ -format UDZO \
    "release/dist/$name.dmg"
  rm "$folder/Applications"
  echo "release/dist/$name.dmg"
}

# The Windows installer, from the folder the .zip is made of
package_setup() {
  local root=$1 name=$2 iscc="${ISCC:-C:/Program Files (x86)/Inno Setup 6/ISCC.exe}"
  if [ ! -x "$iscc" ] && ! command -v "$iscc" >/dev/null 2>&1; then
    echo "No Inno Setup compiler ($iscc), so no installer" >&2
    return
  fi
  # Git Bash would take the /-options for paths and rewrite them
  MSYS2_ARG_CONV_EXCL='*' "$iscc" /Q "/DAppVersion=$VERSION" "/DSourceDir=$(cygpath -aw "$root")" \
    "/DOutputDir=$(cygpath -aw release/dist)" "/DOutputName=$name-setup" resources/windows/opensloper.iss
  echo "release/dist/$name-setup.exe"
}

cmd_package() {
  if [ $# -gt 0 ]; then
    echo "package takes no arguments" >&2
    exit 2
  fi
  VERSION=$(app_version)
  local apps=(opensloper-design opensloper-publish opensloper-measurements opensloper-cli)
  local dist=release/dist stage=release/stage arch name root bundle app lib size iconset
  rm -rf "$stage"
  mkdir -p "$dist" "$stage"

  case "$(uname -m)" in
    x86_64 | amd64) arch=x86_64 ;;
    arm64 | aarch64) arch=arm64 ;;
    *) arch=$(uname -m) ;;
  esac

  case "$(uname -s)" in
    Linux)
      name="opensloper-$VERSION-linux-$arch"
      root="$stage/$name"
      mkdir -p "$root/share/applications" "$root/share/icons" "$root/share/mime/packages"
      for app in "${apps[@]}"; do
        cp "release/$app" "$root/"
      done
      strip_programs "${apps[@]/#/$root/}"
      if [ -n "${BUNDLE_LIBS:-}" ]; then
        mkdir -p "$root/lib"
        for lib in $BUNDLE_LIBS; do
          cp -L "$lib" "$root/lib/"
        done
        for app in opensloper-design opensloper-publish opensloper-measurements; do
          patchelf --set-rpath '$ORIGIN/lib' "$root/$app"
        done
      fi
      cp -R data "$root/data"
      copy_user_guide "$root/data"
      cp resources/linux/*.desktop "$root/share/applications/"
      cp resources/linux/opensloper.xml "$root/share/mime/packages/"
      # Named as the desktop entries' Icon lines name them
      cp resources/opensloper-design.svg resources/opensloper-publish.svg resources/opensloper-measure.svg \
        "$root/share/icons/"
      cp LICENSE CHANGELOG.md "$root/"
      write_readme "$root/README.txt" Linux
      tar -C "$stage" -czf "$dist/$name.tar.gz" "$name"
      echo "$dist/$name.tar.gz"
      package_deb "$root" "$arch"
      ;;
    Darwin)
      # One bundle: the design app opens the other two as programs beside it
      name="opensloper-$VERSION-macos-$arch"
      bundle="$stage/$name/OpenSloper.app"
      mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
      for app in "${apps[@]}"; do
        cp "release/$app" "$bundle/Contents/MacOS/"
      done
      # Code signing takes only programs in MacOS, so the data is a resource
      cp -R data "$bundle/Contents/Resources/data"
      copy_user_guide "$bundle/Contents/Resources/data"
      fetch_ca_bundle "$bundle/Contents/Resources/data"
      copy_openssl_macos "$bundle"
      if command -v rsvg-convert >/dev/null && command -v iconutil >/dev/null; then
        iconset="$stage/OpenSloper.iconset"
        mkdir -p "$iconset"
        for size in 16 32 128 256 512; do
          rsvg-convert -w $size -h $size resources/opensloper-design.svg -o "$iconset/icon_${size}x${size}.png"
          rsvg-convert -w $((size * 2)) -h $((size * 2)) resources/opensloper-design.svg \
            -o "$iconset/icon_${size}x${size}@2x.png"
        done
        iconutil -c icns "$iconset" -o "$bundle/Contents/Resources/OpenSloper.icns"
      else
        echo "No rsvg-convert or iconutil, so the bundle has no icon" >&2
      fi
      # No NSPrincipalClass: the LCL then makes its own TCocoaApplication, and
      # naming NSApplication there gives it one without the LCL's methods
      cat > "$bundle/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>OpenSloper</string>
  <key>CFBundleDisplayName</key><string>OpenSloper</string>
  <key>CFBundleIdentifier</key><string>io.github.billbsing.opensloper</string>
  <key>CFBundleExecutable</key><string>opensloper-design</string>
  <key>CFBundleIconFile</key><string>OpenSloper</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array>
$(plist_document_type "OpenSloper pattern" pattern)
$(plist_document_type "OpenSloper measurements" measurements)
$(plist_document_type "OpenSloper layout" layout)
  </array>
  <key>UTExportedTypeDeclarations</key>
  <array>
$(plist_exported_type "OpenSloper pattern" pattern sloper)
$(plist_exported_type "OpenSloper measurements" measurements slm)
$(plist_exported_type "OpenSloper layout" layout slayout)
  </array>
</dict>
</plist>
EOF
      # Apple silicon runs only signed programs; an ad hoc signature is enough
      # to run once the download's quarantine is cleared
      codesign --force --deep --sign - "$bundle"
      cp LICENSE CHANGELOG.md "$stage/$name/"
      write_third_party "$stage/$name" "in OpenSloper.app/Contents/Frameworks"
      write_readme "$stage/$name/README.txt" macOS
      package_dmg "$stage/$name" "$name"
      ;;
    MINGW* | MSYS* | CYGWIN*)
      name="opensloper-$VERSION-windows-$arch"
      root="$stage/$name"
      mkdir -p "$root"
      local programs=()
      for app in "${apps[@]}"; do
        cp "release/$app.exe" "$root/"
        programs+=("$root/$app.exe")
      done
      strip_programs "${programs[@]}"
      cp -R data "$root/data"
      copy_user_guide "$root/data"
      fetch_ca_bundle "$root/data"
      copy_openssl_windows "$root"
      write_third_party "$root" "libssl-3-x64.dll and libcrypto-3-x64.dll"
      cp LICENSE "$root/LICENSE.txt"
      cp CHANGELOG.md "$root/CHANGELOG.md"
      write_readme "$root/README.txt" Windows
      (cd "$stage" && 7z a -tzip -bso0 "../../$dist/$name.zip" "$name")
      echo "$dist/$name.zip"
      package_setup "$root" "$name"
      ;;
    *)
      echo "No packaging for $(uname -s)" >&2
      exit 1
      ;;
  esac
}

# release: the release notes of a version, by default APP_VERSION: its
# CHANGELOG.md section, without its heading, or when that is missing or empty,
# the subjects of the commits since the previous release's tag (vX.Y.Z), each
# with the issues it closes ("Closes #3").
cmd_release() {
  local version section previous count commit subject issues
  version="${1:-$(app_version)}"

  # From "## VERSION" (perhaps followed by " - date") to the next "## " heading,
  # with the blank lines at either end left out
  section=$(awk -v version="$version" '
    /^## / {
      if (found) exit
      if ($2 == version) { found = 1; next }
    }
    found { print }
  ' CHANGELOG.md | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')

  if grep -q '[^[:space:]]' <<< "$section"; then
    printf '%s\n' "$section"
    return
  fi

  # The newest release tag before this version's own, which moves with it
  previous=$(git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude "v$version" HEAD 2>/dev/null || true)
  if [ -z "$previous" ]; then
    echo "The first release of OpenSloper."
    return
  fi

  echo "Changes since ${previous#v}:"
  echo
  count=0
  while IFS= read -r commit; do
    subject=$(git log -1 --format=%s "$commit")
    issues=$(git log -1 --format=%B "$commit" |
      grep -oiE '\b(close[sd]?|fix(e[sd])?|resolve[sd]?) #[0-9]+' | grep -oE '#[0-9]+' |
      sort -u -t'#' -k2n | paste -sd' ' - || true)
    if [ -n "$issues" ]; then
      echo "- $subject (${issues// /, })"
    else
      echo "- $subject"
    fi
    count=$((count + 1))
  done < <(git rev-list --no-merges --reverse "$previous..HEAD")
  [ "$count" -gt 0 ] || echo "- No changes"
}

COMMAND="${1:-}"
[ $# -gt 0 ] && shift
case "$COMMAND" in
  test) cmd_test "$@" ;;
  build) cmd_build "$@" ;;
  check) cmd_check "$@" ;;
  format) cmd_format "$@" ;;
  pr-check) cmd_pr_check "$@" ;;
  docs) cmd_docs "$@" ;;
  package) cmd_package "$@" ;;
  release) cmd_release "$@" ;;
  version) cmd_version "$@" ;;
  bump) cmd_bump "$@" ;;
  help | -h | --help) usage ;;
  "")
    usage >&2
    exit 2
    ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    usage >&2
    exit 2
    ;;
esac
exit 0

# The standards check, run by "check" with perl -x, which starts at the line below
#!perl
use strict;
use warnings;

my $github = ($ENV{GITHUB_ACTIONS} // '') eq 'true';
my ($errors, $warnings) = (0, 0);

# Units that pull in the LCL (or a GUI library); not allowed below src/ui
my %lcl = map { lc($_) => 1 } qw(
  Forms Graphics Controls Dialogs StdCtrls ExtCtrls ComCtrls Menus ActnList
  ButtonPanel CheckLst Grids Spin Buttons Clipbrd ImgList ExtDlgs Interfaces
  LCLProc LCLType LCLIntf LMessages LResources BGRABitmap BGRABitmapTypes BGRASVG);

# Third-party drawing libraries, built without the LCL, that our own units in a
# thirdparty folder (src/output/thirdparty) may use; every other rule applies there
my %thirdparty = map { lc($_) => 1 } qw(BGRABitmap BGRABitmapTypes BGRASVG);

# Sloper areas each folder may use; folders not listed may use any area
my %allowed = (
  'src/core'     => [qw(Core)],
  'src/document' => [qw(Core Document)],
  'src/api'      => [qw(Core Document Output API)],
  'src/output'   => [qw(Core Output)],
  'src/cli'      => [qw(Core Document Output API Assistant CLI Docs)],
  'src/docs'     => [qw(Core API CLI Docs)],
  'src/assistant' => [qw(Core API Assistant)],
);
my %no_lcl = map { $_ => 1 } qw(src/core src/document src/api src/output src/cli src/docs src/assistant);

# Units where single-letter names match the maths (coding-standards.md)
my %math = map { $_ => 1 } qw(
  src/core/sloper.core.geometry.pas src/core/sloper.core.bezier.pas src/core/sloper.core.numeric.pas);

sub report {
  my ($kind, $file, $line, $msg) = @_;
  if ($kind eq 'error') { $errors++ } else { $warnings++ }
  print "$file:$line: $kind: $msg\n";
  print "::${kind} file=${file},line=${line}::${msg}\n" if $github;
}

sub line_of { my ($text, $pos) = @_; return 1 + (substr($text, 0, $pos) =~ tr/\n//) }

# Blank out comments (and strings, when asked), keeping offsets and newlines,
# so later patterns only see code and still report the right line
sub blank {
  my ($tok, $strings) = @_;
  return $tok if $tok =~ /^'/ && !$strings;
  return "'" . (' ' x (length($tok) - 2)) . "'" if $tok =~ /^'/;
  $tok =~ s/[^\n]/ /g;
  return $tok;
}

sub strip {
  my ($text, $strings) = @_;
  $text =~ s!(\{[^}]*\}|\(\*.*?\*\)|//[^\n]*|'(?:[^'\n]|'')*')!blank($1, $strings)!gse;
  return $text;
}

for my $file (@ARGV) {
  open(my $fh, '<', $file) or do { report('error', $file, 1, "cannot read: $!"); next };
  local $/;
  my $raw = <$fh>;
  close $fh;
  my $nocomments = strip($raw, 0);
  my $code = strip($raw, 1);
  (my $dir = $file) =~ s{/[^/]*$}{};
  # A thirdparty folder belongs to its parent's area and layer
  my $in_thirdparty = $dir =~ s{/thirdparty$}{};
  my $is_test = $file =~ m{^tests/};

  # GPL header, then the compiler mode
  my $head = join("\n", grep { defined } (split /\n/, $raw)[0 .. 24]);
  report('error', $file, 1, 'missing the GPLv3 header from documents/gpl-header.txt')
    unless $head =~ /GNU General Public License/ && $head =~ /either version 3/;
  report('error', $file, 1, 'missing {$mode ObjFPC}{$H+}')
    if $file =~ /\.pas$/ && $raw !~ /\{\$mode\s+objfpc\}\s*\{\$H\+\}/i;

  # Unit name matches the file name and folder
  if ($file =~ /\.pas$/ && $code =~ /^\s*unit\s+([\w.]+)\s*;/mi) {
    my $unit = $1;
    (my $base = $file) =~ s{.*/}{};
    report('error', $file, line_of($code, $-[0]), "unit $unit should be in a file named " . lc($unit) . '.pas')
      unless lc($unit) . '.pas' eq $base;
    my ($area) = $dir =~ m{^(?:src/)?([^/]+)$};
    report('error', $file, line_of($code, $-[0]), "unit $unit should be named Sloper.<Area>.<Name> for folder $dir")
      unless defined $area && $unit =~ /^Sloper\.\Q$area\E\./i;
  }

  # Uses clauses: layering and Sloper.Core.CodePage first in programs
  my $first_uses = 1;
  my $uses_windows = 0;
  while ($code =~ /\buses\b(.*?);/gsi) {
    my ($list, $at) = ($1, $-[0]);
    my @units = map { s/\s+in\s+.*//sr =~ s/^\s+|\s+$//gr } split /,/, $list;
    if ($file =~ /\.lpr$/ && $first_uses) {
      my ($first) = grep { !/^(cthreads|cmem)$/i } @units;
      report('error', $file, line_of($code, $at), 'Sloper.Core.CodePage must be the first unit in a program\'s uses clause')
        unless defined $first && lc($first) eq 'sloper.core.codepage';
    }
    $first_uses = 0;
    for my $unit (@units) {
      $uses_windows = 1 if lc($unit) eq 'windows';
      report('error', $file, line_of($code, $at), "$dir must not use the LCL unit $unit")
        if $no_lcl{$dir} && $lcl{lc $unit} && !($in_thirdparty && $thirdparty{lc $unit});
      if ($allowed{$dir} && $unit =~ /^Sloper\.(\w+)\./i) {
        my $area = $1;
        report('error', $file, line_of($code, $at), "$dir must not use $unit (allowed: Sloper." .
          join(', Sloper.', @{ $allowed{$dir} }) . ')')
          unless grep { lc($_) eq lc($area) } @{ $allowed{$dir} };
      }
    }
  }

  # FreeAndNil, not .Free or .Destroy on a reference; an indexed or typecast
  # item (Controls[0].Free, TObject(List[Index]).Free) is the documented exception
  while ($code =~ /(?<![\w.)\]])([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\.(Free|Destroy)\s*;/g) {
    next if substr($code, 0, $-[0]) =~ /\bdestructor\s+$/i;
    report('error', $file, line_of($code, $-[0]), "use FreeAndNil($1), not $1.$2");
  }

  # Assigned(), not comparisons with nil (default values such as "X: T = nil" are fine)
  while ($code =~ /(<>|(?<![:<>])=)\s*nil\b/gi) {
    my $pos = $-[0];
    my $before = substr($code, 0, $pos);
    next if $1 eq '=' && $before =~ /:\s*[\w.]+\s*$/;
    report('error', $file, line_of($code, $pos), 'test references with Assigned(), not a comparison with nil');
  }

  # The Windows unit's GetEnvironmentVariable(PChar, PChar, DWord) hides the
  # SysUtils one where both are used, which only a Windows build reports
  if ($uses_windows) {
    while ($code =~ /(?<![\w.])GetEnvironmentVariable\s*\(/gi) {
      report('error', $file, line_of($code, $-[0]),
        'call SysUtils.GetEnvironmentVariable in a unit that uses Windows, whose own GetEnvironmentVariable hides it');
    }
  }

  # Shortcuts use ssModifier. The one exception is CONTROL_KEY in
  # Sloper.UI.Commands, for the shortcuts the table writes with Ctrl, which
  # are the Control key on macOS too.
  while ($code =~ /\bssCtrl\b/g) {
    my $line = line_of($code, $-[0]);
    next if $file =~ m{(^|/)src/ui/sloper\.ui\.commands\.pas$} && (split /\n/, $code)[$line - 1] =~ /^\s*CONTROL_KEY = ssCtrl;/;
    report('error', $file, $line, 'use ssModifier for shortcuts, not ssCtrl');
  }

  next if $is_test;

  # User-visible text belongs in resourcestring sections
  while ($nocomments =~ /\b(?:ShowMessage|MessageDlg|QuestionDlg|MessageBox)\s*\(\s*'|\b(?:Caption|Hint)\s*:=\s*'[^']*[A-Za-z]{2}/g) {
    report('error', $file, line_of($nocomments, $-[0]), 'user-visible text should be a resourcestring');
  }

  # Descriptive names: single-letter variables, fields and parameters
  next if $math{$file};
  # The whole name list is matched, so a short name after a long one
  # (Centre, Direction, P: TVec2) is found too
  while ($code =~ /(?:^[ \t]*|[(;][ \t]*(?:const |var |out )?)((?:[A-Za-z_]\w*[ \t]*,[ \t]*)*[A-Za-z_]\w*)[ \t]*:(?!=)/mg) {
    my ($names, $pos) = ($1, $-[1]);
    # Coordinates read well as X, Y, Z
    my @short = grep { /^[A-Za-z]$/ && !/^[XYZ]$/i } split /[ \t]*,[ \t]*/, $names;
    next unless @short;
    report('warning', $file, line_of($code, $pos), 'single-letter name (' . join(', ', @short) . '); use a descriptive name');
  }
}

my $checked = scalar @ARGV;
print "Checked $checked files: $errors errors, $warnings warnings.\n";
exit($errors ? 1 : 0);
