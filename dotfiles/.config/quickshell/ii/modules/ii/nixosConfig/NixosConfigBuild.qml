import qs
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

    signal buildStarted()
    signal buildFinished(int exitCode)

    function performBuild(full) {
        root.logText = "";
        root.lastBuildExit = null;
        root.statusHint = "пересборка запущена…";
        const script = full ? "./update.sh" : "./update.sh --quick";
        buildProc.command = [
            "pkexec",
            "env",
            "QS_BUILD=1",
            "TERM=dumb",
            "PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin",
            "bash",
            "-c",
            `cd /etc/nixos && exec script -qefc '${script}' /dev/null > /tmp/nixos-build.log 2>&1`
        ];
        root.building = true;
        buildProc.running = true;
        buildStarted();
    }

    function cancelBuild() {
        if (buildProc.running) {
            buildProc.signal(15);
            root.statusHint = "прерываю пересборку (SIGTERM)...";
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
                ? "пересборка завершена успешно"
                : `пересборка завершилась с ошибкой (${exitCode})`;
            root.buildFinished(exitCode);
        }
    }

    FileView {
        id: buildLogView
        path: "/tmp/nixos-build.log"
        watchChanges: true
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
}