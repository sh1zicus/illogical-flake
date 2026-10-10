pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * To-do list manager.
 *
 * Каждый элемент — объект с полями:
 *   content   — заголовок/текст
 *   done      — выполнено ли (на уровне задачи)
 *   priority  — "none" | "low" (зелёный) | "medium" (жёлтый) | "high" (красный)
 *   type      — "text" | "code" | "checklist" | "progress" | "timer"
 *   code      — текст сниппета (type=code)
 *   items     — [{ text, done }] подпункты (type=checklist)
 *   current   — выполнено (type=progress)
 *   total     — всего (type=progress)
 *   duration  — длительность таймера в секундах (type=timer)
 *   timerRunning — идёт ли отсчёт (type=timer)
 *   timerEnd  — момент окончания (epoch, сек), валиден при timerRunning (type=timer)
 *   timerRemaining — остаток в секундах на паузе (type=timer)
 *   command   — необязательная команда, выполняемая по завершении (type=timer)
 *
 * Старый формат { content, done } поддерживается: недостающие поля
 * подставляются значениями по умолчанию при загрузке.
 */
Singleton {
    id: root
    property var filePath: Directories.todoPath
    property var list: []

    // Цвета приоритета. M3-палитра тут фиолетовая, поэтому зелёный/жёлтый/красный
    // задаём явно, а нейтральный берём из темы.
    readonly property var priorityColors: ({
        "none": "transparent",
        "low": "#43A047",    // зелёный
        "medium": "#F5A623", // жёлтый
        "high": "#E5484D",   // красный
    })

    readonly property var priorityOrder: ["none", "low", "medium", "high"]

    function priorityColor(priority) {
        return root.priorityColors[priority] ?? "transparent";
    }

    function normalize(item) {
        const empty = { "content": "", "done": false, "priority": "none", "type": "text", "code": "", "items": [], "current": 0, "total": 0, "duration": 0, "timerRunning": false, "timerEnd": 0, "timerRemaining": 0, "command": "" };
        if (!item || typeof item !== "object") {
            empty.content = String(item ?? "");
            return empty;
        }
        return {
            "content": item.content ?? "",
            "done": item.done === true,
            "priority": item.priority ?? "none",
            "type": item.type ?? "text",
            "code": item.code ?? "",
            "items": Array.isArray(item.items) ? item.items : [],
            "current": typeof item.current === "number" ? item.current : 0,
            "total": item.total ?? 0,
            "duration": typeof item.duration === "number" ? item.duration : 0,
            "timerRunning": item.timerRunning === true,
            "timerEnd": typeof item.timerEnd === "number" ? item.timerEnd : 0,
            "timerRemaining": typeof item.timerRemaining === "number" ? item.timerRemaining : 0,
            "command": item.command ?? "",
        }
    }

    function save() {
        // Reassign to trigger onListChanged for derived bindings
        root.list = root.list.slice(0)
        todoFileView.setText(JSON.stringify(root.list))
    }

    function addItem(item) {
        root.list.push(normalize(item))
        save()
    }

    function addTask(desc) {
        addItem({ "content": desc, "done": false })
    }

    function updateItem(index, patch) {
        if (index < 0 || index >= root.list.length) return;
        Object.assign(root.list[index], patch);
        save();
    }

    function deleteItem(index) {
        if (index < 0 || index >= root.list.length) return;
        root.list.splice(index, 1)
        save()
    }

    function setDone(index, done) {
        updateItem(index, { "done": !!done })
    }

    function markDone(index) { setDone(index, true) }
    function markUnfinished(index) { setDone(index, false) }

    function setPriority(index, priority) {
        updateItem(index, { "priority": priority })
    }

    function setContent(index, text) {
        updateItem(index, { "content": text })
    }

    function setType(index, type) {
        updateItem(index, { "type": type })
    }

    // ----------------------------------------------------------- checklist
    function toggleSub(index, subIndex) {
        const item = root.list[index];
        if (!item || !item.items || !item.items[subIndex]) return;
        item.items[subIndex].done = !item.items[subIndex].done;
        save();
    }

    function addSub(index, text) {
        const item = root.list[index];
        if (!item) return;
        if (!item.items) item.items = [];
        item.items.push({ "text": text, "done": false });
        save();
    }

    function removeSub(index, subIndex) {
        const item = root.list[index];
        if (!item || !item.items) return;
        item.items.splice(subIndex, 1);
        save();
    }

    // ------------------------------------------------------------ progress
    function setProgress(index, current) {
        const item = root.list[index];
        if (!item) return;
        const total = item.total ?? 0;
        item.current = Math.max(0, Math.min(current, total));
        save();
    }

    function stepProgress(index, delta) {
        const item = root.list[index];
        if (!item) return;
        setProgress(index, (item.current ?? 0) + delta);
    }

    // ------------------------------------------------------------ таймер
    property real now: 0
    readonly property bool anyTimerRunning: root.list.some(function(item) {
        return item && item.type === "timer" && item.timerRunning;
    })

    function remainingOf(item) {
        if (!item || item.type !== "timer") return 0;
        if (item.timerRunning && item.timerEnd > 0)
            return Math.max(0, item.timerEnd - root.now);
        return Math.max(0, item.timerRemaining ?? 0);
    }

    function setTimerDuration(index, seconds) {
        const s = Math.max(0, Math.floor(seconds));
        updateItem(index, { "duration": s, "timerRemaining": s, "timerEnd": 0, "timerRunning": false });
    }

    function setTimerCommand(index, command) {
        updateItem(index, { "command": command ?? "" });
    }

    function startTimer(index) {
        const item = root.list[index];
        if (!item) return;
        const nowSec = Date.now() / 1000;
        root.now = nowSec; // синхронизируем, иначе карточка мигнёт неверным остатком
        let rem = root.remainingOf(item);
        if (rem <= 0) rem = item.duration ?? 0;
        if (rem <= 0) return;
        item.timerRemaining = rem;
        item.timerEnd = nowSec + rem;
        item.timerRunning = true;
        root.save();
    }

    function pauseTimer(index) {
        const item = root.list[index];
        if (!item) return;
        const nowSec = Date.now() / 1000;
        root.now = nowSec;
        item.timerRemaining = Math.max(0, item.timerEnd - nowSec);
        item.timerRunning = false;
        item.timerEnd = 0;
        root.save();
    }

    function toggleTimer(index) {
        const item = root.list[index];
        if (!item) return;
        if (item.timerRunning) pauseTimer(index);
        else startTimer(index);
    }

    function resetTimer(index) {
        const item = root.list[index];
        if (!item) return;
        item.timerRunning = false;
        item.timerEnd = 0;
        item.timerRemaining = item.duration ?? 0;
        save();
    }

    function checkTimers() {
        let changed = false;
        const nowSec = root.now;
        for (let i = 0; i < root.list.length; i++) {
            const item = root.list[i];
            if (item && item.type === "timer" && item.timerRunning && item.timerEnd > 0 && item.timerEnd <= nowSec) {
                item.timerRunning = false;
                item.timerEnd = 0;
                item.timerRemaining = 0;
                root.notifyTimerFinished(item);
                changed = true;
            }
        }
        if (changed) root.save();
    }

    function notifyTimerFinished(item) {
        const body = (item.content ?? "");
        Quickshell.execDetached([
            "notify-send",
            "-a", "Shell",
            "-u", "normal",
            "-h", "string:x-canonical-private-synchronous:timer",
            Translation.tr("Timer finished"),
            body
        ]);
        root.playAlarmSound();
        if (item.command && item.command.length > 0)
            Quickshell.execDetached(["bash", "-c", item.command]);
    }

    function playAlarmSound() {
        const theme = String(Config.options.sounds.theme ?? "freedesktop").replace(/[^a-zA-Z0-9_.-]/g, "");
        const cmd = "for d in /run/current-system/sw/share/sounds /usr/share/sounds \"$HOME/.local/share/sounds\"; do "
            + "f=\"$d/" + theme + "/stereo/alarm-clock-elapsed.oga\"; "
            + "if [ -f \"$f\" ]; then ffplay -nodisp -autoexit -loglevel quiet \"$f\" >/dev/null 2>&1; break; fi; done";
        Quickshell.execDetached(["bash", "-c", cmd]);
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.anyTimerRunning
        onTriggered: {
            root.now = Date.now() / 1000;
            root.checkTimers();
        }
    }

    function refresh() {
        todoFileView.reload()
    }

    Component.onCompleted: {
        root.now = Date.now() / 1000;
        refresh()
    }

    FileView {
        id: todoFileView
        path: Qt.resolvedUrl(root.filePath)
        onLoaded: {
            const fileContents = todoFileView.text()
            try {
                const parsed = JSON.parse(fileContents)
                root.list = Array.isArray(parsed) ? parsed.map(root.normalize) : []
            } catch (e) {
                console.log("[To Do] Invalid JSON, starting empty: " + e)
                root.list = []
            }
        }
        onLoadFailed: (error) => {
            if(error == FileViewError.FileNotFound) {
                console.log("[To Do] File not found, creating new file.")
                root.list = []
                todoFileView.setText(JSON.stringify(root.list))
            } else {
                console.log("[To Do] Error loading file: " + error)
            }
        }
    }
}
