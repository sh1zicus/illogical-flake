import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Панель systemd-сервиса: клик по строке в списке Services открывает её здесь
// же, в области редактора. Показывает состояние и свойства юнита
// (systemctl show), логи (journalctl, с live-режимом) и даёт управлять
// юнитом. Если сервис пришёл из nix-конфига, кнопка "Open in config"
// возвращает редактор к нужной строке.
Item {
    id: root
    clip: true

    // Имя как пришло из списка: "nginx.service" для запущенных,
    // "networkmanager" (без суффикса) для объявленных в конфиге.
    // Не required: панель живёт в дереве всегда и заполняется из
    // NixosConfigContent.openService() при клике по сервису.
    property string unit: ""
    // "system" | "user" | "config"
    property string scope: "system"
    // Файл nix-конфига (относительно /etc/nixos) и строка, если сервис оттуда.
    property string configPath: ""
    property int configLine: 0

    signal backRequested()
    signal openConfigRequested(string path, int line)

    readonly property bool isUser: scope === "user"
    readonly property bool resolved: props.LoadState !== undefined
        && props.LoadState !== "not-found"
    readonly property string unitId: resolved && props.Id ? props.Id : unit

    property var props: ({})
    property string logText: ""
    property bool live: false
    property string actionStatus: ""
    property bool actionRunning: false
    property int logLines: 200

    implicitHeight: 400
    implicitWidth: 600

    onUnitChanged: {
        root.stopLive();
        root.props = ({});
        root.logText = "";
        root.actionStatus = "";
        Qt.callLater(() => {
            if (root.unit.length > 0) root.refresh();
        });
    }

    onScopeChanged: {
        if (root.unit.length > 0) Qt.callLater(() => root.refresh());
    }

    // ------------------------------------------------------------- systemctl
    // Кандидаты имени: как есть и с .service. Имена без суффикса (из nix-конфига)
    // надо проверить в обоих вариантах — вдруг юнит всё-таки есть в systemd.
    function candidates() {
        const known = [ ".service", ".socket", ".timer", ".target", ".path" ];
        if (known.some(s => root.unit.endsWith(s))) return [ root.unit ];
        return [ root.unit + ".service", root.unit ];
    }

    readonly property var showProps: [
        "Id", "Description", "LoadState", "ActiveState", "SubState", "Result",
        "UnitFileState", "Type", "MainPID", "ExecMainStartTimestamp",
        "ExecMainStatus", "NRestarts", "MemoryCurrent", "MemoryPeak",
        "TasksCurrent", "CPUUsageNSec", "FragmentPath", "ExecStart"
    ]

    function refresh() {
        if (root.unit.length === 0) return;
        propsProc.running = true;
    }

    // systemctl show разделяет блоки разных юнитов пустой строкой.
    function parseBlocks(text) {
        const blocks = [ {} ];
        for (const rawLine of (text || "").split("\n")) {
            const line = rawLine.trim();
            if (line.length === 0) {
                if (Object.keys(blocks[blocks.length - 1]).length > 0) blocks.push({});
                continue;
            }
            const eq = line.indexOf("=");
            if (eq < 0) continue;
            blocks[blocks.length - 1][line.substring(0, eq)] = line.substring(eq + 1);
        }
        return blocks.filter(b => Object.keys(b).length > 0);
    }

    // Из кандидатов берём первый, который реально загружен.
    function pickUnit(blocks) {
        if (blocks.length === 0) return {};
        for (const block of blocks) {
            if (block.LoadState !== undefined && block.LoadState !== "not-found") return block;
        }
        return blocks[0];
    }

    // ------------------------------------------------------------- journalctl
    function logCommand() {
        if (!root.resolved) return [ "true" ];
        const args = [ "journalctl" ];
        if (root.isUser) args.push("--user");
        args.push("-u", root.unitId, "-n", String(root.logLines), "--no-pager",
            "-o", "short-iso");
        if (root.live) args.push("-f");
        return args;
    }

    function refreshLogs() {
        logProc.running = false;
        root.logText = "";
        logProc.command = root.logCommand();
        logProc.running = true;
    }

    function toggleLive() {
        if (!root.resolved) return;
        root.live = !root.live;
        root.refreshLogs();
    }

    function stopLive() {
        if (root.live) {
            root.live = false;
            logProc.running = false;
        }
    }

    onLiveChanged: statusPollTimer.running = root.visible && !root.live && root.unit.length > 0

    // ------------------------------------------------------------- actions
    function canAct() {
        return root.resolved && !root.actionRunning;
    }

    function runAction(action) {
        if (!root.canAct()) return;
        root.actionRunning = true;
        root.actionStatus = Translation.tr("%1: %2…").arg(action).arg(root.unitId);
        actionProc.command = root.isUser
            ? [ "systemctl", "--user", action, root.unitId ]
            : [ "pkexec", "systemctl", action, root.unitId ];
        actionProc.running = true;
    }

    function openUnitFile() {
        const path = root.props.FragmentPath;
        if (!path) {
            root.actionStatus = Translation.tr("No unit file");
            return;
        }
        Quickshell.execDetached([ "xdg-open", path ]);
    }

    // ------------------------------------------------------------- formatting
    function formatBytes(value) {
        const n = parseInt(value, 10);
        if (isNaN(n) || n <= 0) return "—";
        const units = [ "B", "KiB", "MiB", "GiB", "TiB" ];
        let v = n;
        let i = 0;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return `${v.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
    }

    function formatCpu(value) {
        const n = parseInt(value, 10);
        if (isNaN(n) || n <= 0) return "—";
        return `${(n / 1e9).toFixed(1)} s`;
    }

    function formatExecStart(value) {
        if (!value) return "—";
        const m = value.match(/path=([^;]+)/);
        return m ? m[1].trim() : value;
    }

    function prop(key) {
        return root.resolved && root.props[key] !== undefined ? root.props[key] : "—";
    }

    readonly property var propRows: [
        { k: Translation.tr("State"), v: root.resolved ? `${root.props.ActiveState} (${root.props.SubState})` : "—" },
        { k: Translation.tr("Autostart"), v: root.prop("UnitFileState") },
        { k: Translation.tr("Type"), v: root.prop("Type") },
        { k: Translation.tr("Result"), v: root.prop("Result") },
        { k: Translation.tr("PID"), v: root.resolved && root.props.MainPID !== "0" ? root.props.MainPID : "—" },
        { k: Translation.tr("Since"), v: root.prop("ExecMainStartTimestamp") },
        { k: Translation.tr("Memory"), v: root.resolved ? `${root.formatBytes(root.props.MemoryCurrent)} / ${root.formatBytes(root.props.MemoryPeak)}` : "—" },
        { k: Translation.tr("CPU"), v: root.resolved ? root.formatCpu(root.props.CPUUsageNSec) : "—" },
        { k: Translation.tr("Tasks"), v: root.prop("TasksCurrent") },
        { k: Translation.tr("Restarts"), v: root.resolved ? (root.props.NRestarts || "0") : "—" },
        { k: Translation.tr("Exec"), v: root.resolved ? root.formatExecStart(root.props.ExecStart) : "—" },
        { k: Translation.tr("Unit file"), v: root.prop("FragmentPath") },
    ]

    readonly property color stateColor: !root.resolved ? Appearance.m3colors.m3outline
        : (root.props.ActiveState === "active" ? Appearance.m3colors.m3tertiary
            : (root.props.ActiveState === "failed" ? Appearance.m3colors.m3error
                : Appearance.m3colors.m3outline))

    // ================================================================ layout
    // Важно: все дети ниже имеют явные minimum/размеры. Иначе логи (TextArea с
    // NoWrap) задают минимальный размер в тысячи пикселей, ColumnLayout
    // выдавливает содержимое за пределы окна и поверх консоли.
    ColumnLayout {
        anchors {
            fill: parent
            margins: 10
        }
        spacing: 8

        RowLayout { // ------------------------------------------------- header
            id: headerRow
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.minimumHeight: 32
            Layout.preferredHeight: 32
            Layout.maximumHeight: 32
            spacing: 8

            IconToolbarButton { // back to editor
                id: backBtn
                implicitWidth: 32
                implicitHeight: 32
                Layout.preferredWidth: 32
                Layout.minimumWidth: 32
                Layout.maximumWidth: 32
                Layout.preferredHeight: 32
                Layout.minimumHeight: 32
                Layout.maximumHeight: 32
                text: "arrow_back"
                onClicked: root.backRequested()
                StyledToolTip { text: Translation.tr("Back to file") }
            }
            MaterialSymbol {
                text: "settings_input_component"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.minimumWidth: 0
                Layout.maximumWidth: 300
                elide: Text.ElideMiddle
                font {
                    pixelSize: Appearance.font.pixelSize.normal
                    weight: Font.Medium
                }
                color: Appearance.colors.colOnLayer1
                text: root.unitId
            }
            Rectangle { // state chip
                radius: height / 2
                color: Appearance.colors.colSecondaryContainer
                implicitWidth: stateLabel.implicitWidth + 16
                Layout.minimumHeight: 22
                Layout.preferredHeight: 22
                Layout.maximumHeight: 22
                height: 22
                StyledText {
                    id: stateLabel
                    anchors.centerIn: parent
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: root.stateColor
                    text: root.resolved
                        ? `${root.props.ActiveState} · ${root.props.SubState}`
                        : Translation.tr("not found")
                }
            }
            StyledText { // action feedback
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnLayer1
                opacity: 0.85
                text: root.actionStatus
            }
            IconToolbarButton {
                implicitWidth: 32
                implicitHeight: 32
                Layout.preferredWidth: 32
                Layout.minimumWidth: 32
                Layout.maximumWidth: 32
                Layout.preferredHeight: 32
                Layout.minimumHeight: 32
                Layout.maximumHeight: 32
                text: "refresh"
                onClicked: root.refresh()
                StyledToolTip { text: Translation.tr("Refresh") }
            }
        }

        StyledText { // -------------------------------------------- description
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 2
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
            opacity: 0.85
            text: root.resolved && root.props.Description
                ? root.props.Description
                : Translation.tr("Unit is unknown to systemd — it may only be declared in the Nix config")
        }

        Rectangle { // ---------------------------------------------- actions
            // Повторяет верхний тулбар редактора: та же плашка, те же
            // IconAndTextToolbarButton, кнопки поровну делят ширину.
            id: actionsRect
            property int gap: 6
            readonly property int buttonCount: 5
            readonly property real slotWidth: (width - 8 - gap * (buttonCount - 1)) / buttonCount
            readonly property bool compact: slotWidth < 125
            implicitWidth: 0
            implicitHeight: 0
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredHeight: 40
            Layout.minimumHeight: 40
            Layout.maximumHeight: 40
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer0
            clip: true

            RowLayout {
                id: actionsRow
                anchors {
                    fill: parent
                    margins: 4
                }
                spacing: actionsRect.gap

                IconAndTextToolbarButton {
                    implicitHeight: 32
                    Layout.fillWidth: true
                    Layout.minimumWidth: 38
                    iconText: "play_arrow"
                    text: actionsRect.compact ? "" : Translation.tr("Start")
                    enabled: root.canAct()
                    onClicked: root.runAction("start")
                }
                IconAndTextToolbarButton {
                    implicitHeight: 32
                    Layout.fillWidth: true
                    Layout.minimumWidth: 38
                    iconText: "stop"
                    text: actionsRect.compact ? "" : Translation.tr("Stop")
                    enabled: root.canAct()
                    onClicked: root.runAction("stop")
                }
                IconAndTextToolbarButton {
                    implicitHeight: 32
                    Layout.fillWidth: true
                    Layout.minimumWidth: 38
                    iconText: "restart_alt"
                    text: actionsRect.compact ? "" : Translation.tr("Restart")
                    enabled: root.canAct()
                    onClicked: root.runAction("restart")
                }
                IconAndTextToolbarButton {
                    implicitHeight: 32
                    Layout.fillWidth: true
                    Layout.minimumWidth: 38
                    iconText: "description"
                    text: actionsRect.compact ? "" : Translation.tr("Unit file")
                    enabled: root.resolved && root.props.FragmentPath !== ""
                    onClicked: root.openUnitFile()
                }
                IconAndTextToolbarButton {
                    implicitHeight: 32
                    Layout.fillWidth: true
                    Layout.minimumWidth: 38
                    iconText: "code"
                    text: actionsRect.compact ? "" : Translation.tr("Open in config")
                    enabled: root.configPath.length > 0
                    onClicked: {
                        if (root.configPath.length > 0) {
                            root.openConfigRequested(root.configPath, root.configLine);
                        }
                    }
                }
            }
        }

        Rectangle { // -------------------------------------------- properties
            id: propsRect
            // implicitWidth/Height = 0: иначе GridLayout внутри (anchors.fill)
            // раскручивает петлю childrenRect и Rectangle требует ширину контента.
            implicitWidth: 0
            implicitHeight: 0
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.minimumHeight: 0
            Layout.preferredHeight: propGrid.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer0

            GridLayout {
                id: propGrid
                anchors {
                    fill: parent
                    margins: 8
                }
                columns: root.width > 560 ? 2 : 1
                columnSpacing: 20
                rowSpacing: 4

                Repeater {
                    model: root.propRows
                    delegate: Item {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 18

                        StyledText {
                            id: propKey
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 80
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.m3colors.m3outline
                            text: modelData.k
                        }
                        StyledText {
                            anchors {
                                left: propKey.right
                                leftMargin: 6
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            elide: Text.ElideRight
                            font {
                                family: Appearance.font.family.monospace
                                pixelSize: Appearance.font.pixelSize.smallest
                            }
                            color: Appearance.colors.colOnLayer1
                            text: modelData.v
                        }
                    }
                }
            }
        }

        Rectangle { // --------------------------------------------------- logs
            id: logRect
            implicitWidth: 0
            implicitHeight: 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0
            Layout.minimumHeight: 0
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer0
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.minimumHeight: 32
                    Layout.preferredHeight: 32
                    Layout.maximumHeight: 32
                    spacing: 6

                    MaterialSymbol {
                        text: "article"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        font {
                            pixelSize: Appearance.font.pixelSize.smallest
                            weight: Font.Medium
                        }
                        color: Appearance.colors.colOnLayer1
                        text: Translation.tr("Logs")
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.m3colors.m3outline
                        text: root.resolved ? Translation.tr("last %1 lines").arg(root.logLines) : ""
                    }
                    IconAndTextToolbarButton {
                        Layout.minimumHeight: 32
                        Layout.preferredHeight: 32
                        Layout.maximumHeight: 32
                        iconText: root.live ? "pause" : "stream"
                        text: root.live ? Translation.tr("Stop live") : Translation.tr("Live")
                        enabled: root.resolved
                        onClicked: root.toggleLive()
                    }
                    IconToolbarButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        Layout.preferredWidth: 32
                        Layout.minimumWidth: 32
                        Layout.maximumWidth: 32
                        Layout.minimumHeight: 32
                        Layout.preferredHeight: 32
                        Layout.maximumHeight: 32
                        text: "clear_all"
                        onClicked: root.refreshLogs()
                        StyledToolTip { text: Translation.tr("Reload") }
                    }
                }

                ScrollView {
                    id: logScroll
                    // implicit* = 0: размеры логов задаёт контент (TextArea),
                    // наружу он отдаёт только то, что реально помещается.
                    implicitWidth: 0
                    implicitHeight: 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 0
                    Layout.minimumHeight: 0
                    clip: true
                    ScrollBar.horizontal: StyledScrollBar {}
                    ScrollBar.vertical: StyledScrollBar {
                        id: serviceLogBar
                    }

                    StyledTextArea {
                        id: serviceLogArea
                        readOnly: true
                        textFormat: TextEdit.RichText
                        font {
                            family: Appearance.font.family.monospace
                            pixelSize: 12
                        }
                        color: Appearance.colors.colOnLayer1
                        wrapMode: TextEdit.NoWrap
                        text: root.highlightLog(root.logText)
                    }
                }
            }
        }
    }

    // Журнал подсвечиваем по severity, чтобы ошибки было видно сразу.
    function highlightLog(raw) {
        if (!raw) return "";
        const dark = Appearance.m3colors.darkmode;
        const c = {
            err: dark ? "#ff7b72" : "#c62828",
            warn: dark ? "#e3b341" : "#f9a825",
            ok: dark ? "#7ee787" : "#2e7d32",
            time: Appearance.m3colors.m3outline
        };
        const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        const span = (color, inside) => `<span style="color:${color};">${inside}</span>`;
        const out = [];
        for (const line of raw.split("\n")) {
            let html = esc(line);
            const lower = line.toLowerCase();
            if (lower.includes("error") || lower.includes("failed")
                || lower.includes("fatal") || lower.includes("panic")
                || lower.includes("failure")) {
                html = span(c.err, html);
            } else if (lower.includes("warn")) {
                html = span(c.warn, html);
            } else if (lower.includes("started") || lower.includes("ready")
                || lower.includes("success")) {
                html = span(c.ok, html);
            } else {
                // метка времени (short-iso) — приглушаем
                html = html.replace(/^(\d{4}-\d{2}-\d{2}T[\d:.]+[+-]\d{2}:\d{2})/, (m) => span(c.time, m));
            }
            out.push(html);
        }
        return out.join("<br>");
    }

    onLogTextChanged: {
        Qt.callLater(function () {
            if (serviceLogBar.size > 0) serviceLogBar.position = 1.0 - serviceLogBar.size;
        });
    }

    // ================================================================ logic
    Process {
        id: propsProc
        command: {
            const args = [ "systemctl" ];
            if (root.isUser) args.push("--user");
            args.push("show", "--no-pager");
            for (const key of root.showProps) args.push("-p", key);
            for (const name of root.candidates()) args.push(name);
            return args;
        }
        stdout: StdioCollector {
            id: propsCollector
            waitForEnd: true
            onStreamFinished: {
                root.props = root.pickUnit(root.parseBlocks(propsCollector.text));
                root.refreshLogs();
            }
        }
    }

    Process {
        id: logProc
        command: root.logCommand()
        stdout: StdioCollector {
            id: logCollector
            waitForEnd: !root.live
            onTextChanged: {
                if (root.live && logCollector.text.length > 0) root.logText = logCollector.text;
            }
            onStreamFinished: {
                if (!root.live) root.logText = logCollector.text;
            }
        }
    }

    Process {
        id: actionProc
        onExited: (exitCode, exitStatus) => {
            root.actionRunning = false;
            root.actionStatus = exitCode === 0
                ? Translation.tr("done")
                : Translation.tr("failed with code %1").arg(exitCode);
            root.refresh();
        }
    }

    Timer { // автообновление свойств, пока не включён live-режим
        id: statusPollTimer
        interval: 5000
        repeat: true
        running: root.visible && !root.live && root.unit.length > 0
        onTriggered: propsProc.running = true
    }
}
