#!/usr/bin/env python3
"""Выводит TSV: source<TAB>relpath<TAB>openLine<TAB>closeLine<TAB>indent<TAB>withPkgs

Где source: "home" или "system". По этим данным панель пакетов знает, в какой
файл и перед какой строкой вставлять новый пакет, чтобы он попал внутрь
списка, а не в произвольное место под курсором.

openLine: строка, где открывается список (1-based).
closeLine: строка с закрывающей "]" (1-based) — вставка идёт перед ней.
indent: отступ строк внутри списка (пробелы).
withPkgs: 1, если список объявлен как `with pkgs; [ ... ]` — тогда пакет
пишется без префикса `pkgs.`.
"""

import os
import re
import sys

CONFIG_ROOT = os.environ.get("NIXOS_CONFIG_ROOT", "/etc/nixos")

TARGETS = [
    ("home", "home-modules/packages.nix", re.compile(r"home\.packages\s*=\s*")),
    ("system", "system-modules/packages.nix", re.compile(r"environment\.systemPackages\s*=\s*")),
]


def skip_string(text, i):
    n = len(text)
    c = text[i]
    if c == '"':
        j = i + 1
        while j < n:
            if text[j] == "\\":
                j += 2
                continue
            if text[j] == '"':
                return j + 1
            j += 1
        return n
    if text.startswith("''", i):
        end = text.find("''", i + 2)
        return end + 2 if end >= 0 else n
    j = text.find("'", i + 1)
    return j + 1 if j >= 0 else n


def skip_trivia(text, i):
    """Пропускает пробелы и комментарии; возвращает позицию или -1."""
    n = len(text)
    while i < n:
        while i < n and text[i].isspace():
            i += 1
        if i >= n:
            return -1
        if text[i] == "#":
            nl = text.find("\n", i)
            i = n if nl < 0 else nl + 1
            continue
        if text[i] == "/" and text[i + 1 : i + 2] == "*":
            end = text.find("*/", i + 2)
            i = n if end < 0 else end + 2
            continue
        break
    return i


def find_list(text, key_re):
    """Возвращает (open_idx, close_idx) первого списка после key_re."""
    n = len(text)
    for m in key_re.finditer(text):
        i = skip_trivia(text, m.end())
        if i < 0:
            continue
        # `with pkgs; [ ... ]` — преамбула пропускается
        while text.startswith("with", i) and (i + 4 >= n or not (text[i + 4].isalnum() or text[i + 4] == "_")):
            j = skip_trivia(text, i + 4)
            if j < 0:
                break
            while j < n and text[j] != ";":
                if text[j] in "\"'":
                    j = skip_string(text, j)
                elif text[j] == "#":
                    nl = text.find("\n", j)
                    j = n if nl < 0 else nl + 1
                elif text[j] == "/" and text[j + 1 : j + 2] == "*":
                    end = text.find("*/", j + 2)
                    j = n if end < 0 else end + 2
                else:
                    j += 1
            if j >= n:
                break
            i = skip_trivia(text, j + 1)
            if i < 0:
                break
        if i < 0 or text[i] != "[":
            continue
        open_idx = i
        depth = 0
        j = i
        while j < n:
            c = text[j]
            if c in "\"'":
                j = skip_string(text, j)
                continue
            if c == "#":
                nl = text.find("\n", j)
                j = n if nl < 0 else nl + 1
                continue
            if c == "/" and text[j + 1 : j + 2] == "*":
                end = text.find("*/", j + 2)
                j = n if end < 0 else end + 2
                continue
            if c == "[":
                depth += 1
            elif c == "]":
                depth -= 1
                if depth == 0:
                    return open_idx, j
            j += 1
    return None, None


def guess_indent(text, open_idx, close_idx):
    """Отступ последней непустой строки перед закрывающей скобкой."""
    end = text.rfind("\n", 0, close_idx)
    body = text[:end if end > 0 else 0].split("\n")
    for line in reversed(body):
        if line.strip():
            return len(line) - len(line.lstrip(" "))
    # fallback: отступ открывающей скобки + 2
    line_start = text.rfind("\n", 0, open_idx) + 1
    base = len(text[line_start:open_idx].replace("[", "").rstrip())
    return max(2, base + 2)


def main():
    for source, rel, key_re in TARGETS:
        path = os.path.join(CONFIG_ROOT, rel)
        try:
            text = open(path, encoding="utf-8").read()
        except OSError:
            continue
        open_idx, close_idx = find_list(text, key_re)
        if open_idx is None:
            continue
        open_line = text.count("\n", 0, open_idx) + 1
        close_line = text.count("\n", 0, close_idx) + 1
        indent = guess_indent(text, open_idx, close_idx)
        with_pkgs = 1 if re.search(r"=\s*with\s+[^;]+;", text[:open_idx]) else 0
        sys.stdout.write(f"{source}\t{rel}\t{open_line}\t{close_line}\t{indent}\t{with_pkgs}\n")


if __name__ == "__main__":
    main()
