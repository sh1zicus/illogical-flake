import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Scope {
    id: root

    FloatingWindow {
        id: ytWindow
        visible: GlobalStates.ytMusicOpen
        color: "transparent"
        title: "YouTube Music"

        implicitWidth: Appearance.sizes.wallpaperSelectorWidth - Appearance.sizes.elevationMargin * 2
        implicitHeight: Appearance.sizes.wallpaperSelectorHeight - Appearance.sizes.elevationMargin * 2

        mask: Region { item: contentLoader }

        onVisibleChanged: {
            if (visible) {
                GlobalStates.sidebarRightOpen = false;
                centerOnFocusedMonitor();
                raiseTimer.restart();
            }
        }

        Timer {
            id: raiseTimer
            interval: 120
            repeat: false
            onTriggered: Hyprland.dispatch(`hl.dsp.focus({window = "title:^YouTube Music$"})`)
        }

        function centerOnFocusedMonitor() {
            const mon = Hyprland.focusedMonitor;
            if (mon && Qt.screenAt) {
                const sc = Qt.screenAt(mon.x + mon.width / 2, mon.y + mon.height / 2);
                if (sc) ytWindow.screen = sc;
            }
        }

        Loader {
            id: contentLoader
            anchors.fill: parent
            active: GlobalStates.ytMusicOpen
            source: "YtMusicContent.qml"
            onLoaded: {
                if (GlobalStates.ytMusicOpen && contentLoader.item) {
                    contentLoader.item.forceActiveFocus();
                }
            }
        }
    }

    function closeWindow() { GlobalStates.ytMusicOpen = false }
    function toggleWindow() { GlobalStates.ytMusicOpen = !GlobalStates.ytMusicOpen }
    function openWindow() { GlobalStates.ytMusicOpen = true }

    IpcHandler {
        target: "ytMusic"
        function toggle(): void { root.toggleWindow() }
        function open(): void { root.openWindow() }
        function close(): void { root.closeWindow() }
    }

    GlobalShortcut {
        name: "ytMusicToggle"
        description: "Toggle YouTube Music"
        onPressed: root.toggleWindow()
    }
}
