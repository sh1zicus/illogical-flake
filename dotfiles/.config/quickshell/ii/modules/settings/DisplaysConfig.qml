import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    // Persistence: ~/.config/hypr/monitors.lua is required by hyprland.lua
    // (nwg-displays compat path) after hyprland/general.lua, so it overrides
    // the defaults. The file survives rebuilds — it is in the preserve list
    // of the home.activation script in home-modules/dotfiles.nix.
    readonly property string monitorsConf: FileUtils.trimFileProtocol(`${Directories.config}/hypr/monitors.lua`)

    // Monitor list: [{name, description, resW, resH, rate, monScale, transform, posX, posY, enabled, modes}]
    // posX/posY in logical pixels (as hyprctl reports them). modes: [{w, h, rate}]
    property var monitors: []
    property int selectedIndex: 0
    readonly property var selMon: (monitors.length > 0 && selectedIndex < monitors.length) ? monitors[selectedIndex] : null

    function commit() {
        root.monitors = root.monitors.slice();
    }

    function logicalW(m) {
        const w = (m.transform % 2 === 1) ? m.resH : m.resW;
        return w / m.monScale;
    }
    function logicalH(m) {
        const h = (m.transform % 2 === 1) ? m.resW : m.resH;
        return h / m.monScale;
    }

    // ── Read current state ──────────────────────────────────────────────────
    Process {
        id: displayPoller
        running: true
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim());
                    const list = [];
                    for (let i = 0; i < data.length; i++) {
                        const d = data[i];
                        const modes = [];
                        for (const ms of (d.availableModes ?? [])) {
                            const match = ms.match(/(\d+)x(\d+)@([\d.]+)Hz/);
                            if (!match) continue;
                            const mode = {w: parseInt(match[1]), h: parseInt(match[2]), rate: parseFloat(match[3])};
                            if (!modes.some(o => o.w === mode.w && o.h === mode.h && Math.round(o.rate) === Math.round(mode.rate)))
                                modes.push(mode);
                        }
                        // A live mode missing from availableModes means the
                        // monitor's rule carries a custom modeline.
                        const rate = d.refreshRate ?? 60;
                        const customMode = !modes.some(o => o.w === d.width && o.h === d.height && Math.round(o.rate) === Math.round(rate));
                        list.push({
                            name: d.name,
                            description: d.description ?? "",
                            resW: d.width, resH: d.height,
                            rate: rate,
                            monScale: d.scale ?? 1.0,
                            transform: d.transform ?? 0,
                            posX: d.x, posY: d.y,
                            enabled: !d.disabled,
                            modes: modes,
                            customMode: customMode,
                            origW: d.width, origH: d.height, origRate: rate
                        });
                        if (d.focused) root.selectedIndex = i;
                    }
                    root.monitors = list;
                } catch (e) {
                    console.log("[DisplaysConfig] parse error:", e);
                }
            }
        }
    }
    Timer {
        id: repollTimer
        interval: 800
        onTriggered: displayPoller.running = true
    }

    // ── Apply and save ──────────────────────────────────────────────────────
    // Normalizes the origin to (0,0) and returns specs:
    // [{name, mode, position, scale, transform} | {name, disabled}]
    //
    // `mode` handling: `hl.monitor` merges with the existing rule for the same
    // output. Omitting `mode` preserves whatever the rule already has — that
    // includes custom modelines from general.lua that cannot be spelled as
    // "WxH@rate" (customMode monitors keep mode = null until the user picks
    // another one). When a customMode monitor *does* get a new mode, it must be
    // sent as a modeline: a plain "WxH@rate" string never clears the stale
    // drmMode carried over by the merge, and Hyprland applies that custom
    // modeline with higher priority than standard modes (Monitor.cpp, the
    // DRM_MODE_TYPE_USERDEF candidate is tried first), so the requested mode
    // would silently never apply. There is no `cvt` on this system, so the
    // CVT reduced-blanking v1 timings (what `cvt -r` produces) are computed
    // in JS; it validates against the canonical `1920x1080R@60` modeline.
    function cvtrbModeline(w, h, rate) {
        const hfp = 48, hsync = 32, hblank = 160; // RB horizontal constants
        const vfp = 3, vsync = 5; // RB vertical front porch / sync width
        const frac = 0.00046 * rate; // minimum vblank (460us) as frame fraction
        const vblank = Math.max(Math.ceil(frac * h / (1 - frac)), 6);
        const htotal = w + hblank;
        const vtotal = h + vblank;
        const clock = Math.floor(rate * htotal * vtotal / 250000) * 0.25; // MHz, multiple of 0.25
        return `modeline ${clock} ${w} ${w + hfp} ${w + hfp + hsync} ${htotal} ` //
            + `${h} ${h + vfp} ${h + vfp + vsync} ${vtotal} +hsync -vsync`;
    }
    function modeRepresentable(m) {
        return (m.modes ?? []).some(o => o.w === m.resW && o.h === m.resH && Math.round(o.rate) === Math.round(m.rate));
    }
    function modeString(m) {
        const exact = (m.modes ?? []).find(o => o.w === m.resW && o.h === m.resH && Math.round(o.rate) === Math.round(m.rate));
        return `${m.resW}x${m.resH}@${(exact ? exact.rate : m.rate).toFixed(2)}`;
    }
    function buildMonitorSpecs() {
        let minX = Infinity, minY = Infinity;
        for (const m of root.monitors) {
            if (!m.enabled) continue;
            minX = Math.min(minX, m.posX);
            minY = Math.min(minY, m.posY);
        }
        if (minX === Infinity) { minX = 0; minY = 0; }
        const specs = [];
        for (const m of root.monitors) {
            if (!m.enabled) {
                specs.push({name: m.name, disabled: true});
                continue;
            }
            let mode = null;
            if (m.customMode) {
                const changed = m.resW !== m.origW || m.resH !== m.origH //
                    || Math.round(m.rate) !== Math.round(m.origRate);
                mode = changed ? root.cvtrbModeline(m.resW, m.resH, m.rate) : null;
            } else {
                mode = root.modeRepresentable(m) ? root.modeString(m) : null;
            }
            specs.push({
                name: m.name,
                mode: mode,
                position: `${Math.round(m.posX - minX)}x${Math.round(m.posY - minY)}`,
                scale: m.monScale,
                transform: m.transform
            });
        }
        return specs;
    }

    // Runtime only: applied live via `hyprctl eval` (the Lua config parser
    // does not support `hyprctl keyword`). If something goes wrong,
    // `hyprctl reload` restores the saved config.
    function luaRule(s) {
        if (s.disabled)
            return `hl.monitor({ output = '${s.name}', disabled = true })`;
        const parts = [`output = '${s.name}'`];
        if (s.mode)
            parts.push(`mode = '${s.mode}'`);
        parts.push(`position = '${s.position}'`, `scale = ${s.scale}`);
        if (s.transform)
            parts.push(`transform = ${s.transform}`);
        return `hl.monitor({ ${parts.join(", ")} })`;
    }
    function applyRuntime() {
        const chunk = buildMonitorSpecs().map(s => luaRule(s)).join("\n");
        Quickshell.execDetached(["hyprctl", "eval", chunk]);
        repollTimer.restart();
    }

    // Writes monitors.lua (hyprland.lua requires it after general.lua, so it
    // overrides the defaults). Hyprland cannot watch this file until it has
    // required it once (it is an optional require), so reload explicitly.
    function applyAndSave() {
        const lines = [
            "-- Generated by the \"Displays\" page of the Settings app (Super+I).",
            "-- Delete this file to fall back to the defaults in hyprland/general.lua.",
            "-- Note: nwg-displays can also overwrite this file.",
            ...buildMonitorSpecs().map(s => luaRule(s))
        ];
        const content = lines.join("\n") + "\n";
        Quickshell.execDetached(["bash", "-c", `cat > '${root.monitorsConf}' << 'HYPRMON_EOF'\n${content}HYPRMON_EOF`]);
        Quickshell.execDetached(["hyprctl", "reload"]);
        Quickshell.execDetached(["notify-send", Translation.tr("Displays"), Translation.tr("Layout applied and saved to monitors.lua")]);
        repollTimer.restart();
    }

    function setMonProp(prop, value) {
        if (!root.selMon) return;
        root.monitors[root.selectedIndex][prop] = value;
        root.commit();
    }

    // ── Canvas: monitor arrangement ─────────────────────────────────────────
    ContentSection {
        icon: "grid_view"
        title: Translation.tr("Arrangement")

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Drag the screens to arrange them. Click one to edit it below.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        Rectangle {
            id: canvas
            Layout.fillWidth: true
            implicitHeight: 240
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            // Bounding box of the layout in logical pixels
            readonly property var bbox: {
                let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
                for (const m of root.monitors) {
                    minX = Math.min(minX, m.posX);
                    minY = Math.min(minY, m.posY);
                    maxX = Math.max(maxX, m.posX + root.logicalW(m));
                    maxY = Math.max(maxY, m.posY + root.logicalH(m));
                }
                if (minX === Infinity) return {x: 0, y: 0, w: 1920, h: 1080};
                return {x: minX, y: minY, w: Math.max(1, maxX - minX), h: Math.max(1, maxY - minY)};
            }
            readonly property real sf: Math.min((width - 60) / bbox.w, (height - 60) / bbox.h, 0.12)
            readonly property real offX: (width - bbox.w * sf) / 2
            readonly property real offY: (height - bbox.h * sf) / 2

            // Magnet: snaps the dragged monitor's edges to the others'
            function snap(idx, px, py) {
                const m = root.monitors[idx];
                const mw = root.logicalW(m), mh = root.logicalH(m);
                const t = 60; // threshold in logical pixels
                let sx = px, sy = py;
                for (let j = 0; j < root.monitors.length; j++) {
                    if (j === idx || !root.monitors[j].enabled) continue;
                    const o = root.monitors[j];
                    const ox = o.posX, oy = o.posY;
                    const ow = root.logicalW(o), oh = root.logicalH(o);
                    for (const cand of [ox - mw, ox + ow, ox, ox + ow - mw, ox + ow / 2 - mw / 2])
                        if (Math.abs(px - cand) < t) { sx = cand; break; }
                    for (const cand of [oy - mh, oy + oh, oy, oy + oh - mh, oy + oh / 2 - mh / 2])
                        if (Math.abs(py - cand) < t) { sy = cand; break; }
                }
                return {x: Math.round(sx), y: Math.round(sy)};
            }

            Repeater {
                model: root.monitors
                delegate: Rectangle {
                    id: monRect
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === root.selectedIndex

                    width: root.logicalW(modelData) * canvas.sf
                    height: root.logicalH(modelData) * canvas.sf
                    radius: Appearance.rounding.unsharpenmore
                    color: selected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                    border.width: selected ? 2 : 1
                    border.color: selected ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                    opacity: modelData.enabled ? 1 : 0.45

                    Binding {
                        target: monRect; property: "x"
                        value: canvas.offX + (monRect.modelData.posX - canvas.bbox.x) * canvas.sf
                        when: !dragArea.drag.active
                    }
                    Binding {
                        target: monRect; property: "y"
                        value: canvas.offY + (monRect.modelData.posY - canvas.bbox.y) * canvas.sf
                        when: !dragArea.drag.active
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: monRect.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: monRect.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: monRect.modelData.enabled
                                ? `${monRect.modelData.resW}x${monRect.modelData.resH} @ ${Math.round(monRect.modelData.rate)}Hz`
                                : Translation.tr("Disabled")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        cursorShape: Qt.SizeAllCursor
                        drag.target: monRect.modelData.enabled && root.monitors.length > 1 ? monRect : undefined
                        drag.minimumX: -monRect.width / 2
                        drag.maximumX: canvas.width - monRect.width / 2
                        drag.minimumY: -monRect.height / 2
                        drag.maximumY: canvas.height - monRect.height / 2
                        onPressed: root.selectedIndex = monRect.index
                        onReleased: {
                            const px = (monRect.x - canvas.offX) / canvas.sf + canvas.bbox.x;
                            const py = (monRect.y - canvas.offY) / canvas.sf + canvas.bbox.y;
                            const snapped = canvas.snap(monRect.index, px, py);
                            // A click without a drag doesn't count as a change
                            if (Math.abs(snapped.x - monRect.modelData.posX) < 2 //
                                && Math.abs(snapped.y - monRect.modelData.posY) < 2)
                                return;
                            root.monitors[monRect.index].posX = snapped.x;
                            root.monitors[monRect.index].posY = snapped.y;
                            root.commit();
                        }
                    }
                }
            }
        }
    }

    // ── Selected monitor ────────────────────────────────────────────────────
    ContentSection {
        visible: root.selMon !== null
        icon: "monitor"
        title: root.selMon ? root.selMon.name : ""

        StyledText {
            Layout.fillWidth: true
            visible: (root.selMon?.description ?? "") !== ""
            text: root.selMon?.description ?? ""
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        ConfigSwitch {
            buttonIcon: "power_settings_new"
            text: Translation.tr("Enabled")
            checked: root.selMon?.enabled ?? true
            enabled: !(root.selMon?.enabled ?? true) || root.monitors.filter(m => m.enabled).length > 1
            onCheckedChanged: {
                if (root.selMon && checked !== root.selMon.enabled)
                    root.setMonProp("enabled", checked);
            }
            StyledToolTip {
                text: Translation.tr("You cannot disable the only active monitor")
            }
        }

        ContentSubsection {
            title: Translation.tr("Resolution")
            ConfigSelectionArray {
                currentValue: root.selMon ? `${root.selMon.resW}x${root.selMon.resH}` : ""
                onSelected: newValue => {
                    const parts = newValue.split("x");
                    const w = parseInt(parts[0]), h = parseInt(parts[1]);
                    root.monitors[root.selectedIndex].resW = w;
                    root.monitors[root.selectedIndex].resH = h;
                    // When changing resolution, use the highest rate available for it
                    const rates = root.selMon.modes.filter(m => m.w === w && m.h === h).map(m => m.rate);
                    if (rates.length > 0)
                        root.monitors[root.selectedIndex].rate = Math.max(...rates);
                    root.commit();
                }
                options: {
                    if (!root.selMon) return [];
                    const seen = [];
                    for (const m of root.selMon.modes) {
                        const v = `${m.w}x${m.h}`;
                        if (!seen.some(o => o.value === v))
                            seen.push({displayName: v, value: v});
                    }
                    seen.sort((a, b) => parseInt(b.value) - parseInt(a.value));
                    return seen;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Refresh rate")
            ConfigSelectionArray {
                currentValue: root.selMon ? Math.round(root.selMon.rate) : 60
                onSelected: newValue => {
                    const exact = root.selMon.modes.find(m => //
                        m.w === root.selMon.resW && m.h === root.selMon.resH && Math.round(m.rate) === newValue);
                    root.setMonProp("rate", exact ? exact.rate : newValue);
                }
                options: {
                    if (!root.selMon) return [];
                    const opts = [];
                    for (const m of root.selMon.modes) {
                        if (m.w !== root.selMon.resW || m.h !== root.selMon.resH) continue;
                        const r = Math.round(m.rate);
                        if (!opts.some(o => o.value === r))
                            opts.push({displayName: `${r} Hz`, value: r});
                    }
                    opts.sort((a, b) => b.value - a.value);
                    return opts;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Scale")
            ConfigSelectionArray {
                currentValue: root.selMon?.monScale ?? 1
                onSelected: newValue => root.setMonProp("monScale", newValue)
                options: {
                    const std = [1, 1.25, 1.5, 1.75, 2];
                    const cur = root.selMon?.monScale ?? 1;
                    const opts = std.map(s => ({displayName: `${Math.round(s * 100)}%`, value: s}));
                    if (!std.includes(cur))
                        opts.unshift({displayName: `${Math.round(cur * 100)}%`, value: cur});
                    return opts;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Rotation")
            ConfigSelectionArray {
                currentValue: root.selMon?.transform ?? 0
                onSelected: newValue => root.setMonProp("transform", newValue)
                options: [
                    {displayName: Translation.tr("Normal"), icon: "stay_current_landscape", value: 0},
                    {displayName: "90°", icon: "rotate_90_degrees_cw", value: 1},
                    {displayName: "180°", icon: "sync", value: 2},
                    {displayName: "270°", icon: "rotate_90_degrees_ccw", value: 3}
                ]
            }
        }
    }

    // ── Actions ─────────────────────────────────────────────────────────────
    ContentSection {
        icon: "rocket_launch"
        title: Translation.tr("Apply")

        ConfigRow {
            RippleButtonWithIcon {
                materialIcon: "play_arrow"
                mainText: Translation.tr("Preview")
                onClicked: root.applyRuntime()
                StyledToolTip {
                    text: Translation.tr("Applies without saving.\nIf something looks wrong, run: hyprctl reload")
                }
            }
            RippleButtonWithIcon {
                materialIcon: "save"
                mainText: Translation.tr("Apply and save")
                onClicked: root.applyAndSave()
                StyledToolTip {
                    text: Translation.tr("Writes monitors.lua — survives reboots and rebuilds")
                }
            }
            RippleButtonWithIcon {
                materialIcon: "refresh"
                mainText: Translation.tr("Reload current state")
                onClicked: displayPoller.running = true
            }
        }
    }
}
