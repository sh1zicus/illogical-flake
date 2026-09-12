import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    Process {
        id: translationProc
        property string locale: ""
        command: [Directories.aiTranslationScriptPath, translationProc.locale]
    }

    ContentSection {
        icon: "volume_up"
        title: Translation.tr("Audio")

        ConfigSwitch {
            buttonIcon: "hearing"
            text: Translation.tr("Earbang protection")
            checked: Config.options.audio.protection.enable
            onCheckedChanged: {
                Config.options.audio.protection.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Prevents abrupt increments and restricts volume limit")
            }
        }
        ConfigRow {
            enabled: Config.options.audio.protection.enable
            ConfigSpinBox {
                icon: "arrow_warm_up"
                text: Translation.tr("Max allowed increase")
                value: Config.options.audio.protection.maxAllowedIncrease
                from: 0
                to: 100
                stepSize: 2
                onValueChanged: {
                    Config.options.audio.protection.maxAllowedIncrease = value;
                }
            }
            ConfigSpinBox {
                icon: "vertical_align_top"
                text: Translation.tr("Volume limit")
                value: Config.options.audio.protection.maxAllowed
                from: 0
                to: 154 // pavucontrol allows up to 153%
                stepSize: 2
                onValueChanged: {
                    Config.options.audio.protection.maxAllowed = value;
                }
            }
        }
    }

    ContentSection {
        icon: "battery_android_full"
        title: Translation.tr("Battery")

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "warning"
                text: Translation.tr("Low warning")
                value: Config.options.battery.low
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.low = value;
                }
            }
            ConfigSpinBox {
                icon: "dangerous"
                text: Translation.tr("Critical warning")
                value: Config.options.battery.critical
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.critical = value;
                }
            }
        }
        ConfigRow {
            uniform: false
            Layout.fillWidth: false
            ConfigSwitch {
                buttonIcon: "pause"
                text: Translation.tr("Automatic suspend")
                checked: Config.options.battery.automaticSuspend
                onCheckedChanged: {
                    Config.options.battery.automaticSuspend = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Automatically suspends the system when battery is low")
                }
            }
            ConfigSpinBox {
                enabled: Config.options.battery.automaticSuspend
                text: Translation.tr("at")
                value: Config.options.battery.suspend
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.suspend = value;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "charger"
                text: Translation.tr("Full warning")
                value: Config.options.battery.full
                from: 0
                to: 101
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.full = value;
                }
            }
        }
    }

    ContentSection {
        icon: "language"
        title: Translation.tr("Language")

        ContentSubsection {
            title: Translation.tr("Interface Language")
            tooltip: Translation.tr("Select the language for the user interface.\n\"Auto\" will use your system's locale.")

            StyledComboBox {
                id: languageSelector
                buttonIcon: "language"
                textRole: "displayName"

                model: [
                    {
                        displayName: Translation.tr("Auto (System)"),
                        value: "auto"
                    },
                    ...Translation.allAvailableLanguages.map(lang => {
                        return {
                            displayName: lang,
                            value: lang
                        };
                    })]

                currentIndex: {
                    const index = model.findIndex(item => item.value === Config.options.language.ui);
                    return index !== -1 ? index : 0;
                }

                onActivated: index => {
                    Config.options.language.ui = model[index].value;
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Generate translation with Gemini")
            tooltip: Translation.tr("You'll need to enter your Gemini API key first.\nType /key on the sidebar for instructions.")

            ConfigRow {
                MaterialTextArea {
                    id: localeInput
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Locale code, e.g. fr_FR, de_DE, zh_CN...")
                    text: Config.options.language.ui === "auto" ? Qt.locale().name : Config.options.language.ui
                }
                RippleButtonWithIcon {
                    id: generateTranslationBtn
                    Layout.fillHeight: true
                    nerdIcon: ""
                    enabled: !translationProc.running || (translationProc.locale !== localeInput.text.trim())
                    mainText: enabled ? Translation.tr("Generate\nTypically takes 2 minutes") : Translation.tr("Generating...\nDon't close this window!")
                    onClicked: {
                        translationProc.locale = localeInput.text.trim();
                        translationProc.running = false;
                        translationProc.running = true;
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "rule"
        title: Translation.tr("Policies")

        ConfigRow {

            // AI policy
            ColumnLayout {
                ContentSubsectionLabel {
                    text: Translation.tr("AI")
                }

                ConfigSelectionArray {
                    currentValue: Config.options.policies.ai
                    onSelected: newValue => {
                        Config.options.policies.ai = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("No"),
                            icon: "close",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Yes"),
                            icon: "check",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Local only"),
                            icon: "sync_saved_locally",
                            value: 2
                        }
                    ]
                }
            }

            // Weeb policy
            ColumnLayout {

                ContentSubsectionLabel {
                    text: Translation.tr("Weeb")
                }

                ConfigSelectionArray {
                    currentValue: Config.options.policies.weeb
                    onSelected: newValue => {
                        Config.options.policies.weeb = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("No"),
                            icon: "close",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Yes"),
                            icon: "check",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Closet"),
                            icon: "ev_shadow",
                            value: 2
                        }
                    ]
                }
            }
        }
    }

    ContentSection {
        icon: "notification_sound"
        title: Translation.tr("Sounds")
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "battery_android_full"
                text: Translation.tr("Battery")
                checked: Config.options.sounds.battery
                onCheckedChanged: {
                    Config.options.sounds.battery = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "av_timer"
                text: Translation.tr("Pomodoro")
                checked: Config.options.sounds.pomodoro
                onCheckedChanged: {
                    Config.options.sounds.pomodoro = checked;
                }
            }
        }
    }

    ContentSection {
        icon: "nest_clock_farsight_analog"
        title: Translation.tr("Time")

        ConfigSwitch {
            buttonIcon: "pace"
            text: Translation.tr("Second precision")
            checked: Config.options.time.secondPrecision
            onCheckedChanged: {
                Config.options.time.secondPrecision = checked;
            }
            StyledToolTip {
                text: Translation.tr("Enable if you want clocks to show seconds accurately")
            }
        }

        ContentSubsection {
            title: Translation.tr("Format")
            tooltip: ""

            ConfigSelectionArray {
                currentValue: Config.options.time.format
                onSelected: newValue => {
                    if (newValue === "hh:mm") {
                        Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME12\\b/TIME/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`]);
                    } else {
                        Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME\\b/TIME12/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`]);
                    }

                    Config.options.time.format = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("24h"),
                        value: "hh:mm"
                    },
                    {
                        displayName: Translation.tr("12h am/pm"),
                        value: "h:mm ap"
                    },
                    {
                        displayName: Translation.tr("12h AM/PM"),
                        value: "h:mm AP"
                    },
                ]
            }

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Date format (e.g. ddd, dd/MM)")
                text: Config.options.time.dateFormat
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.time.dateFormat = text;
                }
            }

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Short date format (e.g. dd/MM)")
                text: Config.options.time.shortDateFormat
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.time.shortDateFormat = text;
                }
            }

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Date with year format (e.g. dd/MM/yyyy)")
                text: Config.options.time.dateWithYearFormat
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.time.dateWithYearFormat = text;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Pomodoro")

            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "timer"
                    text: Translation.tr("Focus (s)")
                    value: Config.options.time.pomodoro.focus
                    from: 60
                    to: 7200
                    stepSize: 60
                    onValueChanged: {
                        Config.options.time.pomodoro.focus = value;
                    }
                }
                ConfigSpinBox {
                    icon: "coffee"
                    text: Translation.tr("Break (s)")
                    value: Config.options.time.pomodoro.breakTime
                    from: 60
                    to: 3600
                    stepSize: 60
                    onValueChanged: {
                        Config.options.time.pomodoro.breakTime = value;
                    }
                }
            }
            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "coffee"
                    text: Translation.tr("Long break (s)")
                    value: Config.options.time.pomodoro.longBreak
                    from: 60
                    to: 7200
                    stepSize: 60
                    onValueChanged: {
                        Config.options.time.pomodoro.longBreak = value;
                    }
                }
                ConfigSpinBox {
                    icon: "repeat"
                    text: Translation.tr("Cycles before long break")
                    value: Config.options.time.pomodoro.cyclesBeforeLongBreak
                    from: 1
                    to: 10
                    stepSize: 1
                    onValueChanged: {
                        Config.options.time.pomodoro.cyclesBeforeLongBreak = value;
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "work_alert"
        title: Translation.tr("Work safety")

        ConfigSwitch {
            buttonIcon: "assignment"
            text: Translation.tr("Hide clipboard images copied from sussy sources")
            checked: Config.options.workSafety.enable.clipboard
            onCheckedChanged: {
                Config.options.workSafety.enable.clipboard = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "wallpaper"
            text: Translation.tr("Hide sussy/anime wallpapers")
            checked: Config.options.workSafety.enable.wallpaper
            onCheckedChanged: {
                Config.options.workSafety.enable.wallpaper = checked;
            }
        }
    }

    ContentSection {
        icon: "dark_mode"
        title: Translation.tr("Light")

        ContentSubsection {
            title: Translation.tr("Anti-flashbang")
            ConfigSwitch {
                buttonIcon: "flare"
                text: Translation.tr("Enable")
                checked: Config.options.light.antiFlashbang.enable
                onCheckedChanged: {
                    Config.options.light.antiFlashbang.enable = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Prevents sudden brightness flashes when switching content")
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Night light")

            ConfigSwitch {
                buttonIcon: "wb_twilight"
                text: Translation.tr("Automatic")
                checked: Config.options.light.night.automatic
                onCheckedChanged: {
                    Config.options.light.night.automatic = checked;
                }
            }

            ConfigRow {
                enabled: Config.options.light.night.automatic
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("From (HH:mm)")
                    text: Config.options.light.night.from
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.light.night.from = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("To (HH:mm)")
                    text: Config.options.light.night.to
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.light.night.to = text;
                    }
                }
            }

            ConfigSpinBox {
                icon: "light_mode"
                text: Translation.tr("Color temperature (K)")
                value: Config.options.light.night.colorTemperature
                from: 1000
                to: 10000
                stepSize: 100
                onValueChanged: {
                    Config.options.light.night.colorTemperature = value;
                }
            }
        }
    }

    ContentSection {
        icon: "apps"
        title: Translation.tr("Apps")

        ContentSubsection {
            title: Translation.tr("Launch commands")

            ConfigRow {
                uniform: true
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Terminal")
                    text: Config.options.apps.terminal
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.apps.terminal = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Change password")
                    text: Config.options.apps.changePassword
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.apps.changePassword = text;
                    }
                }
            }
            ConfigRow {
                uniform: true
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Network")
                    text: Config.options.apps.network
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.apps.network = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Network (Ethernet)")
                    text: Config.options.apps.networkEthernet
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.apps.networkEthernet = text;
                    }
                }
            }
            ConfigRow {
                uniform: true
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Bluetooth")
                    text: Config.options.apps.bluetooth
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.apps.bluetooth = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Manage user")
                    text: Config.options.apps.manageUser
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.apps.manageUser = text;
                    }
                }
            }
            ConfigRow {
                uniform: true
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Task manager")
                    text: Config.options.apps.taskManager
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.apps.taskManager = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Update")
                    text: Config.options.apps.update
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.apps.update = text;
                    }
                }
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Volume mixer")
                text: Config.options.apps.volumeMixer
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.apps.volumeMixer = text;
                }
            }
        }
    }
}
