import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Окно задач — layer-shell панель, ровно как окно выбора обоев: выезжает
// сверху под бар, фиксированного размера, не перетаскивается (не floating
// xdg-toplevel). Контент существует только пока окно открыто.
Scope {
    id: root

    Loader {
        id: todoWindowLoader
        active: GlobalStates.todoWindowOpen

        sourceComponent: PanelWindow {
            id: panelWindow
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:todoWindow"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors.top: true
            margins {
                top: Config?.options.bar.vertical ? Appearance.sizes.hyprlandGapsOut : Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut
            }

            mask: Region {
                item: content
            }

            implicitHeight: Appearance.sizes.wallpaperSelectorHeight
            implicitWidth: Appearance.sizes.wallpaperSelectorWidth

            Component.onCompleted: {
                GlobalFocusGrab.addDismissable(panelWindow);
            }
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    GlobalStates.todoWindowOpen = false;
                }
            }

            TodoWindowContent {
                id: content
                anchors.fill: parent
            }
        }
    }

    function toggleTodoWindow() {
        GlobalStates.todoWindowOpen = !GlobalStates.todoWindowOpen;
    }

    IpcHandler {
        target: "todoWindow"

        function toggle(): void {
            root.toggleTodoWindow();
        }
    }

    GlobalShortcut {
        name: "todoWindowToggle"
        description: Translation.tr("Toggle to-do window")
        onPressed: {
            root.toggleTodoWindow();
        }
    }
}
