import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root
    readonly property bool usePasswordChars: !PolkitService.flow?.responseVisible ?? true
    readonly property string keyboardLayoutCode: {
        const layoutName = HyprlandXkb.currentLayoutCode;
        if (!layoutName) return "";
        return layoutName.split(" ")[0].slice(0, 2).toUpperCase();
    }

    Component.onCompleted: {
        if (root.usePasswordChars)
            HyprlandXkb.switchToEnglishLayout();
    }

    Keys.onPressed: event => { // Esc to close
        if (event.key === Qt.Key_Escape) {
            PolkitService.cancel();
        }
    }

    function submit() {
        PolkitService.submit(inputField.text);
    }

    function focusPasswordField() {
        if (!PolkitService.interactionAvailable) return;
        Qt.callLater(() => {
            inputField.forceActiveFocus();
        });
    }

    Connections {
        target: PolkitService
        function onInteractionAvailableChanged() {
            if (!PolkitService.interactionAvailable) return;
            inputField.text = "";
            root.focusPasswordField();
        }
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        color: ColorUtils.applyAlpha(Appearance.m3colors.m3scrim, 0.4)
        opacity: 0
        Component.onCompleted: {
            opacity = 1
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    // Start the entrance animation after the layer surface is mapped,
    // otherwise it finishes before the window becomes visible.
    Timer {
        interval: 150
        running: true
        onTriggered: dialog.show = true
    }

    WindowDialog {
        id: dialog
        anchors.centerIn: parent
        backgroundWidth: 460
        backgroundAnimationMovementDistance: 160
        backgroundAnimationDuration: 340
        animateBackgroundHeight: false
        backgroundColor: ColorUtils.applyAlpha(Appearance.colors.colLayer0, 0.92)
        borderWidth: 1
        borderColor: Appearance.colors.colLayer0Border
        show: false
        opacity: show ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: dialog.backgroundAnimationDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }
        onVisibleChanged: {
            if (visible)
                root.focusPasswordField();
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 56
            implicitHeight: 56
            radius: width / 2
            color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.15)

            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: 30
                text: "security"
                color: Appearance.colors.colPrimary
            }
        }

        WindowDialogTitle {
            id: titleText
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Authentication")
        }

        WindowDialogParagraph {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignLeft
            text: PolkitService.cleanMessage
        }

        // Password field, styled like the NixOS config editor
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer1
            border.width: inputField.activeFocus ? 2 : 1
            border.color: inputField.activeFocus
                ? Appearance.colors.colPrimary
                : Appearance.colors.colOutlineVariant

            TextField {
                id: inputField
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                background: null
                padding: 0
                focus: true
                enabled: PolkitService.interactionAvailable
                placeholderText: PolkitService.cleanPrompt
                placeholderTextColor: Appearance.colors.colOnLayer1Inactive
                color: Appearance.colors.colOnLayer1
                echoMode: root.usePasswordChars ? TextInput.Password : TextInput.Normal
                passwordCharacter: "●"
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse: true
                selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                selectionColor: Appearance.colors.colSecondaryContainer
                font {
                    family: Appearance.font.family.main
                    pixelSize: Appearance.font.pixelSize.large
                    hintingPreference: Font.PreferFullHinting
                    variableAxes: Appearance.font.variableAxes.main
                }
                onAccepted: root.submit();

                Keys.onPressed: event => { // Esc to close
                    if (event.key === Qt.Key_Escape) {
                        PolkitService.cancel();
                    }
                }
            }

            Rectangle {
                visible: root.keyboardLayoutCode.length > 0
                anchors {
                    right: parent.right
                    rightMargin: 12
                    verticalCenter: parent.verticalCenter
                }
                implicitWidth: layoutCodeText.implicitWidth + 12
                implicitHeight: 22
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2

                StyledText {
                    id: layoutCodeText
                    anchors.centerIn: parent
                    text: root.keyboardLayoutCode
                    color: Appearance.colors.colOnLayer2
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    animateChange: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.IBeamCursor
                    onClicked: {
                        inputField.forceActiveFocus();
                        inputField.cursorPosition = inputField.text.length;
                    }
                }
            }
        }

        // Buttons, same pill style as the NixOS config editor toolbar
        Item {
            Layout.fillWidth: true
            implicitHeight: 40

            component ActionButton: Rectangle {
                id: actionButton
                property string iconText
                property string label
                property bool primary: false
                signal clicked()

                implicitHeight: 40
                radius: Appearance.rounding.full
                color: !actionButton.enabled
                    ? Appearance.colors.colLayer2
                    : actionButton.primary
                        ? (mouseArea.pressed
                            ? Appearance.colors.colPrimaryActive
                            : mouseArea.containsMouse
                                ? Appearance.colors.colPrimaryHover
                                : Appearance.colors.colPrimary)
                        : (mouseArea.pressed
                            ? Appearance.colors.colLayer2Active
                            : mouseArea.containsMouse
                                ? Appearance.colors.colLayer2Hover
                                : Appearance.colors.colLayer2)
                border.width: actionButton.primary ? 0 : 1
                border.color: Appearance.colors.colOutlineVariant
                opacity: actionButton.enabled ? 1 : 0.5
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        iconSize: 20
                        text: actionButton.iconText
                        color: actionButton.primary
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: actionButton.label
                        color: actionButton.primary
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }
                }

                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: actionButton.enabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: actionButton.clicked()
                }
            }

            ActionButton {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: (parent.width - 10) / 2
                height: parent.height
                iconText: "close"
                label: Translation.tr("Cancel")
                onClicked: PolkitService.cancel()
            }
            ActionButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: (parent.width - 10) / 2
                height: parent.height
                iconText: "check"
                label: Translation.tr("OK")
                primary: true
                enabled: PolkitService.interactionAvailable
                onClicked: root.submit()
            }
        }
    }
}
