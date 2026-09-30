import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.nixosConfig
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root
    focus: true

    Keys.onPressed: (event) => {
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) {
            root.saveFile();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            GlobalStates.nixosConfigOpen = false;
            event.accepted = true;
        }
    }

    property string configRoot: "/etc/nixos"
    property string currentFile: ""
    property bool fileDirty: false
    property bool loading: false
    readonly property bool building: NixosConfigBuild.building
    property bool showConsole: true
    readonly property var lastBuildExit: NixosConfigBuild.lastBuildExit
    property string branch: ""
    property string filterText: ""
    property string statusHint: ""
    readonly property string logText: NixosConfigBuild.logText
    property string rawText: "" // plain file content (edit) | highlighted HTML is derived from it
    property bool syncingText: false // true while applyEditorText() pushes programmatic text
    property int dirtyCount: 0
    // Компактная сводка git внизу дерева файлов.
    property int stagedCount: 0
    property int modifiedCount: 0
    property int untrackedCount: 0
    property int aheadCount: 0
    property int behindCount: 0
    property int pendingLine: 0 // line to jump to after the file finishes loading
    property int tabSize: 4 // spaces shown for each tab, must match the highlight layer
    readonly property real tabWidth: editorFontMetrics.advanceWidth(" ") * root.tabSize
    // Номер строки, где стоит курсор, и высота строки редактора.
    property int cursorLine: 1
    readonly property int totalLines: root.rawText.length === 0
        ? 0
        : root.rawText.split("\n").length
    readonly property real lineHeight: editorFontMetrics.lineSpacing
    // Фактический шаг строк в текстовом документе (на px больше lineSpacing) —
    // по нему считаются номера строк в левой колонке.
    readonly property real lineAdvance: editor.cursorRectangle.height > 0
        ? editor.cursorRectangle.height
        : root.lineHeight
    readonly property real gutterWidth: root.rawText.length === 0
        ? 0
        : Math.max(40, editorFontMetrics.advanceWidth("0") * String(root.totalLines).length + 22)

    // ---- подсказки при наборе ----
    property var wordIndex: []          // слова из всех файлов конфига, по частоте
    property bool indexReady: false
    property string completionPrefix: ""
    property var completionItems: []
    property int completionIndex: 0
    property string completionDismissed: ""
    property bool completionManual: false // открыто по Ctrl+Space: стрелки листают список
    property bool suppressCompletion: false
    readonly property int completionMaxVisible: 10

    // Что показано в центральной области: 0 — редактор файла, 1 — панель сервиса.
    property int viewMode: 0

    property var allRows: []
    property var treeRows: []

    implicitHeight: Appearance.sizes.wallpaperSelectorHeight - Appearance.sizes.hyprlandGapsOut * 2
    implicitWidth: Appearance.sizes.wallpaperSelectorWidth - Appearance.sizes.hyprlandGapsOut * 2

    Component.onCompleted: {
        root.refreshGit();
        wordIndexer.running = true;
    }

    // Фоновая индексация слов по всему конфигу: ~0.3 с, UI не блокируется.
    Process {
        id: wordIndexer
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.applyIndex(text)
        }
        // все текстовые файлы конфига, без фильтра по расширениям: иначе в
        // .json/.md/.service/.toml подсказок не было вообще
        command: ["sh", "-c",
            "grep -rhoIE '[A-Za-z_][A-Za-z0-9_.-]{2,}'"
            + " --exclude-dir=.git " + root.configRoot
            + " 2>/dev/null | sort | uniq -c | sort -rn | head -8000"]
    }

    function currentFilePath() {
        return root.currentFile.length > 0 ? `${root.configRoot}/${root.currentFile}` : "";
    }

    // ---------------------------------------------------------------- git data
    function refreshGit() {
        gitProc.running = true;
    }

    function parseGitOutput(text) {
        if (!text) return;
        const lines = text.split("\n");
        const lsIdx = lines.indexOf("__LS__");
        const brIdx = lines.indexOf("__BR__");
        const abIdx = lines.indexOf("__AB__");
        const statusMap = {};
        const ls = [];
        const statusBlock = lsIdx === -1 ? [] : lines.slice(0, lsIdx);
        const lsBlock = (lsIdx !== -1 && brIdx !== -1) ? lines.slice(lsIdx + 1, brIdx) : [];
        const brBlock = (brIdx !== -1 && abIdx !== -1) ? lines.slice(brIdx + 1, abIdx)
            : (brIdx === -1 ? [] : lines.slice(brIdx + 1));
        const abBlock = abIdx === -1 ? [] : lines.slice(abIdx + 1);

        for (const line of statusBlock) {
            if (line.replace(/\s/g, "").length === 0) continue;
            const code = line.substring(0, 2);
            const path = line.substring(3).trim();
            if (path.length > 0) statusMap[path] = code;
        }
        for (const line of lsBlock) {
            if (line.trim().length > 0) ls.push(line.trim());
        }
        for (const line of brBlock) {
            if (line.trim().length > 0) { root.branch = line.trim(); break; }
        }

        const seen = {};
        const combined = ls.slice();
        for (const p of Object.keys(statusMap)) { // include untracked files not in ls-files
            if (!(p in seen) && combined.indexOf(p) === -1) combined.push(p);
            seen[p] = true;
        }
        const nixOnly = combined.filter((p) => p.endsWith(".nix"));
        root.allRows = root.buildTree(nixOnly, statusMap);
        root.applyFilter();
        let dirty = 0;
        let staged = 0;
        let modified = 0;
        let untracked = 0;
        for (const line of statusBlock) {
            if (line.trim().length === 0) continue;
            dirty++;
            const code = line.substring(0, 2);
            if (code === "??" || code[0] === "?") { untracked++; continue; }
            if (code[0] !== " ") staged++;
            if (code[1] !== " ") modified++;
        }
        root.dirtyCount = dirty;
        root.stagedCount = staged;
        root.modifiedCount = modified;
        root.untrackedCount = untracked;
        const nums = abBlock.filter((l) => /^\d+$/.test(l.trim()));
        root.aheadCount = nums.length > 0 ? parseInt(nums[0], 10) : 0;
        root.behindCount = nums.length > 1 ? parseInt(nums[1], 10) : 0;
        root.statusHint = root.dirtyCount > 0
            ? Translation.tr("%1 changed files in git").arg(root.dirtyCount)
            : Translation.tr("config is clean, branch %1").arg(root.branch);
    }

    function buildTree(paths, statusMap) {
        const children = {}; // parentPath -> [names]
        const type = {};

        function push(parentPath, name) {
            if (!children[parentPath]) children[parentPath] = [];
            if (children[parentPath].indexOf(name) === -1) children[parentPath].push(name);
        }

        for (const rel of paths) {
            const parts = rel.split("/");
            let cur = "";
            for (let i = 0; i < parts.length; i++) {
                const childPath = cur ? `${cur}/${parts[i]}` : parts[i];
                push(cur, parts[i]);
                type[childPath] = (i === parts.length - 1) ? "file" : "dir";
                cur = childPath;
            }
        }

        const out = [];
        const walk = (parentPath, depth) => {
            const kids = (children[parentPath] || []).slice().sort((a, b) => {
                const pa = parentPath ? `${parentPath}/${a}` : a;
                const pb = parentPath ? `${parentPath}/${b}` : b;
                const ta = type[pa] === "dir" ? 0 : 1;
                const tb = type[pb] === "dir" ? 0 : 1;
                return ta - tb || a.localeCompare(b);
            });
            for (const name of kids) {
                const p = parentPath ? `${parentPath}/${name}` : name;
                if (type[p] === "dir") {
                    out.push({ path: p, name, depth, isDir: true, status: "" });
                    walk(p, depth + 1);
                } else {
                    out.push({ path: p, name, depth, isDir: false, status: statusMap[p] || "" });
                }
            }
        };
        walk("", 0);
        return out;
    }

    function applyFilter() {
        const q = root.filterText.trim().toLowerCase();
        if (q.length === 0) {
            root.treeRows = root.allRows;
            return;
        }
        const keep = {};
        for (const row of root.allRows) {
            if (!row.isDir && row.path.toLowerCase().indexOf(q) !== -1) keep[row.path] = true;
        }
        const rows = [];
        for (const row of root.allRows) {
            let show = false;
            if (row.isDir) {
                const prefix = row.path + "/";
                for (const p of Object.keys(keep)) {
                    if (p.startsWith(prefix)) { show = true; break; }
                }
            } else {
                show = keep[row.path] === true;
            }
            if (show) rows.push(row);
        }
        root.treeRows = rows;
    }

    // ---------------------------------------------------------------- file io
    function selectFile(path) {
        root.currentFile = path;
        root.fileDirty = false;
        root.loading = true;
        root.viewMode = 0;
        configFileView.path = root.currentFilePath();
    }

    function showFile() {
        root.viewMode = 0;
    }

    // Открыть systemd-сервис в панели вместо редактора.
    function openService(unit, scope, path, line) {
        servicePanel.stopLive();
        servicePanel.unit = unit;
        servicePanel.scope = scope;
        servicePanel.configPath = path ?? "";
        servicePanel.configLine = line ?? 0;
        root.viewMode = 1;
    }

    // Открыть файл (из правой панели с пакетами) и промотать редактор к строке.
    function openPackage(path, line) {
        console.log("[nixosConfig] openPackage", path, line);
        if (root.currentFile === path) {
            root.viewMode = 0;
            Qt.callLater(() => root.scrollToLine(line));
            return;
        }
        root.pendingLine = line;
        root.selectFile(path);
        root.statusHint = `${path}:${line}`;
    }

    // Позиция первого символа строки (1-based) в текущем тексте.
    function lineStartPos(line) {
        const txt = root.rawText;
        if (line <= 1) return 0;
        let idx = 0;
        for (let l = 1; l < line; l++) {
            const nl = txt.indexOf("\n", idx);
            if (nl < 0) return txt.length;
            idx = nl + 1;
        }
        return idx;
    }

    // Номер строки по позиции курсора.
    function lineOfPosition(pos) {
        const upto = root.rawText.substring(0, Math.max(0, pos));
        let line = 1;
        for (let i = 0; i < upto.length; i++) {
            if (upto.charCodeAt(i) === 10) line++;
        }
        return line;
    }

    // Текст скроллит внешний Flickable, а не сам TextEdit, поэтому при ходьбе
    // стрелками курсор уезжает за нижний край и область видимости не
    // прокручивается. Держим курсор в видимой зоне с запасом в несколько строк.
    function ensureCursorVisible() {
        if (!editor || !editorScrollView) return;
        const view = editorScrollView;
        const rect = editor.cursorRectangle;
        const lineH = Math.max(root.lineAdvance, rect.height);
        // Запас в три строки: курсор не липнет к нижнему краю, а прокрутка
        // начинается чуть заранее.
        const marginY = lineH * 3;
        const marginX = 60;

        // вертикаль
        const maxY = Math.max(0, view.contentHeight - view.height);
        let targetY = view.contentY;
        if (rect.y - marginY < view.contentY) {
            targetY = rect.y - marginY;
        } else if (rect.y + lineH + marginY > view.contentY + view.height) {
            targetY = rect.y + lineH + marginY - view.height;
        }
        targetY = Math.max(0, Math.min(targetY, maxY));
        if (Math.abs(targetY - view.contentY) > 0.5) view.contentY = targetY;

        // горизонталь (нужно при длинных строках: wrapMode NoWrap)
        if (view.contentWidth > view.width) {
            const maxX = Math.max(0, view.contentWidth - view.width);
            let targetX = view.contentX;
            if (rect.x - marginX < view.contentX) {
                targetX = rect.x - marginX;
            } else if (rect.x + marginX > view.contentX + view.width) {
                targetX = rect.x + marginX - view.width;
            }
            targetX = Math.max(0, Math.min(targetX, maxX));
            if (Math.abs(targetX - view.contentX) > 0.5) view.contentX = targetX;
        }
    }

    // Позиция конца строки (посре переноса) — для подсветки выбора.
    // Хлебные крошки: сегменты пути от корня конфига до файла. Если в
    // отведённую ширину не помещаются — оставляем хвост пути и ставим
    // многоточие вместо скрытого начала.
    // ------------------------------------------------- подсказки при наборе
    function currentExtension() {
        const name = root.currentFile.split("/").pop() || "";
        const dot = name.lastIndexOf(".");
        return dot > 0 ? name.substring(dot + 1).toLowerCase() : "";
    }

    // Слово прямо перед курсором — по нему ищем подсказки.
    function currentWordPrefix() {
        if (!editor) return "";
        const pos = Math.max(0, editor.cursorPosition);
        const before = root.rawText.substring(Math.max(0, pos - 120), pos);
        const match = before.match(/[A-Za-z_][A-Za-z0-9_.\-]*$/);
        return match ? match[0] : "";
    }

    // Готовые заготовки под язык файла.
    function snippetList(ext) {
        if (ext === "nix") {
            return [
                { label: "packages", insert: "packages = with pkgs; [ " },
                { label: "systemPackages", insert: "systemPackages = with pkgs; [ " },
                { label: "homePackages", insert: "home.packages = with pkgs; [ " },
                { label: "imports", insert: "imports = [ " },
                { label: "mkIf", insert: "mkIf (cond) { }" },
                { label: "mkMerge", insert: "mkMerge [ ]" },
                { label: "mkOption", insert: "mkOption { type = null; default = null; }" },
                { label: "mkEnableOption", insert: "mkEnableOption true" },
                { label: "mkForce", insert: "lib.mkForce " },
                { label: "mkDefault", insert: "lib.mkDefault " }
            ];
        }
        if (ext === "qml") {
            return [
                { label: "Connections", insert: "Connections {\n    function onTriggered() {\n    }\n}" },
                { label: "Repeater", insert: "Repeater {\n    model: []\n    delegate: null\n}" },
                { label: "Timer", insert: "Timer {\n    interval: 1000\n    running: true\n    repeat: true\n    onTriggered: {\n    }\n}" },
                { label: "MouseArea", insert: "MouseArea {\n    anchors.fill: parent\n    onClicked: {\n    }\n}" },
                { label: "StyledText", insert: "StyledText {\n    color: Appearance.colors.colOnLayer1\n}" },
                { label: "IconButton", insert: "IconButton {\n    iconText: \"\"\n    onClicked: {\n    }\n}" }
            ];
        }
        if (ext === "lua") {
            return [
                { label: "bind", insert: "bind = MOD, KEY, func, {\n}" },
                { label: "bindm", insert: "bindm = MOD, MOUSE, func, {\n}" },
                { label: "workspace", insert: "workspace = 1, monitor:" },
                { label: "monitor", insert: "monitor = , , , 1, transform = 0" }
            ];
        }
        return [];
    }

    function collectCompletions(prefix) {
        const lower = prefix.toLowerCase();
        const top = [];
        const rest = [];
        const subs = [];

        // слова из индекса конфига, в порядке убывания частоты
        for (let i = 0; i < root.wordIndex.length && top.length < 24; i++) {
            const word = root.wordIndex[i];
            const low = word.toLowerCase();
            // молчим только если слово совпадает с набранным один в один,
            // иначе Enter вместо перевода строки вставил бы то же самое
            if (word === prefix) continue;
            if (low.startsWith(lower)) {
                // отличие только в регистре (mkif -> mkIf): заготовка важнее
                // самого слова, поэтому такое слово уходит за сниппеты
                const caseOnly = low === lower;
                (top.length < 6 && !caseOnly ? top : rest).push({
                    label: word,
                    insert: word,
                    hint: "",
                    isSnippet: false
                });
            } else if (subs.length < 6 && word.length > lower.length + 2 && low.includes(lower)) {
                subs.push({ label: word, insert: word, hint: "", isSnippet: false });
            }
        }

        // Заготовки идут первыми: по префиксу вроде 'mk' слова забивают
        // весь список, и шаблон оказывался за пределами видимых строк.
        const snippets = [];
        for (const snip of root.snippetList(root.currentExtension())) {
            if (snip.label.toLowerCase().startsWith(lower)) {
                snippets.push({
                    label: snip.label,
                    insert: snip.insert,
                    hint: Translation.tr("snippet"),
                    isSnippet: true
                });
            }
        }
        return snippets.concat(top, rest, subs).slice(0, 24);
    }

    function updateCompletion() {
        if (root.suppressCompletion) {
            root.completionItems = [];
            return;
        }
        if (!editor || root.viewMode !== 0) {
            root.completionItems = [];
            return;
        }
        const prefix = root.currentWordPrefix();
        root.completionPrefix = prefix;
        if (prefix.length < 2 || root.completionDismissed === prefix) {
            root.completionItems = [];
            return;
        }
        // Слово набрано целиком и уже встречается в конфиге — не лезем с
        // подсказками, иначе Enter вместо перевода строки вставил бы слово
        // длиннее. Регистр при этом учитывается: mkif -> mkIf полезно.
        if (prefix.length >= 3 && root.wordIndex.indexOf(prefix) >= 0) {
            root.completionItems = [];
            return;
        }
        const items = root.collectCompletions(prefix);
        root.completionItems = items;
        root.completionIndex = 0;
    }

    function acceptCompletion(item) {
        const chosen = item || root.completionItems[root.completionIndex];
        if (!chosen || !editor) return;
        const pos = editor.cursorPosition;
        const start = Math.max(0, pos - root.completionPrefix.length);
        const insert = chosen.insert;
        // TextEdit.insert() в этой сборке Qt не работает — правим текст сами.
        root.suppressCompletion = true;
        editor.text = root.rawText.substring(0, start) + insert + root.rawText.substring(pos);
        editor.cursorPosition = start + insert.length;
        editor.forceActiveFocus();
        root.suppressCompletion = false;
        root.completionItems = [];
        root.completionManual = false;
        // чтобы список не выскочил сразу же на только что вставленное слово
        root.completionDismissed = root.currentWordPrefix();
    }

    function toggleCompletion() {
        if (root.completionItems.length > 0) {
            root.completionItems = [];
            root.completionManual = false;
            return;
        }
        const prefix = root.currentWordPrefix();
        if (prefix.length < 1) return;
        root.completionDismissed = "";
        root.completionManual = true;
        const items = root.collectCompletions(prefix);
        root.completionPrefix = prefix;
        root.completionItems = items;
        root.completionIndex = 0;
    }

    function closeCompletion() {
        if (root.completionPrefix.length > 0) root.completionDismissed = root.completionPrefix;
        root.completionItems = [];
        root.completionManual = false;
    }

    function moveCompletion(step) {
        const count = root.completionItems.length;
        if (count === 0) return;
        root.completionIndex = (root.completionIndex + step + count) % count;
    }

    // Результат фонового grep: "частота слово" -> просто слова.
    function applyIndex(text) {
        const out = [];
        const lines = (text || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            const space = line.indexOf(" ");
            if (space > 0) out.push(line.substring(space + 1));
        }
        root.wordIndex = out;
        root.indexReady = true;
    }

    function buildCrumbs(availWidth) {
        const out = [];
        if (root.currentFile.length === 0) return out;
        const parts = root.currentFile.split("/").filter(part => part.length > 0);
        if (parts.length === 0) return out;
        const chevron = 14;
        const pad = 8;
        const max = Math.max(80, availWidth - 12);
        let used = 0;
        for (let i = parts.length - 1; i >= 0; i--) {
            const width = editorFontMetrics.advanceWidth(parts[i]) + pad
                + (out.length > 0 ? chevron : 0);
            if (out.length > 0 && used + width > max) {
                out.unshift({ text: "…", path: "", ellipsis: true, isFile: false });
                break;
            }
            used += width;
            out.unshift({
                text: parts[i],
                path: parts.slice(0, i + 1).join("/"),
                ellipsis: false,
                isFile: i === parts.length - 1
            });
        }
        return out;
    }

    function lineEndPos(line) {
        const pos = root.lineStartPos(line);
        const nl = root.rawText.indexOf("\n", pos);
        return nl < 0 ? root.rawText.length : nl;
    }

    // Промотать редактор так, чтобы строка оказалась на ~трети высоты.
    function scrollToLine(line) {
        if (!editor) { console.log("[nixosConfig] scrollToLine: no editor"); return; }
        const start = Math.min(root.lineStartPos(line), editor.text.length);
        const end = Math.min(root.lineEndPos(line), editor.text.length);
        editor.cursorPosition = start;
        Qt.callLater(() => {
            const y = editor.cursorRectangle.y;
            const maxY = Math.max(0, editorScrollView.contentHeight - editorScrollView.height);
            editorScrollView.contentY = Math.max(0, Math.min(y - Math.max(0, editorScrollView.height / 3), maxY));
            console.log("[nixosConfig] scrollToLine line=" + line + " y=" + y + " start=" + start + " end=" + end);
            editor.select(start, end);
            if (lineFlashTimer) lineFlashTimer.restart();
        });
    }

    Timer { // мигание подсветки выбранного пакета
        id: lineFlashTimer
        interval: 1400
        repeat: false
        onTriggered: {
            if (editor) editor.deselect();
        }
    }

    function saveFile() {
        if (root.currentFile.length === 0) return;
        configFileView.setText(root.rawText);
        root.fileDirty = false;
        root.statusHint = Translation.tr("saving %1…").arg(root.currentFile);
    }

    // Push the current file contents into the editor. The editor always keeps
    // plain text (so it stays editable and tabs survive); syntax highlighting
    // is overlaid via formattedText. No QML binding fights typing because the
    // text is pushed programmatically with a syncingText guard.
    function applyEditorText() {
        if (root.loading || !editor) return;
        root.syncingText = true;
        editor.textFormat = TextEdit.PlainText;
        editor.text = root.rawText;
        root.syncingText = false;
    }

    // ---------------------------------------------------------------- build
    function performBuild(full) {
        NixosConfigBuild.performBuild(full);
        root.showConsole = true;
    }

    function cancelBuild() {
        NixosConfigBuild.cancelBuild();
    }

    // ---------------------------------------------------------------- syntax
    function escapeHtml(str) {
        return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    }

    function highlightNix(raw) {
        if (raw === undefined || raw === null) return "";
        const keywords = ["assert", "else", "if", "in", "inherit", "let", "or", "rec", "then", "with", "true", "false", "null"];
        const dark = Appearance.m3colors.darkmode;
        const col = {
            default: dark ? "#c9d1d9" : "#37474f",
            comment: dark ? "#6e7681" : "#90a4ae",
            keyword: dark ? "#c792ea" : "#7c4dff",
            string: dark ? "#8bffce" : "#00897b",
            number: dark ? "#f78c6c" : "#e65100",
            builtin: dark ? "#82aaff" : "#1565c0",
            attr: dark ? "#e2c792" : "#bf360c"
        };
        const esc = (s) => root.escapeHtml(s).replace(/\t/g, Array(root.tabSize + 1).join("&nbsp;")).replace(/ /g, "&nbsp;");
        const span = (color, inside) => `<span style="color:${color};">` + inside + `</span>`;
        const nl = raw.replace(/\r\n?/g, "\n");
        let out = "";
        let i = 0;
        const n = nl.length;
        while (i < n) {
            const ch = nl[i];
            if (ch === "#") { // comment to EOL
                const j = nl.indexOf("\n", i);
                const end = j === -1 ? n : j;
                out += span(col.comment, esc(nl.substring(i, end)));
                i = end;
                continue;
            }
            if (ch === "\"") { // double quoted string with ${...}
                let j = i + 1;
                let brace = 0;
                while (j < n) {
                    const c = nl[j];
                    if (c === "\\") { j += 2; continue; }
                    if (c === "$" && nl[j + 1] === "{") { brace++; j += 2; continue; }
                    if (c === "{") { brace++; j++; continue; }
                    if (c === "}") { if (brace > 0) brace--; j++; continue; }
                    if (c === "\"" && brace === 0) { j++; break; }
                    j++;
                }
                out += span(col.string, esc(nl.substring(i, j)));
                i = j;
                continue;
            }
            if (ch === "'" && nl[i + 1] === "'") { // '' multiline string
                const close = nl.indexOf("''", i + 2);
                const j = close === -1 ? n : close + 2;
                out += span(col.string, esc(nl.substring(i, j)));
                i = j;
                continue;
            }
            if (/[0-9]/.test(ch)) { // numbers
                let j = i;
                while (j < n && /[0-9a-zA-Z]/.test(nl[j])) j++;
                out += span(col.number, esc(nl.substring(i, j)));
                i = j;
                continue;
            }
            if (/[a-zA-Z_]/.test(ch)) { // idents / keywords / builtins / attr names
                let j = i;
                while (j < n && /[a-zA-Z0-9_'\-*.]/.test(nl[j])) j++;
                const word = nl.substring(i, j);
                if (keywords.indexOf(word) !== -1) {
                    out += span(col.keyword, esc(word));
                } else if (word === "builtins" || word.startsWith("builtins.")) {
                    out += span(col.builtin, esc(word));
                } else {
                    let k = j;
                    while (k < n && /\s/.test(nl[k])) k++;
                    const isAttrName = k < n && nl[k] === "=";
                    out += span(isAttrName ? col.attr : col.default, esc(word));
                }
                i = j;
                continue;
            }
            out += (ch === "\n") ? ch : esc(ch);
            i++;
        }
        return out.replace(/\n/g, "<br>");
    }

    function highlightLog(raw) {
        if (raw === undefined || raw === null) return "";
        const dark = Appearance.m3colors.darkmode;
        const c = {
            head: dark ? "#82aaff" : "#1565c0",
            build: dark ? "#79c0ff" : "#0d47a1",
            store: dark ? "#56d364" : "#2e7d32",
            err: dark ? "#ff7b72" : "#c62828",
            warn: dark ? "#e3b341" : "#f9a825"
        };
        const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        const span = (color, inside) => `<span style="color:${color};">` + inside + `</span>`;
        const storeRe = /\/nix\/store\/[a-z0-9]{32}-[^ \t"<>]+/g;
        const out = [];
        for (const rawLine of raw.split("\n")) {
            let html = esc(rawLine).replace(storeRe, (m) => span(c.store, m));
            const line = rawLine.toLowerCase();
            if (line.indexOf("error") !== -1 || line.indexOf("failed") !== -1) {
                html = span(c.err, html);
            } else if (line.indexOf("warning") !== -1 || line.indexOf("warn ") !== -1) {
                html = span(c.warn, html);
            } else if (line.startsWith("==>")) {
                html = span(c.head, html);
            } else if (line.startsWith("building") || line.startsWith("downloading")
                       || line.startsWith("copying") || line.startsWith("activating")
                       || line.startsWith("setting up")) {
                html = span(c.build, html);
            }
            out.push(html);
        }
        return out.join("<br>");
    }

    // Measures one monospace space, so tabWidth matches the editor's font.
    FontMetrics {
        id: editorFontMetrics
        font {
            family: Appearance.font.family.monospace
            pixelSize: Appearance.font.pixelSize.smallie
        }
    }

    // ================================================================ layout
    StyledRectangularShadow {
        target: contentBackground
    }
    Rectangle {
        id: contentBackground
        anchors.fill: parent
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

        ColumnLayout {
            anchors {
                fill: parent
                margins: 10
            }
            spacing: 8

            RowLayout { // ================================================ main
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                // ------------------------------------------------- tree
                Rectangle {
                    id: treeRect
                    // В узком окне отдаём место центральной колонке,
                    // иначе тулбар и панель сервиса сжимаются в 180px.
                    Layout.preferredWidth: root.width < 1200 ? 220 : 300
                    Layout.fillHeight: true
                    radius: contentBackground.radius - 10
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        id: treeCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        RowLayout { // header
                            id: treeHeader
                            Layout.fillWidth: true
                            spacing: 6

                            MaterialSymbol {
                                text: "data_object"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                font {
                                    pixelSize: Appearance.font.pixelSize.normal
                                    weight: Font.Medium
                                }
                                color: Appearance.colors.colOnLayer1
                                text: Translation.tr("NixOS Config")
                            }
                            Rectangle { // branch chip
                                visible: root.branch.length > 0
                                radius: height / 2
                                color: Appearance.colors.colSecondaryContainer
                                implicitWidth: branchLabel.implicitWidth + 16
                                height: 22
                                StyledText {
                                    id: branchLabel
                                    anchors.centerIn: parent
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnSecondaryContainer
                                    text: root.branch
                                }
                            }
                        }

                        StyledText { // status line
                            id: treeStatus
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnLayer1
                            opacity: 0.8
                            text: root.statusHint
                        }

                        RowLayout {
                            id: treeFilterRow
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36
                            Layout.maximumHeight: 36
                            Layout.minimumHeight: 36
                            spacing: 2

                            ToolbarTextField {
                                id: filterField
                                Layout.fillWidth: true
                                placeholderText: Translation.tr("Search files…")
                                font.pixelSize: Appearance.font.pixelSize.small
                                onTextChanged: {
                                    root.filterText = text;
                                    root.applyFilter();
                                }
                            }
                            IconToolbarButton {
                                implicitWidth: height
                                text: "refresh"
                                onClicked: root.refreshGit()
                                StyledToolTip { text: Translation.tr("Reload git tree") }
                            }
                        }

                        Item {
                            id: treeItem
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            ListView {
                                id: treeView
                                anchors.fill: parent
                                clip: true
                                interactive: true
                                spacing: 1
                                ScrollBar.vertical: StyledScrollBar {}

                                model: root.treeRows

                            delegate: MouseArea {
                                required property var modelData
                                height: 28
                                width: treeView.width
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 6
                                    color: modelData.isDir ? "transparent"
                                        : (root.currentFile === modelData.path) ? Appearance.colors.colPrimary
                                        : (containsMouse ? Appearance.colors.colLayer0 : "transparent")
                                }

                                RowLayout {
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        leftMargin: 6 + modelData.depth * 14
                                        rightMargin: 6
                                        verticalCenter: parent.verticalCenter
                                    }
                                    spacing: 4

                                    MaterialSymbol {
                                        text: modelData.isDir ? "folder" : (root.currentFile === modelData.path ? "description" : "draft")
                                        iconSize: 16
                                        color: modelData.isDir
                                            ? Appearance.colors.colOnLayer1
                                            : (root.currentFile === modelData.path ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1)
                                        opacity: modelData.isDir ? 0.6 : 0.9
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: modelData.isDir
                                            ? Appearance.colors.colOnLayer1
                                            : (root.currentFile === modelData.path ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1)
                                        text: modelData.name
                                        opacity: modelData.isDir ? 0.85 : 1
                                    }
                                    StyledText { // dirty marker
                                        visible: !modelData.isDir && modelData.status.length > 0
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: modelData.status === "??" ? Appearance.m3colors.m3error
                                            : Appearance.colors.colOnLayer1
                                        text: modelData.status === "??" ? "U" : "*"
                                    }
                                }

                                onClicked: {
                                    if (!modelData.isDir) root.selectFile(modelData.path);
                                }
                            }
                            }
                        }
                        Rectangle { // ------------------------------------ git status
                            // Компактная сводка git внизу дерева: сколько файлов в
                            // индексе, сколько изменено, сколько новых и на сколько
                            // коммитов мы впереди/отстаём от upstream.
                            id: gitStatusBar
                            implicitWidth: 0
                            implicitHeight: 0
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredHeight: 26
                            Layout.minimumHeight: 26
                            Layout.maximumHeight: 26
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colLayer0

                            RowLayout { // -------------------------------------- chips
                                id: gitChips
                                anchors {
                                    fill: parent
                                    margins: 2
                                }
                                spacing: 1

                                IconAndTextToolbarButton {
                                    implicitHeight: 20
                                    iconSize: 13
                                    fontPixelSize: Appearance.font.pixelSize.smallest
                                    contentSpacing: 3
                                    iconText: "check"
                                    opacity: root.stagedCount > 0 ? 1 : 0.4
                                    colText: root.stagedCount > 0 ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                                    text: root.stagedCount.toString()
                                    StyledToolTip { text: Translation.tr("Staged (in index)") }
                                }
                                IconAndTextToolbarButton {
                                    implicitHeight: 20
                                    iconSize: 13
                                    fontPixelSize: Appearance.font.pixelSize.smallest
                                    contentSpacing: 3
                                    iconText: "edit"
                                    opacity: root.modifiedCount > 0 ? 1 : 0.4
                                    colText: root.modifiedCount > 0 ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                                    text: root.modifiedCount.toString()
                                    StyledToolTip { text: Translation.tr("Modified in worktree") }
                                }
                                IconAndTextToolbarButton {
                                    implicitHeight: 20
                                    iconSize: 13
                                    fontPixelSize: Appearance.font.pixelSize.smallest
                                    contentSpacing: 3
                                    iconText: "help"
                                    opacity: root.untrackedCount > 0 ? 1 : 0.4
                                    colText: root.untrackedCount > 0 ? Appearance.m3colors.m3outline : Appearance.colors.colOnLayer1
                                    text: root.untrackedCount.toString()
                                    StyledToolTip { text: Translation.tr("Untracked files") }
                                }
                                IconAndTextToolbarButton {
                                    implicitHeight: 20
                                    iconSize: 13
                                    fontPixelSize: Appearance.font.pixelSize.smallest
                                    contentSpacing: 3
                                    iconText: "arrow_upward"
                                    opacity: root.aheadCount > 0 ? 1 : 0.4
                                    colText: root.aheadCount > 0 ? Appearance.m3colors.m3tertiary : Appearance.colors.colOnLayer1
                                    text: root.aheadCount.toString()
                                    StyledToolTip { text: Translation.tr("Commits ahead of upstream") }
                                }
                                IconAndTextToolbarButton {
                                    implicitHeight: 20
                                    iconSize: 13
                                    fontPixelSize: Appearance.font.pixelSize.smallest
                                    contentSpacing: 3
                                    iconText: "arrow_downward"
                                    opacity: root.behindCount > 0 ? 1 : 0.4
                                    colText: root.behindCount > 0 ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                                    text: root.behindCount.toString()
                                    StyledToolTip { text: Translation.tr("Commits behind upstream") }
                                }
                            }
                        }
                    }
                }

                // ------------------------------------------------- editor + console
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    Rectangle { // --------------------------------- toolbar
                        // Единый вид с панелью сервиса: те же
                        // IconAndTextToolbarButton (иконка + подпись), тот же
                        // радиус и цвета. Кнопки делят ширину плашки поровну
                        // (Layout.fillWidth), поэтому ряд всегда ровный.
                        // Если места на подпись не хватает — остаются иконки.
                        id: editorToolbar
                        visible: root.viewMode === 0
                        property int gap: 6
                        readonly property int buttonCount: 7
                        readonly property real slotWidth: (width - 8 - gap * (buttonCount - 1)) / buttonCount
                        readonly property bool compact: slotWidth < 125
                        implicitWidth: 0
                        implicitHeight: 0
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredHeight: 40
                        Layout.minimumHeight: 40
                        Layout.maximumHeight: 40
                        radius: contentBackground.radius - 10
                        color: Appearance.colors.colLayer1
                        clip: true

                        RowLayout {
                            id: editorToolbarFlow
                            anchors {
                                fill: parent
                                margins: 4
                            }
                            spacing: editorToolbar.gap

                            IconAndTextToolbarButton {
                                implicitHeight: 32
                                Layout.fillWidth: true
                                Layout.minimumWidth: 38
                                iconText: "save"
                                text: editorToolbar.compact ? "" : Translation.tr("Save file")
                                enabled: root.currentFile.length > 0
                                onClicked: root.saveFile()
                                StyledToolTip { text: Translation.tr("Save file (Ctrl+S)") }
                            }

                            IconAndTextToolbarButton {
                                implicitHeight: 32
                                Layout.fillWidth: true
                                Layout.minimumWidth: 38
                                iconText: "bolt"
                                text: editorToolbar.compact ? "" : Translation.tr("Quick build")
                                enabled: !root.building
                                onClicked: root.performBuild(false)
                                StyledToolTip { text: Translation.tr("Quick rebuild: ./update.sh --quick (polykit)") }
                            }
                            IconAndTextToolbarButton {
                                implicitHeight: 32
                                Layout.fillWidth: true
                                Layout.minimumWidth: 38
                                iconText: "system_update"
                                text: editorToolbar.compact ? "" : Translation.tr("Full build")
                                enabled: !root.building
                                onClicked: root.performBuild(true)
                                StyledToolTip { text: Translation.tr("Full update & rebuild: ./update.sh (polykit)") }
                            }
                            IconAndTextToolbarButton {
                                implicitHeight: 32
                                Layout.fillWidth: true
                                Layout.minimumWidth: 38
                                iconText: "stop"
                                text: editorToolbar.compact ? "" : Translation.tr("Cancel build")
                                enabled: root.building
                                onClicked: root.cancelBuild()
                                StyledToolTip { text: Translation.tr("Send SIGTERM to the build") }
                            }

                            IconAndTextToolbarButton {
                                implicitHeight: 32
                                Layout.fillWidth: true
                                Layout.minimumWidth: 38
                                iconText: "folder_open"
                                text: editorToolbar.compact ? "" : Translation.tr("Open folder")
                                onClicked: {
                                    const dir = root.currentFile.length > 0
                                        ? `${root.configRoot}/${root.currentFile}`
                                        : root.configRoot;
                                    Quickshell.execDetached(["xdg-open", root.currentFile.length > 0 ? dir.substring(0, dir.lastIndexOf("/")) : dir]);
                                }
                                StyledToolTip { text: Translation.tr("Open folder in file manager") }
                            }
                            IconAndTextToolbarButton {
                                implicitHeight: 32
                                Layout.fillWidth: true
                                Layout.minimumWidth: 38
                                iconText: "terminal"
                                text: editorToolbar.compact ? "" : Translation.tr("Build console")
                                toggled: root.showConsole
                                onClicked: root.showConsole = !root.showConsole
                                StyledToolTip { text: Translation.tr("Toggle build console") }
                            }
                            IconAndTextToolbarButton {
                                implicitHeight: 32
                                Layout.fillWidth: true
                                Layout.minimumWidth: 38
                                iconText: "clear_all"
                                text: editorToolbar.compact ? "" : Translation.tr("Clear build log")
                                onClicked: NixosConfigBuild.clearLog()
                                StyledToolTip { text: Translation.tr("Clear console") }
                            }
                        }
                    }

                    // ------------------------------------------------- editor
                    Rectangle {
                        id: editorBackground
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: contentBackground.radius - 10
                        color: Appearance.colors.colLayer1

                        Flickable {
                            id: editorScrollView
                            visible: root.viewMode === 0
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: breadcrumbRow.visible ? breadcrumbRow.bottom : parent.top
                                bottom: parent.bottom
                                leftMargin: 2
                                rightMargin: 2
                                topMargin: breadcrumbRow.visible ? 1 : 2
                                bottomMargin: 2
                            }
                            clip: true
                            ScrollBar.horizontal: StyledScrollBar {}
                            ScrollBar.vertical: StyledScrollBar {}

                            // The single outer Flickable owns all scrolling. content
                            // is the max of the two auto-grown layers, so both stack
                            // as children and their positions are driven together.
                            contentWidth: Math.max(highlightLayer.contentWidth, editor.contentWidth)
                            contentHeight: Math.max(highlightLayer.contentHeight, editor.contentHeight)

                            // Подсветка строки, где стоит курсор: на всю ширину
                            // редактора, поверх фона, но под текстом.
                            Rectangle {
                                id: cursorLineBand
                                visible: root.viewMode === 0 && root.currentFile.length > 0
                                    && root.rawText.length > 0
                                x: 0
                                // Прямоугольник курсора — реальная геометрия
                                // строки в текстовом документе (FontMetrics.lineSpacing
                                // на px меньше фактического шага строк).
                                y: Math.max(0, editor.cursorRectangle.y)
                                width: Math.max(editorScrollView.contentWidth, editorScrollView.width)
                                height: root.lineAdvance
                                // colLayer1Hover не годится: при прозрачности темы
                                // его alpha ≈ 0.017, полоса была невидима при любой
                                // opacity. Берём непрозрачный акцент темы и гасим его
                                // alpha — мягкая, но отчётливая подсветка строки.
                                color: Appearance.colors.colPrimary
                                opacity: 0.15
                            }

                            // Always-on syntax highlight via two stacked TextEdit
                            // layers (formattedText does not exist in this Qt build,
                            // so no property binding for it). Both layers grow to
                            // their own full content size and do NOT scroll on their
                            // own; the single outer Flickable scrolls them together,
                            // so scrolling/selection/tab widths stay in sync with
                            // zero manual scroll bindings. The bottom layer draws
                            // the RichText highlight; the top one is the editable
                            // PlainText whose glyph color is transparent but cursor
                            // and selection stay visible on top of the highlight.
                            TextEdit {
                                id: highlightLayer
                                x: 0
                                y: 0
                                visible: !root.loading && root.rawText.length > 0
                                readOnly: true
                                selectByMouse: false
                                focus: false
                                textFormat: TextEdit.RichText
                                wrapMode: TextEdit.NoWrap
                                font {
                                    family: Appearance.font.family.monospace
                                    pixelSize: Appearance.font.pixelSize.smallie
                                }
                                tabStopDistance: root.tabWidth
                                leftPadding: lineGutter.width
                                color: Appearance.colors.colOnLayer1
                                text: root.rawText.length > 0 ? root.highlightNix(root.rawText) : ""
                            }

                            TextEdit {
                                id: editor
                                x: 0
                                y: 0
                                visible: !root.loading && root.viewMode === 0
                                focus: root.viewMode === 0
                                persistentSelection: true
                                selectByMouse: true
                                textFormat: TextEdit.PlainText
                                wrapMode: TextEdit.NoWrap
                                font {
                                    family: Appearance.font.family.monospace
                                    pixelSize: Appearance.font.pixelSize.smallie
                                }
                                tabStopDistance: root.tabWidth
                                leftPadding: lineGutter.width
                                color: "transparent"
                                cursorDelegate: Rectangle {
                                    width: 2
                                    color: Appearance.colors.colOnLayer1
                                }
                                selectionColor: Appearance.colors.colLayer1

                                onTextChanged: {
                                    if (!root.loading && !root.syncingText) {
                                        root.fileDirty = true;
                                        if (editor.text !== root.rawText) root.rawText = editor.text;
                                    }
                                    root.cursorLine = root.lineOfPosition(cursorPosition);
                                    // cursorPosition ещё старый: пересчёт после
                                    // того, как курсор встанет на место.
                                    Qt.callLater(root.updateCompletion);
                                }
                                onCursorPositionChanged: {
                                    root.cursorLine = root.lineOfPosition(cursorPosition);
                                    root.ensureCursorVisible();
                                    root.updateCompletion();
                                }
                                onActiveFocusChanged: {
                                    if (!activeFocus) {
                                        root.completionItems = [];
                                        root.completionManual = false;
                                    }
                                }
                            }
                        }

                        // Хлебные крошки пути к файлу: клик по папке открывает
                        // её в файловом менеджере, имя файла — текущее.
                        Item {
                            id: breadcrumbRow
                            visible: root.viewMode === 0 && root.currentFile.length > 0
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                leftMargin: 2
                                rightMargin: 2
                                topMargin: 2
                            }
                            height: 28
                            readonly property var crumbs: root.buildCrumbs(width)

                            Rectangle { // тонкая линия под крошками
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    bottom: parent.bottom
                                }
                                height: 1
                                color: Appearance.colors.colOnLayer1
                                opacity: 0.12
                            }

                            Row {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    leftMargin: 6
                                    rightMargin: 6
                                    verticalCenter: parent.verticalCenter
                                    verticalCenterOffset: -1
                                }
                                spacing: 0

                                Repeater {
                                    model: breadcrumbRow.crumbs
                                    delegate: Row {
                                        id: crumb
                                        required property var modelData
                                        required property int index
                                        height: breadcrumbRow.height
                                        spacing: 0

                                        MaterialSymbol {
                                            visible: crumb.index > 0
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 14
                                            text: "chevron_right"
                                            iconSize: 12
                                            color: Appearance.colors.colOnLayer1
                                            opacity: 0.35
                                        }

                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            leftPadding: 4
                                            rightPadding: 4
                                            font {
                                                family: Appearance.font.family.monospace
                                                pixelSize: Appearance.font.pixelSize.smallie
                                            }
                                            color: Appearance.colors.colOnLayer1
                                            opacity: crumb.modelData.ellipsis
                                                ? 0.35
                                                : (crumbClick.containsMouse
                                                    ? 1
                                                    : (crumb.modelData.isFile ? 0.9 : 0.55))
                                            text: crumb.modelData.text

                                            MouseArea {
                                                id: crumbClick
                                                anchors.fill: parent
                                                enabled: !crumb.modelData.ellipsis
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    Quickshell.execDetached([
                                                        "xdg-open",
                                                        `${root.configRoot}/${crumb.modelData.path}`
                                                    ]);
                                                }
                                                StyledToolTip {
                                                    text: crumb.modelData.isFile
                                                        ? `${root.configRoot}/${crumb.modelData.path}`
                                                        : Translation.tr("Open folder in file manager")
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Левая колонка с номерами строк. Неподвижна по
                        // горизонтали (скроллится только сам текст), по
                        // вертикали синхронна с редактором через contentY.
                        // Фон непрозрачный — уезжающий влево текст уходит под
                        // него, поэтому leftPadding у обоих слоёв = его ширина.
                        Rectangle {
                            id: lineGutter
                            visible: root.viewMode === 0 && root.rawText.length > 0
                            anchors {
                                left: editorScrollView.left
                                top: editorScrollView.top
                                bottom: editorScrollView.bottom
                            }
                            width: root.gutterWidth
                            color: Appearance.colors.colLayer1
                            clip: true

                            Repeater {
                                model: root.totalLines
                                delegate: StyledText {
                                    required property int index
                                    readonly property int lineNo: index + 1
                                    x: 0
                                    y: lineNo * root.lineAdvance - root.lineAdvance - editorScrollView.contentY
                                    width: lineGutter.width
                                    height: root.lineAdvance
                                    horizontalAlignment: Text.AlignRight
                                    rightPadding: 10
                                    visible: y > -root.lineAdvance && y < lineGutter.height
                                    font {
                                        family: Appearance.font.family.monospace
                                        pixelSize: Appearance.font.pixelSize.smallie
                                    }
                                    color: Appearance.colors.colOnLayer1
                                    // Номер текущей строки — заметнее остальных.
                                    opacity: lineNo === root.cursorLine ? 0.95 : 0.4
                                    text: lineNo
                                }
                            }
                        }

                        // Счётчик строк: номер строки курсора и всего файла.
                        Rectangle {
                            id: lineCounter
                            visible: root.viewMode === 0 && root.rawText.length > 0
                            anchors {
                                right: parent.right
                                bottom: parent.bottom
                                rightMargin: 10
                                bottomMargin: 10
                            }
                            implicitWidth: lineCounterRow.implicitWidth + 16
                            implicitHeight: 22
                            radius: height / 2
                            color: Appearance.colors.colLayer0

                            RowLayout {
                                id: lineCounterRow
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialSymbol {
                                    text: "format_list_numbered"
                                    iconSize: 14
                                    color: Appearance.colors.colOnLayer1
                                    opacity: 0.7
                                }
                                StyledText {
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnLayer1
                                    text: Translation.tr("Line %1 of %2")
                                        .arg(root.cursorLine)
                                        .arg(root.totalLines)
                                }
                            }
                        }

                        // Подсказки при наборе: список под курсором. Открывается сам
                        // по набранному префиксу (2+ символа), Enter вставляет,
                        // Esc скрывает до смены слова. По Ctrl+Space включается
                        // ручной режим, где стрелки листают список.
                        Rectangle {
                            id: completionPopup
                            visible: root.completionItems.length > 0 && root.viewMode === 0
                            width: 440
                            height: Math.min(root.completionItems.length, root.completionMaxVisible) * 28
                                + (root.completionItems.length > 0 ? 30 : 0)
                            radius: contentBackground.radius - 6
                            color: Appearance.colors.colLayer0
                            border {
                                width: 1
                                // у группы border нет opacity — задаём alpha в цвете
                                color: Qt.rgba(
                                    Appearance.colors.colOnLayer1.r,
                                    Appearance.colors.colOnLayer1.g,
                                    Appearance.colors.colOnLayer1.b,
                                    0.15)
                            }
                            z: 50
                            x: Math.max(2, Math.min(
                                editor.cursorRectangle.x - editorScrollView.contentX,
                                editorBackground.width - width - 2))
                            y: {
                                const below = editor.cursorRectangle.y - editorScrollView.contentY
                                    + root.lineAdvance + 4;
                                const fits = below + height < editorBackground.height - 2;
                                return Math.max(2, fits
                                    ? below
                                    : (editor.cursorRectangle.y - editorScrollView.contentY - height - 4));
                            }

                            Column {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                    margins: 4
                                }
                                spacing: 0

                                Repeater {
                                    // весь список, но видны только 8 строк вокруг
                                    // выбранного — так можно доскроллить до любого
                                    model: root.completionItems
                                    delegate: Rectangle {
                                        id: completionRow
                                        required property var modelData
                                        required property int index
                                        width: completionPopup.width - 8
                                        height: 28
                                        readonly property int windowStart: Math.max(0,
                                            Math.min(root.completionIndex - root.completionMaxVisible + 1,
                                                Math.max(0, root.completionItems.length - root.completionMaxVisible)))
                                        visible: index >= windowStart
                                            && index < windowStart + root.completionMaxVisible
                                        radius: 6
                                        color: index === root.completionIndex
                                            ? Qt.rgba(
                                                Appearance.colors.colPrimary.r,
                                                Appearance.colors.colPrimary.g,
                                                Appearance.colors.colPrimary.b,
                                                0.28)
                                            : "transparent"

                                        StyledText {
                                            id: completionLabel
                                            anchors {
                                                left: parent.left
                                                right: completionHint.left
                                                leftMargin: 8
                                                rightMargin: 6
                                                verticalCenter: parent.verticalCenter
                                            }
                                            font {
                                                family: Appearance.font.family.monospace
                                                pixelSize: Appearance.font.pixelSize.smallie
                                            }
                                            elide: Text.ElideRight
                                            color: Appearance.colors.colOnLayer1
                                            text: completionRow.modelData.label
                                        }

                                        StyledText {
                                            id: completionHint
                                            anchors {
                                                right: parent.right
                                                rightMargin: 8
                                                verticalCenter: parent.verticalCenter
                                            }
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colOnLayer1
                                            opacity: 0.5
                                            text: completionRow.modelData.hint
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onEntered: root.completionIndex = completionRow.index
                                            onClicked: {
                                                root.completionManual = false;
                                                root.acceptCompletion(completionRow.modelData);
                                            }
                                        }
                                    }
                                }

                                StyledText { // подсказка про клавиши
                                    width: completionPopup.width - 16
                                    height: 22
                                    horizontalAlignment: Text.AlignRight
                                    rightPadding: 6
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnLayer1
                                    opacity: 0.45
                                    text: `${root.completionIndex + 1}/${root.completionItems.length} · `
                                        + (root.completionManual
                                            ? Translation.tr("↑↓ — select, Enter — insert, Esc — hide")
                                            : Translation.tr("Enter — insert, Esc — hide"))
                                }
                            }
                        }

                        Shortcut {
                            sequences: ["Ctrl+Space"]
                            onActivated: root.toggleCompletion()
                        }
                        Shortcut {
                            sequence: "Return"
                            enabled: root.completionItems.length > 0
                            onActivated: root.acceptCompletion()
                        }
                        // Tab тоже применяет подсказку/сниппет, пока список открыт
                        Shortcut {
                            sequence: "Tab"
                            enabled: root.completionItems.length > 0
                            onActivated: root.acceptCompletion()
                        }
                        Shortcut {
                            sequence: "Escape"
                            enabled: root.completionItems.length > 0
                            onActivated: root.closeCompletion()
                        }
                        Shortcut {
                            sequences: ["Down"]
                            enabled: root.completionManual && root.completionItems.length > 0
                            onActivated: root.moveCompletion(1)
                        }
                        Shortcut {
                            sequences: ["Up"]
                            enabled: root.completionManual && root.completionItems.length > 0
                            onActivated: root.moveCompletion(-1)
                        }
                        // в авторежиме стрелки остаются у текста, поэтому выбор
                        // варианта — на Ctrl+стрелки
                        Shortcut {
                            sequences: ["Ctrl+Down"]
                            enabled: root.completionItems.length > 0
                            onActivated: root.moveCompletion(1)
                        }
                        Shortcut {
                            sequences: ["Ctrl+Up"]
                            enabled: root.completionItems.length > 0
                            onActivated: root.moveCompletion(-1)
                        }

                        // Панель сервиса занимает ту же область, что и редактор:
                        // viewMode 0 — файл, 1 — systemd-юнит.
                        NixosConfigServicePanel {
                            id: servicePanel
                            visible: root.viewMode === 1
                            anchors.fill: parent
                            anchors.margins: 2

                            onBackRequested: root.showFile()
                            onOpenConfigRequested: (path, line) => {
                                root.openPackage(path, line);
                            }
                        }
                    }

                    // ------------------------------------------------- console
                    Rectangle {
                        id: consoleBackground
                        // В режиме сервиса консоль сборки только мешает —
                        // у панели юнита своя область логов.
                        visible: root.showConsole && root.viewMode === 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 180
                        radius: contentBackground.radius - 10
                        color: Appearance.colors.colLayer1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                StyledText {
                                    Layout.fillWidth: true
                                    font {
                                        pixelSize: Appearance.font.pixelSize.smallest
                                        weight: Font.Medium
                                    }
                                    color: Appearance.colors.colOnLayer1
                                    text: root.building
                                        ? `⟳ ${Translation.tr("building…")}`
                                        : (root.lastBuildExit === null
                                            ? Translation.tr("console")
                                            : Translation.tr("exited %1").arg(root.lastBuildExit))
                                }
                                StyledText {
                                    visible: root.lastBuildExit === 0
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.m3colors.m3tertiary
                                    text: Translation.tr("ok")
                                }
                                StyledText {
                                    visible: root.lastBuildExit !== null && root.lastBuildExit !== 0
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.m3colors.m3error
                                    text: Translation.tr("failed")
                                }
                            }

                            ScrollView {
                                id: consoleScrollView
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                ScrollBar.vertical: StyledScrollBar {
                                    id: consoleScrollBar
                                }

                                StyledTextArea {
                                    id: consoleArea
                                    readOnly: true
                                    textFormat: TextEdit.RichText
                                    font {
                                        family: Appearance.font.family.monospace
                                        pixelSize: 12
                                    }
                                    color: Appearance.colors.colOnLayer1
                                    wrapMode: TextEdit.Wrap
                                    text: root.highlightLog(root.logText)
                                }
                            }
                        }
                    }
                }

                NixosConfigSidebar {
                    id: rightSidebar
                    Layout.fillHeight: true
                    Layout.preferredWidth: root.width < 1200 ? 240 : 300
                    onPackageClicked: (path, line) => {
                        console.log("[nixosConfig] packageClicked signal", path, line);
                        root.openPackage(path, line);
                    }
                    onServiceClicked: (unit, scope, path, line) => {
                        console.log("[nixosConfig] serviceClicked signal", unit, scope, path, line);
                        root.openService(unit, scope, path, line);
                    }
                }
            }
        }
    }

    // unsaved-changes hint
    Rectangle {
        visible: root.fileDirty
        anchors {
            bottom: contentBackground.bottom
            horizontalCenter: contentBackground.horizontalCenter
            bottomMargin: 14
        }
        radius: 4
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        StyledText {
            anchors.fill: parent
            anchors.margins: 6
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.smallest
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Unsaved changes")
        }
    }

    // ================================================================ processes
    Process {
        id: gitProc
        command: ["bash", "-c", "cd /etc/nixos && git status --short --untracked-files=all; printf '\\n__LS__\\n'; git ls-files; printf '\\n__BR__\\n'; git branch --show-current; printf '\\n__AB__\\n'; (git rev-list --count '@{u}..HEAD' 2>/dev/null || printf 0); printf '\\n'; (git rev-list --count 'HEAD..@{u}' 2>/dev/null || printf 0)"]
        stdout: StdioCollector {
            id: gitCollector
            waitForEnd: true
            onStreamFinished: {
                try {
                    root.parseGitOutput(gitCollector.text);
                } catch (e) {
                    console.log("[nixosConfig] PARSE ERROR:", e);
                    console.log(e.stack ?? "");
                }
            }
        }
    }

    FileView {
        id: configFileView
        path: ""
        watchChanges: true
        onLoaded: {
            if (configFileView.path.length === 0 || configFileView.path !== root.currentFilePath()) return;
            root.loading = false;
            root.rawText = configFileView.text();
            root.applyEditorText();
            root.fileDirty = false;
            if (root.pendingLine > 0) {
                const ln = root.pendingLine;
                root.pendingLine = 0;
                Qt.callLater(() => root.scrollToLine(ln));
            }
        }
        onLoadFailed: (error) => {
            if (configFileView.path.length === 0 || configFileView.path !== root.currentFilePath()) return;
            root.loading = false;
            root.rawText = "";
            root.applyEditorText();
            if (error === FileViewError.FileNotFound) {
                root.statusHint = Translation.tr("no such file: %1").arg(configFileView.path);
            }
        }
        onSaved: {
            root.statusHint = Translation.tr("saved: %1").arg(root.currentFile);
            root.fileDirty = false;
            root.refreshGit();
        }
        onSaveFailed: (error) => {
            root.statusHint = Translation.tr("failed to save: %1")
                .arg(FileViewError.toString(error));
            root.fileDirty = true;
        }
    }

    // Auto-scroll the build console to the bottom on new output.
    onLogTextChanged: {
        Qt.callLater(function () {
            if (consoleScrollBar.size > 0) {
                consoleScrollBar.position = 1.0 - consoleScrollBar.size;
            }
        });
    }

    // ================================================================ focus
    Connections {
        target: NixosConfigBuild
        function onBuildStarted() {
            root.showConsole = true;
            root.statusHint = NixosConfigBuild.statusHint;
        }
        function onBuildFinished(exitCode) {
            root.statusHint = NixosConfigBuild.statusHint;
        }
    }

    Connections {
        target: GlobalStates
        function onNixosConfigOpenChanged() {
            if (GlobalStates.nixosConfigOpen && root.filterField) {
                root.filterField.forceActiveFocus();
            }
        }
    }
}