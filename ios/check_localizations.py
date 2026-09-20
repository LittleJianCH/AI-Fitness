#!/usr/bin/env python3
"""Check native catalog translations and optional Xcode extraction output."""
import argparse
import copy
import json
from pathlib import Path
import re

PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?(lld|ld|d|lf|f|@)")


def arguments(value):
    return {int(position) if position else index: kind
            for index, (position, kind) in enumerate(PLACEHOLDER.findall(value.replace("%%", "")), 1)}


def variants(localization):
    if "stringUnit" in localization:
        return [localization["stringUnit"]]
    return [unit["stringUnit"] for unit in localization.get("variations", {}).get("plural", {}).values()]


def errors(catalog, table):
    issues = []
    if catalog.get("sourceLanguage") != "en":
        issues.append(f"{table}: English must be the development language")
    for key, entry in catalog["strings"].items():
        if entry.get("shouldTranslate") is False:
            continue
        localizations = entry.get("localizations", {})
        source = variants(localizations.get("en", {}))
        expected = arguments(key if table == "Localizable" else source[0]["value"] if source else "")
        for language in ["en", "zh-Hans"]:
            translation = localizations.get(language, {})
            values = variants(translation)
            if not values:
                issues.append(f"{table}/{key}: missing {language} translation")
            for value in values:
                if value.get("state") != "translated" or not value.get("value"):
                    issues.append(f"{table}/{key}: incomplete {language} translation")
                if arguments(value.get("value", "")) != expected:
                    issues.append(f"{table}/{key}: {language} placeholder/type mismatch")
            if "variations" in translation:
                required = {"one", "other"} if language == "en" else {"other"}
                if not required <= translation["variations"].get("plural", {}).keys():
                    issues.append(f"{table}/{key}: missing {language} plural branch")
    return issues


def self_test():
    good = {"sourceLanguage": "en", "strings": {"%lld samples": {"localizations": {
        "en": {"variations": {"plural": {category: {"stringUnit": {"state": "translated", "value": text}}
                for category, text in [("one", "%lld sample"), ("other", "%lld samples")]}}},
        "zh-Hans": {"stringUnit": {"state": "translated", "value": "%lld 个样本"}}}}}}
    assert not errors(good, "Localizable")
    missing = copy.deepcopy(good)
    del missing["strings"]["%lld samples"]["localizations"]["zh-Hans"]
    assert any("missing zh-Hans" in error for error in errors(missing, "Localizable"))
    wrong_type = copy.deepcopy(good)
    wrong_type["strings"]["%lld samples"]["localizations"]["zh-Hans"]["stringUnit"]["value"] = "%@ 个样本"
    assert any("placeholder/type" in error for error in errors(wrong_type, "Localizable"))
    no_plural = copy.deepcopy(good)
    del no_plural["strings"]["%lld samples"]["localizations"]["en"]["variations"]["plural"]["one"]
    assert any("plural branch" in error for error in errors(no_plural, "Localizable"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--extracted", type=Path, help="Xcode Objects-normal/arm64 directory from a completed build")
    args = parser.parse_args()
    self_test()
    app = Path(__file__).resolve().parent / "App"
    catalogs = {path.stem: json.loads(path.read_text()) for path in app.glob("*.xcstrings")}
    issues = [issue for name, catalog in catalogs.items() for issue in errors(catalog, name)]
    if set(catalogs) != {"Localizable", "InfoPlist"}:
        issues.append("Both Localizable and InfoPlist catalogs are required")
    if args.extracted:
        files = list(args.extracted.glob("*.stringsdata"))
        if not files:
            issues.append("No compiler extraction files found; build the iOS app first")
        for path in files:
            for table, entries in json.loads(path.read_text()).get("tables", {}).items():
                for entry in entries:
                    if entry["key"] not in catalogs.get(table, {}).get("strings", {}):
                        issues.append(f"{path.name}: uncatalogued {table} key {entry['key']}")
    if issues:
        raise SystemExit("\n".join(issues))
    print(f"Validated {sum(len(c['strings']) for c in catalogs.values())} native entries, placeholders, plural branches and corruption probes.")


if __name__ == "__main__":
    main()
