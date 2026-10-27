import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Rectangle {
    id: root

    property bool show: false
    default property alias contentData: contentColumn.data
    property real backgroundHeight: contentColumn.implicitHeight + dialogBackground.radius * 2
    property real backgroundWidth: 350
    property real backgroundAnimationMovementDistance: 60
    property int backgroundAnimationDuration: Appearance.animation.elementMoveFast.duration
    property bool animateBackgroundHeight: true
    property color backgroundColor: Appearance.m3colors.m3surfaceContainerHigh
    property color borderColor: "transparent"
    property int borderWidth: 0
    
    signal dismiss()
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            root.dismiss();
            event.accepted = true;
        }
    }

    color: root.show ? Appearance.colors.colScrim : ColorUtils.transparentize(Appearance.colors.colScrim)
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }
    visible: dialogBackground.implicitHeight > 0

    radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

    MouseArea { // Clicking outside the dialog should dismiss
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: root.dismiss()
    }

    Rectangle {
        id: dialogBackground
        anchors.horizontalCenter: parent.horizontalCenter
        radius: Appearance.rounding.large
        color: root.backgroundColor
        border.width: root.borderWidth
        border.color: root.borderColor
        
        property real targetY: root.height / 2 - root.backgroundHeight / 2
        y: root.show ? targetY : (targetY - root.backgroundAnimationMovementDistance)
        implicitWidth: root.backgroundWidth
        implicitHeight: root.show ? root.backgroundHeight : 0
        Behavior on implicitHeight {
            enabled: root.animateBackgroundHeight
            NumberAnimation {
                id: dialogBackgroundHeightAnimation
                duration: root.backgroundAnimationDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.show ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel
            }
        }
        Behavior on y {
            NumberAnimation {
                duration: root.backgroundAnimationDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.show ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel
            }
        }

        MouseArea { // So clicking inside the dialog won't dismiss
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
        }

        ColumnLayout {
            id: contentColumn
            anchors {
                fill: parent
                margins: dialogBackground.radius
            }
            spacing: 16
            opacity: root.show ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

        }
    }
}
