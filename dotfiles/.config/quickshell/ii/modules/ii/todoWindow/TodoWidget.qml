import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property bool showAddDialog: false
    property int dialogMargins: 20

    // Индекс редактируемой задачи, -1 = создание новой.
    property int editingIndex: -1

    // Рабочие поля диалога
    property string dlgContent: ""
    property string dlgPriority: "none"
    property string dlgType: "text"
    property string dlgCode: ""
    property var dlgItems: []
    property int dlgCurrent: 0
    property int dlgTotal: 0
    property string dlgNewSub: ""
    property int dlgHours: 0
    property int dlgMinutes: 1
    property int dlgSeconds: 0
    property string dlgCommand: ""
    property string dlgTags: ""
    property real dlgDue: 0
    property string dlgRecurrence: "none"

    readonly property var typeList: [
        {"id": "text", "name": Translation.tr("Text"), "icon": "notes"},
        {"id": "code", "name": Translation.tr("Code"), "icon": "code"},
        {"id": "checklist", "name": Translation.tr("Checklist"), "icon": "checklist"},
        {"id": "progress", "name": Translation.tr("Progress"), "icon": "linear_scale"},
        {"id": "timer", "name": Translation.tr("Timer"), "icon": "timer"}
    ]
    readonly property var priorityList: [
        {"id": "none", "name": Translation.tr("None"), "color": "transparent"},
        {"id": "low", "name": Translation.tr("Low"), "color": "#4CAF50"},
        {"id": "medium", "name": Translation.tr("Medium"), "color": "#FFB300"},
        {"id": "high", "name": Translation.tr("High"), "color": "#E53935"}
    ]
    readonly property var dueOptions: [
        {"id": -1, "name": Translation.tr("None")},
        {"id": 0, "name": Translation.tr("Today")},
        {"id": 1, "name": Translation.tr("Tomorrow")},
        {"id": 3, "name": Translation.tr("In 3 days")},
        {"id": 7, "name": Translation.tr("In a week")}
    ]
    readonly property var recurrenceList: [
        {"id": "none", "name": Translation.tr("None")},
        {"id": "daily", "name": Translation.tr("Daily")},
        {"id": "weekly", "name": Translation.tr("Weekly")},
        {"id": "monthly", "name": Translation.tr("Monthly")}
    ]

    function computeDue(days) {
        if (days < 0) return 0;
        const d = new Date();
        d.setHours(23, 59, 0, 0);
        d.setDate(d.getDate() + days);
        return Math.floor(d.getTime() / 1000);
    }

    function sortItems(arr) {
        const w = { "high": 0, "medium": 1, "low": 2, "none": 3 };
        return arr.slice(0).sort((x, y) => (w[x.priority] ?? 3) - (w[y.priority] ?? 3));
    }

    readonly property var unfinishedList: sortItems(Todo.list
        .map(function(item, i) { return Object.assign({}, item, {originalIndex: i}); })
        .filter(function(item) { return !item.done; }))
    readonly property var doneList: sortItems(Todo.list
        .map(function(item, i) { return Object.assign({}, item, {originalIndex: i}); })
        .filter(function(item) { return item.done; }))

    function openAdd() {
        root.editingIndex = -1
        root.dlgContent = ""
        root.dlgPriority = "none"
        root.dlgType = "text"
        root.dlgCode = ""
        root.dlgItems = []
        root.dlgCurrent = 0
        root.dlgTotal = 0
        root.dlgNewSub = ""
        root.dlgHours = 0
        root.dlgMinutes = 1
        root.dlgSeconds = 0
        root.dlgCommand = ""
        root.dlgTags = ""
        root.dlgDue = 0
        root.dlgRecurrence = "none"
        titleInput.text = ""
        codeArea.text = ""
        curInput.text = "0"
        totInput.text = "0"
        newSubInput.text = ""
        hourInput.text = "0"
        minuteInput.text = "1"
        secondInput.text = "0"
        cmdInput.text = ""
        tagsInput.text = ""
        root.showAddDialog = true
    }

    function openAddChecklist() {
        openAdd()
        root.dlgType = "checklist"
    }

    function openEdit(index) {
        const item = Todo.list[index]
        if (!item) return
        root.editingIndex = index
        root.dlgContent = item.content ?? ""
        root.dlgPriority = item.priority ?? "none"
        root.dlgType = item.type ?? "text"
        root.dlgCode = item.code ?? ""
        root.dlgItems = (item.items ?? []).map(function(s) { return {"text": s.text, "done": !!s.done} })
        root.dlgCurrent = item.current ?? 0
        root.dlgTotal = item.total ?? 0
        root.dlgNewSub = ""
        const dur = item.duration ?? 0
        root.dlgHours = Math.floor(dur / 3600)
        root.dlgMinutes = Math.floor((dur % 3600) / 60)
        root.dlgSeconds = dur % 60
        root.dlgCommand = item.command ?? ""
        root.dlgTags = (item.tags ?? []).join(", ")
        root.dlgDue = item.due ?? 0
        root.dlgRecurrence = item.recurrence ?? "none"
        titleInput.text = root.dlgContent
        codeArea.text = root.dlgCode
        curInput.text = root.dlgCurrent.toString()
        totInput.text = root.dlgTotal.toString()
        newSubInput.text = ""
        hourInput.text = root.dlgHours.toString()
        minuteInput.text = root.dlgMinutes.toString()
        secondInput.text = root.dlgSeconds.toString()
        cmdInput.text = root.dlgCommand
        tagsInput.text = root.dlgTags
        root.showAddDialog = true
    }

    function commitDialog() {
        if (root.dlgContent.trim().length === 0) return
        const item = {
            "content": root.dlgContent,
            "priority": root.dlgPriority,
            "type": root.dlgType,
            "code": root.dlgCode,
            "items": root.dlgItems,
            "current": root.dlgCurrent,
            "total": root.dlgTotal,
            "tags": root.dlgTags.split(",").map(function (t) { return t.trim(); }).filter(function (t) { return t.length > 0; }),
            "due": root.dlgDue,
            "recurrence": root.dlgRecurrence,
        }
        if (root.dlgType === "timer") {
            const dur = root.dlgHours * 3600 + root.dlgMinutes * 60 + root.dlgSeconds
            item.duration = dur
            item.timerRemaining = dur
            item.timerRunning = false
            item.timerEnd = 0
            item.command = root.dlgCommand
        }
        if (root.editingIndex >= 0) {
            Todo.updateItem(root.editingIndex, item)
        } else {
            item.done = false
            item.current = 0
            Todo.addItem(item)
        }
        root.showAddDialog = false
    }

    function addSubFromField() {
        const txt = root.dlgNewSub.trim()
        if (txt.length === 0) return
        root.dlgItems = root.dlgItems.concat([{"text": txt, "done": false}])
        root.dlgNewSub = ""
        newSubInput.text = ""
    }

    Keys.onPressed: (event) => {
        // Open add dialog on "N"
        if (event.key === Qt.Key_N && !root.showAddDialog) {
            root.openAdd()
            event.accepted = true;
        }
        else if (event.key === Qt.Key_Escape && root.showAddDialog) {
            root.showAddDialog = false
            event.accepted = true;
        }
    }

    component Field: TextField {
        id: field
        padding: 10
        color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
        renderType: Text.NativeRendering
        selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
        selectionColor: Appearance.colors.colSecondaryContainer
        placeholderTextColor: Appearance.m3colors.m3outline
        background: Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.verysmall
            border.width: 2
            border.color: field.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outline
            color: "transparent"
        }
        cursorDelegate: Rectangle {
            width: 1
            color: field.activeFocus ? Appearance.colors.colPrimary : "transparent"
            radius: 1
        }
    }

    component ChoiceChip: RippleButton {
        id: chip
        property string label: ""
        property bool selected: false
        property color accent: Appearance.colors.colPrimary
        property color dotColor: "transparent"

        implicitHeight: 32
        implicitWidth: chipRow.implicitWidth + 20
        buttonRadius: Appearance.rounding.full
        toggled: chip.selected

        colBackground: "transparent"
        colBackgroundHover: ColorUtils.transparentize(chip.accent, 0.86)
        colBackgroundToggled: ColorUtils.transparentize(chip.accent, 0.72)
        colBackgroundToggledHover: ColorUtils.transparentize(chip.accent, 0.62)
        colRipple: ColorUtils.transparentize(chip.accent, 0.5)

        contentItem: RowLayout {
            id: chipRow
            spacing: 6

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: chip.dotColor.a > 0
                implicitWidth: 10
                implicitHeight: 10
                radius: width / 2
                color: chip.dotColor
            }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: chip.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: chip.selected ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnSurfaceVariant
            }
        }
    }

    // Две видимые колонки: незавершённые | завершённые (равной ширины)
    RowLayout {
        id: columnsRow
        anchors.fill: parent
        spacing: 12

        readonly property real columnWidth: (width - spacing * 2 - 1) / 2

        ColumnLayout { // незавершённые
            Layout.preferredWidth: columnsRow.columnWidth
            Layout.fillWidth: false
            Layout.fillHeight: true
            spacing: 8

            TaskList {
                Layout.fillWidth: true
                Layout.fillHeight: true
                listBottomPadding: 8
                listKey: "unfinished"
                emptyPlaceholderIcon: "check_circle"
                emptyPlaceholderText: Translation.tr("Nothing here!")
                taskList: root.unfinishedList
                onEditRequested: (index) => root.openEdit(index)
            }
        }

        Rectangle { // вертикальный разделитель
            Layout.fillHeight: true
            Layout.topMargin: 6
            Layout.bottomMargin: 6
            implicitWidth: 1
            color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.5)
        }

        ColumnLayout { // готово
            Layout.preferredWidth: columnsRow.columnWidth
            Layout.fillWidth: false
            Layout.fillHeight: true
            spacing: 8

            TaskList {
                Layout.fillWidth: true
                Layout.fillHeight: true
                listBottomPadding: 8
                listKey: "done"
                emptyPlaceholderIcon: "checklist"
                emptyPlaceholderText: Translation.tr("Nothing here!")
                taskList: root.doneList
                onEditRequested: (index) => root.openEdit(index)
            }
        }
    }

    Item {
        anchors.fill: parent
        z: 9999

        visible: opacity > 0
        opacity: root.showAddDialog ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        onVisibleChanged: {
            if (!visible) {
                root.dlgNewSub = ""
            }
        }

        Rectangle { // Scrim
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.colors.colScrim
            MouseArea {
                hoverEnabled: true
                anchors.fill: parent
                preventStealing: true
                propagateComposedEvents: false
                onClicked: root.showAddDialog = false
            }
        }

        Rectangle { // The dialog
            id: dialog
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: root.dialogMargins
            implicitHeight: Math.min(dialogColumn.implicitHeight + 32, 580)
            color: Appearance.m3colors.m3surfaceContainerHigh
            radius: Appearance.rounding.normal

            ScrollView {
                id: dialogScroll
                anchors.fill: parent
                anchors.margins: 16
                contentWidth: availableWidth
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                ColumnLayout {
                    id: dialogColumn
                    width: dialogScroll.availableWidth
                    spacing: 16

                    StyledText {
                        Layout.fillWidth: true
                        color: Appearance.m3colors.m3onSurface
                        font.pixelSize: Appearance.font.pixelSize.larger
                        text: root.editingIndex >= 0
                            ? Translation.tr("Edit task")
                            : Translation.tr("Add task")
                    }

                    Field { // title
                        id: titleInput
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Task description")
                        focus: root.showAddDialog
                        onTextChanged: root.dlgContent = text
                        onAccepted: root.commitDialog()
                    }

                    // ------------------------------------------- приоритет
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        StyledText {
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: Translation.tr("Priority")
                        }
                        RowLayout {
                            spacing: 6
                            Repeater {
                                model: root.priorityList
                                delegate: ChoiceChip {
                                    required property var modelData
                                    label: modelData.name
                                    selected: root.dlgPriority === modelData.id
                                    accent: modelData.color === "transparent"
                                        ? Appearance.colors.colOutline
                                        : modelData.color
                                    dotColor: modelData.color
                                    onClicked: root.dlgPriority = modelData.id
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }

                    // ------------------------------------------- теги
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        StyledText {
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: Translation.tr("Tags (comma separated)")
                        }
                        Field {
                            id: tagsInput
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("e.g. work, home")
                            onTextChanged: root.dlgTags = text
                        }
                    }

                    // ------------------------------------------- дедлайн
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        StyledText {
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: Translation.tr("Due date")
                        }
                        RowLayout {
                            spacing: 6
                            Repeater {
                                model: root.dueOptions
                                delegate: ChoiceChip {
                                    required property var modelData
                                    label: modelData.name
                                    selected: modelData.id < 0
                                        ? (root.dlgDue === 0)
                                        : (root.dlgDue > 0 && Math.abs(root.dlgDue - root.computeDue(modelData.id)) < 60)
                                    accent: Appearance.colors.colPrimary
                                    onClicked: root.dlgDue = root.computeDue(modelData.id)
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }

                    // ------------------------------------------- повтор
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        StyledText {
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: Translation.tr("Repeat")
                        }
                        RowLayout {
                            spacing: 6
                            Repeater {
                                model: root.recurrenceList
                                delegate: ChoiceChip {
                                    required property var modelData
                                    label: modelData.name
                                    selected: root.dlgRecurrence === modelData.id
                                    accent: Appearance.colors.colPrimary
                                    onClicked: root.dlgRecurrence = modelData.id
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }

                    // ------------------------------------------- тип
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        StyledText {
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: Translation.tr("Type")
                        }
                        RowLayout {
                            spacing: 6
                            Repeater {
                                model: root.typeList
                                delegate: ChoiceChip {
                                    required property var modelData
                                    label: modelData.name
                                    selected: root.dlgType === modelData.id
                                    accent: Appearance.colors.colPrimary
                                    onClicked: root.dlgType = modelData.id
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }

                    // ------------------------------------------- тело по типу
                    Rectangle { // code
                        Layout.fillWidth: true
                        visible: root.dlgType === "code"
                        implicitHeight: 130
                        radius: Appearance.rounding.verysmall
                        color: Appearance.colors.colLayer1

                        TextArea {
                            id: codeArea
                            anchors.fill: parent
                            anchors.margins: 10
                            padding: 0
                            wrapMode: TextEdit.Wrap
                            placeholderText: Translation.tr("Code / snippet")
                            placeholderTextColor: Appearance.m3colors.m3outline
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                            selectionColor: Appearance.colors.colSecondaryContainer
                            selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                            background: null
                            onTextChanged: root.dlgCode = text
                        }
                    }

                    ColumnLayout { // checklist
                        Layout.fillWidth: true
                        visible: root.dlgType === "checklist"
                        spacing: 6

                        Column {
                            id: dlgSubList
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: root.dlgItems
                                delegate: RowLayout {
                                    id: dlgSubRow
                                    required property var modelData
                                    required property int index
                                    width: dlgSubList.width
                                    spacing: 6

                                    Field {
                                        Layout.fillWidth: true
                                        text: dlgSubRow.modelData.text
                                        placeholderText: Translation.tr("Sub-item")
                                        onTextChanged: {
                                            // Правим элемент на месте, без пересоздания
                                            // всего списка (иначе поле теряет фокус).
                                            if (root.dlgItems[dlgSubRow.index])
                                                root.dlgItems[dlgSubRow.index].text = text
                                        }
                                    }
                                    IconToolbarButton {
                                        text: "close"
                                        Layout.fillHeight: false
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.preferredWidth: 32
                                        Layout.preferredHeight: 32
                                        onClicked: {
                                            const next = root.dlgItems.slice(0)
                                            next.splice(dlgSubRow.index, 1)
                                            root.dlgItems = next
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Field {
                                id: newSubInput
                                Layout.fillWidth: true
                                placeholderText: Translation.tr("Add sub-item…")
                                onTextChanged: root.dlgNewSub = text
                                onAccepted: root.addSubFromField()
                            }
                            DialogButton {
                                buttonText: Translation.tr("Add")
                                enabled: root.dlgNewSub.trim().length > 0
                                onClicked: root.addSubFromField()
                            }
                        }
                    }

                    RowLayout { // progress
                        Layout.fillWidth: true
                        visible: root.dlgType === "progress"
                        spacing: 8

                        Field {
                            id: curInput
                            Layout.preferredWidth: 100
                            placeholderText: "0"
                            validator: IntValidator { bottom: 0 }
                            onTextChanged: root.dlgCurrent = Math.max(0, parseInt(text) || 0)
                        }
                        StyledText {
                            text: "/"
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        Field {
                            id: totInput
                            Layout.preferredWidth: 100
                            placeholderText: "0"
                            validator: IntValidator { bottom: 0 }
                            onTextChanged: root.dlgTotal = Math.max(0, parseInt(text) || 0)
                        }
                        Item { Layout.fillWidth: true }
                    }

                    ColumnLayout { // timer
                        Layout.fillWidth: true
                        visible: root.dlgType === "timer"
                        spacing: 6

                        StyledText {
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: Translation.tr("Duration")
                        }
                        RowLayout {
                            spacing: 8

                            Field {
                                id: hourInput
                                Layout.preferredWidth: 64
                                placeholderText: "0"
                                validator: IntValidator { bottom: 0; top: 99 }
                                onTextChanged: root.dlgHours = Math.max(0, parseInt(text) || 0)
                            }
                            StyledText {
                                text: Translation.tr("Hours")
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            Field {
                                id: minuteInput
                                Layout.preferredWidth: 64
                                placeholderText: "0"
                                validator: IntValidator { bottom: 0; top: 59 }
                                onTextChanged: root.dlgMinutes = Math.max(0, parseInt(text) || 0)
                            }
                            StyledText {
                                text: Translation.tr("Minutes")
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            Field {
                                id: secondInput
                                Layout.preferredWidth: 64
                                placeholderText: "0"
                                validator: IntValidator { bottom: 0; top: 59 }
                                onTextChanged: root.dlgSeconds = Math.max(0, parseInt(text) || 0)
                            }
                            StyledText {
                                text: Translation.tr("Seconds")
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            Item { Layout.fillWidth: true }
                        }

                        StyledText {
                            Layout.topMargin: 6
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.small
                            text: Translation.tr("Run command on finish (optional)")
                        }
                        Field {
                            id: cmdInput
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("e.g. notify-send \"done\"")
                            font.family: Appearance.font.family.monospace
                            onTextChanged: root.dlgCommand = text
                        }
                    }

                    RowLayout { // кнопки
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 5

                        Item { Layout.fillWidth: true }
                        DialogButton {
                            buttonText: Translation.tr("Cancel")
                            onClicked: root.showAddDialog = false
                        }
                        DialogButton {
                            buttonText: root.editingIndex >= 0
                                ? Translation.tr("Save")
                                : Translation.tr("Add")
                            enabled: root.dlgContent.trim().length > 0
                            onClicked: root.commitDialog()
                        }
                    }
                }
            }
        }
    }
}
