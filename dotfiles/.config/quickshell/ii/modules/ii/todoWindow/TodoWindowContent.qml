import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    focus: true

    property int remainingCount: Todo.list.filter(task => !task.done).length
    property int doneCount: Todo.list.filter(task => task.done).length
    property int totalCount: Todo.list.length
    readonly property real doneRatio: totalCount > 0 ? doneCount / totalCount : 0

    // Геометрия, общая для хедера и тела — чтобы заголовки колонок
    // в хедере совпадали со своими списками.
    readonly property int overviewWidth: 200
    readonly property int bodySpacing: 8
    readonly property int columnsOffset: overviewWidth + bodySpacing

    property bool undoVisible: false

    // Диалог добавления ежедневного пункта
    property bool dailyDialogVisible: false
    property string dailyText: ""
    property string dailyRemind: ""
    property string dailyDuration: ""
    readonly property bool dailyRemindValid: root.dailyRemind.trim().length === 0
        || Daily.parseMinutes(root.dailyRemind) >= 0
    readonly property bool dailyDurationValid: root.dailyDuration.trim().length === 0
        || Daily.parseDuration(root.dailyDuration) > 0

    function openDailyDialog() {
        root.dailyText = ""
        root.dailyRemind = ""
        root.dailyDuration = ""
        dailyTextInput.text = ""
        dailyRemindInput.text = ""
        dailyDurationInput.text = ""
        root.dailyDialogVisible = true
        dailyTextInput.forceActiveFocus()
    }

    function commitDailyDialog() {
        const txt = root.dailyText.trim()
        if (txt.length === 0 || !root.dailyRemindValid || !root.dailyDurationValid) return
        Daily.addItem(txt, root.dailyRemind, root.dailyDuration)
        root.dailyDialogVisible = false
    }

    onDailyDialogVisibleChanged: {
        if (root.dailyDialogVisible) dailyTextInput.forceActiveFocus()
    }

    component MiniTick: RippleButton {
        id: mini
        property string symbol
        property color colText: Appearance.colors.colOnLayer1
        implicitWidth: 22
        implicitHeight: 22
        buttonRadius: Appearance.rounding.full
        colBackground: "transparent"
        colBackgroundHover: ColorUtils.transparentize(mini.colText, 0.86)
        colRipple: ColorUtils.transparentize(mini.colText, 0.7)
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: mini.symbol
            iconSize: Appearance.font.pixelSize.normal
            color: mini.colText
        }
    }

    Connections {
        target: Todo
        function onItemDeleted(content) {
            root.undoVisible = true;
            undoHideTimer.restart();
        }
    }

    Timer {
        id: undoHideTimer
        interval: 5000
        onTriggered: root.undoVisible = false
    }

    Keys.onPressed: event => {
        if (root.dailyDialogVisible) {
            if (event.key === Qt.Key_Escape) {
                root.dailyDialogVisible = false;
                event.accepted = true;
            }
            return;
        }
        if (event.key === Qt.Key_Escape && !todoWidget.showAddDialog) {
            GlobalStates.todoWindowOpen = false;
            event.accepted = true;
        } else if (event.key === Qt.Key_N && !todoWidget.showAddDialog) {
            todoWidget.openAdd();
            event.accepted = true;
        } else if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier)) {
            Todo.undoDelete();
            root.undoVisible = false;
            event.accepted = true;
        }
    }

    implicitHeight: Appearance.sizes.wallpaperSelectorHeight - Appearance.sizes.hyprlandGapsOut * 2
    implicitWidth: Appearance.sizes.wallpaperSelectorWidth - Appearance.sizes.hyprlandGapsOut * 2

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

        Item {
            anchors {
                fill: parent
                margins: 10
            }

            // ------------------------------------------------------- header
            Item {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 34

                // заголовки колонок, выровнены над своими списками
                RowLayout {
                    id: headerColumns
                    anchors.left: parent.left
                    anchors.leftMargin: root.columnsOffset
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    readonly property real columnWidth: (width - spacing * 2 - 1) / 2

                    RowLayout { // незавершённые
                        Layout.preferredWidth: headerColumns.columnWidth
                        Layout.fillWidth: false
                        spacing: 6

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            iconSize: Appearance.font.pixelSize.normal
                            text: "radio_button_unchecked"
                            color: Appearance.colors.colOnLayer1Inactive
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            font {
                                pixelSize: Appearance.font.pixelSize.normal
                                weight: Font.Medium
                            }
                            color: Appearance.colors.colOnLayer1
                            text: Translation.tr("Unfinished")
                        }
                        Rectangle { // счётчик
                            Layout.alignment: Qt.AlignVCenter
                            implicitHeight: 20
                            implicitWidth: headerUnfinishedCount.implicitWidth + 14
                            radius: height / 2
                            color: Appearance.colors.colSecondaryContainer

                            StyledText {
                                id: headerUnfinishedCount
                                anchors.centerIn: parent
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnSecondaryContainer
                                text: root.remainingCount.toString()
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                    }

                    Rectangle { // вертикальный разделитель
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 1
                        implicitHeight: 18
                        color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.5)
                    }

                    RowLayout { // завершённые
                        Layout.preferredWidth: headerColumns.columnWidth
                        Layout.fillWidth: false
                        spacing: 6

                        MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.normal
                            text: "check_circle"
                            color: Appearance.colors.colOnLayer1Inactive
                        }
                        StyledText {
                            font {
                                pixelSize: Appearance.font.pixelSize.normal
                                weight: Font.Medium
                            }
                            color: Appearance.colors.colOnLayer1
                            text: Translation.tr("Done")
                        }
                        Rectangle {
                            implicitWidth: headerDoneCount.implicitWidth + 14
                            implicitHeight: 18
                            radius: height / 2
                            color: Appearance.colors.colSecondaryContainer

                            StyledText {
                                id: headerDoneCount
                                anchors.centerIn: parent
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnSecondaryContainer
                                text: root.doneCount.toString()
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                    }
                }

                // справа: добавить, закрыть
                RowLayout {
                    id: headerActions
                    z: 1
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    IconToolbarButton {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        text: "add"
                        onClicked: todoWidget.openAdd()
                        StyledToolTip {
                            text: Translation.tr("Add task")
                        }
                    }
                    IconToolbarButton {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        text: "close"
                        onClicked: GlobalStates.todoWindowOpen = false
                        StyledToolTip {
                            text: Translation.tr("Close")
                        }
                    }
                }
            }

            // -------------------------------------------------------- body
            RowLayout {
                anchors.fill: parent
                spacing: root.bodySpacing

                // Обзорная панель
                Rectangle {
                    id: overviewPanel
                    Layout.preferredWidth: root.overviewWidth
                    Layout.fillHeight: true
                    radius: contentBackground.radius - 10
                    color: Appearance.colors.colLayer1

                    Flickable {
                        id: overviewScroll
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                            bottom: addTaskButton.top
                            margins: 12
                            bottomMargin: 6
                        }
                        clip: true
                        contentWidth: width
                        contentHeight: overviewCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                        id: overviewCol
                        width: overviewScroll.width
                        spacing: 6

                        RowLayout { // заголовок панели
                            spacing: 6

                            MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.larger
                                text: "fact_check"
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                font {
                                    pixelSize: Appearance.font.pixelSize.normal
                                    weight: Font.Medium
                                }
                                color: Appearance.colors.colOnLayer1
                                text: Translation.tr("Tasks")
                            }
                        }

                        StyledProgressBar {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            visible: root.totalCount > 0
                            value: root.doneRatio
                            StyledToolTip {
                                text: "%1 / %2".arg(root.doneCount).arg(root.totalCount)
                            }
                        }

                        RowLayout { // сделано
                            spacing: 6

                            MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.normal
                                text: "check_circle"
                                color: Appearance.colors.colOnLayer1Inactive
                            }
                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                                text: Translation.tr("Done")
                            }
                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                                text: root.doneCount.toString()
                            }
                        }
                        RowLayout { // не сделано
                            spacing: 6

                            MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.normal
                                text: "radio_button_unchecked"
                                color: Appearance.colors.colOnLayer1Inactive
                            }
                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                                text: Translation.tr("Unfinished")
                            }
                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                                text: root.remainingCount.toString()
                            }
                        }

                        RowLayout { // статистика за сегодня
                            spacing: 6

                            MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.normal
                                text: "today"
                                color: Appearance.colors.colOnLayer1Inactive
                            }
                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                                text: Translation.tr("Done today")
                            }
                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colPrimary
                                text: Todo.doneTodayCount.toString()
                            }
                        }

                        RowLayout { // серия дней подряд
                            spacing: 6
                            visible: Todo.streak > 0

                            MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.normal
                                text: "local_fire_department"
                                color: Appearance.colors.colOnLayer1Inactive
                            }
                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                                text: Translation.tr("Streak")
                            }
                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colPrimary
                                text: Todo.streak.toString()
                            }
                        }

                        Rectangle { // разделитель перед ежедневными
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            implicitHeight: 1
                            color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.5)
                        }

                        RowLayout { // заголовок "Ежедневные"
                            Layout.topMargin: 2
                            spacing: 6

                            MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.normal
                                text: "event_available"
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                font {
                                    pixelSize: Appearance.font.pixelSize.small
                                    weight: Font.Medium
                                }
                                color: Appearance.colors.colOnLayer1
                                text: Translation.tr("Daily tasks")
                            }
                            MiniTick {
                                symbol: "add"
                                colText: Appearance.colors.colPrimary
                                onClicked: root.openDailyDialog()
                                StyledToolTip {
                                    text: Translation.tr("Add daily task")
                                }
                            }
                        }

                        ColumnLayout { // список ежедневных пунктов
                            Layout.fillWidth: true
                            spacing: 2

                            Repeater {
                                model: Daily.list

                                delegate: ColumnLayout {
                                    id: dailyRow
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    spacing: 1

                                    RowLayout { // строка задачи
                                        Layout.fillWidth: true
                                        spacing: 4

                                        MiniTick {
                                            implicitWidth: 22
                                            implicitHeight: 22
                                            symbol: dailyRow.modelData.done ? "check_circle" : "radio_button_unchecked"
                                            colText: dailyRow.modelData.done
                                                ? Appearance.colors.colPrimary
                                                : Appearance.colors.colOnLayer1Inactive
                                            onClicked: Daily.toggle(dailyRow.index)
                                            StyledToolTip {
                                                text: Translation.tr("Done")
                                            }
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: dailyRow.modelData.text
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.strikeout: dailyRow.modelData.done
                                            color: dailyRow.modelData.done
                                                ? Appearance.colors.colOnLayer1Inactive
                                                : Appearance.colors.colOnLayer1
                                        }
                                        StyledText { // время напоминания
                                            visible: String(dailyRow.modelData.remind ?? "").length > 0
                                            text: dailyRow.modelData.remind
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Daily.isOverdue(dailyRow.modelData) ? Font.DemiBold : Font.Normal
                                            color: Daily.isOverdue(dailyRow.modelData)
                                                ? Appearance.colors.colError
                                                : Appearance.colors.colPrimary
                                        }
                                    }

                                    RowLayout { // компактный таймер — чуть ниже задачи
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 26
                                        visible: (dailyRow.modelData.duration ?? 0) > 0
                                        spacing: 4

                                        RippleButton { // «Начать»
                                            visible: Daily.timerIndex !== dailyRow.index
                                            implicitHeight: 20
                                            implicitWidth: startRow.implicitWidth + 16
                                            buttonRadius: Appearance.rounding.full
                                            colBackground: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.84)
                                            colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.72)
                                            colRipple: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)
                                            onClicked: Daily.startTimer(dailyRow.index)
                                            contentItem: Item {
                                                RowLayout {
                                                    id: startRow
                                                    anchors.centerIn: parent
                                                    spacing: 2
                                                    MaterialSymbol {
                                                        Layout.alignment: Qt.AlignVCenter
                                                        text: "play_arrow"
                                                        iconSize: Appearance.font.pixelSize.small
                                                        color: Appearance.colors.colPrimary
                                                    }
                                                    StyledText {
                                                        Layout.alignment: Qt.AlignVCenter
                                                        text: Translation.tr("Start")
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        color: Appearance.colors.colPrimary
                                                    }
                                                }
                                            }
                                        }

                                        RowLayout { // идёт отсчёт
                                            visible: Daily.timerIndex === dailyRow.index
                                            spacing: 2
                                            MaterialSymbol {
                                                text: "timer"
                                                iconSize: Appearance.font.pixelSize.small
                                                color: Appearance.colors.colPrimary
                                            }
                                            StyledText {
                                                text: Daily.formatSeconds(Daily.timerRemaining)
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                font.weight: Font.DemiBold
                                                color: Appearance.colors.colPrimary
                                            }
                                            MiniTick {
                                                symbol: "stop_circle"
                                                colText: Appearance.colors.colError
                                                onClicked: Daily.stopTimer()
                                                StyledToolTip {
                                                    text: Translation.tr("Stop")
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: Daily.list.length === 0
                                text: Translation.tr("Nothing here!")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer1Inactive
                            }
                        }

                        }   // ColumnLayout (overviewCol)
                    }       // Flickable (overviewScroll)

                    RippleButton { // добавить задачу — прижат к низу панели
                        id: addTaskButton
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                            margins: 12
                        }
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.normal
                        toggled: true
                        colBackgroundToggled: Appearance.colors.colPrimary
                        colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                        colRippleToggled: Appearance.colors.colPrimaryActive
                        onClicked: todoWidget.openAdd()

                        contentItem: RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.larger
                                text: "add"
                                color: Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnPrimary
                                text: Translation.tr("Add task")
                            }
                        }
                    }
                }           // Rectangle (overviewPanel)

                // Список задач
                Rectangle {
                    id: todoArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.topMargin: 44
                    radius: contentBackground.radius - 10
                    color: Appearance.colors.colLayer1
                    clip: true

                    TodoWidget {
                        id: todoWidget
                        anchors {
                            fill: parent
                            margins: 8
                        }
                    }
                }
            }
        }
    }

    // Undo snackbar
    Rectangle {
        id: undoSnackbar
        z: 1000
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        implicitHeight: 46
        implicitWidth: snackRow.implicitWidth + 24
        radius: Appearance.rounding.full
        color: Appearance.colors.colTooltip
        border.width: 1
        border.color: ColorUtils.transparentize(Appearance.colors.colOnTooltip, 0.86)
        visible: opacity > 0
        opacity: root.undoVisible ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        RowLayout {
            id: snackRow
            anchors.centerIn: parent
            spacing: 14

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: "delete"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnTooltip
            }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: Translation.tr("Task deleted")
                color: Appearance.colors.colOnTooltip
                elide: Text.ElideRight
                Layout.maximumWidth: 360
            }
            RippleButton {
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 30
                implicitWidth: 86
                buttonRadius: Appearance.rounding.full
                toggled: true
                colBackgroundToggled: Appearance.colors.colPrimary
                colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                colRippleToggled: Appearance.colors.colPrimaryActive
                onClicked: {
                    Todo.undoDelete();
                    root.undoVisible = false;
                }
                contentItem: StyledText {
                    anchors.centerIn: parent
                    text: Translation.tr("Undo")
                    color: Appearance.colors.colOnPrimary
                    font {
                        pixelSize: Appearance.font.pixelSize.small
                        weight: Font.Medium
                    }
                }
            }
        }
    }

    // Диалог добавления ежедневного пункта
    Rectangle {
        id: dailyDialogOverlay
        anchors.fill: parent
        z: 1001
        visible: root.dailyDialogVisible
        color: Appearance.colors.colScrim

        MouseArea {
            anchors.fill: parent
            onClicked: root.dailyDialogVisible = false
        }

        Rectangle {
            id: dailyDialogPanel
            anchors.centerIn: parent
            width: Math.min(parent.width - 32, 360)
            implicitHeight: dailyDialogColumn.implicitHeight + 40
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                id: dailyDialogColumn
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.m3colors.m3onSurface
                    font.pixelSize: Appearance.font.pixelSize.larger
                    text: Translation.tr("Add daily task")
                }

                MaterialTextField {
                    id: dailyTextInput
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Daily task")
                    focus: root.dailyDialogVisible
                    onTextChanged: root.dailyText = text
                    onAccepted: root.commitDailyDialog()
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    StyledText {
                        Layout.fillWidth: true
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: Translation.tr("Reminder time")
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialTextField {
                            id: dailyRemindInput
                            Layout.preferredWidth: 100
                            placeholderText: "08:00"
                            onTextChanged: root.dailyRemind = text
                            onAccepted: root.commitDailyDialog()
                        }
                        StyledText {
                            Layout.fillWidth: true
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            text: Translation.tr("Empty — no reminder")
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: Translation.tr("Timer (minutes)")
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialTextField {
                            id: dailyDurationInput
                            Layout.preferredWidth: 100
                            placeholderText: "25"
                            onTextChanged: root.dailyDuration = text
                            onAccepted: root.commitDailyDialog()
                        }
                        StyledText {
                            Layout.fillWidth: true
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            text: Translation.tr("Empty — no timer")
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item { Layout.fillWidth: true }
                    DialogButton {
                        buttonText: Translation.tr("Cancel")
                        onClicked: root.dailyDialogVisible = false
                    }
                    DialogButton {
                        buttonText: Translation.tr("Add")
                        enabled: root.dailyText.trim().length > 0 && root.dailyRemindValid && root.dailyDurationValid
                        onClicked: root.commitDailyDialog()
                    }
                }
            }
        }
    }
}
