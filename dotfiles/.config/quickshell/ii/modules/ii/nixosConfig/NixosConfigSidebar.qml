import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Rectangle {
    id: root

    radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1 - 10
    color: Appearance.colors.colLayer1

    property int selectedTab: 0
    property string query: ""
    onQueryChanged: root.refreshFilter()
    property var pkgRows: []
    property var pkgModel: []
    property var serviceRows: []   // отфильтрованные (видно в списке)
    property var allServiceRows: [] // полный список до фильтрации
    property var runningRows: []
    property var configServiceRows: []
    property var todoRows: []   // отфильтрованные (видно в списке)
    property var allTodoRows: [] // полный список до фильтрации

    // Поиск пакета в nixpkgs (не в конфиге) и вставка его в редактор.
    property bool pkgsMode: false
    property bool pkgsBusy: false
    property bool pkgsIndexReady: false
    property var pkgsRows: []

    // Куда добавлять найденный пакет: список файлов с домашними/системными
    // пакетами и позицией вставки. Заполняется scripts/nixos-pkg-targets.py.
    property var pkgTargets: []
    property var pkgsTarget: null

    // Клик по пакету из nixpkgs: вставить "pkgs.<attr>" в текущий файл.
    signal insertPackage(string attr)

    // Клик по пакету из nixpkgs в режиме добавления: новая строка в конец
    // выбранного списка пакетов (target: {path, closeLine, indent, withPkgs}).
    signal insertPackageLine(string attr, var target)

    // Клик по пакету в списке: открыть файл конфига на нужной строке.
    signal packageClicked(string path, int line)

    // Клик по сервису: открыть панель systemd-юнита (статус + логи).
    // scope: "user" | "system" | "config"; path/line — место в nix-конфиге,
    // если сервис оттуда (для кнопки "Open in config").
    signal serviceClicked(string unit, string scope, string path, int line)

    Component.onCompleted: {
        root.refreshPackages();
        root.refreshServices();
        root.refreshTodos();
        targetsProc.running = true;
    }

    Process {
        id: targetsProc
        command: ["python3", Quickshell.shellPath("scripts/nixos-pkg-targets.py")]
        stdout: StdioCollector {
            id: targetsOutput
            waitForEnd: true
            onStreamFinished: root.parseTargets(targetsOutput.text)
        }
    }

    function parseTargets(txt) {
        const rows = [];
        for (const line of txt.split("\n")) {
            if (line.trim() === "") continue;
            const f = line.split("\t");
            if (f.length < 6) continue;
            rows.push({
                source: f[0],
                path: f[1],
                openLine: parseInt(f[2]),
                closeLine: parseInt(f[3]),
                indent: parseInt(f[4]),
                withPkgs: f[5] === "1"
            });
        }
        // home.packages идёт первым — это цель по умолчанию (пользовательские приложения).
        rows.sort((a, b) => (a.source === "home" ? 0 : 1) - (b.source === "home" ? 0 : 1));
        root.pkgTargets = rows;
        if (!root.pkgsTarget || !rows.some(t => t.source === root.pkgsTarget.source)) {
            root.pkgsTarget = rows[0] ?? null;
        }
    }

    // ------------------------------------------------------------- packages
    Process {
        id: pkgProc
        command: ["python3", Quickshell.shellPath("scripts/nixos-list-packages.py")]
        stdout: StdioCollector {
            id: pkgOutput
            waitForEnd: true
            onStreamFinished: {
                root.parsePackages(pkgOutput.text);
            }
        }
    }

    function refreshPackages() {
        pkgProc.running = true;
    }

    function parsePackages(txt) {
        const rows = [];
        for (const line of txt.split("\n")) {
            const parts = line.split("\t");
            if (parts.length < 4) continue;
            const attr = parts[3].trim();
            const path = parts[1].trim();
            if (!attr || attr === "inline-expr" || !path) continue;
            rows.push({
                source: parts[0].trim(),
                file: path.split("/").pop(),
                path: path,
                line: parseInt(parts[2], 10) || 1,
                attr: attr,
                kind: parts[0].trim() === "system" ? "S" : "H"
            });
        }
        rows.sort((a, b) => a.attr.localeCompare(b.attr, "en"));
        root.pkgRows = rows;
        root.refreshFilter();
    }

    function refreshFilter() {
        const q = root.query.trim().toLowerCase();
        root.pkgModel = q.length === 0
            ? root.pkgRows
            : root.pkgRows.filter(pkg =>
                (pkg.attr + " " + pkg.file).toLowerCase().includes(q));
        root.serviceRows = q.length === 0
            ? root.allServiceRows
            : root.allServiceRows.filter(svc =>
                (svc.unit + " " + svc.desc + " " + (svc.file ?? ""))
                    .toLowerCase().includes(q));
        root.todoRows = q.length === 0
            ? root.allTodoRows
            : root.allTodoRows.filter(t =>
                (t.tag + " " + t.text + " " + t.path).toLowerCase().includes(q));
    }

    function clearSearch() {
        searchField.text = "";
        root.query = "";
    }

    function pkgCount(source) {
        return root.pkgRows.filter(pkg => pkg.source === source).length;
    }

    // ------------------------------------------------------------- services
    Process {
        id: servicesProc
        command: ["bash", "-c",
            "echo '___USER___'; systemctl --user --no-pager --no-legend --plain -t service --state=running; echo '___SYSTEM___'; systemctl --no-pager --no-legend --plain -t service --state=running"]
        stdout: StdioCollector {
            id: servicesOutput
            waitForEnd: true
            onStreamFinished: {
                root.parseServices(servicesOutput.text);
            }
        }
    }

    Process {
        id: configServicesProc
        command: ["python3", Quickshell.shellPath("scripts/nixos-list-services.py")]
        stdout: StdioCollector {
            id: configServicesOutput
            waitForEnd: true
            onStreamFinished: {
                root.parseConfigServices(configServicesOutput.text);
            }
        }
    }

    function parseServices(txt) {
        const lines = txt.split("\n");
        const rows = [];
        let group = "user";
        for (const line of lines) {
            if (line.startsWith("___USER___")) { group = "user"; continue; }
            if (line.startsWith("___SYSTEM___")) { group = "system"; continue; }
            if (line.trim().length === 0) continue;
            const parts = line.trim().split(/\s+/);
            if (parts.length < 4) continue;
            const unit = parts[0];
            const sub = parts[3];
            const desc = parts.slice(4).join(" ");
            rows.push({ group, unit, sub, desc });
        }
        root.runningRows = rows;
        root.mergeServices();
    }

    function parseConfigServices(txt) {
        const rows = [];
        for (const line of txt.split("\n")) {
            const parts = line.split("\t");
            if (parts.length < 4) continue;
            const name = parts[3].trim();
            const path = parts[1].trim();
            if (!name || !path) continue;
            rows.push({
                source: parts[0].trim(),
                group: "config",
                unit: name,
                sub: "",
                desc: "",
                file: path.split("/").pop(),
                path: path,
                line: parseInt(parts[2], 10) || 1
            });
        }
        root.configServiceRows = rows;
        root.mergeServices();
    }

    function mergeServices() {
        const pri = { config: 0, user: 1, system: 2 };
        const rows = root.configServiceRows.concat(root.runningRows);
        rows.sort((a, b) =>
            (pri[a.group] - pri[b.group]) || a.unit.localeCompare(b.unit, "en"));
        root.allServiceRows = rows;
        root.refreshFilter();
    }

    function svcCount(group) {
        return root.serviceRows.filter(svc => svc.group === group).length;
    }

    function refreshServices() {
        servicesProc.running = true;
        configServicesProc.running = true;
    }

    // Клик по строке сервиса. Для сервисов из nix-конфига (`services.foo`,
    // `systemd.services.bar`) имени юнита может не быть в списке running —
    // ищем совпадение по basename среди запущенных, иначе отдаём имя как есть
    // (панель сама покажет «not found» и кнопку перехода в конфиг).
    function emitService(row) {
        if (row.group === "config") {
            const wanted = row.unit;
            const match = root.runningRows.find(svc =>
                svc.unit === wanted
                || svc.unit === wanted + ".service"
                || svc.unit.replace(/\.service$/, "") === wanted);
            if (match) {
                root.serviceClicked(match.unit, match.group, row.path, row.line);
            } else {
                root.serviceClicked(wanted, "config", row.path, row.line);
            }
            return;
        }
        root.serviceClicked(row.unit, row.group, "", 0);
    }

    // --------------------------------------------------------- nixpkgs search
    Process {
        id: pkgsSearchProc
        // command задаётся в runPkgsSearch(): у Process при повторном
        // запуске с тем же command ничего не происходит, а менять запрос
        // через биндинг нельзя — он не даёт перезапустить процесс.
        command: []
        stdout: StdioCollector {
            id: pkgsSearchOut
            waitForEnd: true
            onStreamFinished: {
                root.pkgsBusy = false;
                root.pkgsIndexReady = true;
                root.parsePkgs(pkgsSearchOut.text);
            }
        }
        stderr: StdioCollector {
            id: pkgsSearchErr
            waitForEnd: true
            // Индекса нет — скрипт пишет NOINDEX в stderr и ничего не выводит.
            onStreamFinished: {
                if (pkgsSearchErr.text.indexOf("NOINDEX") !== -1) {
                    root.pkgsIndexReady = false;
                    root.pkgsRows = [];
                }
            }
        }
    }

    Process {
        id: pkgsBuildProc
        command: ["python3", Quickshell.shellPath("scripts/nixos-pkgs-search.py"), "build"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                // Индекс собран — сразу показываем результаты по текущему запросу.
                root.pkgsBusy = true;
                root.runPkgsSearch();
            }
        }
        stderr: StdioCollector {
            id: pkgsBuildErr
            waitForEnd: true
            onStreamFinished: root.pkgsBusy = false
        }
    }

    Timer {
        id: pkgsDebounce
        interval: 250
        onTriggered: root.runPkgsSearch()
    }

    function runPkgsSearch() {
        pkgsSearchProc.command = [
            "python3",
            Quickshell.shellPath("scripts/nixos-pkgs-search.py"),
            "search",
            root.query ?? ""
        ];
        pkgsSearchProc.running = true;
    }

    function toPkgsMode() {
        root.pkgsMode = true;
        root.pkgsBusy = true;
        root.runPkgsSearch();
    }

    function leavePkgsMode() {
        root.pkgsMode = false;
        pkgsDebounce.stop();
        if (pkgsSearchProc.running) pkgsSearchProc.running = false;
        if (pkgsBuildProc.running) pkgsBuildProc.running = false;
        root.pkgsBusy = false;
    }

    function buildPkgsIndex() {
        root.pkgsBusy = true;
        pkgsBuildProc.running = true;
    }

    function parsePkgs(txt) {
        const rows = [];
        for (const line of txt.split("\n")) {
            const parts = line.split("\t");
            if (parts.length < 1) continue;
            const attr = parts[0].trim();
            if (!attr) continue;
            rows.push({
                attr: attr,
                version: (parts[1] ?? "").trim(),
                desc: (parts[2] ?? "").trim()
            });
        }
        root.pkgsRows = rows;
    }

    // ------------------------------------------------------------- todos
    Process {
        id: todoProc
        command: ["python3", Quickshell.shellPath("scripts/nixos-list-todos.py")]
        stdout: StdioCollector {
            id: todoOutput
            waitForEnd: true
            onStreamFinished: root.parseTodos(todoOutput.text);
        }
    }

    function refreshTodos() {
        todoProc.running = true;
    }

    function parseTodos(txt) {
        const rows = [];
        for (const line of txt.split("\n")) {
            const parts = line.split("\t");
            if (parts.length < 3) continue;
            const tag = parts[0].trim();
            const path = parts[1].trim();
            if (!tag || !path) continue;
            rows.push({
                tag: tag,
                tagUp: tag.toUpperCase(),
                file: path.split("/").pop(),
                path: path,
                line: parseInt(parts[2], 10) || 1,
                text: (parts[3] ?? "").trim()
            });
        }
        root.allTodoRows = rows;
        root.refreshFilter();
    }

    // ------------------------------------------------------------- ui
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        RowLayout { // header
            id: headerRow
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            Layout.maximumHeight: 34
            spacing: 6

            MaterialSymbol {
                id: headerIcon
                text: ["inventory_2", "apps", "bookmark"][root.selectedTab] ?? "inventory_2"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                font {
                    pixelSize: Appearance.font.pixelSize.normal
                    weight: Font.Medium
                }
                color: Appearance.colors.colOnLayer1
                text: [
                    Translation.tr("Packages"),
                    Translation.tr("Services"),
                    Translation.tr("Notes")
                ][root.selectedTab] ?? ""
            }
            IconToolbarButton { // refresh
                id: reloadBtn
                Layout.fillWidth: false
                Layout.fillHeight: false
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                text: "refresh"
                onClicked: {
                    if (root.selectedTab === 0) {
                        if (root.pkgsMode) {
                            root.pkgsBusy = true;
                            root.runPkgsSearch();
                        } else {
                            root.refreshPackages();
                        }
                    } else if (root.selectedTab === 1) root.refreshServices();
                    else root.refreshTodos();
                }
                StyledToolTip { text: Translation.tr("Reload") }
            }
            Rectangle { // count chip
                radius: height / 2
                color: Appearance.colors.colSecondaryContainer
                implicitWidth: countLabel.implicitWidth + 16
                height: 22
                StyledText {
                    id: countLabel
                    anchors.centerIn: parent
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnSecondaryContainer
                    text: root.selectedTab === 0 && root.pkgsMode
                        ? Translation.tr("%1 found").arg(root.pkgsRows.length)
                        : [
                            Translation.tr("%1 pkgs").arg(root.pkgRows.length),
                            Translation.tr("%1 services").arg(root.serviceRows.length),
                            Translation.tr("%1 notes").arg(root.allTodoRows.length)
                        ][root.selectedTab] ?? ""
                }
            }
            IconToolbarButton { // close window
                Layout.fillWidth: false
                Layout.fillHeight: false
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                Layout.alignment: Qt.AlignVCenter
                text: "close"
                onClicked: GlobalStates.nixosConfigOpen = false
                StyledToolTip { text: Translation.tr("Close") }
            }
        }

        RowLayout { // tabs
            id: tabsRow
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            spacing: 4

            TabChip {
                text: Translation.tr("Packages")
                iconText: "inventory_2"
                active: root.selectedTab === 0
                onClicked: {
                    root.selectedTab = 0;
                    root.clearSearch();
                }
            }
            TabChip {
                text: Translation.tr("Services")
                iconText: "apps"
                active: root.selectedTab === 1
                onClicked: {
                    root.selectedTab = 1;
                    root.clearSearch();
                    root.refreshServices();
                }
            }
            TabChip {
                text: Translation.tr("Notes")
                iconText: "bookmark"
                active: root.selectedTab === 2
                onClicked: {
                    root.selectedTab = 2;
                    root.clearSearch();
                    root.refreshTodos();
                }
            }
            Item {
                Layout.fillWidth: true
            }
        }

        Item { // search + переключатель «пакеты конфига / nixpkgs»
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.preferredHeight: 36
            Layout.maximumHeight: 36
            Layout.minimumHeight: 36

            // Важно: сначала поле, потом кнопка — порядок объявления = порядок
            // отрисовки, иначе TextField перекрывает кнопку и перехватывает клик.
            ToolbarTextField { // search
                id: searchField
                anchors.fill: parent
                rightPadding: pkgsModeBtn.visible ? 42 : 10
                placeholderText: [
                    Translation.tr("Search packages…"),
                    Translation.tr("Search services…"),
                    Translation.tr("Search notes…")
                ][root.selectedTab] ?? ""
                onTextChanged: {
                    root.query = text;
                    // В режиме nixpkgs запрос идёт в скрипт (по индексу это ~0.3 c),
                    // поэтому просто перезапускаем процесс с задержкой.
                    if (root.pkgsMode) {
                        root.pkgsBusy = true;
                        pkgsDebounce.restart();
                    }
                }
            }

            IconToolbarButton { // одна кнопка на оба режима, поверх поля поиска
                id: pkgsModeBtn
                visible: root.selectedTab === 0
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 28
                text: root.pkgsMode ? "arrow_back" : "travel_explore"
                toggled: root.pkgsMode
                onClicked: {
                    if (root.pkgsMode) root.leavePkgsMode();
                    else root.toPkgsMode();
                }
                StyledToolTip {
                    text: root.pkgsMode
                        ? Translation.tr("Back to config packages")
                        : Translation.tr("Search packages in nixpkgs")
                }
            }
        }

        RowLayout { // куда добавлять пакет (только в режиме nixpkgs)
            id: targetRow
            visible: root.selectedTab === 0 && root.pkgsMode && root.pkgTargets.length > 0
            Layout.fillWidth: true
            Layout.topMargin: 2
            Layout.preferredHeight: visible ? 32 : 0
            Layout.minimumHeight: visible ? 32 : 0
            Layout.maximumHeight: visible ? 32 : 0
            spacing: 6

            Repeater {
                model: root.pkgTargets
                delegate: IconAndTextToolbarButton {
                    id: targetChip
                    required property var modelData
                    // Сравнение по source, а не по ссылке на объект: надёжнее.
                    readonly property bool selected:
                        root.pkgsTarget !== null && root.pkgsTarget.source === modelData.source
                    text: modelData.source === "home"
                        ? Translation.tr("home.packages") : Translation.tr("systemPackages")
                    iconText: modelData.source === "home" ? "person" : "dns"
                    fontPixelSize: Appearance.font.pixelSize.smallie
                    iconSize: 16
                    contentSpacing: 8
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    Layout.minimumWidth: 0
                    toggled: targetChip.selected
                    // RippleButton рисует фон через colBackgroundToggled*,
                    // когда toggled=true, поэтому акцент задаём именно там —
                    // иначе смена выбора не видна. Невыбранный — плоский слой.
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer3
                    colBackgroundToggled: Appearance.colors.colPrimary
                    colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                    colRippleToggled: Appearance.colors.colPrimaryActive
                    colText: targetChip.selected
                        ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colOnLayer1
                    onClicked: root.pkgsTarget = modelData
                    StyledToolTip {
                        text: `${modelData.path}:${modelData.closeLine}`
                    }
                }
            }
        }

        Item { // content
            id: sidebarContent
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView { // packages
                id: pkgList
                visible: root.selectedTab === 0
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                spacing: 2
                model: root.pkgsMode ? root.pkgsRows : root.pkgModel
                ScrollBar.vertical: StyledScrollBar {}
                section.property: root.pkgsMode ? "" : "source"
                section.delegate: PkgSectionHeader {}
                header: Item { // переход из конфига в nixpkgs
                    width: pkgList.width
                    height: root.query.trim().length >= 2 && root.pkgModel.length === 0
                        && !root.pkgsMode ? 32 : 0
                    visible: height > 0
                    MouseArea {
                        id: toPkgsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toPkgsMode()
                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: toPkgsMouse.containsMouse
                                ? Appearance.colors.colLayer2
                                : "transparent"
                            border.width: 1
                            border.color: Appearance.colors.colSecondaryContainer
                        }
                        RowLayout {
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 8
                                rightMargin: 8
                            }
                            spacing: 6
                            MaterialSymbol {
                                text: "travel_explore"
                                iconSize: 16
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSecondaryContainer
                                text: Translation.tr("Search “%1” in nixpkgs").arg(root.query.trim())
                            }
                        }
                    }
                }
                delegate: MouseArea {
                    required property var modelData
                    width: pkgList.width
                    height: root.pkgsMode ? 44 : 30
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onContainsMouseChanged: console.log("[sidebarDBG] hover", containsMouse, modelData.attr)
                    onPressed: console.log("[sidebarDBG] press", modelData.attr)
                    onClicked: {
                        console.log("[sidebarDBG] pkg click", modelData.path, modelData.line);
                        if (root.pkgsMode) {
                            if (root.pkgsTarget) root.insertPackageLine(modelData.attr, root.pkgsTarget);
                        }
                        else root.packageClicked(modelData.path, modelData.line);
                    }

                    Rectangle { // background
                        anchors.fill: parent
                        radius: 6
                        color: containsMouse ? Appearance.colors.colLayer2 : "transparent"
                        Behavior on color {
                            ColorAnimation { duration: 100 }
                        }
                    }

                    ColumnLayout { // результат nixpkgs: имя + описание
                        visible: root.pkgsMode
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 4
                            rightMargin: 4
                        }
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font {
                                family: Appearance.font.family.monospace
                                pixelSize: Appearance.font.pixelSize.small
                            }
                            color: Appearance.colors.colOnLayer1
                            text: modelData.attr
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnLayer1
                            opacity: 0.65
                            text: modelData.desc ?? ""
                        }
                    }

                    RowLayout { // content
                        visible: !root.pkgsMode
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 6

                        Item { // marker column: 20px, как у служб
                            width: 20
                            height: 16
                            Rectangle { // source badge
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                radius: 4
                                color: modelData.source === "system"
                                    ? Appearance.colors.colSecondaryContainer
                                    : Appearance.colors.colTertiaryContainer
                                StyledText {
                                    anchors.centerIn: parent
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: modelData.source === "system"
                                        ? Appearance.colors.colOnSecondaryContainer
                                        : Appearance.colors.colOnTertiaryContainer
                                    text: modelData.kind
                                }
                            }
                        }
                        StyledText {
                            font {
                                family: Appearance.font.family.monospace
                                pixelSize: Appearance.font.pixelSize.small
                            }
                            color: Appearance.colors.colOnLayer1
                            text: modelData.attr
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.m3colors.m3outline
                            text: `${modelData.file}:${modelData.line}`
                        }
                    }
                }
            }

            StyledText { // packages empty
                anchors.centerIn: parent
                visible: root.selectedTab === 0
                    && (root.pkgsMode
                        ? (root.pkgsRows.length === 0 && !root.pkgsBusy)
                        : (root.pkgModel.length === 0 && root.pkgRows.length > 0))
                color: Appearance.m3colors.m3outline
                text: root.pkgsMode
                    ? (root.pkgsIndexReady
                        ? Translation.tr("Nothing found")
                        : Translation.tr("Index is being built…"))
                    : Translation.tr("No packages")
            }

            // Индекса nixpkgs ещё нет: полный eval legacyPackages занимает
            // минуту, поэтому запускаем его только по явному клику.
            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - 48
                visible: root.selectedTab === 0 && root.pkgsMode
                    && !root.pkgsIndexReady && !root.pkgsBusy
                spacing: 10

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1
                    opacity: 0.75
                    text: Translation.tr("No nixpkgs index yet. Building it evaluates all packages and takes about a minute.")
                }
                IconAndTextToolbarButton {
                    Layout.alignment: Qt.AlignHCenter
                    iconText: "cloud_download"
                    text: Translation.tr("Build index")
                    onClicked: root.buildPkgsIndex()
                    StyledToolTip { text: Translation.tr("Build nixpkgs index (~1 min)") }
                }
            }

            ListView { // services
                id: servicesList
                visible: root.selectedTab === 1
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                spacing: 2
                model: root.serviceRows
                ScrollBar.vertical: StyledScrollBar {}
                section.property: "group"
                section.delegate: Item {
                    height: 26
                    width: servicesList.width
                    RowLayout {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 6
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnLayer1
                            opacity: 0.85
                            text: section === "config"
                                ? Translation.tr("From config")
                                : (section === "user"
                                    ? Translation.tr("User running")
                                    : Translation.tr("System running"))
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        Rectangle {
                            radius: height / 2
                            color: Appearance.colors.colTertiaryContainer
                            implicitWidth: svcCountLabel.implicitWidth + 14
                            height: 18
                            StyledText {
                                id: svcCountLabel
                                anchors.centerIn: parent
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnTertiaryContainer
                                text: `${root.svcCount(section)}`
                            }
                        }
                    }
                }
                delegate: Item {
                    required property var modelData
                    width: servicesList.width
                    implicitHeight: 30

                    MouseArea {
                        id: svcMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            console.log("[sidebarDBG] svc click", modelData.unit, modelData.group);
                            root.emitService(modelData);
                        }
                        Rectangle { // hover bg
                            anchors.fill: parent
                            radius: 6
                            Behavior on color {
                                ColorAnimation { duration: 100 }
                            }
                            color: svcMouse.containsMouse
                                ? Appearance.colors.colLayer2
                                : "transparent"
                        }
                    }

                    RowLayout {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 6

                        Item { // marker: source badge (config) or status dot (running)
                            width: 20
                            height: 16
                            Rectangle { // config: system/home badge
                                id: svcBadge
                                visible: modelData.group === "config"
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                radius: 4
                                color: modelData.source === "system"
                                    ? Appearance.colors.colSecondaryContainer
                                    : Appearance.colors.colTertiaryContainer
                                StyledText {
                                    anchors.centerIn: parent
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: modelData.source === "system"
                                        ? Appearance.colors.colOnSecondaryContainer
                                        : Appearance.colors.colOnTertiaryContainer
                                    text: modelData.source === "system" ? "S" : "H"
                                }
                            }
                            Rectangle { // running: status dot
                                visible: modelData.group !== "config"
                                anchors.centerIn: parent
                                width: 8
                                height: 8
                                radius: 4
                                color: modelData.sub === "running"
                                    ? "#56d364"
                                    : Appearance.m3colors.m3outline
                            }
                        }
                        StyledText {
                            font {
                                family: modelData.group === "config"
                                    ? Appearance.font.family.monospace
                                    : Appearance.font.family.main
                                pixelSize: modelData.group === "config"
                                    ? Appearance.font.pixelSize.small
                                    : Appearance.font.pixelSize.small
                            }
                            color: Appearance.colors.colOnLayer1
                            text: modelData.unit.replace(/\.service$/, "")
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        StyledText {
                            Layout.maximumWidth: 180
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnLayer1
                            opacity: 0.7
                            text: modelData.group === "config"
                                ? `${modelData.file}:${modelData.line}`
                                : modelData.desc
                        }
                    }
                }
            }

            ListView { // notes (TODO/FIXME/…)
                id: todoList
                visible: root.selectedTab === 2
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                spacing: 2
                model: root.todoRows
                ScrollBar.vertical: StyledScrollBar {}
                delegate: Item {
                    required property var modelData
                    width: todoList.width
                    implicitHeight: 44

                    MouseArea {
                        id: todoMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.packageClicked(modelData.path, modelData.line)
                        Rectangle { // hover bg
                            anchors.fill: parent
                            radius: 6
                            Behavior on color {
                                ColorAnimation { duration: 100 }
                            }
                            color: todoMouse.containsMouse
                                ? Appearance.colors.colLayer2
                                : "transparent"
                        }
                    }

                    RowLayout {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 2
                            rightMargin: 4
                        }
                        spacing: 6

                        Rectangle { // метка
                            width: 52
                            height: 16
                            radius: 4
                            color: modelData.tagUp === "FIXME"
                                ? Appearance.m3colors.m3errorContainer
                                : Appearance.colors.colTertiaryContainer
                            StyledText {
                                anchors.centerIn: parent
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: modelData.tagUp === "FIXME"
                                    ? Appearance.m3colors.m3onErrorContainer
                                    : Appearance.colors.colOnTertiaryContainer
                                text: modelData.tagUp
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: modelData.text.length > 0
                                    ? Appearance.colors.colOnLayer1
                                    : "transparent"
                                text: modelData.text.length > 0
                                    ? modelData.text
                                    : modelData.file
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnLayer1
                                opacity: 0.6
                                text: modelData.text.length > 0
                                    ? `${modelData.file}:${modelData.line}`
                                    : Translation.tr("no text")
                            }
                        }
                    }
                }
            }

            StyledText { // notes empty
                anchors.centerIn: parent
                visible: root.selectedTab === 2 && root.todoRows.length === 0
                color: Appearance.m3colors.m3outline
                text: Translation.tr("No TODO/FIXME in config")
            }

            StyledText { // services empty
                anchors.centerIn: parent
                visible: root.selectedTab === 1 && root.serviceRows.length === 0
                color: Appearance.m3colors.m3outline
                text: root.query.trim().length > 0
                    ? Translation.tr("Nothing found")
                    : Translation.tr("Loading services…")
            }
        }

        // Подсказка внизу вкладки «Заметки»: без неё непонятно, какие
        // маркеры скрипт вообще ищет.
        Rectangle {
            id: notesLegend
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 40 : 0
            Layout.minimumHeight: visible ? 40 : 0
            Layout.maximumHeight: visible ? 40 : 0
            visible: root.selectedTab === 2
            radius: 6
            color: Appearance.colors.colLayer2

            ColumnLayout {
                anchors {
                    fill: parent
                    margins: 6
                }
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1
                    opacity: 0.7
                    text: Translation.tr("Markers: TODO, FIXME, XXX, HACK, NOTE, WARN, OPTIM")
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1
                    opacity: 0.55
                    text: Translation.tr("Comments # and /* */ in .nix files. Click opens the file at that line.")
                }
            }
        }
    }

    // Раньше это были самописные прямоугольники с own hover-логикой: цвета
    // не совпадали с остальными кнопками, а после наведения фон залипал.
    // Теперь это тот же виджет, что у кнопок тулбара и плашки git-статуса,
    // просто с включённым состоянием активной вкладки.
    component TabChip: IconAndTextToolbarButton {
        id: tabChipRoot
        required property bool active

        Layout.fillWidth: true
        Layout.preferredHeight: 32
        Layout.minimumHeight: 32
        Layout.maximumHeight: 32
        iconSize: 18
        fontPixelSize: Appearance.font.pixelSize.small
        contentSpacing: 6
        toggled: tabChipRoot.active
    }

    component PkgSectionHeader: Item {
        implicitHeight: 26
        width: pkgList.width

        RowLayout {
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            spacing: 6

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnLayer1
                opacity: 0.85
                text: section === "system"
                    ? Translation.tr("System — environment.systemPackages")
                    : Translation.tr("Home — home.packages")
            }
            Item {
                Layout.fillWidth: true
            }
            Rectangle {
                radius: height / 2
                color: Appearance.colors.colTertiaryContainer
                implicitWidth: chipLabel.implicitWidth + 14
                height: 18
                StyledText {
                    id: chipLabel
                    anchors.centerIn: parent
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnTertiaryContainer
                    text: `${root.pkgCount(section)}`
                }
            }
        }
    }

}