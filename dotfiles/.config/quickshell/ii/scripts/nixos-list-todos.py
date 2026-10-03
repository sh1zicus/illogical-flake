#!/usr/bin/env python3
"""Выводит TSV: tag<TAB>relpath<TAB>line<TAB>text — заметки в NixOS-конфиге.

tag: TODO | FIXME | XXX | HACK | NOTE | WARN | OPTIM (регистр сохраняется).
relpath: путь .nix-файла относительно CONFIG_ROOT.
line: номер строки (1-based).
text: текст комментария без маркера, обрезанный до 160 символов.

Строки внутри "..." и ''...'' пропускаются, чтобы не ловить "# TODO" в
строках. Комментарии /* ... */ наоборот сканируются — пометки там тоже
полезны. Каталоги .git, result и скрытые пропускаются.
"""

import os
import re
import sys

CONFIG_ROOT = os.environ.get("NIXOS_CONFIG_ROOT", "/etc/nixos")
SKIP_DIRS = {".git", "result", "node_modules"}
MARKER_RE = re.compile(r"\b(TODO|FIXME|XXX|HACK|NOTE|WARN|OPTIM)\b[: \t]*(.*)", re.IGNORECASE)


def find_markers(text):
    """Возвращает [(tag, line, tail)] по всему файлу, пропуская строковые литералы."""
    out = []
    n = len(text)
    i = 0
    line = 1
    at_line_start = True  # чтобы ловить маркер в начале строки

    def scan_line_end(chunk):
        nonlocal line, at_line_start
        nl = chunk.count("\n")
        if nl:
            line += nl
            at_line_start = True

    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            at_line_start = True
            i += 1
            continue
        if c == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == '"':
                    j += 1
                    break
                if text[j] == "\n":
                    line += 1
                    at_line_start = True
                j += 1
            scan_line_end("")
            i = j
            continue
        if text.startswith("''", i):
            end = text.find("''", i + 2)
            j = n if end < 0 else end + 2
            scan_line_end(text[i:j])
            i = j
            continue
        if c == "#":
            end = text.find("\n", i)
            end = n if end < 0 else end
            body = text[i + 1 : end]
            m = MARKER_RE.search(body)
            if m:
                out.append((m.group(1), line, m.group(2)))
            i = end
            continue
        if c == "/" and text[i + 1 : i + 2] == "*":
            # содержимое блока сканируем построчно
            end = text.find("*/", i + 2)
            end = n if end < 0 else end + 2
            body = text[i:end]
            for off, raw in enumerate(body.split("\n")):
                m = MARKER_RE.search(raw)
                if m:
                    out.append((m.group(1), line + off, m.group(2)))
            line += body.count("\n")
            at_line_start = True
            i = end
            continue
        if not c.isspace():
            at_line_start = False
        i += 1
    return out


def iter_nix_files(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS and not d.startswith("."))
        for name in sorted(filenames):
            if name.endswith(".nix"):
                yield os.path.join(dirpath, name)


def main():
    rows = []
    for path in iter_nix_files(CONFIG_ROOT):
        try:
            text = open(path, encoding="utf-8").read()
        except OSError:
            continue
        rel = os.path.relpath(path, CONFIG_ROOT)
        for tag, line, tail in find_markers(text):
            tail = " ".join(tail.split())
            if len(tail) > 160:
                tail = tail[:157] + "..."
            rows.append((tag, rel, line, tail))
    order = {"FIXME": 0, "TODO": 1, "XXX": 2, "HACK": 3, "WARN": 4, "NOTE": 5, "OPTIM": 6}
    rows.sort(key=lambda r: (order.get(r[0].upper(), 9), r[1], r[2]))
    for tag, rel, line, tail in rows:
        sys.stdout.write(f"{tag}\t{rel}\t{line}\t{tail}\n")


if __name__ == "__main__":
    main()
