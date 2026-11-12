#!/usr/bin/env python3
"""Backend for the QuickShell PortProton clone.

The clone has two modes:

* ``native`` - the original PortProton CLI is installed.  Prefixes, Wine/Proton
  builds, shortcuts and ``user.conf`` are used directly from the original
  ``~/.Games/PortProton`` installation.
* ``standalone`` - no PortProton command is required.  The same original data
  directory is still used when it exists (so everything can be imported), but
  prefixes and games are managed by this helper using a Wine/Proton binary from
  ``data/dist``, Steam or the system PATH.  If there is no original data at all
  a private directory under ``~/.local/share`` is created.

Commands emit newline-delimited JSON on stdout.  ``progress`` events keep the
QuickShell UI alive while long Wine operations are running.
"""

import argparse
import getpass
import glob
import io
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import time
import zipfile

EXE_RE = re.compile(r"\.exe$", re.I)
BAD_NAME_RE = re.compile(
    r"(unins|uninstall|setup|install|redist|vc_?redist|dotnet|dxsetup|directx|dxwebsetup|"
    r"update|crash|report|register|cleanup|remove|helper|eula|readme|"
    r"^(7z|7zfm|7zg|oalinst|iexplore|wmplayer|notepad|regedit|wineboot|winedbg|winemine)$)",
    re.I,
)
BAD_DIR_RE = re.compile(
    r"(^|/)(windows|windows\.old|winsxs|\$recycle\.bin|temp|tmp|common files|installshield|"
    r"redist|directx|dotnet|microsoft\.net|windows defender|system32|syswow64|"
    r"internet explorer|windows media player|windows nt|windowsapps|uninstall)(/|$)",
    re.I,
)
GOOD_DIR_RE = re.compile(
    r"(program files|program files \(x86\)|games|gog games|steam|epic games|battle\.net|"
    r"ubisoft|origin|electronic arts)",
    re.I,
)
WIN_VER_MAP = {
    "11": "win10",
    "10": "win10",
    "8.1": "win81",
    "8": "win81",
    "7": "win7",
    "xp": "winxp",
}
WINE_METADATA_URLS = [
    "https://git.linux-gaming.ru/Boria138/PortProton-Wine-Metadata/raw/branch/main/wine_metadata.json",
    "https://raw.githubusercontent.com/Boria138/PortProton-Wine-Metadata/main/wine_metadata.json",
]
WINE_METADATA_URL = WINE_METADATA_URLS[0]
WINE_CLOUD_MIRROR = "https://cloud.linux-gaming.ru/portproton"


def emit(data):
    print(json.dumps(data, ensure_ascii=False), flush=True)


def progress(stage, message, percent=None, log_line=None):
    item = {"type": "progress", "stage": stage, "message": message}
    if percent is not None:
        item["percent"] = max(0, min(100, int(percent)))
    if log_line:
        item["log"] = str(log_line).strip()
    emit(item)


def result(data):
    data = dict(data or {})
    data["type"] = "result"
    emit(data)


def fail(message, exit_code=1):
    emit({"type": "error", "error": message, "exitCode": exit_code})


# ---------------------------------------------------------------------------
# Paths and mode detection
# ---------------------------------------------------------------------------


def home_dir():
    return os.path.expanduser("~")


def standalone_root():
    data_home = os.environ.get("XDG_DATA_HOME", os.path.join(home_dir(), ".local", "share"))
    return os.path.join(data_home, "quickshell-portproton")


def config_path():
    return os.path.join(home_dir(), ".config", "PortProton.conf")


