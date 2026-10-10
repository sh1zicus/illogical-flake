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

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && !todoWidget.showAddDialog) {
            GlobalStates.todoWindowOpen = false;
            event.accepted = true;
        } else if (event.key === Qt.Key_N && !todoWidget.showAddDialog) {
            todoWidget.openAdd();
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

        ColumnLayout {
            anchors {
                fill: parent
                margins: 10
            }
            spacing: 8

            // ------------------------------------------------------- header
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                Layout.maximumHeight: 38

                // слева: иконка + заголовок
                RowLayout {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    MaterialSymbol {
                        iconSize: Appearance.font.pixelSize.larger
                        text: "task_alt"
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                        font {
                            pixelSize: Appearance.font.pixelSize.normal
                            weight: Font.Medium
                        }
                        color: Appearance.colors.colOnLayer1
                        text: Translation.tr("To Do")
                    }
                }

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
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: root.bodySpacing

                // Обзорная панель
                Rectangle {
                    id: overviewPanel
                    Layout.preferredWidth: root.overviewWidth
                    Layout.fillHeight: true
                    radius: contentBackground.radius - 10
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
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

                        Item { // большое число: осталось
                            Layout.fillWidth: true
                            Layout.preferredHeight: 104

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 2

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    font {
                                        pixelSize: Appearance.font.pixelSize.huge
                                        weight: Font.DemiBold
                                    }
                                    color: Appearance.colors.colPrimary
                                    text: root.remainingCount.toString()
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnSurfaceVariant
                                    text: Translation.tr("Unfinished")
                                }
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

                        Item { // пружина
                            Layout.fillHeight: true
                        }

                        RippleButton { // добавить задачу
                            Layout.fillWidth: true
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
                    }
                }

                // Список задач
                Rectangle {
                    id: todoArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
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
}
