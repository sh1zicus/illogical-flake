import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

// Persistent build manager. Lives for the whole shell session, independent of
// the NixOS config window, so a running rebuild (pkexec ./update.sh) survives
// closing and unloading the window.
pragma Singleton

Singleton {
    id: root

    property bool building: false
    property bool cancelRequested: false
    property var lastBuildExit: null
    property string logText: ""
    property string statusHint: ""

    // Лог пишет root, поэтому он лежит в /var/log: пользователь не может
    // заранее создать там symlink и заставить root перезаписать чужой файл.
    readonly property string buildLogPath: "/var/log/nixos-build.log"
    readonly property string buildSupervisorPath: "/etc/nixos/dotfiles/.config/quickshell/ii/scripts/nixos-build-supervisor.sh"
    readonly property string buildCancelPath: {
        const dir = Quickshell.env("XDG_RUNTIME_DIR");
        return (dir && dir.length > 0 ? dir : "/tmp") + "/nixos-build.cancel";
    }

    signal buildStarted()
    signal buildFinished(int exitCode)

    function performBuild(full, reopenEditor = false) {
        root.logText = "";
        root.lastBuildExit = null;
        root.cancelRequested = false;
        root.statusHint = Translation.tr("rebuild started…");
        Quickshell.execDetached(["rm", "-f", root.buildCancelPath]);
        buildProc.command = [
            "pkexec",
            "env",
            "QS_BUILD=1",
            "TERM=dumb",
            "PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin",
            `QS_CANCEL_FILE=${root.buildCancelPath}`,
            `QS_REOPEN_EDITOR=${reopenEditor ? "1" : "0"}`,
            `QS_REOPEN_MARKER=${Directories.nixosConfigReopenMarker}`,
            `QS_USER=${Quickshell.env("USER") || ""}`,
            `HYPRLAND_INSTANCE_SIGNATURE=${Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""}`,
            `XDG_RUNTIME_DIR=${Quickshell.env("XDG_RUNTIME_DIR") || ""}`,
            "bash",
            root.buildSupervisorPath,
            full ? "full" : "quick"
        ];
        root.building = true;
        buildProc.running = true;
        buildStarted();
    }

    function cancelBuild() {
        if (buildProc.running) {
            root.cancelRequested = true;
            // Root-обёртка следит за файлом и останавливает всю группу
            // процессов сборки, включая nixos-rebuild и nix.
            Quickshell.execDetached(["touch", root.buildCancelPath]);
            root.statusHint = Translation.tr("stopping rebuild…");
        }
    }

    function clearLog() {
        root.logText = "";
    }

    Process {
        id: buildProc
        onExited: (exitCode, exitStatus) => {
            const wasCancelled = root.cancelRequested && exitCode !== 0;
            root.building = false;
            root.cancelRequested = false;
            root.lastBuildExit = exitCode;
            root.statusHint = wasCancelled
                ? Translation.tr("rebuild cancelled")
                : (exitCode === 0
                    ? Translation.tr("rebuild finished successfully")
                    : Translation.tr("rebuild failed with error (%1)").arg(exitCode));
            Quickshell.execDetached(["rm", "-f", root.buildCancelPath]);
            buildLogView.reload();
            finalLogReloadTimer.restart();
            root.buildFinished(exitCode);
        }
    }

    FileView {
        id: buildLogView
        path: root.buildLogPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const out = buildLogView.text().replace(/\r/g, "").replace(/\^@/g, "");
            if (out !== root.logText) root.logText = out;
        }
    }

    Timer {
        id: buildLogPollTimer
        interval: 400
        repeat: true
        running: root.building
        onTriggered: {
            if (buildLogView.path.length > 0) buildLogView.reload();
        }
    }

    Timer {
        id: finalLogReloadTimer
        interval: 250
        repeat: false
        onTriggered: buildLogView.reload()
    }
}