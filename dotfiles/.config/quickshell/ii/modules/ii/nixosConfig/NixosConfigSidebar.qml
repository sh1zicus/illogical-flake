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
    property var serviceRows: []
    property var runningRows: []
    property var configServiceRows: []

    // Клик по пакету в списке: открыть файл конфига на нужной строке.
    signal packageClicked(string path, int line)

    Component.onCompleted: {
        root.refreshPackages();
        root.refreshServices();
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
        root.serviceRows = rows;
    }

    function svcCount(group) {
        return root.serviceRows.filter(svc => svc.group === group).length;
    }

    function refreshServices() {
        servicesProc.running = true;
        configServicesProc.running = true;
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
                text: root.selectedTab === 0 ? "inventory_2" : "apps"
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
                text: root.selectedTab === 0 ? "Packages from config" : "Services (config + running)"
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
                    if (root.selectedTab === 0) root.refreshPackages();
                    else root.refreshServices();
                }
                StyledToolTip { text: "Reload" }
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
                    text: root.selectedTab === 0
                        ? `${root.pkgRows.length} pkgs`
                        : `${root.serviceRows.length} services`
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
                StyledToolTip { text: "Close" }
            }
        }

        RowLayout { // tabs
            id: tabsRow
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            spacing: 4

            TabChip {
                text: "Packages"
                active: root.selectedTab === 0
                onClicked: root.selectedTab = 0
            }
            TabChip {
                text: "Services"
                active: root.selectedTab === 1
                onClicked: {
                    root.selectedTab = 1;
                    root.refreshServices();
                }
            }
            Item {
                Layout.fillWidth: true
            }
        }

        MaterialTextField { // search
            id: searchField
            visible: root.selectedTab === 0
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            Layout.maximumHeight: 44
            placeholderText: "Search packages…"
            onTextChanged: root.query = text
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
                model: root.pkgModel
                ScrollBar.vertical: StyledScrollBar {}
                section.property: "source"
                section.delegate: PkgSectionHeader {}
                delegate: MouseArea {
                    required property var modelData
                    width: pkgList.width
                    height: 32
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onContainsMouseChanged: console.log("[sidebarDBG] hover", containsMouse, modelData.attr)
                    onPressed: console.log("[sidebarDBG] press", modelData.attr)
                    onClicked: {
                        console.log("[sidebarDBG] pkg click", modelData.path, modelData.line);
                        root.packageClicked(modelData.path, modelData.line);
                    }

                    Rectangle { // background
                        anchors.fill: parent
                        radius: 6
                        color: containsMouse ? Appearance.colors.colLayer2 : "transparent"
                        Behavior on color {
                            ColorAnimation { duration: 100 }
                        }
                    }

                    RowLayout { // content
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 6

                        Rectangle { // source badge
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
                visible: root.selectedTab === 0 && root.pkgModel.length === 0
                color: Appearance.m3colors.m3outline
                text: "No packages"
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
                            anchors.left: parent.left
                            anchors.leftMargin: 2
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.m3colors.m3outline
                            text: section === "config"
                                ? "From config"
                                : (section === "user" ? "User running" : "System running")
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
                    implicitHeight: 30

                    MouseArea {
                        anchors.fill: parent
                        enabled: modelData.group === "config"
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            console.log("[sidebarDBG] svc click", modelData.path, modelData.line);
                            root.packageClicked(modelData.path, modelData.line);
                        }
                        Rectangle { // hover bg
                            anchors.fill: parent
                            radius: 6
                            color: modelData.group === "config" && containsMouse
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

            StyledText { // services empty
                anchors.centerIn: parent
                visible: root.selectedTab === 1 && root.serviceRows.length === 0
                color: Appearance.m3colors.m3outline
                text: "Loading services…"
            }
        }
    }

    component TabChip: Item {
        id: tabChipRoot
        required property string text
        required property bool active
        signal clicked()

        implicitWidth: chipLabel.implicitWidth + 20
        height: 30

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: tabChipRoot.active
                ? Appearance.colors.colPrimary
                : (chipMouse.containsMouse ? Appearance.colors.colLayer2 : "transparent")
            Behavior on color {
                ColorAnimation { duration: 100 }
            }
        }
        StyledText {
            id: chipLabel
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.pixelSize.small
            color: tabChipRoot.active
                ? Appearance.colors.colOnPrimary
                : Appearance.colors.colOnLayer1
            text: tabChipRoot.text
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tabChipRoot.clicked()
        }
    }

    component PkgSectionHeader: Item {
        implicitHeight: 24
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
                    ? "System — environment.systemPackages"
                    : "Home — home.packages"
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