import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.models.hyprland

ContentPage {
    id: root
    forceWidth: true

    // Values are written by hyprconfigurator into hyprland/shellOverrides/main.lua,
    // which hyprland.lua sources last, so they override hyprland/general.lua.
    // Hyprland reloads automatically on change.
    readonly property string shellOverrides: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/shellOverrides/main.lua`)
    // Re-enables blur on regular windows. hyprland/rules.lua disables it with a
    // `no_blur = true` rule; shellOverrides are sourced after rules.lua, so this
    // rule is registered later and wins.
    readonly property string windowBlurRule: 'hl.window_rule({ match = { class = ".*" }, no_blur = false })'

    function setOption(key, value) {
        HyprlandConfig.set(key, value);
    }

    HyprlandConfigOption { id: activeOp;     key: "decoration:active_opacity" }
    HyprlandConfigOption { id: inactiveOp;   key: "decoration:inactive_opacity" }
    HyprlandConfigOption { id: fullscreenOp; key: "decoration:fullscreen_opacity" }
    HyprlandConfigOption { id: blurXray;      key: "decoration:blur:xray" }
    HyprlandConfigOption { id: blurSize;      key: "decoration:blur:size" }
    HyprlandConfigOption { id: blurPasses;    key: "decoration:blur:passes" }

    // State of the "blur on windows" rule (lives in shellOverrides/main.lua)
    property bool windowBlur: false
    property bool windowBlurFetched: false
    Process {
        id: windowBlurCheck
        running: true
        command: ["bash", "-c", `grep -qF 'no_blur = false' '${root.shellOverrides}' && echo yes || echo no`]
        stdout: StdioCollector {
            onStreamFinished: {
                root.windowBlur = text.trim() === "yes";
                root.windowBlurFetched = true;
            }
        }
    }

    ContentSection {
        icon: "opacity"
        title: Translation.tr("Window opacity")

        ConfigSpinBox {
            icon: "center_focus_strong"
            text: Translation.tr("Focused window (%)")
            value: Math.round((activeOp.value ?? 0.95) * 100)
            from: 30
            to: 100
            stepSize: 5
            onValueChanged: {
                const newVal = value / 100;
                if (activeOp.value !== undefined && Math.abs(newVal - activeOp.value) > 0.004)
                    root.setOption("decoration:active_opacity", newVal);
            }
        }
        ConfigSpinBox {
            icon: "filter_none"
            text: Translation.tr("Unfocused windows (%)")
            value: Math.round((inactiveOp.value ?? 0.85) * 100)
            from: 30
            to: 100
            stepSize: 5
            onValueChanged: {
                const newVal = value / 100;
                if (inactiveOp.value !== undefined && Math.abs(newVal - inactiveOp.value) > 0.004)
                    root.setOption("decoration:inactive_opacity", newVal);
            }
        }
        ConfigSpinBox {
            icon: "fullscreen"
            text: Translation.tr("Fullscreen (%)")
            value: Math.round((fullscreenOp.value ?? 1.0) * 100)
            from: 30
            to: 100
            stepSize: 5
            onValueChanged: {
                const newVal = value / 100;
                if (fullscreenOp.value !== undefined && Math.abs(newVal - fullscreenOp.value) > 0.004)
                    root.setOption("decoration:fullscreen_opacity", newVal);
            }
        }
    }

    ContentSection {
        icon: "blur_on"
        title: Translation.tr("Blur")

        ConfigSwitch {
            buttonIcon: "select_window"
            text: Translation.tr("Blur on windows")
            checked: root.windowBlur
            onCheckedChanged: {
                if (!root.windowBlurFetched || checked === root.windowBlur)
                    return;
                root.windowBlur = checked;
                if (checked) {
                    Quickshell.execDetached(["bash", "-c", //
                        `grep -qF 'no_blur = false' '${root.shellOverrides}' || echo '${root.windowBlurRule}' >> '${root.shellOverrides}'` //
                    ]);
                } else {
                    Quickshell.execDetached(["bash", "-c", //
                        `sed -i '/no_blur = false/d' '${root.shellOverrides}'` //
                    ]);
                }
            }
            StyledToolTip {
                text: Translation.tr("The dotfiles disable blur on windows by default.\nThis re-enables it for transparent windows.")
            }
        }
        ConfigSwitch {
            buttonIcon: "visibility"
            text: Translation.tr("X-ray (blur skips windows behind)")
            checked: blurXray.value === 1 || blurXray.value === true
            onCheckedChanged: {
                if (blurXray.value === undefined)
                    return;
                const current = blurXray.value === 1 || blurXray.value === true;
                if (checked !== current)
                    root.setOption("decoration:blur:xray", checked ? "true" : "false");
            }
            StyledToolTip {
                text: Translation.tr("On: blur shows only the wallpaper (faster).\nOff: windows behind are also blurred (more depth).")
            }
        }
        ConfigSpinBox {
            icon: "lens_blur"
            text: Translation.tr("Blur size")
            value: blurSize.value ?? 10
            from: 1
            to: 30
            stepSize: 1
            onValueChanged: {
                if (blurSize.value !== undefined && value !== blurSize.value)
                    root.setOption("decoration:blur:size", value);
            }
        }
        ConfigSpinBox {
            icon: "layers"
            text: Translation.tr("Blur passes")
            value: blurPasses.value ?? 3
            from: 1
            to: 6
            stepSize: 1
            onValueChanged: {
                if (blurPasses.value !== undefined && value !== blurPasses.value)
                    root.setOption("decoration:blur:passes", value);
            }
            StyledToolTip {
                text: Translation.tr("Size and passes also affect the bar, launcher and notifications")
            }
        }
    }
}
