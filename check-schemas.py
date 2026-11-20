#!/usr/bin/env python3
# Checks the file format schemas in docs/reference/schemas/ and every pattern,
# measurement, layout, drape and Blender scene file under the folders given against them. A schema
# describes its format's current version, so files of older versions (kept in
# tests/files/v<n>/ to test upgrading) are counted but not checked.
# Usage: python3 check-schemas.py [FOLDER...] (by default docs and tests, as opensloper-make.sh docs runs it)
import json
import pathlib
import sys

from jsonschema import Draft202012Validator

SCHEMAS = pathlib.Path(__file__).resolve().parent / "docs" / "reference" / "schemas"
EXTENSIONS = {".sloper": "pattern", ".slm": "measurements", ".slayout": "layout", ".sdrape": "drape", ".blender.json": "blender"}


def kind_of(path):
    for extension, kind in EXTENSIONS.items():
        if path.name.endswith(extension):
            return kind
    return None


def main(folders):
    validators = {}
    for name in EXTENSIONS.values():
        schema = json.loads((SCHEMAS / f"{name}.schema.json").read_text(encoding="utf-8"))
        Draft202012Validator.check_schema(schema)
        validators[name] = Draft202012Validator(schema)
    failed = checked = older = 0
    for folder in folders:
        for path in sorted(pathlib.Path(folder).rglob("*")):
            kind = kind_of(path)
            if kind is None or not path.is_file():
                continue
            data = json.loads(path.read_text(encoding="utf-8"))
            current = validators[kind].schema["properties"]["version"]["maximum"]
            if isinstance(data.get("version"), int) and data["version"] < current:
                older += 1
                continue
            checked += 1
            for error in sorted(validators[kind].iter_errors(data), key=lambda e: list(e.path)):
                where = "/".join(str(part) for part in error.path) or "(top)"
                print(f"{path}: {where}: {error.message}")
                failed += 1
    print(f"Checked {checked} files against the schemas: {failed} problems; {older} of older versions left out")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or ["docs", "tests"]))
