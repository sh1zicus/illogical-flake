pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Файловый менеджер: обычное toplevel-окно (как NixosConfig и PortProton),
// а не layer-shell оверлей. Позицией и размером управляет композитор.
// Контент живёт только пока окно открыто.
Scope {
    id: root

    Loader {
        id: fileManagerLoader
        active: GlobalStates.fileManagerOpen

        sourceComponent: FloatingWindow {
            id: window

            visible: GlobalStates.fileManagerOpen
            title: "File Manager"
            color: "transparent"

            implicitWidth: 1100
            implicitHeight: 720

            mask: Region {
                item: content
            }

            onClosed: GlobalStates.fileManagerOpen = false

            onVisibleChanged: {
                if (visible) content.forceActiveFocus();
            }

            function delegateClicked(item, entry) {
                const mods = item.lastClickModifiers || 0;
                if (mods & Qt.ControlModifier) FileManagerModel.toggleSelection(entry.path);
                else if (mods & Qt.ShiftModifier) FileManagerModel.selectRangeTo(entry.path);
                else FileManagerModel.selectOnly(entry.path);
            }

            function openEntryMenu(item, entry, event) {
                if (entry && !FileManagerModel.selection.includes(entry.path))
                    FileManagerModel.selectOnly(entry.path);
                const p = item.mapToItem(fileListContainer, event.x, event.y);
                contextMenu.openFor(entry, p.x, p.y);
            }

            function renameSelectedEntry() {
                const entry = FileManagerModel.renameSelected();
                if (entry) renameField.openFor(entry);
            }

            function gridColumns() {
                return Math.max(1, Math.floor(gridView.width / gridView.cellWidth));
            }

            function moveHorizontal(delta, extend) {
                if (FileManagerModel.viewMode === "grid") {
                    FileManagerModel.moveSelectionGrid(delta, 0, window.gridColumns(), extend);
                } else if (FileManagerModel.viewMode === "tree") {
                    if (extend) FileManagerModel.extendSelection(delta);
                    else if (delta < 0) FileManagerModel.treeLeft();
                    else FileManagerModel.treeRight();
                } else if (extend) {
                    FileManagerModel.extendSelection(delta);
                } else {
                    FileManagerModel.moveSelection(delta);
                }
            }

            function moveVertical(delta, extend) {
                if (FileManagerModel.viewMode === "grid") {
                    FileManagerModel.moveSelectionGrid(0, delta, window.gridColumns(), extend);
                } else if (extend) {
                    FileManagerModel.extendSelection(delta);
                } else {
                    FileManagerModel.moveSelection(delta);
                }
            }

            function actionPaths(entry) {
                if (!entry) return [...FileManagerModel.selection];
                if (FileManagerModel.selection.includes(entry.path)) return [...FileManagerModel.selection];
                return [entry.path];
            }

            readonly property bool navEnabled: !renameField.visible
                && !pathField.activeFocus
                && !contextMenu.visible
                && !deleteConfirm.visible

            component FileEntryIcon: Item {
                id: entryIcon
                property var entry: null
                property bool previewFailed: false
                property int iconAttempt: 0
                readonly property bool preview: entry !== null
                    && !entry.isDir
                    && !previewFailed
                    && /\.(png|jpe?g|webp|gif|svg|bmp|avif)$/i.test(entry.name)
                readonly property var iconSources: entry === null ? [] : FileManagerModel.iconFileCandidates(entry.iconName, Math.min(width, height))
                onEntryChanged: {
                    previewFailed = false;
                    iconAttempt = 0;
                }
                onWidthChanged: iconAttempt = 0
                onHeightChanged: iconAttempt = 0

                Image {
                    anchors.fill: parent
                    visible: !entryIcon.preview
                    asynchronous: false
                    fillMode: Image.PreserveAspectFit
                    source: entryIcon.iconAttempt < entryIcon.iconSources.length ? entryIcon.iconSources[entryIcon.iconAttempt] : ""
                    onStatusChanged: {
                        if (status === Image.Error && entryIcon.iconAttempt + 1 < entryIcon.iconSources.length)
                            entryIcon.iconAttempt++;
                    }
                }

                StyledImage {
                    anchors.fill: parent
                    visible: entryIcon.preview
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: 64
                    sourceSize.height: 64
                    source: entryIcon.preview ? entryIcon.entry.fileUrl : ""
                    onStatusChanged: {
                        if (status === Image.Error && entryIcon.preview) entryIcon.previewFailed = true;
                    }
                }
            }

            Rectangle {
                id: content
                anchors.fill: parent
                focus: true
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer0Base
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                clip: true

                ColumnLayout {
                    id: contentColumn
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    // ---------- верхняя панель ----------
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        Layout.minimumHeight: 34
                        Layout.maximumHeight: 34
                        spacing: 6

                        IconToolbarButton {
                            text: "keyboard_arrow_left"
                            enabled: FileManagerModel.canGoBack
                            onClicked: FileManagerModel.goBack()
                        }
                        IconToolbarButton {
                            text: "keyboard_arrow_right"
                            enabled: FileManagerModel.canGoForward
                            onClicked: FileManagerModel.goForward()
                        }
                        IconToolbarButton {
                            text: "keyboard_arrow_up"
                            onClicked: FileManagerModel.goUp()
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            Layout.minimumHeight: 34
                            Layout.maximumHeight: 34
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer1Base
                            border.width: 1
                            border.color: pathField.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border

                            StyledTextInput {
                                id: pathField
                                anchors.fill: parent
                                leftPadding: 10
                                rightPadding: 10
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                text: FileManagerModel.currentPath
                                onAccepted: {
                                    FileManagerModel.navigate(text);
                                    content.forceActiveFocus();
                                }
                                onActiveFocusChanged: {
                                    if (!activeFocus) text = FileManagerModel.currentPath;
                                }
                            }
                        }

                        IconToolbarButton {
                            text: "view_list"
                            toggled: FileManagerModel.viewMode === "list"
                            onClicked: FileManagerModel.setViewMode("list")
                        }
                        IconToolbarButton {
                            text: "grid_view"
                            toggled: FileManagerModel.viewMode === "grid"
                            onClicked: FileManagerModel.setViewMode("grid")
                        }
                        IconToolbarButton {
                            text: "account_tree"
                            toggled: FileManagerModel.viewMode === "tree"
                            onClicked: FileManagerModel.setViewMode("tree")
                        }
                        IconToolbarButton {
                            text: "zoom_out"
                            onClicked: FileManagerModel.adjustIconScale(-10)
                            altAction: () => FileManagerModel.resetIconScale()
                        }
                        IconToolbarButton {
                            text: "zoom_in"
                            onClicked: FileManagerModel.adjustIconScale(10)
                            altAction: () => FileManagerModel.resetIconScale()
                        }
                        IconToolbarButton {
                            text: FileManagerModel.showHidden ? "visibility" : "visibility_off"
                            toggled: FileManagerModel.showHidden
                            onClicked: FileManagerModel.toggleHidden()
                        }
                        IconToolbarButton {
                            text: "sort"
                            onClicked: FileManagerModel.cycleSort()
                            altAction: () => FileManagerModel.toggleSortDirection()
                        }
                        IconToolbarButton {
                            text: "refresh"
                            onClicked: FileManagerModel.reload()
                        }
                        IconToolbarButton {
                            text: "create_new_folder"
                            onClicked: FileManagerModel.newFolder()
                        }
                        IconToolbarButton {
                            text: "note_add"
                            onClicked: FileManagerModel.newFile()
                        }
                        IconToolbarButton {
                            text: "close"
                            onClicked: GlobalStates.fileManagerOpen = false
                        }
                    }

                    Connections {
                        target: FileManagerModel
                        function onCurrentPathChanged() {
                            if (!pathField.activeFocus) pathField.text = FileManagerModel.currentPath;
                        }
                    }

                    // ---------- контент ----------
                    RowLayout {
                        id: mainRow
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10

                        // сайдбар мест
                        ColumnLayout {
                            id: sidebarColumn
                            spacing: 2
                            Layout.preferredWidth: 160
                            Layout.minimumWidth: 160
                            Layout.maximumWidth: 160
                            Layout.fillHeight: true

                            Repeater {
                                model: FileManagerModel.places

                                RippleButton {
                                    id: placeButton
                                    required property var modelData
                                    Layout.fillWidth: true
                                    height: 34

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        spacing: 8

                                        MaterialSymbol {
                                            text: placeButton.modelData.icon
                                        }
                                        StyledText {
                                            text: placeButton.modelData.name
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    onClicked: {
                                        if (placeButton.modelData.path === "trash:///") {
                                            FileManagerModel.navigate(FileUtils.trimFileProtocol(Directories.home) + "/.local/share/Trash/files");
                                        } else {
                                            FileManagerModel.navigate(placeButton.modelData.path);
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }
                        }

                        Rectangle {
                            id: fileListContainer
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer1Base
                            border.width: 1
                            border.color: Appearance.colors.colLayer0Border
                            clip: true

                            // список / дерево
                            StyledListView {
                                id: fileList
                                anchors.fill: parent
                                anchors.margins: 6
                                interactive: false
                                visible: FileManagerModel.viewMode !== "grid"
                                model: FileManagerModel.displayEntries

                                delegate: RippleButton {
                                    id: fileDelegate
                                    required property var modelData
                                    required property int index
                                    width: ListView.view ? ListView.view.width : 0
                                    height: Math.max(36, FileManagerModel.listIconSize + 14)
                                    toggled: FileManagerModel.selection.includes(fileDelegate.modelData.path)

                                    onClicked: window.delegateClicked(fileDelegate, fileDelegate.modelData)
                                    doubleClickAction: () => FileManagerModel.openEntry(fileDelegate.modelData)
                                    altAction: (event) => window.openEntryMenu(fileDelegate, fileDelegate.modelData, event)
                                    middleClickAction: () => FileManagerModel.openWithTerminal(fileDelegate.modelData)

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10 + (fileDelegate.modelData.depth || 0) * 18
                                        anchors.rightMargin: 10
                                        spacing: 8

                                        Item {
                                            visible: fileDelegate.modelData.isDir
                                                && FileManagerModel.viewMode === "tree"
                                                && fileDelegate.modelData.treeHasChildren !== false
                                            Layout.preferredWidth: 20
                                            Layout.preferredHeight: 20

                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: fileDelegate.modelData.treeExpanded ? "expand_more" : "chevron_right"
                                                iconSize: 18
                                                opacity: 0.8
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: (mouse) => {
                                                    mouse.accepted = true;
                                                    FileManagerModel.toggleTree(fileDelegate.modelData.path);
                                                }
                                            }
                                        }

                                        FileEntryIcon {
                                            entry: fileDelegate.modelData
                                            Layout.preferredWidth: FileManagerModel.listIconSize
                                            Layout.preferredHeight: FileManagerModel.listIconSize
                                        }
                                        StyledText {
                                            text: fileDelegate.modelData.name
                                            elide: Text.ElideMiddle
                                            opacity: fileDelegate.modelData.hidden ? 0.6 : 1
                                            Layout.fillWidth: true
                                        }
                                        StyledText {
                                            visible: !fileDelegate.modelData.isDir
                                            text: FileManagerModel.formatSize(fileDelegate.modelData.size)
                                            font.pixelSize: (Appearance?.font?.pixelSize?.small ?? 12)
                                            opacity: 0.7
                                        }
                                        StyledText {
                                            visible: fileDelegate.modelData.modified > 0
                                            text: FileManagerModel.formatModifiedShort(fileDelegate.modelData.modified)
                                            font.pixelSize: (Appearance?.font?.pixelSize?.small ?? 12)
                                            opacity: 0.55
                                        }
                                    }
                                }

                                TapHandler {
                                    acceptedButtons: Qt.RightButton
                                    onSingleTapped: (eventPoint) => {
                                        const p = fileList.mapToItem(fileListContainer, eventPoint.position.x, eventPoint.position.y);
                                        contextMenu.openFor(null, p.x, p.y);
                                    }
                                }
                            }

                            // сетка
                            GridView {
                                id: gridView
                                anchors.fill: parent
                                anchors.margins: 8
                                interactive: false
                                visible: FileManagerModel.viewMode === "grid"
                                model: FileManagerModel.displayEntries
                                clip: true
                                cellWidth: FileManagerModel.gridCellSize
                                cellHeight: FileManagerModel.gridCellSize

                                delegate: RippleButton {
                                    id: gridDelegate
                                    required property var modelData
                                    required property int index
                                    width: gridView.cellWidth - 8
                                    height: gridView.cellHeight - 8
                                    toggled: FileManagerModel.selection.includes(gridDelegate.modelData.path)

                                    onClicked: window.delegateClicked(gridDelegate, gridDelegate.modelData)
                                    doubleClickAction: () => FileManagerModel.openEntry(gridDelegate.modelData)
                                    altAction: (event) => window.openEntryMenu(gridDelegate, gridDelegate.modelData, event)
                                    middleClickAction: () => FileManagerModel.openWithTerminal(gridDelegate.modelData)

                                    Item {
                                        anchors.fill: parent
                                        anchors.margins: 4

                                        FileEntryIcon {
                                            id: gridIcon
                                            entry: gridDelegate.modelData
                                            anchors.top: parent.top
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: FileManagerModel.gridIconSize
                                            height: FileManagerModel.gridIconSize
                                        }
                                        StyledText {
                                            anchors.top: gridIcon.bottom
                                            anchors.topMargin: 4
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            horizontalAlignment: Text.AlignHCenter
                                            text: gridDelegate.modelData.name
                                            elide: Text.ElideMiddle
                                            wrapMode: Text.Wrap
                                            maximumLineCount: 2
                                            font.pixelSize: 12
                                            opacity: gridDelegate.modelData.hidden ? 0.6 : 1
                                        }
                                    }
                                }

                                TapHandler {
                                    acceptedButtons: Qt.RightButton
                                    onSingleTapped: (eventPoint) => {
                                        const p = gridView.mapToItem(fileListContainer, eventPoint.position.x, eventPoint.position.y);
                                        contextMenu.openFor(null, p.x, p.y);
                                    }
                                }
                            }

                            StyledText {
                                anchors.centerIn: parent
                                visible: FileManagerModel.displayEntries.length === 0 && !FileManagerModel.loading
                                text: "Папка пуста"
                                opacity: 0.45
                            }

                            // закрытие меню кликом мимо
                            MouseArea {
                                id: menuDismiss
                                anchors.fill: parent
                                visible: contextMenu.visible
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                z: 9
                                onPressed: contextMenu.close()
                            }

                            // блокировка кликов при подтверждении удаления
                            MouseArea {
                                anchors.fill: parent
                                visible: FileManagerModel.pendingPermanentDelete.length > 0
                                acceptedButtons: Qt.AllButtons
                                z: 11
                                onPressed: (mouse) => mouse.accepted = true
                            }

                            // контекстное меню
                            Rectangle {
                                id: contextMenu
                                property var entry: null
                                property var fileActions: []

                                function buildFileActions(entry) {
                                    const paths = window.actionPaths(entry);
                                    const actions = [
                                        { label: "Открыть", action: () => FileManagerModel.openEntry(entry) },
                                        { label: "Открыть в терминале", action: () => FileManagerModel.openWithTerminal(entry) },
                                        { label: "Копировать", action: () => FileManagerModel.copyEntries(paths) },
                                        { label: "Вырезать", action: () => FileManagerModel.cutEntries(paths) },
                                        { label: "Переименовать...", action: () => renameField.openFor(entry) },
                                        { label: "Свойства", action: () => FileManagerModel.describeEntry(entry) },
                                    ];
                                    actions.push({
                                        label: FileManagerModel.inTrash ? "Удалить безвозвратно" : "Удалить",
                                        action: () => FileManagerModel.deleteEntries(paths)
                                    });
                                    return actions;
                                }
                                property var blankActions: [
                                    { label: "Новая папка", action: () => FileManagerModel.newFolder() },
                                    { label: "Новый файл", action: () => FileManagerModel.newFile() },
                                    { label: "Вставить", action: () => FileManagerModel.pasteEntries() },
                                    { label: "Выделить всё", action: () => FileManagerModel.selectAll() },
                                    { label: "Обновить", action: () => FileManagerModel.reload() },
                                    { label: "Скрытые файлы", action: () => FileManagerModel.toggleHidden() },
                                    { label: "Сменить сортировку", action: () => FileManagerModel.cycleSort() },
                                ]

                                function openFor(entry, px, py) {
                                    contextMenu.entry = entry;
                                    contextMenu.fileActions = entry ? contextMenu.buildFileActions(entry) : [];
                                    contextMenu.visible = true;
                                    contextMenu.x = Math.max(8, Math.min(px, fileListContainer.width - contextMenu.width - 8));
                                    contextMenu.y = Math.max(8, Math.min(py, fileListContainer.height - contextMenu.height - 8));
                                }
                                function close() {
                                    contextMenu.visible = false;
                                }

                                visible: false
                                z: 10
                                width: 240
                                height: menuColumn.implicitHeight + 12
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer2Base
                                border.width: 1
                                border.color: Appearance.colors.colLayer0Border

                                ColumnLayout {
                                    id: menuColumn
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 2

                                    Repeater {
                                        model: contextMenu.entry ? contextMenu.fileActions : contextMenu.blankActions

                                        RippleButton {
                                            id: menuItem
                                            required property var modelData
                                            Layout.fillWidth: true
                                            height: 30
                                            buttonText: menuItem.modelData.label
                                            onClicked: {
                                                menuItem.modelData.action();
                                                contextMenu.close();
                                            }
                                        }
                                    }
                                }
                            }

                            // поле переименования
                            Rectangle {
                                id: renameField
                                property var entry: null

                                function openFor(entry) {
                                    contextMenu.close();
                                    renameField.entry = entry;
                                    renameField.visible = true;
                                    Qt.callLater(() => {
                                        renameInput.forceActiveFocus();
                                        renameInput.selectAll();
                                    });
                                }
                                function close() {
                                    renameField.visible = false;
                                    renameField.entry = null;
                                    content.forceActiveFocus();
                                }

                                visible: false
                                z: 10
                                anchors.centerIn: parent
                                width: 420
                                height: 56
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer2Base
                                border.width: 1
                                border.color: Appearance.colors.colLayer0Border

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 34
                                        Layout.minimumHeight: 34
                                        Layout.maximumHeight: 34
                                        radius: Appearance.rounding.small
                                        color: Appearance.colors.colLayer1Base
                                        border.width: 1
                                        border.color: renameInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border

                                        StyledTextInput {
                                            id: renameInput
                                            anchors.fill: parent
                                            leftPadding: 10
                                            rightPadding: 10
                                            verticalAlignment: TextInput.AlignVCenter
                                            clip: true
                                            onAccepted: {
                                                FileManagerModel.renameEntry(renameField.entry, text);
                                                renameField.close();
                                            }
                                        }
                                    }

                                    IconToolbarButton {
                                        text: "check"
                                        onClicked: {
                                            FileManagerModel.renameEntry(renameField.entry, renameInput.text);
                                            renameField.close();
                                        }
                                    }
                                    IconToolbarButton {
                                        text: "close"
                                        onClicked: renameField.close()
                                    }
                                }
                            }

                            Rectangle {
                                id: deleteConfirm
                                visible: FileManagerModel.pendingPermanentDelete.length > 0
                                z: 12
                                anchors.centerIn: parent
                                width: 460
                                height: 132
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer2Base
                                border.width: 1
                                border.color: Appearance.colors.colLayer0Border

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 10

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: {
                                            const paths = FileManagerModel.pendingPermanentDelete;
                                            if (paths.length === 1) {
                                                const entry = FileManagerModel.entryByPath(paths[0]);
                                                return `Удалить безвозвратно «${entry ? entry.name : paths[0]}»?`;
                                            }
                                            return `Удалить безвозвратно ${paths.length} объектов?`;
                                        }
                                        wrapMode: Text.Wrap
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Item { Layout.fillWidth: true }
                                        RippleButton {
                                            Layout.preferredWidth: 100
                                            Layout.preferredHeight: 30
                                            buttonText: "Отмена"
                                            onClicked: {
                                                FileManagerModel.cancelPermanentDelete();
                                                content.forceActiveFocus();
                                            }
                                        }
                                        RippleButton {
                                            Layout.preferredWidth: 140
                                            Layout.preferredHeight: 30
                                            buttonText: "Удалить"
                                            colBackground: Appearance.colors.colErrorContainer
                                            colBackgroundHover: Appearance.colors.colErrorContainerHover
                                            onClicked: {
                                                FileManagerModel.confirmPermanentDelete();
                                                content.forceActiveFocus();
                                            }
                                        }
                                    }
                                }
                            }

                            WheelHandler {
                                acceptedModifiers: Qt.ControlModifier
                                onWheel: (event) => FileManagerModel.adjustIconScale(event.angleDelta.y > 0 ? 10 : -10)
                            }
                        }
                    }

                    // ---------- статусбар ----------
                    RowLayout {
                        Layout.fillWidth: true

                        StyledText {
                            text: FileManagerModel.loading
                                ? "Загрузка..."
                                : (FileManagerModel.statusMessage || `${FileManagerModel.displayEntries.length} объектов`)
                            font.pixelSize: (Appearance?.font?.pixelSize?.small ?? 12)
                        }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            text: `Иконки: ${FileManagerModel.iconScale}%`
                            font.pixelSize: (Appearance?.font?.pixelSize?.small ?? 12)
                            opacity: 0.7
                        }
                        StyledText {
                            visible: FileManagerModel.selection.length > 0
                            text: `Выбрано: ${FileManagerModel.selection.length}`
                            font.pixelSize: (Appearance?.font?.pixelSize?.small ?? 12)
                        }
                    }
                }
            }

            Connections {
                target: FileManagerModel
                function onCurrentPathChanged() {
                    if (!pathField.activeFocus) pathField.text = FileManagerModel.currentPath;
                }
                function onSelectionMoved(index) {
                    if (index < 0) return;
                    const view = FileManagerModel.viewMode === "grid" ? gridView : fileList;
                    if (view) view.positionViewAtIndex(index, 4);
                }
            }

            Shortcut { sequence: "Alt+Left"; onActivated: FileManagerModel.goBack() }
            Shortcut { sequence: "Alt+Right"; onActivated: FileManagerModel.goForward() }
            Shortcut { sequence: "Alt+Up"; onActivated: FileManagerModel.goUp() }
            Shortcut { sequence: "Up"; enabled: window.navEnabled; onActivated: window.moveVertical(-1, false) }
            Shortcut { sequence: "Down"; enabled: window.navEnabled; onActivated: window.moveVertical(1, false) }
            Shortcut { sequence: "Left"; enabled: window.navEnabled; onActivated: window.moveHorizontal(-1, false) }
            Shortcut { sequence: "Right"; enabled: window.navEnabled; onActivated: window.moveHorizontal(1, false) }
            Shortcut { sequence: "Shift+Up"; enabled: window.navEnabled; onActivated: window.moveVertical(-1, true) }
            Shortcut { sequence: "Shift+Down"; enabled: window.navEnabled; onActivated: window.moveVertical(1, true) }
            Shortcut { sequence: "Shift+Left"; enabled: window.navEnabled; onActivated: window.moveHorizontal(-1, true) }
            Shortcut { sequence: "Shift+Right"; enabled: window.navEnabled; onActivated: window.moveHorizontal(1, true) }
            Shortcut { sequence: "Home"; enabled: window.navEnabled; onActivated: FileManagerModel.selectFirst() }
            Shortcut { sequence: "End"; enabled: window.navEnabled; onActivated: FileManagerModel.selectLast() }
            Shortcut { sequence: "PageUp"; enabled: window.navEnabled; onActivated: window.moveVertical(-8, false) }
            Shortcut { sequence: "PageDown"; enabled: window.navEnabled; onActivated: window.moveVertical(8, false) }
            Shortcut {
                sequence: "Space"
                enabled: window.navEnabled
                onActivated: FileManagerModel.toggleSelectionAtCurrent()
            }
            Shortcut {
                sequence: "Return"
                enabled: deleteConfirm.visible
                onActivated: FileManagerModel.confirmPermanentDelete()
            }
            Shortcut {
                sequence: "Return"
                enabled: window.navEnabled
                onActivated: FileManagerModel.openSelected()
            }
            Shortcut {
                sequence: "Backspace"
                enabled: window.navEnabled
                onActivated: FileManagerModel.goUp()
            }
            Shortcut {
                sequence: "Delete"
                enabled: window.navEnabled
                onActivated: FileManagerModel.deleteEntries([])
            }
            Shortcut {
                sequence: "F2"
                enabled: window.navEnabled
                onActivated: window.renameSelectedEntry()
            }
            Shortcut {
                sequence: "F5"
                enabled: !renameField.visible && !deleteConfirm.visible
                onActivated: FileManagerModel.reload()
            }
            Shortcut {
                sequence: "Ctrl+H"
                enabled: window.navEnabled
                onActivated: FileManagerModel.toggleHidden()
            }
            Shortcut {
                sequence: "Ctrl+A"
                enabled: window.navEnabled
                onActivated: FileManagerModel.selectAll()
            }
            Shortcut {
                sequence: "Ctrl+C"
                enabled: window.navEnabled
                onActivated: FileManagerModel.copyEntries([])
            }
            Shortcut {
                sequence: "Ctrl+X"
                enabled: window.navEnabled
                onActivated: FileManagerModel.cutEntries([])
            }
            Shortcut {
                sequence: "Ctrl+V"
                enabled: window.navEnabled
                onActivated: FileManagerModel.pasteEntries()
            }
            Shortcut {
                sequence: "Ctrl+L"
                enabled: !deleteConfirm.visible
                onActivated: {
                    pathField.forceActiveFocus();
                    pathField.selectAll();
                }
            }
            Shortcut { sequence: "Ctrl+-"; onActivated: FileManagerModel.adjustIconScale(-10) }
            Shortcut { sequence: "Ctrl+="; onActivated: FileManagerModel.adjustIconScale(10) }
            Shortcut { sequence: "Ctrl+0"; onActivated: FileManagerModel.resetIconScale() }
            Shortcut { sequence: "Ctrl+1"; onActivated: FileManagerModel.setViewMode("list") }
            Shortcut { sequence: "Ctrl+2"; onActivated: FileManagerModel.setViewMode("grid") }
            Shortcut { sequence: "Ctrl+3"; onActivated: FileManagerModel.setViewMode("tree") }
            Shortcut {
                sequence: "Escape"
                onActivated: {
                    if (deleteConfirm.visible) FileManagerModel.cancelPermanentDelete();
                    else if (contextMenu.visible) contextMenu.close();
                    else if (renameField.visible) renameField.close();
                    else if (pathField.activeFocus) content.forceActiveFocus();
                    else GlobalStates.fileManagerOpen = false;
                }
            }
        }
    }

    GlobalShortcut {
        name: "fileManagerToggle"
        description: "Toggles the file manager"

        onPressed: GlobalStates.fileManagerOpen = !GlobalStates.fileManagerOpen
    }

    IpcHandler {
        target: "fileManager"

        function toggle(): void {
            GlobalStates.fileManagerOpen = !GlobalStates.fileManagerOpen
        }

        function open(): void {
            GlobalStates.fileManagerOpen = true
        }

        function openPath(path: string): void {
            FileManagerModel.navigate(path)
            GlobalStates.fileManagerOpen = true
        }

        function view(mode: string): void {
            FileManagerModel.setViewMode(mode)
        }

        function scale(value: int): void {
            FileManagerModel.setIconScale(value)
        }
    }
}
