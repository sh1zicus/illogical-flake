#!/usr/bin/env python3
"""Выводит TSV: source<TAB>relpath<TAB>line<TAB>name — сервисы из NixOS-конфига.

source: "system" для system-modules, "home" для home-модулей.
relpath: путь .nix-файла относительно CONFIG_ROOT.
line: номер строки, где объявлен сервис (1-based).
name: имя сервиса — systemd-юнит (systemd.services.*) или верхний атрибут
services.* (модуль, для которого задан enable = true либо блок конфига).
Комментарии и строки вырезаны, поэтому enable = false и закомментированные
объявления в список не попадают.
"""

import glob
import os
import re
import sys

CONFIG_ROOT = os.environ.get("NIXOS_CONFIG_ROOT", "/etc/nixos")
SOURCE_DIRS = {
    os.path.join(CONFIG_ROOT, "system-modules"): "system",
    os.path.join(CONFIG_ROOT, "home-modules"): "home",
    os.path.join(CONFIG_ROOT, "home"): "home",
}

RE_SYSTEMD_SVC = re.compile(r"\bsystemd\.(?:user\.)?services\.([A-Za-z0-9_+\-]+)")
RE_ENABLE = re.compile(
    r"\bservices\.([A-Za-z0-9_+\-]+)(?:\.[A-Za-z0-9_+\-]+)*\.enable\s*=\s*(true|false)\b"
)
RE_BLOCK = re.compile(r"\bservices\.([A-Za-z0-9_+\-]+)\s*=\s*\{")


def mask(text):
    """Возвращает текст с пробелами вместо комментариев и строк (длина та же)."""
    out = list(text)
    n = len(text)

    def blank(a, b):
        for k in range(a, b):
            if out[k] != "\n":
                out[k] = " "

    i = 0
    while i < n:
        c = text[i]
        if c == "#":
            j = text.find("\n", i)
            blank(i, n if j < 0 else j)
            i = n if j < 0 else j
        elif c == "/" and text[i + 1 : i + 2] == "*":
            j = text.find("*/", i + 2)
            if j < 0:
                blank(i, n)
                i = n
            else:
                blank(i, j + 2)
                i = j + 2
        elif c == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                elif text[j] == '"':
                    j += 1
                    break
                else:
                    j += 1
            blank(i, j)
            i = j
        elif text.startswith("''", i):
            j = text.find("''", i + 2)
            if j < 0:
                j = n
            else:
                j += 2
            blank(i, j)
            i = j
        else:
            i += 1
    return "".join(out)


def scan(text):
    masked = mask(text)
    hits = []  # (name, span_start)
    for m in RE_SYSTEMD_SVC.finditer(masked):
        hits.append((m.group(1), m.start()))
    for m in RE_ENABLE.finditer(masked):
        if m.group(2) == "true":
            hits.append((m.group(1), m.start()))
    for m in RE_BLOCK.finditer(masked):
        hits.append((m.group(1), m.start()))
    return hits


def main():
    rows = []
    for pattern, source in SOURCE_DIRS.items():
        for path in sorted(glob.glob(os.path.join(pattern, "**", "*.nix"), recursive=True)):
            try:
                text = open(path, encoding="utf-8").read()
            except OSError:
                continue
            rel = os.path.relpath(path, CONFIG_ROOT)
            for name, pos in scan(text):
                line = text.count("\n", 0, pos) + 1
                rows.append((source, rel, line, name))

    # Дедупликация по (source, rel, name): оставляем самое раннее объявление.
    rows.sort(key=lambda r: (r[0], r[1], r[2]))
    seen = set()
    out = []
    for source, rel, line, name in rows:
        key = (source, rel, name)
        if key in seen:
            continue
        seen.add(key)
        out.append((source, rel, line, name))

    out.sort(key=lambda r: (r[0], r[3], r[2]))
    for source, rel, line, name in out:
        sys.stdout.write(f"{source}\t{rel}\t{line}\t{name}\n")


if __name__ == "__main__":
    main()