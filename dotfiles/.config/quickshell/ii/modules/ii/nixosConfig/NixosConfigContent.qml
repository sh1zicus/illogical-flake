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
    property int pendingLine: 0 // line to jump to after the file finishes loading
    property int tabSize: 4 // spaces shown for each tab, must match the highlight layer
    readonly property real tabWidth: editorFontMetrics.horizontalAdvance(" ") * root.tabSize

    property var allRows: []
    property var treeRows: []

    implicitHeight: Appearance.sizes.wallpaperSelectorHeight - Appearance.sizes.hyprlandGapsOut * 2
    implicitWidth: Appearance.sizes.wallpaperSelectorWidth - Appearance.sizes.hyprlandGapsOut * 2

    Component.onCompleted: {
        root.refreshGit();
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
        const statusMap = {};
        const ls = [];
        const statusBlock = lsIdx === -1 ? [] : lines.slice(0, lsIdx);
        const lsBlock = (lsIdx !== -1 && brIdx !== -1) ? lines.slice(lsIdx + 1, brIdx) : [];
        const brBlock = brIdx === -1 ? [] : lines.slice(brIdx + 1);

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
        for (const line of statusBlock) { if (line.trim().length > 0) dirty++; }
        root.dirtyCount = dirty;
        root.statusHint = root.dirtyCount > 0
            ? `${root.dirtyCount} изменённых файлов в git`
            : `конфиг чист, ветка ${root.branch}`;
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
        configFileView.path = root.currentFilePath();
    }

    // Открыть файл (из правой панели с пакетами) и промотать редактор к строке.
    function openPackage(path, line) {
        console.log("[nixosConfig] openPackage", path, line);
        if (root.currentFile === path) {
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

    // Позиция конца строки (после переноса) — для подсветки выбора.
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
        root.statusHint = `сохраняю ${root.currentFile}...`;
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
                    Layout.preferredWidth: 300
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
                                text: "NixOS Config"
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
                    }
                }

                // ------------------------------------------------- editor + console
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    Toolbar { // toolbar
                        padding: 4
                        spacing: 2

                        IconToolbarButton {
                            implicitWidth: height
                            text: "save"
                            enabled: root.currentFile.length > 0
                            onClicked: root.saveFile()
                            StyledToolTip { text: Translation.tr("Save file (Ctrl+S)") }
                        }

                        Item { Layout.fillWidth: true }

                        IconToolbarButton {
                            id: quickBuildButton
                            implicitWidth: height
                            text: "bolt"
                            enabled: !root.building
                            onClicked: root.performBuild(false)
                            StyledToolTip { text: Translation.tr("Quick rebuild: ./update.sh --quick (polykit)") }
                        }
                        IconToolbarButton {
                            id: fullBuildButton
                            implicitWidth: height
                            text: "system_update"
                            enabled: !root.building
                            onClicked: root.performBuild(true)
                            StyledToolTip { text: Translation.tr("Full update & rebuild: ./update.sh (polykit)") }
                        }
                        IconToolbarButton {
                            id: cancelBuildButton
                            implicitWidth: height
                            text: "stop"
                            enabled: root.building
                            onClicked: root.cancelBuild()
                            StyledToolTip { text: Translation.tr("Send SIGTERM to the build") }
                        }

                        Item { Layout.fillWidth: true }

                        IconToolbarButton {
                            implicitWidth: height
                            text: "folder_open"
                            onClicked: {
                                const dir = root.currentFile.length > 0
                                    ? `${root.configRoot}/${root.currentFile}`
                                    : root.configRoot;
                                Quickshell.execDetached(["xdg-open", root.currentFile.length > 0 ? dir.substring(0, dir.lastIndexOf("/")) : dir]);
                            }
                            StyledToolTip { text: Translation.tr("Open folder in file manager") }
                        }
                        IconToolbarButton {
                            implicitWidth: height
                            text: "terminal"
                            toggled: root.showConsole
                            onClicked: root.showConsole = !root.showConsole
                            StyledToolTip { text: Translation.tr("Toggle build console") }
                        }
                        IconToolbarButton {
                            implicitWidth: height
                            text: "clear_all"
                            onClicked: NixosConfigBuild.clearLog()
                            StyledToolTip { text: Translation.tr("Clear console") }
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
                            anchors.fill: parent
                            anchors.margins: 2
                            clip: true
                            ScrollBar.horizontal: StyledScrollBar {}
                            ScrollBar.vertical: StyledScrollBar {}

                            // The single outer Flickable owns all scrolling. content
                            // is the max of the two auto-grown layers, so both stack
                            // as children and their positions are driven together.
                            contentWidth: Math.max(highlightLayer.contentWidth, editor.contentWidth)
                            contentHeight: Math.max(highlightLayer.contentHeight, editor.contentHeight)

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
                                color: Appearance.colors.colOnLayer1
                                text: root.rawText.length > 0 ? root.highlightNix(root.rawText) : ""
                            }

                            TextEdit {
                                id: editor
                                x: 0
                                y: 0
                                visible: !root.loading
                                focus: true
                                persistentSelection: true
                                selectByMouse: true
                                textFormat: TextEdit.PlainText
                                wrapMode: TextEdit.NoWrap
                                font {
                                    family: Appearance.font.family.monospace
                                    pixelSize: Appearance.font.pixelSize.smallie
                                }
                                tabStopDistance: root.tabWidth
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
                                }
                            }
                        }
                    }

                    // ------------------------------------------------- console
                    Rectangle {
                        id: consoleBackground
                        visible: root.showConsole
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
                                        ? "⟳ building…"
                                        : (root.lastBuildExit === null ? "console" : `exited ${root.lastBuildExit}`)
                                }
                                StyledText {
                                    visible: root.lastBuildExit === 0
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.m3colors.m3tertiary
                                    text: "ok"
                                }
                                StyledText {
                                    visible: root.lastBuildExit !== null && root.lastBuildExit !== 0
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.m3colors.m3error
                                    text: "failed"
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
                    Layout.preferredWidth: 300
                    onPackageClicked: (path, line) => {
                        console.log("[nixosConfig] packageClicked signal", path, line);
                        root.openPackage(path, line);
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
        command: ["bash", "-c", "cd /etc/nixos && git status --short --untracked-files=all; printf '\\n__LS__\\n'; git ls-files; printf '\\n__BR__\\n'; git branch --show-current"]
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
                root.statusHint = "нет такого файла: " + configFileView.path;
            }
        }
        onSaved: {
            root.statusHint = `сохранено: ${root.currentFile}`;
            root.fileDirty = false;
            root.refreshGit();
        }
        onSaveFailed: (error) => {
            root.statusHint = "не удалось сохранить: " + FileViewError.toString(error);
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