def root_from_config():
    try:
        with open(config_path(), "r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                value = line.strip()
                if value:
                    return value
    except OSError:
        pass
    return ""


def looks_like_portproton(path):
    if not path or not os.path.isdir(path):
        return False
    markers = [
        os.path.join(path, "data", "scripts", "start.sh"),
        os.path.join(path, "data", "prefixes"),
        os.path.join(path, "data", "dist"),
        os.path.join(path, "prefixes"),
    ]
    return any(os.path.exists(marker) for marker in markers)


def detect_original_root():
    candidates = []
    env_root = os.environ.get("PORTPROTON_ROOT", "").strip()
    if env_root:
        candidates.append(env_root)
    conf_root = root_from_config()
    if conf_root:
        candidates.append(conf_root)
    candidates.extend([
        os.path.join(home_dir(), ".Games", "PortProton"),
        os.path.join(home_dir(), ".local", "share", "PortProton"),
    ])
    for candidate in candidates:
        candidate = os.path.abspath(os.path.expanduser(candidate))
        if looks_like_portproton(candidate):
            return os.path.realpath(candidate)
    return ""


def has_native_scripts(root):
    start = os.path.join(root, "data", "scripts", "start.sh")
    return os.path.isfile(start) and os.access(start, os.X_OK)


def native_command():
    return shutil.which("portproton") or ""


def resolve_context(root_arg=""):
    original = detect_original_root()
    if root_arg:
        root = os.path.realpath(os.path.abspath(os.path.expanduser(root_arg)))
    else:
        root = original or standalone_root()

    command = native_command()
    mode = "native" if (command and has_native_scripts(root)) else "standalone"
    return {
        "root": root,
        "originalRoot": original,
        "mode": mode,
        "command": command,
    }


def ensure_layout(root):
    for rel in ("data/prefixes", "data/img", "data/tmp", "data/scripts", "data/dist"):
        os.makedirs(os.path.join(root, rel), exist_ok=True)


def prefixes_dir(root):
    data_prefixes = os.path.join(root, "data", "prefixes")
    if os.path.isdir(data_prefixes):
        return data_prefixes
    legacy = os.path.join(root, "prefixes")
    if os.path.isdir(legacy):
        return legacy
    return data_prefixes


def list_prefixes(root):
    directory = prefixes_dir(root)
    try:
        return sorted(
            entry
            for entry in os.listdir(directory)
            if os.path.isdir(os.path.join(directory, entry)) and not entry.startswith(".")
        )
    except OSError:
        return []


def prefix_path(root, name):
    safe = re.sub(r"[^A-Za-z0-9._-]+", "_", str(name or "").strip()).strip("_")
    return os.path.join(prefixes_dir(root), safe)


def user_conf_path(root):
    return os.path.join(root, "data", "user.conf")


def log_path(root):
    return os.path.join(root, "PortProton.log")


def running_path(root):
    return os.path.join(root, "data", "tmp", "quickshell-running.json")


def tail_file(path, lines=4):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            content = handle.read().splitlines()
        return "\n".join(content[-lines:])
    except OSError:
        return ""


def append_log(root, text):
    try:
        os.makedirs(os.path.dirname(log_path(root)), exist_ok=True)
        with open(log_path(root), "a", encoding="utf-8") as handle:
            handle.write(text.rstrip("\n") + "\n")
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Wine/Proton discovery
# ---------------------------------------------------------------------------


def executable(path):
    return bool(path) and os.path.isfile(path) and os.access(path, os.X_OK)


def is_nixos():
    return os.path.exists("/etc/NIXOS")


def needs_steam_run(wine_path):
    return (
        is_nixos()
        and wine_path
        and not wine_path.startswith("/nix/store/")
        and not os.environ.get("QS_PORTPROTON_NO_STEAM_RUN")
    )


def wine_command(wine_path, command):
    if needs_steam_run(wine_path):
        runner = shutil.which("steam-run")
        if runner:
            return [runner] + command
    return command


def wine_in_dist(directory):
    candidates = [
        os.path.join(directory, "files", "bin", "wine"),
        os.path.join(directory, "bin", "wine"),
        os.path.join(directory, "files", "bin-wow64", "wine"),
        os.path.join(directory, "bin-wow64", "wine"),
        os.path.join(directory, "wine"),
    ]
    for candidate in candidates:
        if executable(candidate):
            return os.path.realpath(candidate)
    found = glob.glob(os.path.join(directory, "**", "bin", "wine"), recursive=True)
    for candidate in sorted(found):
        if executable(candidate):
            return os.path.realpath(candidate)
    return ""


def steam_roots():
    roots = [
        os.path.join(home_dir(), ".steam", "steam"),
        os.path.join(home_dir(), ".local", "share", "Steam"),
    ]
    seen = set()
    result = []
    for root in roots:
        real = os.path.realpath(root)
        if real in seen or not os.path.isdir(real):
            continue
        seen.add(real)
        result.append(real)
    return result


def discover_wines(root, original_root=""):
    wines = []
    seen_ids = set()
    seen_paths = set()

    def add(item):
        if not item.get("path") or item["path"] in seen_paths:
            return
        item_id = item["id"]
        suffix = 2
        while item_id in seen_ids:
            item_id = "%s-%d" % (item["id"], suffix)
            suffix += 1
        item["id"] = item_id
        seen_ids.add(item_id)
        seen_paths.add(item["path"])
        wines.append(item)

    dist_dirs = []
    for base in (original_root, root):
        dist = os.path.join(base, "data", "dist") if base else ""
        if dist and os.path.isdir(dist) and dist not in dist_dirs:
            dist_dirs.append(dist)
    for dist in dist_dirs:
        try:
            entries = sorted(os.listdir(dist))
        except OSError:
            continue
        for name in entries:
            directory = os.path.join(dist, name)
            if not os.path.isdir(directory):
                continue
            path = wine_in_dist(directory)
            if not path:
                continue
            add({
                "id": name,
                "name": name,
                "path": path,
                "kind": "proton" if os.path.isfile(os.path.join(directory, "proton")) else "wine",
            })

    for steam in steam_roots():
        tools = os.path.join(steam, "compatibilitytools.d")
        if os.path.isdir(tools):
            try:
                entries = sorted(os.listdir(tools))
            except OSError:
                entries = []
            for name in entries:
                path = wine_in_dist(os.path.join(tools, name))
                if path:
                    add({"id": name, "name": name, "path": path, "kind": "proton"})
        common = os.path.join(steam, "steamapps", "common")
        if os.path.isdir(common):
            try:
                entries = sorted(os.listdir(common))
            except OSError:
                entries = []
            for name in entries:
                if not name.lower().startswith("proton"):
                    continue
                path = wine_in_dist(os.path.join(common, name))
                if path:
                    add({"id": name, "name": name, "path": path, "kind": "proton"})

    system_wine = shutil.which("wine") or shutil.which("wine64")
    if system_wine:
        add({
            "id": "system-wine",
            "name": "Системный Wine",
            "path": os.path.realpath(system_wine),
            "kind": "wine",
        })
    return wines


def wine_metadata_path(root):
    return os.path.join(root, "data", "tmp", "wine_metadata.json")


def dist_directories(root, original_root=""):
    directories = []
    for base in (root, original_root):
        if not base:
            continue
        directory = os.path.realpath(os.path.join(base, "data", "dist"))
        if directory not in directories:
            directories.append(directory)
    return directories


def installed_dist_versions(root, original_root=""):
    installed = set()
    for directory in dist_directories(root, original_root):
        try:
            entries = os.listdir(directory)
        except OSError:
            continue
        for entry in entries:
            if not entry.startswith(".") and os.path.isdir(os.path.join(directory, entry)):
                installed.add(entry)
    return installed


def wine_is_managed(wine, root, original_root=""):
    path = os.path.realpath(wine.get("path", ""))
    for directory in dist_directories(root, original_root):
        if path.startswith(directory + os.sep):
            return True
    return False


def cpu_level():
    flags = set()
    try:
        with open("/proc/cpuinfo", "r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if line.startswith("flags"):
                    flags = set(line.split(":", 1)[1].split())
                    break
    except OSError:
        return 0
    level = 0
    if {"lm", "cmov", "cx8", "fpu", "fxsr", "mmx", "syscall", "sse2"} <= flags:
        level = 1
    if level >= 1 and {"cx16", "lahf", "popcnt", "sse4_1", "sse4_2", "ssse3"} <= flags:
        level = 2
    if level >= 2 and {"avx", "avx2", "bmi1", "bmi2", "f16c", "fma", "abm", "movbe", "xsave"} <= flags:
        level = 3
    if level >= 3 and {"avx512f", "avx512bw", "avx512cd", "avx512dq", "avx512vl"} <= flags:
        level = 4
    return level


def cpu_requirement(name):
    match = re.search(r"v([234])", str(name or ""), re.I)
    return int(match.group(1)) if match else 0


def fetch_wine_metadata(root, refresh=False):
    ensure_layout(root)
    cache = wine_metadata_path(root)
    cached = None
    try:
        with open(cache, "r", encoding="utf-8", errors="replace") as handle:
            loaded = json.load(handle)
        if isinstance(loaded, dict):
            cached = loaded
    except (OSError, ValueError):
        cached = None

    if cached is not None and not refresh:
        return cached, True, ""

    curl = shutil.which("curl")
    if not curl:
        if cached is not None:
            return cached, True, "curl не найден — показан сохранённый список"
        raise RuntimeError("Не найден curl для загрузки списка версий Wine/Proton")

    errors = []
    metadata = None
    for url in WINE_METADATA_URLS:
        try:
            process = subprocess.run(
                [curl, "-fsSL", "--connect-timeout", "12", "--max-time", "45",
                 "-A", "PortProton", url],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=60,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            errors.append(str(exc))
            continue

        if process.returncode != 0:
            detail = process.stderr.decode("utf-8", "replace").strip()
            errors.append(detail or "curl завершился с кодом %d" % process.returncode)
            continue

        try:
            loaded = json.loads(process.stdout.decode("utf-8", "replace"))
        except ValueError as exc:
            errors.append("некорректный JSON: %s" % exc)
            continue
        if not isinstance(loaded, dict):
            errors.append("сервер вернул некорректный список")
            continue
        metadata = loaded
        break

    if metadata is None:
        detail = "; ".join(errors) or "нет доступных источников"
        if cached is not None:
            return cached, True, "Не удалось обновить список: %s" % detail
        raise RuntimeError("Не удалось загрузить список версий Wine/Proton: %s" % detail)

    try:
        os.makedirs(os.path.dirname(cache), exist_ok=True)
        with open(cache, "w", encoding="utf-8") as handle:
            json.dump(metadata, handle, ensure_ascii=False)
    except OSError:
        pass
    return metadata, False, ""


def remote_size(curl, url):
    try:
        process = subprocess.run(
            [curl, "-fsIL", "--connect-timeout", "15", "--max-time", "30",
             "-A", "PortProton", url],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=40,
        )
    except (OSError, subprocess.TimeoutExpired):
        return 0
    sizes = re.findall(r"(?im)^content-length:\s*(\d+)\s*$", process.stdout.decode("utf-8", "replace"))
    try:
        return int(sizes[-1]) if sizes else 0
    except ValueError:
        return 0


def download_file(url, destination, stage, label, start_percent, end_percent):
    curl = shutil.which("curl")
    if not curl:
        return False, "curl не найден"
    filename = os.path.basename(url.split("?", 1)[0].split("#", 1)[0])
    candidates = [url]
    if filename:
        mirror = WINE_CLOUD_MIRROR.rstrip("/") + "/" + filename
        if mirror != url:
            candidates.append(mirror)

    errors = []
    for index, candidate in enumerate(candidates):
        total = remote_size(curl, candidate)
        part = destination + ".part"
        try:
            os.remove(part)
        except OSError:
            pass
        if index > 0:
            progress(stage, "%s — пробую зеркало" % label, start_percent)
        try:
            process = subprocess.Popen(
                [curl, "-fL", "--retry", "2", "--retry-delay", "2",
                 "--connect-timeout", "20", "--max-time", "1800",
                 "-A", "PortProton", "-o", part, candidate],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                cwd=home_dir(),
            )
        except OSError as exc:
            errors.append(str(exc))
            continue

        last_report = -10
        while process.poll() is None:
            now = time.time()
            if now - last_report >= 1:
                last_report = now
                try:
                    size = os.path.getsize(part)
                except OSError:
                    size = 0
                if total > 0:
                    percent = start_percent + (end_percent - start_percent) * min(1.0, size / float(total))
                    progress(stage, "%s — %d%%" % (label, int(size * 100 / total)), percent)
                else:
                    progress(stage, "%s — %d МБ" % (label, size // 1048576), None)
            time.sleep(0.5)

        code = process.wait()
        if code == 0 and os.path.isfile(part) and os.path.getsize(part) > 0:
            os.replace(part, destination)
            return True, ""
        errors.append("curl завершился с кодом %d" % code)
        try:
            os.remove(part)
        except OSError:
            pass
    return False, "; ".join(errors) or "не удалось скачать файл"


def extract_archive(archive, destination):
    lower = archive.lower()
    if lower.endswith((".tar.xz", ".txz")):
        command = ["tar", "-xJf", archive, "-C", destination]
    elif lower.endswith((".tar.gz", ".tgz")):
        command = ["tar", "-xzf", archive, "-C", destination]
    elif lower.endswith((".tar.zst", ".tzst")):
        command = ["tar", "--zstd", "-xf", archive, "-C", destination]
    elif lower.endswith(".tar"):
        command = ["tar", "-xf", archive, "-C", destination]
    elif lower.endswith(".zip"):
        try:
            with zipfile.ZipFile(archive) as handle:
                handle.extractall(destination)
            return 0
        except (OSError, zipfile.BadZipFile):
            return 1
    elif lower.endswith(".7z"):
        seven = shutil.which("7z") or shutil.which("7za")
        if not seven:
            return 127
        command = [seven, "x", "-y", "-o" + destination, archive]
    else:
        command = ["tar", "-xf", archive, "-C", destination]

    try:
        return subprocess.run(
            command,
            cwd=home_dir(),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=900,
        ).returncode
    except (OSError, subprocess.TimeoutExpired):
        return 1


def wine_catalog(args):
    context = resolve_context(args.root)
    root = context["root"]
    ensure_layout(root)
    try:
        metadata, cached, warning = fetch_wine_metadata(root, bool(args.refresh))
    except RuntimeError as exc:
        fail(str(exc))
        return

    keys = list(metadata.keys())
    if "proton_lg" in keys:
        keys.remove("proton_lg")
        keys.insert(0, "proton_lg")
    installed = installed_dist_versions(root, context["originalRoot"])
    level = cpu_level()
    categories = []
    for key in keys:
        entries = metadata.get(key)
        if not isinstance(entries, list):
            continue
        items = []
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            name = str(entry.get("name") or "").strip()
            url = str(entry.get("url") or "").strip()
            if not name or not url:
                continue
            if "cachyos" in str(key).lower():
                required = cpu_requirement(name)
                compatible = not required or not level or level >= required
            else:
                compatible = True
            items.append({
                "name": name,
                "url": url,
                "size": str(entry.get("size_human") or "").strip(),
                "installed": name in installed,
                "compatible": compatible,
            })
        if items:
            categories.append({
                "id": key,
                "label": str(key).upper().replace("_", "-"),
                "items": items,
            })

    result({
        "categories": categories,
        "installed": sorted(installed),
        "stale": bool(cached),
        "warning": warning,
        "cpuLevel": level,
        "metadataUrl": WINE_METADATA_URL,
        "metadataUrls": WINE_METADATA_URLS,
    })


def wine_install(args):
    name = str(args.wine or args.name or "").strip()
    if not name or os.path.basename(name) != name or name in (".", ".."):
        fail("Укажи корректное имя версии Wine/Proton")
        return
    context = resolve_context(args.root)
    root = context["root"]
    ensure_layout(root)
    url = str(args.url or "").strip()
    if not url:
        try:
            metadata, _, _ = fetch_wine_metadata(root, False)
        except RuntimeError as exc:
            fail(str(exc))
            return
        for entries in metadata.values():
            if not isinstance(entries, list):
                continue
            for entry in entries:
                if not isinstance(entry, dict):
                    continue
                if str(entry.get("name") or "").strip().lower() == name.lower():
                    url = str(entry.get("url") or "").strip()
                    break
            if url:
                break
    if not url:
        fail("Версия %s не найдена в списке доступных" % name)
        return

    dist = os.path.join(root, "data", "dist")
    target = os.path.join(dist, name)
    if os.path.exists(target):
        fail("Версия %s уже установлена" % name)
        return
    for record in current_running(root):
        if record.get("wine") == name:
            fail("Нельзя установить поверх %s: версия используется запущенной игрой" % name)
            return

    filename = os.path.basename(url.split("?", 1)[0].split("#", 1)[0]) or (name + ".tar.xz")
    archive = os.path.join(root, "data", "tmp", filename)
    progress("download", "Скачиваю %s…" % name, 1)
    ok, error = download_file(url, archive, "download", "Скачивание %s" % name, 2, 80)
    if not ok:
        fail("Не удалось скачать %s: %s" % (name, error))
        return

    progress("unpack", "Распаковываю %s…" % name, 82)
    extract_dir = tempfile.mkdtemp(prefix=".qs-wine-", dir=os.path.join(root, "data", "tmp"))
    try:
        code = extract_archive(archive, extract_dir)
        if code != 0:
            fail("Не удалось распаковать %s (код %d)" % (filename, code))
            return
        entries = [entry for entry in os.listdir(extract_dir) if not entry.startswith(".")]
        if not entries:
            fail("Архив %s пуст" % filename)
            return
        if len(entries) == 1 and os.path.isdir(os.path.join(extract_dir, entries[0])):
            shutil.move(os.path.join(extract_dir, entries[0]), target)
        else:
            os.makedirs(target, exist_ok=True)
            for entry in entries:
                shutil.move(os.path.join(extract_dir, entry), os.path.join(target, entry))
        wine_path = wine_in_dist(target)
        if not wine_path:
            shutil.rmtree(target, ignore_errors=True)
            fail("В архиве %s не найден исполняемый файл Wine" % filename)
            return
        append_log(root, "Установлен Wine/Proton %s из %s" % (name, url))
        progress("done", "Wine/Proton %s установлен" % name, 100)
        result({"installed": name, "path": target, "wine": wine_path})
    finally:
        shutil.rmtree(extract_dir, ignore_errors=True)
        try:
            os.remove(archive)
        except OSError:
            pass


def wine_remove(args):
    name = str(args.wine or args.name or "").strip()
    if not name or os.path.basename(name) != name or name in (".", ".."):
        fail("Укажи корректное имя версии Wine/Proton")
        return
    context = resolve_context(args.root)
    root = context["root"]
    for record in current_running(root):
        if record.get("wine") == name:
            fail("Нельзя удалить %s: версия используется запущенной игрой" % name)
            return
    target = ""
    for directory in dist_directories(root, context["originalRoot"]):
        candidate = os.path.join(directory, name)
        if os.path.isdir(candidate):
            target = candidate
            break
    if not target:
        fail("Версия %s не найдена в data/dist" % name)
        return
    progress("remove", "Удаляю %s…" % name, 10)
    try:
        shutil.rmtree(target)
    except OSError as exc:
        fail("Не удалось удалить %s: %s" % (name, exc))
        return
    append_log(root, "Удалён Wine/Proton %s (%s)" % (name, target))
    progress("done", "Wine/Proton %s удалён" % name, 100)
    result({"removed": name, "path": target})


def marker_path(root, name):
    return os.path.join(prefix_path(root, name), ".quickshell-wine")


def remember_wine(root, name, wine_id):
    try:
        os.makedirs(prefix_path(root, name), exist_ok=True)
        with open(marker_path(root, name), "w", encoding="utf-8") as handle:
            handle.write(str(wine_id or ""))
    except OSError:
        pass


def remembered_wine(root, name):
    try:
        with open(marker_path(root, name), "r", encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def resolve_wine(root, wine_id="", original_root=""):
    wines = discover_wines(root, original_root)
    if not wines:
        return None
    wanted = str(wine_id or "").strip()
    if wanted:
        for wine in wines:
            if wanted in (wine["id"], wine["name"], wine["path"]):
                return wine
    if is_nixos():
        for wine in wines:
            if wine["id"] == "system-wine":
                return wine
    for wine in wines:
        if wine["kind"] == "wine":
            return wine
    return wines[0]


def prefix_boot_exe(wine_path):
    directory = os.path.dirname(wine_path)
    for name in ("wineboot", "wineboot.exe"):
        candidate = os.path.join(directory, name)
        if executable(candidate):
            return candidate
    return shutil.which("wineboot") or ""


def prefix_server_exe(wine_path):
    directory = os.path.dirname(wine_path)
    for name in ("wineserver", "wineserver.exe"):
        candidate = os.path.join(directory, name)
        if executable(candidate):
            return candidate
    return shutil.which("wineserver") or ""


def winetricks_exe():
    return shutil.which("winetricks") or ""


def gamemoderun_exe():
    return shutil.which("gamemoderun") or ""


def mangohud_exe():
    return shutil.which("mangohud") or ""


def parse_env_items(items):
    env = {}
    for item in items or []:
        if "=" not in item:
            continue
        key, value = item.split("=", 1)
        if key:
            env[key] = value
    return env


def wine_env(root, name, wine, extra_env=None):
    env = os.environ.copy()
    env["WINEPREFIX"] = prefix_path(root, name)
    env.pop("WINEDEBUG", None)
    env.setdefault("WINEDLLOVERRIDES", "mscoree,mshtml=")
    env.setdefault("WINEDLLPATH", "")
    env.setdefault("MESA_GL_VERSION_OVERRIDE", "4.6COMPAT")
    values = extra_env or {}
    for key in (
        "WINEDLLOVERRIDES",
        "LANG",
        "LC_ALL",
        "PW_MESA_GL_VERSION_OVERRIDE",
        "PW_VKD3D_FEATURE_LEVEL",
        "PW_MESA_VK_WSI_PRESENT_MODE",
        "PW_WINE_CPU_TOPOLOGY",
        "PW_USE_ESYNC",
        "PW_USE_FSYNC",
        "PW_USE_NTSYNC",
        "DXVK_HUD",
        "MANGOHUD",
        "MANGOHUD_CONFIG",
    ):
        if key in values and str(values[key]).strip():
            env[key] = str(values[key])
    locale = values.get("PW_LOCALE_SELECT", "").strip()
    if locale:
        env["LANG"] = locale
        env["LC_ALL"] = locale
    if values.get("PW_USE_GAMEMODE") in ("1", "true", "True"):
        exe = gamemoderun_exe()
        if exe:
            env["QS_GAMEMODERUN"] = exe
    if values.get("PW_MANGOHUD") in ("1", "true", "True"):
        exe = mangohud_exe()
        if exe:
            env["QS_MANGOHUD"] = exe
    xdg_runtime = env.get("XDG_RUNTIME_DIR", "")
    if not xdg_runtime:
        fallback = "/run/user/%d" % os.getuid()
        if os.path.isdir(fallback):
            env["XDG_RUNTIME_DIR"] = fallback
    if needs_steam_run(wine["path"]):
        wine_dir = os.path.dirname(wine["path"])
        env["PATH"] = wine_dir + os.pathsep + env.get("PATH", "")
    return env


def run_process(command, env, cwd, log_file, timeout, stage, message, start_percent=None, end_percent=None):
    os.makedirs(os.path.dirname(log_file), exist_ok=True)
    started = time.time()
    last_report = -10
    try:
        with open(log_file, "ab") as handle:
            handle.write(("\n=== %s ===\n%s\n" % (time.strftime("%F %T"), shlex.join(command))).encode())
            handle.flush()
            process = subprocess.Popen(
                command,
                cwd=cwd or None,
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=handle,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
    except OSError as exc:
        append_log(os.environ.get("QS_PORTPROTON_ROOT", home_dir()), "Cannot run %s: %s" % (command[0], exc))
        progress(stage, "Не удалось запустить %s: %s" % (command[0], exc), None)
        return 127

    last_tail = ""
    while process.poll() is None:
        elapsed = time.time() - started
        if elapsed - last_report >= 5:
            last_report = elapsed
            percent = None
            if start_percent is not None and end_percent is not None:
                percent = start_percent + min(end_percent - start_percent, elapsed / 8.0)
            last_tail = tail_file(log_file, 3)
            progress(stage, "%s — %d с" % (message, int(elapsed)), percent, last_tail)
        if timeout and elapsed > timeout:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except OSError:
                pass
            time.sleep(2)
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except OSError:
                pass
            break
        time.sleep(0.5)

    code = process.wait()
    progress(stage, "%s — завершено (код %d)" % (message, code), end_percent, tail_file(log_file, 3))
    return code


def run_quiet(command, env, cwd=None, timeout=30):
    try:
        return subprocess.run(
            command,
            cwd=cwd or home_dir(),
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
        ).returncode
    except (OSError, subprocess.TimeoutExpired):
        return 1


# ---------------------------------------------------------------------------
# Prefix creation / installation / launch
# ---------------------------------------------------------------------------


def windows_version_arg(value):
    raw = str(value or "").strip()
    return WIN_VER_MAP.get(raw.lower().replace("windows", "").strip(), "")


def apply_windows_version(wine, env, root, name, version):
    win_ver = windows_version_arg(version)
    if not win_ver:
        return
    run_quiet(
        wine_command(wine["path"], [wine["path"], "reg", "add", r"HKCU\Software\Wine", "/v", "Version", "/d", win_ver, "/f"]),
        env,
    )
    append_log(root, "Windows version for %s: %s" % (name, win_ver))


def ensure_prefix(root, name, wine, windows_ver="", dll_install="", dll_overrides="", extra_env=None):
    prefix = prefix_path(root, name)
    os.makedirs(prefix, exist_ok=True)
    env = wine_env(root, name, wine, extra_env)
    if str(dll_overrides or "").strip():
        env["WINEDLLOVERRIDES"] = str(dll_overrides).strip()
    fresh = not os.path.isfile(os.path.join(prefix, "system.reg"))
    if fresh:
        progress("prefix", "Создаю префикс %s…" % name, 8)
        boot = prefix_boot_exe(wine["path"])
        if boot:
            command = [boot, "-u"]
        else:
            command = [wine["path"], "wineboot", "-u"]
        code = run_process(
            wine_command(wine["path"], command), env, home_dir(), os.path.join(prefix, ".quickshell-create.log"),
            timeout=600, stage="prefix", message="Инициализирую префикс %s" % name,
            start_percent=8, end_percent=18,
        )
        if code != 0:
            append_log(root, "wineboot returned %d for %s" % (code, name))
        server = prefix_server_exe(wine["path"])
        if server:
            run_quiet(wine_command(wine["path"], [server, "-w"]), env, timeout=20)
    else:
        progress("prefix", "Префикс %s уже существует" % name, 12)

    remember_wine(root, name, wine["id"])
    apply_windows_version(wine["path"], env, root, name, windows_ver)

    libraries = [token for token in str(dll_install or "").replace(",", " ").split() if token]
    winetricks = winetricks_exe()
    if libraries and winetricks:
        progress("winetricks", "Устанавливаю библиотеки: %s" % " ".join(libraries), 22)
        code = run_process(
            wine_command(wine["path"], [winetricks, "-q"] + libraries), env, home_dir(),
            os.path.join(prefix, ".quickshell-winetricks.log"),
            timeout=3600, stage="winetricks",
            message="winetricks (%s)" % " ".join(libraries),
            start_percent=22, end_percent=45,
        )
        if code != 0:
            append_log(root, "winetricks returned %d for %s" % (code, name))
    elif libraries:
        append_log(root, "winetricks is not installed, skipped: %s" % " ".join(libraries))
    return fresh


def installer_command(wine_path, installer):
    extension = os.path.splitext(installer)[1].lower()
    if extension == ".msi":
        return [wine_path, "msiexec", "/i", installer]
    if extension == ".bat":
        return [wine_path, "cmd", "/c", installer]
    if extension == ".lnk":
        return [wine_path, "start", "/unix", installer]
    return [wine_path, installer]


def do_standalone_install(root, name, installer, wine_id, windows_ver, locale, sound_driver,
                          dll_install, dll_overrides, launch_args, display_name="", original_root=""):
    ensure_layout(root)
    wine = resolve_wine(root, wine_id, original_root)
    if not wine:
        fail("Не найден Wine/Proton. Установи wine (или PortProton) и повтори.")
        return
    root_absolute = os.path.abspath(root)
    extra_env = {
        "PW_LOCALE_SELECT": locale or "",
        "PW_SOUND_DRIVER_USE": sound_driver or "",
    }
    ensure_prefix(
        root_absolute, name, wine, windows_ver,
        dll_install=dll_install, dll_overrides=dll_overrides, extra_env=extra_env,
    )
    env = wine_env(root_absolute, name, wine, extra_env)
    if str(dll_overrides or "").strip():
        env["WINEDLLOVERRIDES"] = str(dll_overrides).strip()
    progress("installer", "Запущен установщик. Заверши установку в окне Wine.", 50)
    code = run_process(
        wine_command(wine["path"], installer_command(wine["path"], installer)), env, home_dir(),
        log_path(root_absolute), timeout=7200, stage="installer",
        message="Установщик %s" % os.path.basename(installer),
        start_percent=50, end_percent=90,
    )
    server = prefix_server_exe(wine["path"])
    if server:
        run_quiet(wine_command(wine["path"], [server, "-w"]), env, timeout=60)
    progress("scan", "Ищу исполняемый файл игры…", 94)
    scan = scan_prefix(root_absolute, prefix_path(root_absolute, name), display_name or name,
                       mode="standalone", wine=wine["id"])
    scan["exitCode"] = max(0, int(code))
    scan["wine"] = wine["id"]
    return scan


def do_native_install(context, name, installer, wine_id, windows_ver, locale, sound_driver,
                      dll_install, dll_overrides, launch_args, display_name=""):
    root = context["root"]
    env = os.environ.copy()
    env["PW_PREFIX_NAME"] = name
    if wine_id:
        env["PW_WINE_USE"] = wine_id
    if windows_ver:
        env["PW_WINDOWS_VER"] = str(windows_ver)
    if locale:
        env["PW_LOCALE_SELECT"] = locale
    if sound_driver:
        env["PW_SOUND_DRIVER_USE"] = sound_driver
    if dll_install:
        env["PW_DLL_INSTALL"] = dll_install
    if dll_overrides:
        env["WINEDLLOVERRIDES"] = dll_overrides
    if launch_args:
        env["LAUNCH_PARAMETERS"] = launch_args
    env["SKIP_CHECK_UPDATES"] = "1"

    progress("prepare", "Проверяю префикс %s…" % name, 8)
    command = [context["command"], "cli", "--launch", installer]
    progress("installer", "Запущен установщик PortProton. Заверши установку в его окне.", 50)
    code = run_process(
        command, env, root, log_path(root), timeout=7200, stage="installer",
        message="Установщик %s" % os.path.basename(installer),
        start_percent=50, end_percent=90,
    )
    progress("scan", "Ищу исполняемый файл игры…", 94)
    scan = scan_prefix(root, prefix_path(root, name), display_name or name, mode="native", wine=wine_id)
    scan["exitCode"] = max(0, int(code))
    scan["wine"] = wine_id
    return scan


def install_game(args):
    context = resolve_context(args.root)
    root = context["root"]
    installer = os.path.abspath(os.path.expanduser(args.installer)) if args.installer else ""
    if not installer or not os.path.isfile(installer):
        fail("Установщик не найден: %s" % (args.installer or "(пусто)"))
        return
    if not os.path.isdir(root):
        ensure_layout(root)
    display_name = (args.name or "").strip() or "GAME"
    name = re.sub(r"[^A-Za-z0-9._-]+", "_", (args.prefix or args.name or "GAME").strip()).strip("_") or "GAME"
    progress("prepare", "Подготовка установки %s…" % display_name, 3)
    try:
        if context["mode"] == "native":
            scan = do_native_install(
                context, name, installer, args.wine, args.windows_ver, args.locale,
                args.sound_driver, args.dll_install, args.dll_overrides, args.args,
                display_name,
            )
        else:
            scan = do_standalone_install(
                root, name, installer, args.wine, args.windows_ver, args.locale,
                args.sound_driver, args.dll_install, args.dll_overrides, args.args,
                display_name, context["originalRoot"],
            )
    except Exception as exc:  # keep the UI usable on unexpected Wine failures
        append_log(root, "install exception: %s" % exc)
        fail("Ошибка установки: %s" % exc)
        return
    if scan is None:
        return
    scan["name"] = display_name
    scan["prefix"] = os.path.basename(prefix_path(root, name))
    result(scan)


def launch_game(args):
    context = resolve_context(args.root)
    root = context["root"]
    if not os.path.isdir(root):
        ensure_layout(root)
    name = re.sub(r"[^A-Za-z0-9._-]+", "_", (args.prefix or "DEFAULT").strip()).strip("_") or "DEFAULT"
    exe = os.path.abspath(os.path.expanduser(args.exe)) if args.exe else ""
    if not exe or not os.path.isfile(exe):
        fail("Исполняемый файл не найден: %s" % (args.exe or "(пусто)"))
        return
    extra_env = parse_env_items(args.env)
    extra_env.setdefault("PW_PREFIX_NAME", name)
    if args.wine:
        extra_env.setdefault("PW_WINE_USE", args.wine)
    if args.args:
        extra_env.setdefault("LAUNCH_PARAMETERS", args.args)

    wine = resolve_wine(root, args.wine or remembered_wine(root, name), context["originalRoot"])
    if not wine:
        fail("Не найден Wine/Proton для запуска.")
        return

    env = wine_env(root, name, wine, extra_env)
    arguments = shlex.split(args.args or extra_env.get("LAUNCH_PARAMETERS", ""))
    if context["mode"] == "native":
        command = [context["command"], "cli", "--launch", exe]
        env = os.environ.copy()
        for key, value in extra_env.items():
            if value is not None and str(value).strip():
                env[key] = str(value)
        env["PW_PREFIX_NAME"] = name
        env["SKIP_CHECK_UPDATES"] = "1"
        if launch_args := arguments:
            env["LAUNCH_PARAMETERS"] = shlex.join(launch_args)
    else:
        prefix = os.path.dirname(marker_path(root, name))
        env["WINEPREFIX"] = prefix
        command = wine_command(wine["path"], [wine["path"], exe] + arguments)
        gamemoderun = env.pop("QS_GAMEMODERUN", "")
        mangohud = env.pop("QS_MANGOHUD", "")
        if gamemoderun:
            command = [gamemoderun] + command
            env["GAMEMODERUNEXEC"] = gamemoderun
        if mangohud:
            command = [mangohud] + command

    os.makedirs(os.path.dirname(log_path(root)), exist_ok=True)
    try:
        log = open(log_path(root), "ab")
        log.write(("\n=== launch %s ===\n%s\n" % (time.strftime("%F %T"), shlex.join(command))).encode())
        log.flush()
        process = subprocess.Popen(
            command,
            cwd=home_dir(),
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        log.close()
    except OSError as exc:
        fail("Не удалось запустить игру: %s" % exc)
        return

    record = {
        "pid": process.pid,
        "exe": exe,
        "prefix": name,
        "name": args.name or os.path.basename(exe),
        "wine": wine["id"],
        "mode": context["mode"],
        "started": int(time.time()),
    }
    records = load_running(root)
    records.append(record)
    save_running(root, records)
    result({"running": record})


def load_running(root):
    path = running_path(root)
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        return data if isinstance(data, list) else []
    except (OSError, ValueError):
        return []


def save_running(root, records):
    path = running_path(root)
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(records, handle, ensure_ascii=False)
    except OSError:
        pass


def pid_alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError, TypeError):
        return False


def process_group(pid):
    try:
        return os.getpgid(int(pid))
    except (OSError, ValueError, TypeError):
        return 0


def process_command(pid):
    try:
        with open("/proc/%d/cmdline" % int(pid), "rb") as handle:
            return handle.read().replace(b"\x00", b" ").decode("utf-8", "replace").strip()
    except OSError:
        return ""


def native_sessions(root):
    command = shutil.which("pgrep")
    if not command:
        return []
    try:
        probe = subprocess.run(
            [command, "-af", os.path.join(root, "data", "scripts", "start.sh")],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    sessions = []
    for line in probe.stdout.decode("utf-8", "replace").splitlines():
        parts = line.split(None, 1)
        if not parts:
            continue
        try:
            pid = int(parts[0])
        except ValueError:
            continue
        if pid == os.getpid():
            continue
        sessions.append({
            "pid": pid,
            "exe": "",
            "prefix": "",
            "name": "PortProton",
            "wine": "",
            "mode": "native",
            "started": 0,
        })
    return sessions


def current_running(root):
    records = load_running(root)
    alive = []
    for record in records:
        pid = record.get("pid")
        if pid and pid_alive(pid):
            alive.append(record)
    if len(alive) != len(records):
        save_running(root, alive)
    seen = set()
    groups = set()
    for record in alive:
        pid = record.get("pid")
        try:
            seen.add(int(pid))
        except (TypeError, ValueError):
            pass
        group = process_group(pid)
        if group:
            groups.add(group)
    for session in native_sessions(root):
        pid = int(session["pid"])
        group = process_group(pid)
        if pid in seen or (group and group in groups):
            continue
        alive.append(session)
        seen.add(pid)
        if group:
            groups.add(group)
    return alive


def stop_game(args):
    root = resolve_context(args.root)["root"]
    records = current_running(root)
    stopped = []
    for record in records:
        exe = record.get("exe", "")
        matches = args.all
        if not matches and args.pid:
            matches = int(record.get("pid", 0)) == args.pid
        elif not matches and args.exe:
            matches = bool(exe) and os.path.realpath(exe) == os.path.realpath(args.exe)
        elif not matches:
            matches = True
        if matches:
            try:
                os.killpg(int(record["pid"]), signal.SIGTERM)
            except OSError:
                try:
                    os.kill(int(record["pid"]), signal.SIGTERM)
                except OSError:
                    pass
            stopped.append(record)
    save_running(root, [record for record in records if record not in stopped])
    if args.all:
        for prefix in list_prefixes(root):
            wine = resolve_wine(root, remembered_wine(root, prefix))
            if wine:
                server = prefix_server_exe(wine["path"])
                if server:
                    run_quiet(
                        wine_command(wine["path"], [server, "-k"]),
                        wine_env(root, prefix, wine),
                        timeout=10,
                    )
    result({"stopped": stopped})


# ---------------------------------------------------------------------------
# Prefix tools
# ---------------------------------------------------------------------------


def create_prefix(args):
    context = resolve_context(args.root)
    root = context["root"]
    ensure_layout(root)
    name = re.sub(r"[^A-Za-z0-9._-]+", "_", (args.prefix or "DEFAULT").strip()).strip("_") or "DEFAULT"
    wine = resolve_wine(root, args.wine or remembered_wine(root, name), context["originalRoot"])
    if not wine:
        fail("Не найден Wine/Proton. Установи wine или PortProton.")
        return
    try:
        ensure_prefix(
            root, name, wine, args.windows_ver,
            dll_install=args.dll_install, dll_overrides=args.dll_overrides, extra_env={},
        )
    except Exception as exc:
        fail("Не удалось создать префикс: %s" % exc)
        return
    result({"prefix": name, "path": prefix_path(root, name), "wine": wine["id"]})


def open_tool(args):
    context = resolve_context(args.root)
    root = context["root"]
    name = re.sub(r"[^A-Za-z0-9._-]+", "_", (args.prefix or "DEFAULT").strip()).strip("_") or "DEFAULT"
    wine = resolve_wine(root, args.wine or remembered_wine(root, name), context["originalRoot"])
    if not wine:
        fail("Не найден Wine/Proton.")
        return
    if not os.path.isfile(os.path.join(prefix_path(root, name), "system.reg")):
        ensure_prefix(root, name, wine)
    env = wine_env(root, name, wine)
    tool = args.tool
    if tool == "winetricks":
        command = [winetricks_exe()]
    elif tool == "cmd":
        command = [wine["path"], "cmd"]
    else:
        command = [wine["path"], tool]
    if not command[0]:
        fail("Инструмент %s не найден." % tool)
        return
    command = wine_command(wine["path"], command)
    try:
        subprocess.Popen(
            command,
            cwd=home_dir(),
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError as exc:
        fail("Не удалось открыть %s: %s" % (tool, exc))
        return
    result({"prefix": name, "tool": tool})


def clear_prefix(args):
    root = resolve_context(args.root)["root"]
    name = re.sub(r"[^A-Za-z0-9._-]+", "_", (args.prefix or "").strip()).strip("_")
    path = prefix_path(root, name)
    if not name or not os.path.isdir(path):
        fail("Префикс не найден: %s" % (args.prefix or ""))
        return
    try:
        shutil.rmtree(path)
    except OSError as exc:
        fail("Не удалось очистить префикс: %s" % exc)
        return
    result({"prefix": name, "cleared": True})


def backup_prefix(args):
    root = resolve_context(args.root)["root"]
    name = re.sub(r"[^A-Za-z0-9._-]+", "_", (args.prefix or "").strip()).strip("_")
    source = prefix_path(root, name)
    if not name or not os.path.isdir(source):
        fail("Префикс не найден: %s" % (args.prefix or ""))
        return
    destination = os.path.abspath(os.path.expanduser(args.dest or home_dir()))
    os.makedirs(destination, exist_ok=True)
    archive = os.path.join(destination, "%s-%s.ppack" % (name, time.strftime("%Y%m%d-%H%M%S")))
    progress("backup", "Архивирую префикс %s…" % name, 10)
    try:
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(source, arcname=name)
    except OSError as exc:
        fail("Не удалось создать бэкап: %s" % exc)
        return
    result({"prefix": name, "archive": archive})


def restore_prefix(args):
    root = resolve_context(args.root)["root"]
    source = os.path.abspath(os.path.expanduser(args.pack or ""))
    if not source or not os.path.isfile(source):
        fail("Архив не найден: %s" % (args.pack or ""))
        return
    destination = prefixes_dir(root)
    os.makedirs(destination, exist_ok=True)
    progress("restore", "Распаковываю %s…" % os.path.basename(source), 20)
    try:
        if tarfile.is_tarfile(source):
            with tarfile.open(source, "r:*") as tar:
                tar.extractall(destination)
        elif zipfile.is_zipfile(source):
            with zipfile.ZipFile(source) as archive:
                archive.extractall(destination)
        else:
            fail("Формат архива не поддерживается: %s" % os.path.basename(source))
            return
    except (OSError, tarfile.TarError, zipfile.BadZipFile) as exc:
        fail("Не удалось восстановить префикс: %s" % exc)
        return
    result({"restored": source, "prefixes": list_prefixes(root)})


# ---------------------------------------------------------------------------
# Original scan/import helpers (shortcuts, icons, executable detection)
# ---------------------------------------------------------------------------


def find_plugins(root):
    candidates = sorted(glob.glob(os.path.join(root, "data", "tmp", "plugins*")))
    return candidates[-1] if candidates else ""


def resolve_ci(path):
    if not path:
        return None
    if os.path.exists(path):
        return os.path.realpath(path)
    current = "/" if path.startswith("/") else ""
    for part in path.split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            current = os.path.dirname(current)
            continue
        try:
            entries = os.listdir(current or ".")
        except OSError:
            return None
        match = next((entry for entry in entries if entry.lower() == part.lower()), None)
        if not match:
            return None
        current = os.path.join(current, match)
    return os.path.realpath(current) if os.path.exists(current) else None


def windows_to_linux(prefix, winpath):
    if not winpath:
        return None
    path = str(winpath).strip().strip('"').strip("'")
    path = path.replace("\\\\", "\\")
    replacements = {
        "%ProgramFiles(x86)%": r"C:\Program Files (x86)",
        "%ProgramFiles%": r"C:\Program Files",
        "%ProgramW6432%": r"C:\Program Files",
        "%SystemRoot%": r"C:\windows",
        "%windir%": r"C:\windows",
        "%USERPROFILE%": r"C:\users\%s" % os.environ.get("USER", "user"),
        "%APPDATA%": r"C:\users\%s\AppData\Roaming" % os.environ.get("USER", "user"),
        "%LOCALAPPDATA%": r"C:\users\%s\AppData\Local" % os.environ.get("USER", "user"),
    }
    for key, value in replacements.items():
        path = re.sub(re.escape(key), lambda _m, v=value: v, path, flags=re.I)
    path = path.replace("\\", "/")
    drive_match = re.match(r"^([A-Za-z]):/(.*)$", path)
    if drive_match:
        drive = drive_match.group(1).lower()
        rest = drive_match.group(2)
        if drive == "c":
            base = os.path.join(prefix, "drive_c")
        else:
            link = os.path.join(prefix, "dosdevices", drive + ":")
            base = os.path.realpath(link) if os.path.islink(link) else os.path.join(prefix, "drive_" + drive)
        candidate = os.path.join(base, rest)
    else:
        candidate = os.path.join(prefix, "drive_c", path.lstrip("/"))
    return resolve_ci(candidate)


def parse_lnk(root, lnk):
    plugins = find_plugins(root)
    if plugins:
        exiftool = os.path.join(plugins, "portable", "bin", "exiftool")
        if os.path.exists(exiftool):
            env = os.environ.copy()
            env["PERL5LIB"] = os.path.join(plugins, "portable", "lib", "perl5")
            try:
                out = subprocess.check_output(
                    ["perl", exiftool, "-s3", "-LocalBasePath", lnk],
                    env=env,
                    stderr=subprocess.DEVNULL,
                    timeout=6,
                ).decode("utf-8", "replace").strip()
                if out:
                    return out
            except Exception:
                pass
    try:
        data = open(lnk, "rb").read()
        for match in re.finditer(rb"[A-Za-z]:\\\\[^\x00\r\n]{3,260}?\.exe", data, re.I):
            return match.group(0).decode("latin1", "replace")
        text = data.decode("utf-16le", "ignore")
        for match in re.finditer(r"[A-Za-z]:\\\\[^\x00\r\n]{3,260}?\.exe", text, re.I):
            return match.group(0)
    except Exception:
        pass
    return ""


def name_from_path(path):
    base = os.path.basename(path)
    base = EXE_RE.sub("", base)
    base = base.replace("_", " ").replace("-", " ").strip()
    return base or os.path.basename(os.path.dirname(path))


def desktop_for_exe(root, exe):
    real = os.path.realpath(exe).lower()
    for desktop in glob.glob(os.path.join(root, "*.desktop")):
        try:
            text = open(desktop, "r", encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        exec_match = re.search(r"^Exec=(.*)$", text, re.M)
        icon_match = re.search(r"^Icon=(.*)$", text, re.M)
        if not exec_match:
            continue
        exec_line = exec_match.group(1).lower()
        icon = icon_match.group(1).strip() if icon_match else ""
        if real in exec_line:
            return desktop, icon
    return "", ""


def extract_icon(root, exe, game_name):
    img_dir = os.path.join(root, "data", "img")
    safe = re.sub(r"[^A-Za-z0-9._-]+", "_", game_name or name_from_path(exe)).strip("_") or "game"
    out = os.path.join(img_dir, safe + ".png")
    out48 = os.path.join(img_dir, safe + "_48.png")
    if os.path.exists(out):
        return out
    os.makedirs(img_dir, exist_ok=True)
    plugins = find_plugins(root)
    if plugins:
        site = os.path.join(plugins, "portable", "lib", "python3.9", "site-packages")
        if os.path.isdir(site) and site not in sys.path:
            sys.path.insert(0, site)
    try:
        from icoextract import IconExtractor
        from PIL import Image

        raw = IconExtractor(exe).get_icon().getvalue()
        image = Image.open(io.BytesIO(raw))
        if hasattr(image, "ico"):
            try:
                image.size = max(image.ico.sizes())
            except Exception:
                pass
        image = image.convert("RGBA")
        large = image.copy()
        large.thumbnail((256, 256))
        large.save(out, "PNG")
        small = image.copy()
        small.thumbnail((48, 48))
        small.save(out48, "PNG")
        return out
    except Exception:
        pass

    wrestool = shutil.which("wrestool")
    icotool = shutil.which("icotool")
    if wrestool and icotool:
        temporary = tempfile.mkdtemp(prefix="qs-pp-icon-")
        try:
            subprocess.run([wrestool, "-x", "-t", "14", "-o", temporary, exe],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
            for icon in glob.glob(os.path.join(temporary, "*.ico")):
                subprocess.run([icotool, "-x", "-o", temporary, icon],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
            pngs = glob.glob(os.path.join(temporary, "*.png"))
            if pngs:
                shutil.copy2(sorted(pngs, key=lambda p: os.path.getsize(p))[-1], out)
                return out
        except Exception:
            pass
        finally:
            shutil.rmtree(temporary, ignore_errors=True)

    for generic_name in ("game.png", "Game.png", "setup.png", "exe.png"):
        generic = os.path.join(img_dir, generic_name)
        if os.path.exists(generic):
            return generic
    return ""


def quote_exec(value):
    return '"%s"' % str(value).replace('"', '\\"')


def create_desktop(root, exe, game_name, icon, mode="standalone", prefix="", wine_id=""):
    safe = re.sub(r"[^A-Za-z0-9._-]+", "_", game_name).strip("_") or "Game"
    desktop = os.path.join(root, safe + ".desktop")
    if os.path.exists(desktop):
        try:
            text = open(desktop, "r", encoding="utf-8", errors="replace").read()
            if os.path.realpath(exe).lower() in text.lower():
                return desktop
        except OSError:
            pass
    lines = [
        "[Desktop Entry]",
        "Name=" + game_name,
    ]
    if mode == "native":
        start_sh = os.path.join(root, "data", "scripts", "start.sh")
        if prefix:
            lines.append('Exec=env PW_PREFIX_NAME=%s "%s" "%s"' % (quote_exec(prefix), start_sh, exe))
        else:
            lines.append('Exec=env "%s" "%s"' % (start_sh, exe))
    else:
        wine = resolve_wine(root, wine_id)
        prefix_dir = prefix_path(root, prefix) if prefix else os.path.join(prefixes_dir(root), "DEFAULT")
        if wine:
            env_parts = ["env", "WINEPREFIX=%s" % quote_exec(prefix_dir)]
            if wine_id:
                env_parts.append("PW_WINE_USE=%s" % quote_exec(wine_id))
            launch = wine_command(wine["path"], [wine["path"], exe])
            lines.append("Exec=" + " ".join(env_parts + [quote_exec(part) for part in launch]))
        else:
            lines.append('Exec=env WINEPREFIX=%s wine %s' % (quote_exec(prefix_dir), quote_exec(exe)))
    lines.extend([
        "Type=Application",
        "Categories=Game",
        "StartupNotify=true",
    ])
    if mode == "native":
        lines.append("Path=" + os.path.join(root, "data", "scripts") + "/")
    if icon:
        lines.append("Icon=" + icon)
    try:
        with open(desktop, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")
        os.chmod(desktop, 0o755)
        applications = os.path.expanduser("~/.local/share/applications")
        os.makedirs(applications, exist_ok=True)
        shutil.copy2(desktop, os.path.join(applications, os.path.basename(desktop)))
    except OSError:
        pass
    return desktop


def recent_enough(path, since):
    if not since:
        return True
    try:
        return os.path.getctime(path) >= since - 5
    except OSError:
        return True


def collect_lnk_candidates(root, prefix, game_name, since=0):
    patterns = [
        "drive_c/users/*/Desktop/**/*.lnk",
        "drive_c/users/Public/Desktop/**/*.lnk",
        "drive_c/users/*/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/**/*.lnk",
        "drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs/**/*.lnk",
    ]
    candidates = []
    seen = set()
    for pattern in patterns:
        for lnk in glob.glob(os.path.join(prefix, pattern), recursive=True):
            target = windows_to_linux(prefix, parse_lnk(root, lnk))
            if not target or not os.path.isfile(target) or not EXE_RE.search(target):
                continue
            if not recent_enough(lnk, since):
                continue
            real = os.path.realpath(target)
            if real.lower() in seen:
                continue
            seen.add(real.lower())
            link_name = os.path.splitext(os.path.basename(lnk))[0] or name_from_path(real)
            tokens = [token for token in re.split(r"[^A-Za-z0-9]+", game_name.lower()) if len(token) > 2]
            score = 120
            lower_name = (link_name + " " + os.path.basename(real)).lower()
            if tokens and any(token in lower_name for token in tokens):
                score += 60
            candidates.append({
                "exe": real,
                "name": link_name,
                "score": score,
                "source": "shortcut",
            })
    return candidates


def collect_exe_candidates(prefix, game_name, since=0):
    candidates = []
    seen = set()
    root_dir = os.path.join(prefix, "drive_c")
    prune = {"windows", "windows.old", "winsxs", "$recycle.bin", "temp", "tmp", "installshield",
             "redist", "directx", "dotnet", "microsoft.net", "system32", "syswow64"}
    tokens = [token for token in re.split(r"[^A-Za-z0-9]+", game_name.lower()) if len(token) > 2]
    for current, dirs, files in os.walk(root_dir):
        dirs[:] = [d for d in dirs if d.lower() not in prune]
        rel = os.path.relpath(current, root_dir)
        if BAD_DIR_RE.search(rel.replace(os.sep, "/")):
            dirs[:] = []
            continue
        for filename in files:
            if not EXE_RE.search(filename) or BAD_NAME_RE.search(EXE_RE.sub("", filename)):
                continue
            path = os.path.join(current, filename)
            if not recent_enough(path, since):
                continue
            try:
                real = os.path.realpath(path)
            except OSError:
                continue
            if real.lower() in seen:
                continue
            seen.add(real.lower())
            score = 10
            lower = real.lower()
            if GOOD_DIR_RE.search(rel.replace(os.sep, "/")):
                score += 30
            if tokens and any(token in lower for token in tokens):
                score += 40
            depth = rel.count(os.sep)
            score += max(0, 15 - depth)
            candidates.append({
                "exe": real,
                "name": name_from_path(real),
                "score": score,
                "source": "exe",
            })
    return candidates


def scan_prefix(root, prefix, game_name, since=0, mode="standalone", wine=""):
    result_data = {
        "exe": "", "name": game_name, "prefix": os.path.basename(prefix),
        "icon": "", "desktopFile": "", "candidates": [],
    }
    if not os.path.isdir(prefix):
        return result_data

    candidates = collect_lnk_candidates(root, prefix, game_name, since)
    candidates.extend(collect_exe_candidates(prefix, game_name, since))
    deduped = {}
    for candidate in candidates:
        key = candidate["exe"].lower()
        if key not in deduped or candidate["score"] > deduped[key]["score"]:
            deduped[key] = candidate
    ranked = sorted(deduped.values(), key=lambda item: (-item["score"], len(item["exe"]), item["exe"].lower()))
    result_data["candidates"] = [
        {"exe": item["exe"], "name": item["name"], "score": item["score"]}
        for item in ranked[:30]
    ]

    if ranked:
        chosen = ranked[0]
        desktop, icon = desktop_for_exe(root, chosen["exe"])
        if not icon:
            icon = extract_icon(root, chosen["exe"], game_name)
        if not desktop:
            desktop = create_desktop(
                root, chosen["exe"], game_name, icon, mode=mode,
                prefix=os.path.basename(prefix), wine_id=wine,
            )
        result_data.update({
            "exe": chosen["exe"],
            "name": game_name,
            "icon": icon,
            "desktopFile": desktop,
        })
    return result_data


# ---------------------------------------------------------------------------
# Info / status
# ---------------------------------------------------------------------------


def info(args):
    context = resolve_context(args.root)
    root = context["root"]
    wines = discover_wines(root, context["originalRoot"])
    prefixes = list_prefixes(root)
    ready = bool(context["command"]) if context["mode"] == "native" else bool(wines)
    if not os.path.isdir(root) and not context["originalRoot"]:
        ready = False
    result_data = {
        "mode": context["mode"],
        "root": root,
        "originalRoot": context["originalRoot"],
        "originalAvailable": bool(context["originalRoot"]),
        "commandAvailable": bool(context["command"]),
        "command": context["command"],
        "ready": ready,
        "prefixes": prefixes,
        "wines": [
            {
                "id": wine["id"],
                "name": wine["name"],
                "path": wine["path"],
                "kind": wine["kind"],
                "managed": wine_is_managed(wine, root, context["originalRoot"]),
            }
            for wine in wines
        ],
        "wineVersions": [wine["id"] for wine in wines],
        "paths": {
            "prefixes": prefixes_dir(root),
            "dist": os.path.join(root, "data", "dist"),
            "userConf": user_conf_path(root),
            "config": config_path(),
            "log": log_path(root),
        },
        "running": current_running(root),
    }
    result(result_data)


def status(args):
    root = resolve_context(args.root)["root"]
    result({"running": current_running(root)})


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=[
        "info", "status", "install", "launch", "stop", "create-prefix",
        "clear-prefix", "backup", "restore", "tool", "scan",
        "wine-catalog", "wine-install", "wine-remove",
    ])
    parser.add_argument("--root", default="")
    parser.add_argument("--prefix", default="")
    parser.add_argument("--name", default="")
    parser.add_argument("--installer", default="")
    parser.add_argument("--exe", default="")
    parser.add_argument("--pid", type=int, default=0)
    parser.add_argument("--wine", default="")
    parser.add_argument("--windows-ver", default="")
    parser.add_argument("--locale", default="")
    parser.add_argument("--sound-driver", default="")
    parser.add_argument("--dll-install", default="")
    parser.add_argument("--dll-overrides", default="")
    parser.add_argument("--args", default="")
    parser.add_argument("--env", action="append", default=[])
    parser.add_argument("--tool", default="winecfg")
    parser.add_argument("--dest", default="")
    parser.add_argument("--pack", default="")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--url", default="")
    args = parser.parse_args()

    if args.command == "info":
        info(args)
    elif args.command == "status":
        status(args)
    elif args.command == "install":
        install_game(args)
    elif args.command == "launch":
        launch_game(args)
    elif args.command == "stop":
        stop_game(args)
    elif args.command == "create-prefix":
        create_prefix(args)
    elif args.command == "clear-prefix":
        clear_prefix(args)
    elif args.command == "backup":
        backup_prefix(args)
    elif args.command == "restore":
        restore_prefix(args)
    elif args.command == "tool":
        open_tool(args)
    elif args.command == "scan":
        context = resolve_context(args.root)
        root = context["root"]
        scan = scan_prefix(
            root, prefix_path(root, args.prefix or args.name), args.name or "Game",
            mode=context["mode"], wine=args.wine,
        )
        result(scan)
    elif args.command == "wine-catalog":
        wine_catalog(args)
    elif args.command == "wine-install":
        wine_install(args)
    elif args.command == "wine-remove":
        wine_remove(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
