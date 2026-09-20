#!/usr/bin/env python3
"""Check maintained Android catalogs without an SDK or translation runtime."""
from pathlib import Path
import copy
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
PLACEHOLDER = re.compile(r"%(\d+)\$([sdf])")

def catalog(path):
    result = {}
    for node in ET.parse(path).getroot():
        key = (node.tag, node.attrib["name"])
        if key in result:
            raise ValueError(f"Duplicate resource: {key}")
        result[key] = ({child.attrib["quantity"]: child.text or "" for child in node}
                       if node.tag == "plurals" else {"value": node.text or ""})
    return result

def validate(source, translated):
    if source.keys() != translated.keys():
        raise ValueError(f"Resource keys differ: {source.keys() ^ translated.keys()}")
    for key, variants in source.items():
        reference = set(PLACEHOLDER.findall(next(iter(variants.values()))))
        for locale, forms in (("en", variants), ("zh-Hans", translated[key])):
            required = {"one", "other"} if locale == "en" else {"other"}
            if key[0] == "plurals" and not required <= forms.keys():
                raise ValueError(f"Missing plural branch: {locale} {key}")
            for value in forms.values():
                if not value.strip() or set(PLACEHOLDER.findall(value)) != reference:
                    raise ValueError(f"Empty text or incompatible placeholders: {locale} {key}")
                if re.search(r"%(?!%|\d+\$[sdf])", value):
                    raise ValueError(f"Use typed positional placeholders: {locale} {key}")

def self_test(source, translated):
    mutations = []
    missing = copy.deepcopy(translated)
    missing.pop(next(iter(missing)))
    mutations.append(missing)
    wrong_type = copy.deepcopy(translated)
    wrong_type[("string", "split_title")]["value"] = "%1$s %2$s"
    mutations.append(wrong_type)
    plural = copy.deepcopy(translated)
    plural[("plurals", "chart_samples")].pop("other")
    mutations.append(plural)
    for mutated in mutations:
        try:
            validate(source, mutated)
        except ValueError:
            continue
        raise AssertionError("Catalog regression was not detected")

if __name__ == "__main__":
    resources = ROOT / "app/src/main/res"
    source = catalog(resources / "values/strings.xml")
    translated = catalog(resources / "values-b+zh+Hans/strings.xml")
    validate(source, translated)
    self_test(source, translated)
    referenced = set()
    for file in (ROOT / "app/src/main/java").rglob("*.kt"):
        text = file.read_text()
        referenced.update(re.findall(r"R\.(string|plurals)\.(\w+)", text))
        if re.search(r"[\u4e00-\u9fff]", text):
            raise ValueError(f"Unextracted Chinese UI copy: {file}")
    if not referenced <= source.keys():
        raise ValueError(f"Missing referenced resources: {referenced - source.keys()}")
    print(f"Android localization: {len(source)} resources; keys, arguments, plurals, missing-translation regression checks passed.")
