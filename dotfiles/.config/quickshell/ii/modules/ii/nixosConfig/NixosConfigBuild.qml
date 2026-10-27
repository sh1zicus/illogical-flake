import qs
import qs.services
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
    property var lastBuildExit: null
    property string logText: ""
    property string statusHint: ""
    // Лог в приватном runtime-каталоге пользователя, а не в общем /tmp:
    // другой пользователь не сможет подменить его симлинком.
    readonly property string buildLogPath: {
        const dir = Quickshell.env("XDG_RUNTIME_DIR");
        return (dir && dir.length > 0 ? dir : "/tmp") + "/nixos-build.log";
    }

    signal buildStarted()
    signal buildFinished(int exitCode)

    function performBuild(full) {
        root.logText = "";
        root.lastBuildExit = null;
        root.statusHint = Translation.tr("rebuild started…");
        const script = full ? "./update.sh" : "./update.sh --quick";
        buildProc.command = [
            "pkexec",
            "env",
            "QS_BUILD=1",
            "TERM=dumb",
            "PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin",
            "bash",
            "-c",
            `umask 022; cd /etc/nixos && exec script -qefc '${script}' /dev/null > '${root.buildLogPath}' 2>&1`
        ];
        root.building = true;
        buildProc.running = true;
        buildStarted();
    }

    function cancelBuild() {
        if (buildProc.running) {
            buildProc.signal(15);
            root.statusHint = Translation.tr("stopping rebuild (SIGTERM)…");
        }
    }

    function clearLog() {
        root.logText = "";
    }

    Process {
        id: buildProc
        onExited: (exitCode, exitStatus) => {
            root.building = false;
            root.lastBuildExit = exitCode;
            root.statusHint = exitCode === 0
                ? Translation.tr("rebuild finished successfully")
                : Translation.tr("rebuild failed with error (%1)").arg(exitCode);
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
            const out = buildLogView.text().replace(/\r/g, "");
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