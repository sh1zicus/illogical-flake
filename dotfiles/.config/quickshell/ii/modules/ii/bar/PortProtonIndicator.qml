pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

RippleButton {
    id: root

    property bool menuOpen: false

    visible: PortProtonService.running
    implicitWidth: 30
    implicitHeight: 30
    buttonRadius: Appearance.rounding.full
    toggled: root.menuOpen
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive

    background.implicitWidth: 30
    background.implicitHeight: 30
    background.anchors.centerIn: root

    downAction: () => root.menuOpen = !root.menuOpen
    altAction: () => PortProtonService.openLauncher()
    middleClickAction: () => PortProtonService.stopAll()

    function closeMenu() {
        root.menuOpen = false;
        focusGrab.active = false;
    }

    onMenuOpenChanged: {
        if (root.menuOpen) {
            Qt.callLater(() => {
                if (root.menuOpen)
                    focusGrab.active = true;
            });
        } else {
            focusGrab.active = false;
        }
    }

    Connections {
        target: PortProtonService
        function onRunningChanged() {
            if (!PortProtonService.running)
                root.closeMenu();
        }
    }

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: "sports_esports"
        iconSize: 24
        color: root.menuOpen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
    }

    Rectangle {
        visible: PortProtonService.runningGames.length > 1
        anchors {
            top: parent.top
            right: parent.right
        }
        width: 15
        height: 15
        radius: width / 2
        color: Appearance.colors.colError
        border.width: 1
        border.color: Appearance.colors.colLayer0

        StyledText {
            anchors.centerIn: parent
            text: PortProtonService.runningGames.length
            font.pixelSize: 9
            font.weight: Font.Bold
            color: Appearance.colors.colOnError
        }
    }

    HyprlandFocusGrab {
        id: focusGrab
        active: false
        windows: [menuColumn?.QsWindow?.window]
        onCleared: root.closeMenu()
    }

    StyledPopup {
        id: popup
        hoverTarget: root
        active: root.menuOpen

        ColumnLayout {
            id: menuColumn
            anchors.centerIn: parent
            implicitWidth: 300
            spacing: 4

            Repeater {
                model: PortProtonService.runningGames

                delegate: RowLayout {
                    id: gameRow
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        text: "sports_esports"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: gameRow.modelData.name || "PortProton"
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: gameRow.modelData.mode === "native"
                                ? Translation.tr("Native-сессия")
                                : (gameRow.modelData.prefix || "")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }

                    IconToolbarButton {
                        implicitWidth: 30
                        implicitHeight: 30
                        text: "stop_circle"
                        onClicked: PortProtonService.stopGame(gameRow.modelData)
                        StyledToolTip {
                            text: Translation.tr("Остановить")
                        }
                    }
                }
            }

            StyledText {
                visible: PortProtonService.runningGames.length === 0
                text: Translation.tr("Нет запущенных игр")
                color: Appearance.colors.colOnSurfaceVariant
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 36
                buttonRadius: Appearance.rounding.small
                downAction: () => {
                    root.closeMenu();
                    PortProtonService.openLauncher();
                }

                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    MaterialSymbol {
                        text: "open_in_new"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Открыть PortProton")
                    }
                }
            }

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 36
                buttonRadius: Appearance.rounding.small
                downAction: () => {
                    root.closeMenu();
                    PortProtonService.stopAll();
                }

                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    MaterialSymbol {
                        text: "stop_circle"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colError
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Остановить все")
                        color: Appearance.colors.colError
                    }
                }
            }
        }
    }
}
