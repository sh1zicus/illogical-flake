import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// PortProton-style game launcher that can use the original PortProton CLI or
// run standalone. The window is a normal tiled app window, like NixosConfig.
Scope {
    id: root

    FloatingWindow {
        id: launcherWindow
        visible: GlobalStates.portProtonOpen
        color: "transparent"
        title: "PortProton"

        implicitWidth: Appearance.sizes.wallpaperSelectorWidth - Appearance.sizes.elevationMargin * 2
        implicitHeight: Appearance.sizes.wallpaperSelectorHeight - Appearance.sizes.elevationMargin * 2

        mask: Region {
            item: contentLoader
        }

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
            onTriggered: Hyprland.dispatch(`hl.dsp.focus({window = "title:^PortProton$"})`)
        }

        function centerOnFocusedMonitor() {
            const mon = Hyprland.focusedMonitor;
            if (mon && Qt.screenAt) {
                const sc = Qt.screenAt(mon.x + mon.width / 2, mon.y + mon.height / 2);
                if (sc) launcherWindow.screen = sc;
            }
        }

        Loader {
            id: contentLoader
            anchors.fill: parent
            active: GlobalStates.portProtonOpen
            source: "PortProtonContent.qml"
            onLoaded: {
                if (GlobalStates.portProtonOpen && contentLoader.item) {
                    contentLoader.item.forceActiveFocus();
                }
            }
        }
    }

    function closeLauncher() {
        GlobalStates.portProtonOpen = false;
    }

    function toggleLauncher() {
        GlobalStates.portProtonOpen = !GlobalStates.portProtonOpen;
    }

    function openSettings() {
        GlobalStates.portProtonOpen = true;
        settingsTimer.restart();
    }

    function openInstall() {
        GlobalStates.portProtonOpen = true;
        installTimer.restart();
    }

    Timer {
        id: installTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (contentLoader.item) {
                contentLoader.item.viewIndex = 6;
                contentLoader.item.openInstallDialog();
            }
            raiseTimer.restart();
        }
    }

    Timer {
        id: settingsTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (contentLoader.item) contentLoader.item.viewIndex = 4;
            raiseTimer.restart();
        }
    }

    IpcHandler {
        target: "portProton"

        function toggle(): void {
            root.toggleLauncher();
        }

        function settings(): void {
            root.openSettings();
        }

        function install(): void {
            root.openInstall();
        }
    }

    GlobalShortcut {
        name: "portProtonToggle"
        description: "Toggle PortProton launcher"
        onPressed: {
            root.toggleLauncher();
        }
    }
}
