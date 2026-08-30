pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common

Item {
    id: root

    // Simple round dot crosshair, fully configurable from the settings app.
    property string dotColor: Config.options.crosshair.color
    property string outlineColor: Config.options.crosshair.outlineColor
    property int dotSize: Config.options.crosshair.dotSize
    property int outlineThickness: Config.options.crosshair.outlineThickness

    property real borderWidth: Math.max(root.outlineThickness, 0)
    property real dotTotalSize: root.dotSize + root.borderWidth * 2

    implicitWidth: Math.max(dotTotalSize, 1) + 2 // +2 pixel correction
    implicitHeight: implicitWidth

    Rectangle {
        id: centerDot
        anchors.centerIn: parent
        z: 10

        color: root.dotColor
        width: root.dotTotalSize
        height: width
        radius: root.dotTotalSize / 2

        border.width: root.borderWidth
        border.color: root.outlineColor
    }
}
