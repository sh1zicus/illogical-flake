import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    required property var taskList
    property string emptyPlaceholderIcon
    property string emptyPlaceholderText
    property int todoListItemSpacing: 8
    property int todoListItemPadding: 12
    property int listBottomPadding: 80

    signal editRequested(int index)

    function progressColor(ratio) {
        if (ratio >= 1) return "#43A047" // зелёный — выполнено
        if (ratio >= 0.5) return "#F5A623" // жёлтый — больше половины
        return "#E5484D" // красный — меньше половины
    }

    function formatTime(seconds) {
        const total = Math.max(0, Math.round(seconds))
        const h = Math.floor(total / 3600)
        const m = Math.floor((total % 3600) / 60)
        const s = total % 60
        const pad = (n) => (n < 10 ? "0" + n : "" + n)
        return h > 0 ? (h + ":" + pad(m) + ":" + pad(s)) : (pad(m) + ":" + pad(s))
    }

    // Небольшая иконочная кнопка для служебных контролов (чекбокс подпункта,
    // «−»/«+» у прогресса, удаление подпункта).
    component MiniButton: RippleButton {
        id: mini
        property string symbol
        property color colText: Appearance.colors.colOnLayer1
        implicitWidth: 28
        implicitHeight: 28
        buttonRadius: Appearance.rounding.full
        colBackground: "transparent"
        colBackgroundHover: ColorUtils.transparentize(mini.colText, 0.86)
        colRipple: ColorUtils.transparentize(mini.colText, 0.7)
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: mini.symbol
            iconSize: Appearance.font.pixelSize.larger
            color: mini.colText
        }
    }

    // Текст, который можно выделять мышью и копировать (Ctrl+C)
    component SelectableText: TextArea {
        id: selText
        readOnly: true
        selectByMouse: true
        persistentSelection: true
        wrapMode: TextEdit.Wrap
        textFormat: TextEdit.PlainText
        renderType: Text.NativeRendering
        background: null
        padding: 0
        color: Appearance.colors.colOnLayer1
        selectionColor: Appearance.colors.colSecondaryContainer
        selectedTextColor: Appearance.colors.colOnSecondaryContainer
        font.pixelSize: Appearance.font.pixelSize.normal
        Layout.fillWidth: true
        implicitHeight: contentHeight
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            cursorShape: Qt.IBeamCursor
        }
    }

    StyledListView {
        id: listView
        anchors.fill: parent
        spacing: root.todoListItemSpacing
        animateAppearance: false
        model: ScriptModel {
            values: root.taskList
        }
        delegate: Item {
            id: todoItem
            required property var modelData
            property bool enableHeightAnimation: false

            implicitHeight: card.implicitHeight
            width: ListView.view.width
            clip: true

            Behavior on implicitHeight {
                enabled: enableHeightAnimation
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            Rectangle {
                id: card
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                implicitHeight: cardRow.implicitHeight
                radius: Appearance.rounding.normal

                readonly property bool isProgress: todoItem.modelData.type === "progress" && !todoItem.modelData.done
                readonly property bool isTimer: todoItem.modelData.type === "timer"
                // Остаток берём из «живого» элемента (modelData — это копия),
                // а через Todo.now привязка пересчитывается каждую секунду.
                readonly property real timerRemaining: {
                    const live = Todo.list[todoItem.modelData.originalIndex]
                    const it = live ?? todoItem.modelData
                    const now = Todo.now
                    if (it.timerRunning && it.timerEnd > 0) return Math.max(0, it.timerEnd - now)
                    return Math.max(0, it.timerRemaining ?? 0)
                }
                readonly property real timerDuration: {
                    const live = Todo.list[todoItem.modelData.originalIndex]
                    return (live?.duration) ?? (todoItem.modelData.duration ?? 0)
                }
                readonly property real timerRatio: card.timerDuration > 0
                    ? 1 - card.timerRemaining / card.timerDuration : 0
                property real fillRatio: {
                    if (!card.isProgress) return 0
                    const total = todoItem.modelData.total ?? 0
                    return total > 0 ? Math.max(0, Math.min(1, (todoItem.modelData.current ?? 0) / total)) : 0
                }
                property color cardBase: {
                    const base = todoItem.modelData.done ? Appearance.colors.colLayer1 : Appearance.colors.colLayer2
                    if (card.isProgress) return base
                    if (!todoItem.modelData.done && todoItem.modelData.priority && todoItem.modelData.priority !== "none")
                        return ColorUtils.mix(Todo.priorityColor(todoItem.modelData.priority), base, 0.16)
                    return base
                }
                property color fillColor: ColorUtils.mix(root.progressColor(card.fillRatio), card.cardBase, 0.3)
                color: cardHover.hovered
                    ? ColorUtils.mix(Appearance.colors.colPrimary, cardBase, 0.05)
                    : cardBase
                border.width: 1
                border.color: cardHover.hovered
                    ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.5)
                    : ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.45)

                property bool ready: false
                Component.onCompleted: ready = true

                Rectangle { // фон-индикатор прогресса
                    id: progressFill
                    visible: card.isProgress
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 1
                    width: (card.width - 2) * card.fillRatio
                    radius: Math.min(card.radius - 1, width / 2)
                    color: card.fillColor
                    Behavior on width {
                        enabled: card.ready
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                }

                HoverHandler {
                    id: cardHover
                }

                RowLayout {
                    id: cardRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 0

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        ColumnLayout { // блок контента (с отступами)
                            Layout.fillWidth: true
                            Layout.margins: root.todoListItemPadding
                            spacing: 8

                        // -------------------------------------------------- заголовок
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignTop
                                visible: todoItem.modelData.done
                                text: "check_circle"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colPrimary
                            }
                            SelectableText {
                                Layout.fillWidth: true
                                text: todoItem.modelData.content
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: todoItem.modelData.done
                                    ? Appearance.colors.colOnLayer1Inactive
                                    : Appearance.colors.colOnLayer1
                            }
                        }

                        // -------------------------------------------------- тело по типу
                        Rectangle { // code
                            Layout.fillWidth: true
                            visible: todoItem.modelData.type === "code"
                                && todoItem.modelData.code
                                && todoItem.modelData.code.length > 0
                            implicitHeight: codeText.implicitHeight + 16
                            radius: Appearance.rounding.verysmall
                            color: Appearance.colors.colLayer1

                            SelectableText {
                                id: codeText
                                anchors.fill: parent
                                anchors.margins: 8
                                text: todoItem.modelData.code ?? ""
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer1
                            }
                        }

                        Column { // checklist
                            id: checklistCol
                            Layout.fillWidth: true
                            visible: todoItem.modelData.type === "checklist"
                            spacing: 1

                            Repeater {
                                model: todoItem.modelData.items ?? []
                                delegate: Item {
                                    id: subItem
                                    required property var modelData
                                    required property int index
                                    width: checklistCol.width
                                    height: 30

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 6

                                        MiniButton {
                                            implicitWidth: 26
                                            implicitHeight: 26
                                            symbol: subItem.modelData.done ? "check_box" : "check_box_outline_blank"
                                            colText: subItem.modelData.done
                                                ? Appearance.colors.colPrimary
                                                : Appearance.colors.colOnLayer1
                                            onClicked: Todo.toggleSub(todoItem.modelData.originalIndex, subItem.index)
                                        }
                                        SelectableText {
                                            Layout.fillWidth: true
                                            text: subItem.modelData.text
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: subItem.modelData.done
                                                ? Appearance.colors.colOnLayer1Inactive
                                                : Appearance.colors.colOnLayer1
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout { // progress
                            Layout.fillWidth: true
                            visible: todoItem.modelData.type === "progress"
                            spacing: 6

                            MiniButton {
                                symbol: "remove"
                                onClicked: Todo.stepProgress(todoItem.modelData.originalIndex, -1)
                            }
                            MiniButton {
                                symbol: "add"
                                onClicked: Todo.stepProgress(todoItem.modelData.originalIndex, 1)
                            }
                            TextField { // числовой ввод текущего значения
                                id: progressField
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 46
                                implicitHeight: 30
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 0
                                rightPadding: 0
                                color: Appearance.colors.colOnLayer1
                                selectionColor: Appearance.colors.colSecondaryContainer
                                selectedTextColor: Appearance.colors.colOnSecondaryContainer
                                font.pixelSize: Appearance.font.pixelSize.small
                                inputMethodHints: Qt.ImhDigitsOnly
                                validator: IntValidator {
                                    bottom: 0
                                    top: Math.max(todoItem.modelData.total ?? 0, 0)
                                }
                                Binding on text {
                                    when: !progressField.activeFocus
                                    value: String(todoItem.modelData.current ?? 0)
                                }
                                background: Rectangle {
                                    radius: Appearance.rounding.verysmall
                                    color: Appearance.colors.colLayer1
                                    border.width: 1
                                    border.color: progressField.activeFocus
                                        ? Appearance.colors.colPrimary
                                        : ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.3)
                                }
                                onEditingFinished: {
                                    const v = parseInt(text)
                                    if (!isNaN(v)) Todo.setProgress(todoItem.modelData.originalIndex, v)
                                }
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                text: "/ " + (todoItem.modelData.total ?? 0)
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1Inactive
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                text: Math.round(card.fillRatio * 100) + "%"
                                font {
                                    pixelSize: Appearance.font.pixelSize.small
                                    weight: Font.DemiBold
                                }
                                color: root.progressColor(card.fillRatio)
                            }
                            Item {
                                Layout.fillWidth: true
                            }
                        }

                        ColumnLayout { // timer
                            Layout.fillWidth: true
                            visible: card.isTimer
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                MiniButton {
                                    symbol: (Todo.list[todoItem.modelData.originalIndex]?.timerRunning) ? "pause" : "play_arrow"
                                    onClicked: Todo.toggleTimer(todoItem.modelData.originalIndex)
                                    StyledToolTip {
                                        text: (Todo.list[todoItem.modelData.originalIndex]?.timerRunning)
                                            ? Translation.tr("Pause")
                                            : Translation.tr("Start")
                                    }
                                }
                                MiniButton {
                                    symbol: "restart_alt"
                                    onClicked: Todo.resetTimer(todoItem.modelData.originalIndex)
                                    StyledToolTip {
                                        text: Translation.tr("Reset")
                                    }
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: root.formatTime(card.timerRemaining)
                                    font {
                                        family: Appearance.font.family.monospace
                                        pixelSize: Appearance.font.pixelSize.larger
                                        weight: Font.DemiBold
                                    }
                                    color: card.timerRemaining <= 0
                                        ? Appearance.colors.colError
                                        : Appearance.colors.colPrimary
                                }
                                StyledProgressBar {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: card.timerDuration > 0
                                    value: Math.max(0, Math.min(1, card.timerRatio))
                                    highlightColor: card.timerRemaining <= 0
                                        ? Appearance.colors.colError
                                        : Appearance.colors.colPrimary
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: ((Todo.list[todoItem.modelData.originalIndex]?.command) ?? "").length > 0
                                text: "⚙ " + ((Todo.list[todoItem.modelData.originalIndex]?.command) ?? "")
                                elide: Text.ElideRight
                                font {
                                    family: Appearance.font.family.monospace
                                    pixelSize: Appearance.font.pixelSize.smaller
                                }
                                color: Appearance.colors.colOnLayer1Inactive
                            }
                        }

                        } // конец блока контента
                    } // конец колонки контента

                    // вертикальный ряд иконок-действий (справа, сверху вниз)
                    ColumnLayout {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 6
                        Layout.rightMargin: 6
                        Layout.bottomMargin: 6
                        spacing: 2

                        MiniButton {
                            implicitWidth: 26
                            implicitHeight: 26
                            symbol: todoItem.modelData.done ? "undo" : "check"
                            onClicked: Todo.setDone(todoItem.modelData.originalIndex, !todoItem.modelData.done)
                            StyledToolTip {
                                text: todoItem.modelData.done ? Translation.tr("Return") : Translation.tr("Done")
                            }
                        }
                        MiniButton {
                            implicitWidth: 26
                            implicitHeight: 26
                            symbol: "edit"
                            onClicked: root.editRequested(todoItem.modelData.originalIndex)
                            StyledToolTip {
                                text: Translation.tr("Edit")
                            }
                        }
                        MiniButton {
                            implicitWidth: 26
                            implicitHeight: 26
                            symbol: "delete"
                            colText: Appearance.colors.colError
                            onClicked: Todo.deleteItem(todoItem.modelData.originalIndex)
                            StyledToolTip {
                                text: Translation.tr("Delete")
                            }
                        }
                    }
                }
            }
        }
    }

    Item {
        // Placeholder when list is empty
        visible: opacity > 0
        opacity: taskList.length === 0 ? 1 : 0
        anchors.fill: parent

        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 5

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                iconSize: 55
                color: Appearance.m3colors.m3outline
                text: emptyPlaceholderIcon
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.m3colors.m3outline
                horizontalAlignment: Text.AlignHCenter
                text: emptyPlaceholderText
            }
        }
    }
}
