pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Файловый менеджер — модель и операции.
 *
 * entries / displayEntries — объекты:
 *   name, path, fileUrl, isDir, isLink, hidden, size, modified, iconName
 * В режиме tree к displayEntries добавляются depth, treeExpanded, treeLoaded,
 * treeHasChildren.
 */
Singleton {
    id: root

    readonly property string homePath: FileUtils.trimFileProtocol(Directories.home)

    property string currentPath: root.homePath
    property var entries: []
    property var displayEntries: []
    property var selection: []
    property int selectionAnchor: -1
    property string statusMessage: ""
    property bool loading: false
    property bool showHidden: false

    property int iconScale: Persistent.states.fileManager?.iconScale ?? 100
    onIconScaleChanged: {
        if (Persistent.states.fileManager && Persistent.states.fileManager.iconScale !== iconScale)
            Persistent.states.fileManager.iconScale = iconScale;
    }
    readonly property int listIconSize: Math.max(16, Math.round(22 * root.iconScale / 100))
    readonly property int gridIconSize: Math.max(32, Math.round(48 * root.iconScale / 100))
    readonly property int gridCellSize: Math.max(88, root.gridIconSize + 64)
    readonly property string trashFilesPath: root.homePath + "/.local/share/Trash/files"
    readonly property string trashInfoPath: root.homePath + "/.local/share/Trash/info"
    readonly property bool inTrash: root.currentPath === root.trashFilesPath || root.currentPath.startsWith(root.trashFilesPath + "/")
    property var pendingPermanentDelete: []

    property string viewMode: "list" // list | grid | tree
    property string sortBy: "name"    // name | size | modified | type
    property bool sortAscending: true

    property var history: [root.homePath]
    property int historyIndex: 0
    readonly property bool canGoBack: historyIndex > 0
    readonly property bool canGoForward: historyIndex < history.length - 1

    property var clipboardPaths: []
    property string clipboardMode: "copy" // copy | cut

    property var treeExpanded: ({})
    property var treeChildren: ({})
    property var treeLoaded: ({})
    property var treeQueue: []
    property string treeLoadingPath: ""
    property string pendingSelectPath: ""

    signal selectionMoved(int index)

    readonly property var places: [
        { name: "Home", icon: "home", path: root.homePath },
        { name: "Downloads", icon: "download", path: FileUtils.trimFileProtocol(Directories.downloads) },
        { name: "Documents", icon: "description", path: FileUtils.trimFileProtocol(Directories.documents) },
        { name: "Pictures", icon: "image", path: FileUtils.trimFileProtocol(Directories.pictures) },
        { name: "Music", icon: "music_note", path: FileUtils.trimFileProtocol(Directories.music) },
        { name: "Videos", icon: "video_library", path: FileUtils.trimFileProtocol(Directories.videos) },
        { name: "Root", icon: "hard_drive", path: "/" },
        { name: "Trash", icon: "delete", path: "trash:///" }
    ]

    // ---------- навигация ----------

    function normalizePath(path) {
        let p = FileUtils.trimFileProtocol(String(path ?? "").trim());
        if (!p) return root.homePath;
        if (p === "~") p = root.homePath;
        else if (p.startsWith("~/")) p = root.homePath + p.slice(1);
        if (!p.startsWith("/")) p = root.currentPath.replace(/\/+$/, "") + "/" + p;
        p = p.replace(/\/+/g, "/");
        if (p.length > 1) p = p.replace(/\/+$/, "");
        return p;
    }

    function navigate(path) {
        root.pendingPermanentDelete = [];
        const p = normalizePath(path);
        if (!p) return;
        if (p === root.currentPath) {
            root.reload();
            return;
        }
        root.currentPath = p;
        if (root.historyIndex < root.history.length - 1)
            root.history = root.history.slice(0, root.historyIndex + 1);
        root.history = [...root.history, p];
        root.historyIndex = root.history.length - 1;
        root.selection = [];
        root.selectionAnchor = -1;
        root.reload();
    }

    function goUp() {
        root.navigate(parentOf(root.currentPath));
    }

    function goBack() {
        root.pendingPermanentDelete = [];
        if (!root.canGoBack) return;
        root.historyIndex--;
        root.currentPath = root.history[root.historyIndex];
        root.selection = [];
        root.selectionAnchor = -1;
        root.reload();
    }

    function goForward() {
        root.pendingPermanentDelete = [];
        if (!root.canGoForward) return;
        root.historyIndex++;
        root.currentPath = root.history[root.historyIndex];
        root.selection = [];
        root.selectionAnchor = -1;
        root.reload();
    }

    function reload() {
        root.loading = true;
        root.clearTreeCache();
        findProcess.running = false;
        findProcess.command = findCommand(root.currentPath);
        findProcess.running = true;
    }

    // ---------- вид и сортировка ----------

    function setViewMode(mode) {
        if (root.viewMode === mode) return;
        root.viewMode = mode;
        root.rebuildDisplay();
        if (mode === "tree") root.ensureVisibleTreeLoads();
    }

    function cycleViewMode() {
        const modes = ["list", "grid", "tree"];
        root.setViewMode(modes[(modes.indexOf(root.viewMode) + 1) % modes.length]);
        root.setStatus("Вид: " + root.viewMode);
    }

    function cycleSort() {
        const modes = ["name", "size", "modified", "type"];
        root.sortBy = modes[(modes.indexOf(root.sortBy) + 1) % modes.length];
        root.sortAscending = true;
        root.rebuildDisplay();
        root.setStatus("Сортировка: " + root.sortBy);
    }

    function toggleSortDirection() {
        root.sortAscending = !root.sortAscending;
        root.rebuildDisplay();
        root.setStatus(root.sortAscending ? "По возрастанию" : "По убыванию");
    }

    function toggleHidden() {
        root.showHidden = !root.showHidden;
        root.clearTreeCache();
        root.reload();
    }

    function setIconScale(value) {
        const numeric = Number(value);
        if (!Number.isFinite(numeric)) return;
        const clamped = Math.max(60, Math.min(200, Math.round(numeric / 10) * 10));
        root.iconScale = clamped;
        root.setStatus(`Масштаб иконок: ${clamped}%`);
    }

    function adjustIconScale(delta) {
        root.setIconScale(root.iconScale + delta);
    }

    function resetIconScale() {
        root.setIconScale(100);
    }

    // ---------- выделение ----------

    function selectOnly(path) {
        root.selection = [path];
        root.selectionAnchor = root.indexOfPath(path);
        root.selectionMoved(root.selectionAnchor);
    }

    function toggleSelection(path) {
        if (root.selection.includes(path))
            root.selection = root.selection.filter(p => p !== path);
        else
            root.selection = [...root.selection, path];
        root.selectionAnchor = root.indexOfPath(path);
        root.selectionMoved(root.selectionAnchor);
    }

    function selectRangeTo(path) {
        const idx = root.indexOfPath(path);
        if (idx < 0) return;
        const anchor = root.selectionAnchor >= 0 ? root.selectionAnchor : idx;
        const from = Math.min(anchor, idx);
        const to = Math.max(anchor, idx);
        root.selection = root.displayEntries.slice(from, to + 1).map(e => e.path);
        root.selectionMoved(idx);
    }

    function selectAll() {
        root.selection = root.displayEntries.map(e => e.path);
        root.selectionAnchor = 0;
        root.setStatus(`Выбрано: ${root.selection.length}`);
    }

    function clearSelection() {
        root.selection = [];
        root.selectionAnchor = -1;
    }

    function selectedEntry() {
        if (!root.selection.length) return null;
        return root.entryByPath(root.selection[root.selection.length - 1]);
    }

    function selectedIndex() {
        if (!root.selection.length) return -1;
        return root.indexOfPath(root.selection[root.selection.length - 1]);
    }

    function selectIndex(index, extend) {
        if (!root.displayEntries.length) return;
        const idx = Math.max(0, Math.min(root.displayEntries.length - 1, index));
        if (extend) {
            const anchor = root.selectionAnchor >= 0 ? root.selectionAnchor : idx;
            const from = Math.min(anchor, idx);
            const to = Math.max(anchor, idx);
            root.selection = root.displayEntries.slice(from, to + 1).map(e => e.path);
            root.selectionAnchor = anchor;
        } else {
            root.selection = [root.displayEntries[idx].path];
            root.selectionAnchor = idx;
        }
        root.selectionMoved(idx);
    }

    function moveSelection(delta) {
        if (!root.displayEntries.length) return;
        const current = root.selectedIndex();
        const base = current < 0 ? (delta > 0 ? -1 : 0) : current;
        root.selectIndex(base + delta, false);
    }

    function extendSelection(delta) {
        if (!root.displayEntries.length) return;
        const current = root.selectedIndex();
        const base = current < 0 ? 0 : current;
        root.selectIndex(base + delta, true);
    }

    function moveSelectionGrid(dx, dy, columns, extend) {
        if (!root.displayEntries.length) return;
        columns = Math.max(1, Number(columns) || 1);
        const current = root.selectedIndex();
        let idx = current < 0 ? 0 : current;
        let row = Math.floor(idx / columns);
        let col = idx % columns;
        if (dy !== 0) {
            row += dy;
        } else {
            col += dx;
            if (col < 0) {
                if (row > 0) {
                    row--;
                    col = columns - 1;
                } else {
                    col = 0;
                }
            } else if (col >= columns) {
                if ((row + 1) * columns < root.displayEntries.length) {
                    row++;
                    col = 0;
                } else {
                    col = columns - 1;
                }
            }
        }
        const maxRow = Math.max(0, Math.ceil(root.displayEntries.length / columns) - 1);
        row = Math.max(0, Math.min(maxRow, row));
        idx = Math.min(root.displayEntries.length - 1, row * columns + col);
        root.selectIndex(idx, extend);
    }

    function selectFirst() {
        root.selectIndex(0, false);
    }

    function selectLast() {
        root.selectIndex(root.displayEntries.length - 1, false);
    }

    function toggleSelectionAtCurrent() {
        const entry = root.selectedEntry();
        if (entry) root.toggleSelection(entry.path);
    }

    function treeLeft() {
        const entry = root.selectedEntry();
        if (!entry) return;
        if (entry.isDir && root.treeExpanded[entry.path]) {
            root.toggleTree(entry.path);
            return;
        }
        const parentPath = root.parentOf(entry.path);
        const idx = root.indexOfPath(parentPath);
        if (idx >= 0) root.selectIndex(idx, false);
    }

    function treeRight() {
        const entry = root.selectedEntry();
        if (!entry) return;
        if (!entry.isDir) {
            root.openEntry(entry);
            return;
        }
        if (!root.treeExpanded[entry.path]) {
            root.toggleTree(entry.path);
            return;
        }
        const idx = root.indexOfPath(entry.path);
        if (idx >= 0 && idx + 1 < root.displayEntries.length)
            root.selectIndex(idx + 1, false);
    }

    function openSelected() {
        if (!root.selection.length) return;
        const entry = root.entryByPath(root.selection[0]);
        if (entry) root.openEntry(entry);
    }

    function renameSelected() {
        if (!root.selection.length) return null;
        return root.entryByPath(root.selection[0]);
    }

    function entryByPath(path) {
        return root.displayEntries.find(e => e.path === path)
            || root.entries.find(e => e.path === path)
            || null;
    }

    function indexOfPath(path) {
        return root.displayEntries.findIndex(e => e.path === path);
    }

    // ---------- операции ----------

    function openEntry(entry) {
        if (!entry) return;
        if (entry.isDir) {
            root.navigate(entry.path);
        } else {
            Quickshell.execDetached(["xdg-open", entry.path]);
        }
    }

    function openWithTerminal(entry) {
        if (!entry) return;
        const term = (Config?.options?.apps?.terminal ?? "foot");
        const cwd = entry.isDir ? entry.path : parentOf(entry.path);
        Quickshell.execDetached(["bash", "-c", 'cd -- "$1" && exec "$2"', "bash", cwd, term]);
    }

    function deleteEntries(paths, permanent) {
        paths = (paths && paths.length) ? paths : root.selection;
        if (!paths.length) return;
        if (root.inTrash && permanent !== true) {
            root.pendingPermanentDelete = [...paths];
            root.setStatus(`Удалить безвозвратно: ${paths.length}?`);
            return;
        }
        if (root.inTrash) {
            Quickshell.execDetached(["bash", "-c",
                `trash="$1"; info="$2"; shift 2; for p in "$@"; do [ -n "$p" ] || continue; rm -rf -- "$p"; case "$p" in "$trash"/*/*) ;; "$trash"/*) rm -f -- "$info/$(basename -- "$p").trashinfo";; esac; done; true`,
                "bash", root.trashFilesPath, root.trashInfoPath].concat(paths));
        } else {
            Quickshell.execDetached(["bash", "-c",
                `for p in "$@"; do if command -v trash-put >/dev/null 2>&1; then trash-put -- "$p"; else gio trash -- "$p"; fi; done; true`,
                "bash"].concat(paths));
        }
        root.pendingPermanentDelete = [];
        root.clearSelection();
        root.setStatus(`${root.inTrash ? "Удалено безвозвратно" : "Удалено в корзину"}: ${paths.length}`);
        reloadTimer.restart();
    }

    function confirmPermanentDelete() {
        if (!root.pendingPermanentDelete.length) return;
        root.deleteEntries(root.pendingPermanentDelete, true);
    }

    function cancelPermanentDelete() {
        root.pendingPermanentDelete = [];
        root.setStatus("Удаление отменено");
    }

    function copyEntries(paths) {
        paths = (paths && paths.length) ? paths : root.selection;
        if (!paths.length) return;
        root.clipboardPaths = [...paths];
        root.clipboardMode = "copy";
        root.writeClipboard(paths);
        root.setStatus(`Скопировано: ${paths.length}`);
    }

    function cutEntries(paths) {
        paths = (paths && paths.length) ? paths : root.selection;
        if (!paths.length) return;
        root.clipboardPaths = [...paths];
        root.clipboardMode = "cut";
        root.writeClipboard(paths);
        root.setStatus(`Вырезано: ${paths.length}`);
    }

    function pasteEntries() {
        const paths = root.clipboardPaths;
        const mode = root.clipboardMode;
        if (!paths.length) {
            Quickshell.execDetached(["bash", "-c",
                `cd -- "$1" && wl-paste --type text/uri-list 2>/dev/null | python3 -c 'import sys,urllib.parse;[print(urllib.parse.unquote(l.strip()[7:])) for l in sys.stdin if l.strip().startswith("file://")]' | while IFS= read -r p; do [ -e "$p" ] && cp -r -- "$p" .; done; true`,
                "bash", root.currentPath]);
        } else {
            Quickshell.execDetached(["bash", "-c",
                `mode="$1"; target="$2"; shift 2; for p in "$@"; do if [ "$mode" = cut ]; then mv -- "$p" "$target/"; else cp -r -- "$p" "$target/"; fi; done; true`,
                "bash", mode, root.currentPath].concat(paths));
            if (mode === "cut") {
                root.clipboardPaths = [];
                root.clipboardMode = "copy";
            }
        }
        root.setStatus(mode === "cut" ? "Перемещение..." : "Вставка...");
        reloadTimer.restart();
    }

    function renameEntry(entry, newName) {
        if (!entry) return;
        newName = String(newName ?? "").trim();
        if (!newName || newName === entry.name || newName.includes("/")) return;
        const dir = parentOf(entry.path);
        const target = dir === "/" ? "/" + newName : dir + "/" + newName;
        Quickshell.execDetached(["bash", "-c", 'if [ -e "$2" ]; then exit 1; fi; mv -- "$1" "$2"', "bash", entry.path, target]);
        root.pendingSelectPath = target;
        root.setStatus(`Переименован: ${entry.name} → ${newName}`);
        reloadTimer.restart();
    }

    function newFolder() {
        let name = "New Folder";
        let i = 2;
        const names = root.entries.map(e => e.name);
        while (names.includes(name)) name = `New Folder ${i++}`;
        const target = root.currentPath === "/" ? "/" + name : root.currentPath + "/" + name;
        Quickshell.execDetached(["bash", "-c", 'mkdir -- "$1"', "bash", target]);
        root.pendingSelectPath = target;
        root.setStatus(`Создана папка: ${name}`);
        reloadTimer.restart();
    }

    function newFile() {
        let name = "New File.txt";
        let i = 2;
        const names = root.entries.map(e => e.name);
        while (names.includes(name)) name = `New File ${i++}.txt`;
        const target = root.currentPath === "/" ? "/" + name : root.currentPath + "/" + name;
        Quickshell.execDetached(["bash", "-c", 'touch -- "$1"', "bash", target]);
        root.pendingSelectPath = target;
        root.setStatus(`Создан файл: ${name}`);
        reloadTimer.restart();
    }

    function describeEntry(entry) {
        if (!entry) return;
        const kind = entry.isDir ? "папка" : entry.isLink ? "ссылка" : "файл";
        const size = entry.isDir ? "—" : root.formatSize(entry.size);
        root.setStatus(`${entry.name} · ${kind} · ${size} · ${root.formatModified(entry.modified)}`);
    }

    function writeClipboard(paths) {
        Quickshell.execDetached(["bash", "-c",
            `for p in "$@"; do printf 'file://%s\\n' "$p"; done | wl-copy -t text/uri-list 2>/dev/null || true`,
            "bash"].concat(paths));
    }

    // ---------- дерево ----------

    function toggleTree(path) {
        if (root.treeExpanded[path]) {
            root.treeExpanded = objectWith(path, false, root.treeExpanded);
            root.rebuildDisplay();
            return;
        }
        root.treeExpanded = objectWith(path, true, root.treeExpanded);
        if (!root.treeLoaded[path]) root.queueTreeLoad(path);
        root.rebuildDisplay();
    }

    function queueTreeLoad(path) {
        if (root.treeLoaded[path] === true || root.treeLoadingPath === path) return;
        if (root.treeQueue.includes(path)) return;
        root.treeQueue = [...root.treeQueue, path];
        if (!treeProcess.running) root.startNextTreeLoad();
    }

    function startNextTreeLoad() {
        if (!root.treeQueue.length) {
            root.treeLoadingPath = "";
            return;
        }
        root.treeLoadingPath = root.treeQueue[0];
        root.treeQueue = root.treeQueue.slice(1);
        treeProcess.running = false;
        treeProcess.command = findCommand(root.treeLoadingPath);
        treeProcess.running = true;
    }

    function finishTreeLoad(text) {
        const path = root.treeLoadingPath;
        if (!path) return;
        root.treeChildren = objectWith(path, root.parseEntries(text, path), root.treeChildren);
        root.treeLoaded = objectWith(path, true, root.treeLoaded);
        root.treeLoadingPath = "";
        if (root.viewMode === "tree") root.rebuildDisplay();
        root.startNextTreeLoad();
    }

    function ensureVisibleTreeLoads() {
        for (const path of Object.keys(root.treeExpanded)) {
            if (root.treeExpanded[path] && !root.treeLoaded[path]) root.queueTreeLoad(path);
        }
    }

    function clearTreeCache() {
        treeProcess.running = false;
        root.treeQueue = [];
        root.treeLoadingPath = "";
        root.treeChildren = ({});
        root.treeLoaded = ({});
    }

    // ---------- internals ----------

    function findCommand(path) {
        return ["find", path, "-maxdepth", "1", "-mindepth", "1", "-printf", "%y\t%s\t%T@\t%f\n"];
    }

    function parseEntries(text, basePath) {
        const out = [];
        const base = basePath.replace(/\/+$/, "");
        for (const line of String(text ?? "").split("\n")) {
            if (!line) continue;
            const first = line.indexOf("\t");
            const second = line.indexOf("\t", first + 1);
            const third = line.indexOf("\t", second + 1);
            if (first < 0 || second < 0 || third < 0) continue;
            const type = line.slice(0, first);
            const size = Number(line.slice(first + 1, second));
            const modified = Number(line.slice(second + 1, third));
            const name = line.slice(third + 1);
            if (!name || name === "." || name === "..") continue;
            const hidden = name.startsWith(".");
            if (hidden && !root.showHidden) continue;
            const isDir = type === "d";
            const isLink = type === "l";
            const path = base + "/" + name;
            out.push({
                name: name,
                path: path,
                fileUrl: "file://" + path,
                isDir: isDir,
                isLink: isLink,
                hidden: hidden,
                size: Number.isFinite(size) ? size : 0,
                modified: Number.isFinite(modified) ? modified : 0,
                iconName: root.iconFor({ name: name, isDir: isDir }),
            });
        }
        return out;
    }

    function sortEntries(list) {
        const arr = list.slice();
        const direction = root.sortAscending ? 1 : -1;
        arr.sort((a, b) => {
            if (a.isDir !== b.isDir) return a.isDir ? -1 : 1;
            let result = 0;
            if (root.sortBy === "size") result = a.size - b.size;
            else if (root.sortBy === "modified") result = a.modified - b.modified;
            else if (root.sortBy === "type") result = extensionOf(a.name).localeCompare(extensionOf(b.name));
            else result = a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" });
            if (result === 0) result = a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" });
            return result * direction;
        });
        return arr;
    }

    function rebuildDisplay() {
        if (root.viewMode === "tree") {
            root.displayEntries = root.flattenTree(root.sortEntries(root.entries), 0);
        } else {
            root.displayEntries = root.sortEntries(root.entries);
        }
        const visible = {};
        for (const entry of root.displayEntries) visible[entry.path] = true;
        root.selection = root.selection.filter(p => visible[p]);
        if (root.selectionAnchor >= root.displayEntries.length) root.selectionAnchor = -1;
        if (root.pendingSelectPath) {
            const idx = root.indexOfPath(root.pendingSelectPath);
            if (idx >= 0) {
                root.selection = [root.pendingSelectPath];
                root.selectionAnchor = idx;
                root.pendingSelectPath = "";
            }
        }
    }

    function flattenTree(list, depth) {
        let out = [];
        for (const entry of list) {
            const expanded = !!root.treeExpanded[entry.path];
            const loaded = root.treeLoaded[entry.path] === true;
            const children = root.treeChildren[entry.path];
            out.push(objectWith("depth", depth, objectWith("treeExpanded", expanded, objectWith("treeLoaded", loaded, objectWith("treeHasChildren", entry.isDir && (!loaded || (children && children.length > 0)), entry)))));
            if (entry.isDir && expanded) {
                if (children) out = out.concat(root.flattenTree(root.sortEntries(children), depth + 1));
                else root.queueTreeLoad(entry.path);
            }
        }
        return out;
    }

    function finishMainLoad(text) {
        root.entries = root.parseEntries(text, root.currentPath);
        root.loading = false;
        root.rebuildDisplay();
    }

    function objectWith(key, value, base) {
        const out = {};
        for (const k in base) out[k] = base[k];
        out[key] = value;
        return out;
    }

    function parentOf(path) {
        const idx = path.lastIndexOf("/");
        return idx <= 0 ? "/" : path.slice(0, idx);
    }

    function extensionOf(name) {
        const idx = name.lastIndexOf(".");
        return idx > -1 ? name.slice(idx + 1).toLowerCase() : "";
    }

    function formatSize(bytes) {
        if (!Number.isFinite(bytes) || bytes < 1024) return `${Math.max(0, bytes | 0)} B`;
        const units = ["KB", "MB", "GB", "TB"];
        let value = bytes / 1024;
        let i = 0;
        while (value >= 1024 && i < units.length - 1) {
            value /= 1024;
            i++;
        }
        return `${value >= 10 ? value.toFixed(0) : value.toFixed(1)} ${units[i]}`;
    }

    function formatModified(seconds) {
        if (!seconds) return "—";
        return new Date(seconds * 1000).toLocaleString();
    }

    function formatModifiedShort(seconds) {
        if (!seconds) return "";
        return new Date(seconds * 1000).toISOString().slice(0, 16).replace("T", " ");
    }

    function setStatus(msg) {
        root.statusMessage = msg;
        statusTimer.restart();
    }

    function iconFileCandidates(name, size) {
        let icon = String(name || "text-x-generic");
        if (icon === "nix") icon = "text-x-generic";
        const user = Quickshell.env("USER") || "";
        const breeze = "/etc/profiles/per-user/" + user + "/share/icons/breeze-dark";
        const papirus = root.homePath + "/.local/share/icons/Papirus-Dark";
        const isDir = icon === "folder" || icon.indexOf("folder-") === 0;
        const categories = isDir ? ["places"] : ["mimetypes", "places"];
        const sizes = size >= 80
            ? [96, 64, 48, 32, 24, 22, 16]
            : size >= 40
                ? [64, 48, 32, 24, 22, 16]
                : size <= 20
                    ? [16, 22, 24, 32, 48, 64]
                    : [22, 24, 16, 32, 48, 64];
        const result = [];
        for (const category of categories) {
            for (const s of sizes) result.push("file://" + breeze + "/" + category + "/" + s + "/" + icon + ".svg");
        }
        for (const category of categories) {
            for (const s of sizes) result.push("file://" + papirus + "/" + s + "x" + s + "/" + category + "/" + icon + ".svg");
        }
        for (const s of sizes) {
            result.push("file://" + breeze + "/mimetypes/" + s + "/text-x-generic.svg");
            result.push("file://" + papirus + "/" + s + "x" + s + "/mimetypes/text-x-generic.svg");
        }
        return result;
    }

    function iconFor(entry) {
        const n = entry.name.toLowerCase();
        if (entry.isDir) return "folder";
        if (/\.(png|jpe?g|webp|gif|svg|bmp|avif)$/.test(n)) return "image-x-generic";
        if (/\.(mp4|mkv|webm|avi|mov|m4v)$/.test(n)) return "video-x-generic";
        if (/\.(mp3|flac|ogg|wav|m4a|opus)$/.test(n)) return "audio-x-generic";
        if (/\.(zip|tar\.gz|tgz|7z|rar|xz|bz2|zst)$/.test(n)) return "application-x-archive";
        if (n.endsWith(".jar")) return "application-x-java-archive";
        if (n.endsWith(".pdf")) return "application-pdf";
        if (n.endsWith(".nix")) return "nix";
        if (n.endsWith(".qml")) return "text-x-qml";
        if (n.endsWith(".py")) return "text-x-python";
        if (n.endsWith(".rs")) return "text-x-rust";
        if (/\.(sh|bash|zsh|fish)$/.test(n)) return "text-x-script";
        if (/\.(html?|css|js|ts|json|yml|yaml|toml|md|lua)$/.test(n)) return "text-x-generic";
        return "text-x-generic";
    }

    Timer {
        id: statusTimer
        interval: 4000
        onTriggered: root.statusMessage = ""
    }

    Timer {
        id: reloadTimer
        interval: 350
        onTriggered: root.reload()
    }

    Process {
        id: findProcess
        command: ["true"]
        stdout: StdioCollector {
            onStreamFinished: root.finishMainLoad(this.text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text) root.setStatus(this.text.trim());
            }
        }
    }

    Process {
        id: treeProcess
        command: ["true"]
        stdout: StdioCollector {
            onStreamFinished: root.finishTreeLoad(this.text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text) root.setStatus(this.text.trim());
            }
        }
    }

    Component.onCompleted: reload()
}
