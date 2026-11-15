#!/usr/bin/env python3
"""Checks every external reference in the catalog against its source of truth.

Homebrew casks/formulae (deprecated, disabled, renamed, app name), npm packages
(deprecated or missing), suggested Ollama model tags (must exist in the registry)
and preset ids (must exist in the catalog). Exits 1 when something needs attention.

Usage: python3 tools/audit_catalog.py [repo-root]
"""
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "Sources", "MT3KMacTools")
ENV = dict(os.environ, HOMEBREW_NO_AUTO_UPDATE="1", HOMEBREW_NO_ENV_HINTS="1")
findings = []


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, env=ENV)


def read(name):
    with open(os.path.join(SOURCES, name), encoding="utf-8") as handle:
        return handle.read()


def catalog_items():
    body = read("Catalog.swift")
    body = body[body.index("static let items"):]
    items = []
    for block in re.split(r"\n\s*\.init\(", body)[1:]:
        item_id = re.search(r'id: "([^"]+)"', block).group(1)
        app = re.search(r'appName: "([^"]+)"', block)
        method = re.search(r'\.(brewCask|brewFormula|brewTap|npm)\("([^"]+)"\)', block)
        items.append({
            "id": item_id,
            "kind": method.group(1) if method else "other",
            "arg": method.group(2) if method else None,
            "app": app.group(1) if app else None,
        })
    return items


def brew_info(flag, names):
    """One brew call for all names; falls back to one call per name if any is unknown."""
    result = run("brew", "info", "--json=v2", flag, *names)
    key = "casks" if flag == "--cask" else "formulae"
    if result.returncode == 0:
        return dict(zip(names, json.loads(result.stdout)[key]))
    found = {}
    for name in names:
        single = run("brew", "info", "--json=v2", flag, name)
        found[name] = json.loads(single.stdout)[key][0] if single.returncode == 0 else None
    return found


def cask_apps(cask):
    apps = []
    for artifact in cask.get("artifacts", []):
        for entry in artifact.get("app", []):
            if isinstance(entry, str):
                apps.append(entry.split("/")[-1])
            elif isinstance(entry, dict) and "target" in entry:
                apps = apps[:-1] + [entry["target"].split("/")[-1]]
    return apps


def check_brew(items):
    for kind, flag, name_key in (("brewCask", "--cask", "token"), ("brewFormula", "--formula", "name")):
        wanted = [item for item in items if item["kind"] == kind]
        info = brew_info(flag, [item["arg"] for item in wanted])
        for item in wanted:
            entry = info.get(item["arg"])
            if entry is None:
                findings.append(f"{item['id']}: Homebrew has no {item['arg']}")
                continue
            if entry.get("disabled"):
                findings.append(f"{item['id']}: {item['arg']} is disabled ({entry.get('disable_reason')})")
            elif entry.get("deprecated"):
                findings.append(f"{item['id']}: {item['arg']} is deprecated ({entry.get('deprecation_reason')})")
            if entry[name_key] != item["arg"]:
                findings.append(f"{item['id']}: {item['arg']} was renamed to {entry[name_key]}")
            if kind == "brewCask" and item["app"]:
                apps = cask_apps(entry)
                if apps and item["app"] not in apps:
                    findings.append(f"{item['id']}: appName {item['app']!r} but the cask installs {apps}")


def check_npm(items):
    for item in items:
        if item["kind"] != "npm":
            continue
        result = run("npm", "view", item["arg"], "deprecated")
        if result.returncode != 0:
            findings.append(f"{item['id']}: npm has no {item['arg']}")
        elif result.stdout.strip():
            findings.append(f"{item['id']}: npm {item['arg']} is deprecated: {result.stdout.strip()[:90]}")


def check_presets(items):
    ids = {item["id"] for item in items}
    for group in re.findall(r"itemIDs: \[([^\]]+)\]", read("AppsView.swift")):
        for preset_id in re.findall(r'"([^"]+)"', group):
            if preset_id not in ids:
                findings.append(f"preset: id {preset_id!r} is not in the catalog")


def check_ollama():
    source = read("OllamaPanel.swift")
    block = source[source.index("static let popular"):source.index("static var categories")]
    for model in re.findall(r'\.init\(id: "([^"]+)"', block):
        name, _, tag = model.partition(":")
        repo = name if "/" in name else f"library/{name}"
        request = urllib.request.Request(
            f"https://registry.ollama.ai/v2/{repo}/manifests/{tag or 'latest'}",
            headers={"Accept": "application/vnd.docker.distribution.manifest.v2+json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                status = response.status
        except urllib.error.HTTPError as error:
            status = error.code
        except OSError as error:
            findings.append(f"ollama: {model} could not be checked ({error})")
            continue
        if status != 200:
            findings.append(f"ollama: {model} returned HTTP {status}")


def main():
    items = catalog_items()
    check_brew(items)
    check_npm(items)
    check_presets(items)
    check_ollama()
    print(f"catalog: {len(items)} items checked, {len(findings)} finding(s)")
    for finding in findings:
        print(f"  - {finding}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
