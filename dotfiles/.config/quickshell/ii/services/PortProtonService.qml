pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string homePath: FileUtils.trimFileProtocol(Directories.home)
    readonly property string defaultRoot: FileUtils.trimFileProtocol(`${root.homePath}/.Games/PortProton`)
    readonly property string helperPath: FileUtils.trimFileProtocol(Quickshell.shellPath("modules/ii/portproton/portproton-install-helper.py"))

    property string rootPath: root.defaultRoot
    property var runningGames: []
    readonly property bool running: root.runningGames.length > 0
    property bool stopBusy: false

    function parseJson(text) {
        try {
            return JSON.parse(text);
        } catch (error) {
            return null;
        }
    }

    function refresh() {
        if (statusProc.running)
            return;
        statusProc.command = ["python3", root.helperPath, "status", "--root", root.rootPath];
        statusProc.running = true;
    }

    function stopGame(record) {
        if (!record || root.stopBusy)
            return;
        const args = ["stop", "--root", root.rootPath];
        const pid = Number(record.pid ?? 0);
        if (pid > 0)
            args.push("--pid", String(pid));
        else if (record.exe)
            args.push("--exe", String(record.exe));
        else
            return;
        root.runStop(args);
    }

    function stopAll() {
        if (root.stopBusy)
            return;
        root.runStop(["stop", "--root", root.rootPath, "--all"]);
    }

    function runStop(args) {
        root.stopBusy = true;
        stopProc.command = ["python3", root.helperPath].concat(args);
        stopProc.running = true;
    }

    function openLauncher() {
        GlobalStates.portProtonOpen = true;
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: statusProc
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const data = root.parseJson(text);
                if (data && Array.isArray(data.running))
                    root.runningGames = data.running;
            }
        }
        stderr: SplitParser {
            onRead: data => console.log("[portproton] status:", data)
        }
    }

    Process {
        id: stopProc
        running: false
        stdout: StdioCollector {
            waitForEnd: true
        }
        stderr: SplitParser {
            onRead: data => console.log("[portproton] stop:", data)
        }
        onExited: {
            root.stopBusy = false;
            root.refresh();
        }
    }
}
