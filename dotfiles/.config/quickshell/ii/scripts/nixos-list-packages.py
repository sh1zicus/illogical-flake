#!/usr/bin/env python3
"""Выводит TSV: source<TAB>relpath<TAB>line<TAB>attr — пакеты из NixOS-конфига.

source: "system" для environment.systemPackages, "home" для home.packages.
relpath: путь .nix-файла относительно CONFIG_ROOT.
line: номер строки в файле, где объявлен атрибут (1-based).
attr: атрибут/выражение пакета.
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

KEY_RE = re.compile(r"environment\.systemPackages\s*=\s*|home\.packages\s*=\s*")
ATTR_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_'.-]*(?:\.[A-Za-z_][A-Za-z0-9_'.-]*)*")
INSIDE_PAREN_RE = re.compile(r"(?:pkgs|customPkgs|nwm)\.([A-Za-z0-9_.-]+)")


def skip_string(text, i):
    """Пропускает "..." / '...' / ''...'' строку, начинающуюся на i."""
    n = len(text)
    c = text[i]
    if c == '"':
        j = i + 1
        while j < n:
            if text[j] == "\\":
                j += 1
            elif text[j] == '"':
                return j + 1
            j += 1
        return n
    if text.startswith("''", i):
        end = text.find("''", i + 2)
        return end + 2 if end >= 0 else n
    j = text.find("'", i + 1)
    return j + 1 if j >= 0 else n


def skip_line_comment(text, i):
    end = text.find("\n", i)
    return len(text) if end < 0 else end


def skip_block_comment(text, i):
    end = text.find("*/", i + 2)
    return len(text) if end < 0 else end + 2


def scan_trivia(text, i, n):
    """Пропускает пробелы/комментарии с позиции i; возвращает i или -1 если EOF."""
    while i < n:
        while i < n and text[i].isspace():
            i += 1
        if i >= n:
            return -1
        if text[i] == "#":
            i = skip_line_comment(text, i)
            continue
        if text[i] == "/" and text[i + 1 : i + 2] == "*":
            i = skip_block_comment(text, i)
            continue
        break
    return i


def bracket_body(text, open_idx):
    """Возвращает (body, open_after) — текст внутри [] и позицию сразу после '['."""
    depth = 0
    n = len(text)
    i = open_idx
    while i < n:
        c = text[i]
        if c in '"\'`':
            i = skip_string(text, i)
        elif c == "#":
            i = skip_line_comment(text, i)
        elif c == "/" and text[i + 1 : i + 2] == "*":
            i = skip_block_comment(text, i)
        else:
            if c == "[":
                depth += 1
            elif c == "]":
                depth -= 1
                if depth == 0:
                    return text[open_idx + 1 : i], open_idx + 1
            i += 1
    return None, None


def extract_list_body(text, start):
    """После '=' достаёт (body, body_off) списка, пропуская 'with ...;' преамбулу."""
    n = len(text)
    i = start
    while True:
        i = scan_trivia(text, i, n)
        if i < 0:
            return None, None
        if text.startswith("with", i) and (
            i + 4 >= n or not (text[i + 4].isalnum() or text[i + 4] == "_")
        ):
            j = i + 4
            depth = 0
            while j < n:
                c = text[j]
                if c in "([{":
                    depth += 1
                elif c in ")]}":
                    depth -= 1
                elif c in '"\'`':
                    j = skip_string(text, j)
                elif c == "#":
                    j = skip_line_comment(text, j)
                elif c == "/" and text[j + 1 : j + 2] == "*":
                    j = skip_block_comment(text, j)
                elif c == ";" and depth == 0:
                    break
                else:
                    j += 1
            if j >= n:
                return None, None
            i = j + 1
            continue
        if text[i] == "[":
            return bracket_body(text, i)
        return None, None


def split_items(body, base_off):
    """Разбивает тело списка на (item, item_off). Комментарии на верхнем уровне
    закрывают текущий элемент; внутри ()/[]/{} пропускаются."""
    items = []
    cur = []
    cur_off = -1
    stack = []
    close = {"(": ")", "[": "]", "{": "}"}
    i = 0
    n = len(body)
    while i < n:
        c = body[i]
        if c in "([{":
            stack.append(close[c])
            if not cur:
                cur_off = i
            cur.append(c)
        elif c in ")]}":
            if stack:
                stack.pop()
            cur.append(c)
        elif c in '"\'`':
            if not cur:
                cur_off = i
            cur.append(c)
            i = skip_string(body, i) - 1
        elif c == "#":
            if stack:
                i = skip_line_comment(body, i)
                cur.append(body[cur_off:i]) if False else None
            else:
                if cur:
                    items.append(("".join(cur), base_off + cur_off))
                    cur = []
                    cur_off = -1
                i = skip_line_comment(body, i)
        elif c == "/" and body[i + 1 : i + 2] == "*":
            if stack:
                i = skip_block_comment(body, i) - 1
            else:
                if cur:
                    items.append(("".join(cur), base_off + cur_off))
                    cur = []
                    cur_off = -1
                i = skip_block_comment(body, i) - 1
        elif c.isspace():
            if cur:
                items.append(("".join(cur), base_off + cur_off))
                cur = []
                cur_off = -1
        elif c in ",;":
            pass
        else:
            if not cur:
                cur_off = i
            cur.append(c)
        i += 1
    if cur:
        items.append(("".join(cur), base_off + cur_off))
    return items


def label(item):
    stripped = item.strip()
    if not stripped:
        return None
    if stripped.startswith("("):
        m = INSIDE_PAREN_RE.search(stripped)
        return m.group(1) if m else "inline-expr"
    m = ATTR_RE.match(stripped)
    return m.group(0) if m else None


def main():
    rows = []
    seen = set()
    for pattern, source in SOURCE_DIRS.items():
        for path in sorted(glob.glob(os.path.join(pattern, "**", "*.nix"), recursive=True)):
            try:
                text = open(path, encoding="utf-8").read()
            except OSError:
                continue
            rel = os.path.relpath(path, CONFIG_ROOT)
            for m in KEY_RE.finditer(text):
                body, base = extract_list_body(text, m.end())
                if body is None:
                    continue
                for item, off in split_items(body, base):
                    attr = label(item)
                    if not attr:
                        continue
                    line = text.count("\n", 0, off) + 1
                    key = (source, rel, line, attr)
                    if key in seen:
                        continue
                    seen.add(key)
                    rows.append(key)

    rows.sort(key=lambda r: (r[0], r[1], r[2], r[3]))
    for source, rel, line, attr in rows:
        sys.stdout.write(f"{source}\t{rel}\t{line}\t{attr}\n")


if __name__ == "__main__":
    main()