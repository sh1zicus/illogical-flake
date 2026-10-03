#!/usr/bin/env python3
"""Автокоммит + push конфига с осмысленным сообщением.

Сообщение строится по conventional commits (как в истории репозитория):
    <type>(<scope>): <subject>

  * scope  — по изменённым файлам: nixosConfig / quickshell / dotfiles /
             nixos / home / flake;
  * type   — feat, если появились новые файлы или добавлений не меньше
             удалений; fix — если правки в основном убирают; chore — для
             flake.lock и служебных файлов;
  * subject — из самих изменений: для packages.nix перечисляются добавленные
             и удалённые пакеты, для .qml — имена файлов, иначе — список
             файлов. Тело — список файлов с +add/-del.

Примеры:
    feat(packages): add gparted, remove zenity
    fix(nixosConfig): update NixosConfigContent, NixosConfigSidebar

Использование:
    nixos-git-autocommit.py [--repo /etc/nixos] [--dry-run] [--no-push]
"""

import argparse
import os
import re
import subprocess
import sys

# Строки, которые встречаются в списках пакетов, но пакетом не являются.
NOT_A_PKGS = {
    "with", "import", "inherit", "pkgs", "lib", "config", "cfg", "true", "false",
    "null", "if", "then", "else", "let", "in", "rec", "}", "{", "]", "[", ";", ",",
}


