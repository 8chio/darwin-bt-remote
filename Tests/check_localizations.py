#!/usr/bin/env python3
"""Check catalog coverage and the compiled language tables, without changing preferences."""
import argparse
import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
FORMAT = re.compile(r"%(?:\d+\$)?[-+ #0]*(?:\d+)?(?:\.\d+)?(?:hh|ll|h|l|z|t|j)?[@diuoxXfFeEgGcsSp%]")


def check(app=None):
    catalogs = {}
    for table in ("Localizable", "InfoPlist"):
        catalog = json.loads((ROOT / "BTRemote" / (table + ".xcstrings")).read_text())
        catalogs[table] = catalog
        assert catalog["sourceLanguage"] == "en"
        for key, entry in catalog["strings"].items():
            values = {}
            for language in ("en", "ko"):
                unit = entry["localizations"][language]["stringUnit"]
                values[language] = unit["value"]
                assert values[language].strip() and values[language] != key, (table, language, key)
            assert FORMAT.findall(values["en"]) == FORMAT.findall(values["ko"]), ("format arguments", key)
        print(f"PASS: {table}: complete en/ko coverage, nonempty values and matching format arguments ({len(catalog['strings'])} keys)")

    references = set()
    for filename in ("L10n.swift", "L10nExtensions.swift"):
        references.update(re.findall(r'"([a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+)"', (ROOT / "BTRemote" / filename).read_text()))
    for source in (ROOT / "BTRemote").glob("DirectInput*.swift"):
        references.update(re.findall(r'"(shortcut\.[a-z_]+)"', source.read_text()))
    assert references <= catalogs["Localizable"]["strings"].keys(), references - catalogs["Localizable"]["strings"].keys()
    print(f"PASS: all {len(references)} referenced L10n/shortcut keys exist")

    if app:
        resources = app / "Contents" / "Resources"
        for table, catalog in catalogs.items():
            for language in ("en", "ko"):
                path = resources / (language + ".lproj") / (table + ".strings")
                compiled = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(path)]))
                for key, entry in catalog["strings"].items():
                    unit = entry["localizations"][language]["stringUnit"]
                    actual = compiled.get(key)
                    if table == "InfoPlist" and actual is None and unit["state"] == "new":
                        # Xcode omits an untranslated development-language entry;
                        # system bundle info falls back to the base Info.plist.
                        base_info = json.loads(subprocess.check_output([
                            "plutil", "-convert", "json", "-o", "-", str(app / "Contents" / "Info.plist")
                        ]))
                        actual = base_info.get(key)
                    assert actual == unit["value"], (path, key)
                print(f"PASS: compiled {language}.lproj/{table}.strings (base Info.plist fallback where applicable)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=pathlib.Path)
    check(parser.parse_args().app)
