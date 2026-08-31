import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    id: root

    name: Translation.tr("Power Profile")

    // Текущий CPU governor (performance / schedutil / ...).
    property string gov: "schedutil"
    readonly property bool isPerformance: gov === "performance"

    toggled: isPerformance
    icon: isPerformance ? "local_fire_department" : "airwave"
    statusText: isPerformance ? Translation.tr("Performance") : Translation.tr("Balanced")

    // Читаем актуальный governor через sudo? Нет — читаем файл напрямую (доступно всем).
    function refresh() {
        govReader.running = false;
        govReader.running = true;
    }

    mainAction: () => {
        const next = isPerformance ? "schedutil" : "performance";
        // sudoers-правило разрешает daen2772 запускать cpu-gov-set без пароля.
        Quickshell.execDetached(["sudo", "-n", "cpu-gov-set", next]);
        root.gov = next;
    }

    tooltipText: Translation.tr("Click to toggle CPU governor (Performance / Balanced). Requires the cpu-gov-set sudoers rule.")

    Process {
        id: govReader
        command: ["bash", "-c", "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim();
                if (out) root.gov = out;
            }
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }
}