def out(msg):
    try:
        sys.stdout.write(msg + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        # вызывающий может оборвать вывод (| head) — это не ошибка
        pass


def git(repo, *args, check=True):
    proc = subprocess.run(
        ["git", "-C", repo, *args], capture_output=True, text=True
    )
    if check and proc.returncode != 0:
        err = (proc.stderr or proc.stdout).strip()
        out(f"error: git {' '.join(args[:2])}: {err}")
        sys.exit(2)
    return proc


def scope_of(path):
    if "/quickshell/ii/modules/ii/nixosConfig/" in path:
        return "nixosConfig"
    if "/quickshell/" in path:
        return "quickshell"
    if path.startswith("dotfiles/"):
        return "dotfiles"
    if path.startswith("system-modules/"):
        return "nixos"
    if path.startswith("home-modules/") or path.startswith("home/"):
        return "home"
    if path.startswith("flake."):
        return "flake"
    if path in (".gitignore", "README.md", "install.sh", "update.sh"):
        return "repo"
    return "config"


def commit_type(statuses, adds, dels):
    if all(s == "M" for s in statuses) and set(statuses) and dels > adds:
        return "fix"
    if any(s in ("A", "??") for s in statuses) or adds >= dels:
        return "feat"
    return "fix"


def package_tokens(repo):
    """Добавленные/удалённые пакеты в *packages.nix из staged-диффа."""
    added, removed = [], []
    diff = git(repo, "diff", "--cached", "--unified=0", "--", "*packages.nix").stdout
    for line in diff.split("\n"):
        if not line or line[0] not in "+-":
            continue
        sign, body = line[0], line[1:]
        if body.lstrip().startswith("#"):
            continue
        token = body.strip()
        # только «голое» имя пакета в списке
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.+'-]*", token):
            continue
        if token in NOT_A_PKGS or token.startswith("pkgs."):
            continue
        (added if sign == "+" else removed).append(token)
    return added, removed


def fmt_names(items, limit=4):
    items = list(dict.fromkeys(items))
    if len(items) > limit:
        return ", ".join(items[:limit]) + f" (+{len(items) - limit})"
    return ", ".join(items)


def build_subject(repo, paths, statuses, adds, dels, stat_lines):
    pkg_files = [p for p in paths if p.endswith("packages.nix")]
    if pkg_files:
        added, removed = package_tokens(repo)
        parts = []
        if added:
            parts.append("add " + fmt_names(added))
        if removed:
            parts.append("remove " + fmt_names(removed))
        if parts:
            return ", ".join(parts)
        return "update package lists"

    svc = [p for p in paths if p.endswith("services.nix")]
    if svc:
        return "update services"

    # Клаузы по весу изменения: что переписано сильнее всего — важнее.
    def weight(paths_subset):
        return sum(
            a + d for p, a, d in stat_lines if p in paths_subset
        )

    qml = [p for p in paths if p.endswith(".qml")]
    new_scripts = [
        p for p, s in zip(paths, statuses) if s == "A" and p.endswith(".py")
    ]

    clauses = []
    if qml:
        clauses.append((weight(qml), "update " + fmt_names([os.path.basename(p) for p in qml], 2)))
    if new_scripts:
        noun = "script" if len(new_scripts) == 1 else "scripts"
        clauses.append((weight(new_scripts), f"add {len(new_scripts)} {noun}"))
    if not clauses:
        clauses.append((0, "update " + fmt_names([os.path.basename(p) for p in paths], 3)))

    clauses.sort(key=lambda c: -c[0])
    subject = ""
    for _, text in clauses:
        cand = text if not subject else f"{subject}, {text}"
        if len(cand) > 88 and subject:
            break
        subject = cand
    return subject


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.environ.get("NIXOS_CONFIG_ROOT", "/etc/nixos"))
    ap.add_argument("--dry-run", action="store_true", help="только показать сообщение")
    ap.add_argument("--no-push", action="store_true")
    args = ap.parse_args()

    repo = args.repo
    if not os.path.isdir(os.path.join(repo, ".git")):
        out(f"error: {repo} is not a git repository")
        return 2

    # В dry-run индекс не трогаем: запоминаем, был ли он staged, и если нет —
    # откатываем add, чтобы пользователю не пришлось разбираться с индексом.
    had_staged = bool(git(repo, "diff", "--cached", "--name-only").stdout.strip())
    git(repo, "add", "-A")
    staged = git(repo, "diff", "--cached", "--name-only").stdout.strip()
    if not staged:
        out("Nothing to commit — working tree is clean.")
        return 1

    paths = [p for p in staged.split("\n") if p]
    statuses = []
    for line in git(repo, "diff", "--cached", "--name-status").stdout.split("\n"):
        if not line.strip():
            continue
        fields = line.split("\t")
        statuses.append(fields[0][0])

    adds = dels = 0
    stat_lines = []
    for line in git(repo, "diff", "--cached", "--numstat").stdout.split("\n"):
        if not line.strip():
            continue
        a, d, path = line.split("\t")
        a_i = 0 if a == "-" else int(a)
        d_i = 0 if d == "-" else int(d)
        adds += a_i
        dels += d_i
        stat_lines.append((path, a_i, d_i))

    # scope — самый частый среди изменённых файлов
    scopes = [scope_of(p) for p in paths]
    scope = max(set(scopes), key=scopes.count)
    ctype = commit_type(statuses, adds, dels)
    if all(os.path.basename(p) == "flake.lock" for p in paths):
        ctype = "chore"

    subject = build_subject(repo, paths, statuses, adds, dels, stat_lines)
    head = f"{ctype}({scope}): {subject}"
    body = "\n".join(f"- {p} (+{a} -{d})" for p, a, d in stat_lines)
    if len(paths) > 1:
        body += f"\n\n{len(paths)} files, +{adds} -{dels}"

    out("Proposed commit message:")
    out(head)
    if body:
        out("")
        out(body)
    if args.dry_run:
        if not had_staged:
            git(repo, "reset", "-q")
        return 0

    commit = git(repo, "commit", "-m", head, "-m", body, check=False)
    if commit.returncode != 0:
        msg = (commit.stderr or commit.stdout).strip()
        if "nothing to commit" in msg.lower():
            out("Nothing to commit — working tree is clean.")
            return 1
        out(f"error: commit failed: {msg}")
        return 2

    sha = git(repo, "rev-parse", "--short", "HEAD").stdout.strip()
    out(f"Committed {sha}: {head}")

    if args.no_push:
        out("Push skipped (--no-push).")
        return 0

    if not git(repo, "remote").stdout.strip():
        out("No remote configured — committed, but not pushed.")
        return 0

    push = git(repo, "push", check=False)
    if push.returncode != 0:
        out(f"error: push failed: {(push.stderr or push.stdout).strip()}")
        return 2
    out(f"Pushed {sha} to {git(repo, 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}').stdout.strip() or 'remote'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
