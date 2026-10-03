#!/usr/bin/env python3
"""Ищет пакеты в nixpkgs и печатает TSV: attr<TAB>version<TAB>description.

Индекс один раз кэшируется в $XDG_CACHE_HOME/quickshell/nixpkgs-index.json
(собранный `nix search nixpkgs --json`), дальше поиск идёт по нему локально
и мгновенно. Печать: `path` — готовый индекс (для панели), `build` — собрать.
"""

import json
import os
import subprocess
import sys

CACHE = os.path.join(
    os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
    "quickshell",
    "nixpkgs-index.json",
)


def run(cmd, timeout=None):
    return subprocess.run(
        cmd,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        timeout=timeout,
    ).stdout


def nixpkgs_path():
    return run(["nix", "eval", "--raw", "nixpkgs#path"]).strip()


def load_cached():
    """Читает индекс как есть. Актуальность проверяется только при сборке:
    сверка с nixpkgs#path сама по себе стоит несколько секунд."""
    try:
        with open(CACHE, encoding="utf-8") as f:
            pkgs = json.load(f).get("packages", [])
    except (OSError, ValueError):
        return None
    # В nixpkgs много алиасов с одинаковым именем (NeovimExt и т.п.) —
    # в списке они бесполезны, оставляем по одному.
    seen = set()
    out = []
    for row in pkgs:
        key = row[0].lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(row)
    return out


def build_index(path):
    # Полный eval legacyPackages дорогой (десятки секунд на холодном кэше),
    # поэтому процесс не блокирует панель: он идёт в фоне, а UI показывает
    # «Searching nixpkgs…».
    raw = run(["nix", "search", "--json", "nixpkgs", "."], timeout=1800)
    data = json.loads(raw)
    pkgs = []
    for attr, meta in data.items():
        name = attr.split(".")[-1]
        pkgs.append([name, meta.get("version", ""), " ".join((meta.get("description") or "").split())])
    pkgs.sort(key=lambda r: r[0].lower())
    out = {"nixpkgsPath": path, "packages": pkgs}
    tmp = CACHE + ".tmp"
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    os.replace(tmp, CACHE)
    return pkgs


def score(attr, desc, query, terms):
    """Чем меньше bucket, тем лучше: сначала имя, потом описание."""
    name = attr.lower()
    dsc = desc.lower()
    if name == query:
        bucket = 0
    elif name.startswith(query):
        bucket = 1
    elif query in name:
        bucket = 2
    elif all(t in name for t in terms):
        bucket = 3
    elif dsc.startswith(query):
        bucket = 4
    elif all(t in dsc for t in terms):
        bucket = 5
    else:
        return None
    return (bucket, len(attr), attr)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "search"
    query = sys.argv[2] if len(sys.argv) > 2 else ""
    if mode == "build":
        path = nixpkgs_path()
        build_index(path)
        print(len(load_cached() or []), file=sys.stderr)
        return
    # В режиме поиска nix зовём только при build: `nix eval nixpkgs#path`
    # сам по себе занимает ~5 c, а поиск должен быть мгновенным.
    pkgs = load_cached()
    if pkgs is None:
        print("NOINDEX", file=sys.stderr)
        return
    query = query.strip().lower()
    terms = [t for t in query.split() if t]
    rows = []
    if terms:
        for attr, version, desc in pkgs:
            s = score(attr, desc, query, terms)
            if s is not None:
                rows.append((s, attr, version, desc))
        rows.sort(key=lambda r: r[0])
    else:
        rows = [((2, len(a), a), a, v, d) for a, v, d in pkgs]
    for _, attr, version, desc in rows[:300]:
        sys.stdout.write(f"{attr}\t{version}\t{desc}\n")


if __name__ == "__main__":
    main()
