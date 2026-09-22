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

// NixOS config manager window.
// It is a regular floating window (a normal app window, movable between
// workspaces) rather than an overlay layer-shell panel.
// Content is loaded only while the window is open (Loader.active is tied to
// GlobalStates.nixosConfigOpen), so nothing of the editor stays in memory when
// the window is closed. A running rebuild survives closing because the build
// process lives in the NixosConfigBuild singleton, not in the window.
Scope {
    id: root

    FloatingWindow {
        id: configWindow
        visible: GlobalStates.nixosConfigOpen
        color: "transparent"
        title: "NixOS Config"

        implicitWidth: Appearance.sizes.wallpaperSelectorWidth - Appearance.sizes.elevationMargin * 2
        implicitHeight: Appearance.sizes.wallpaperSelectorHeight - Appearance.sizes.elevationMargin * 2

        mask: Region {
            item: contentLoader
        }

        onVisibleChanged: {
            if (visible) {
                // The right panel would get in the way of the window.
                GlobalStates.sidebarRightOpen = false;
                centerOnFocusedMonitor();
            }
        }

        // Place the window on the currently focused monitor each time it
        // opens. Floating windows have no qml x/y handles, so we pick the
        // screen by pointing at the focused monitor's center.
        function centerOnFocusedMonitor() {
            const mon = Hyprland.focusedMonitor;
            if (mon && Qt.screenAt) {
                const sc = Qt.screenAt(mon.x + mon.width / 2, mon.y + mon.height / 2);
                if (sc) configWindow.screen = sc;
            }
        }

        Loader {
            id: contentLoader
            anchors.fill: parent
            active: GlobalStates.nixosConfigOpen
            source: "NixosConfigContent.qml"
            onLoaded: {
                if (GlobalStates.nixosConfigOpen && contentLoader.item) {
                    contentLoader.item.forceActiveFocus();
                }
            }
        }
    }

    function toggleNixosConfig() {
        GlobalStates.nixosConfigOpen = !GlobalStates.nixosConfigOpen
    }

    IpcHandler {
        target: "nixosConfig"

        function toggle(): void {
            root.toggleNixosConfig();
        }
    }

    GlobalShortcut {
        name: "nixosConfigToggle"
        description: "Toggle NixOS config manager"
        onPressed: {
            root.toggleNixosConfig();
        }
    }
}