pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * Ежедневный чеклист (привычки): помыться, спорт и т.п.
 *
 * Хранится отдельно от основной задачи (todo.json) в daily.json:
 *   {
 *     "lastReset": "2026-10-10",
 *     "items": [ { "text": "", "done": false, "remind": "HH:MM"|"", "reminded": false, "duration": 0 } ]
 *   }
 *
 * При смене дня все галочки сбрасываются, а напоминания снова активируются.
 * Напоминание (remind) — время "HH:MM"; когда оно наступает, а пункт ещё не
 * отмечен, один раз за день показывается уведомление.
 * duration — длительность таймера в минутах (0 = без таймера).
 */
Singleton {
    id: root
    property var filePath: Directories.dailyPath
    property var list: []
    property string lastReset: ""
    property real now: 0

    // ------------------------------------------------------------ таймер
    // Активный таймер — только один на весь список. Для идущего пункта
    // показывается обратный отсчёт; по нулю — уведомление + звук.
    property int timerIndex: -1
    property real timerEndAt: 0
    property int timerTotal: 0
    readonly property int timerRemaining: root.timerIndex < 0
        ? 0
        : Math.max(0, Math.ceil((root.timerEndAt - root.now * 1000) / 1000))

    // ------------------------------------------------------------- утилиты
    function parseDuration(value) {
        const n = parseInt(value, 10);
        if (!isFinite(n) || n <= 0) return 0;
        return n;
    }

    function formatSeconds(sec) {
        const total = Math.max(0, Math.floor(sec));
        const m = Math.floor(total / 60);
        const s = total % 60;
        return m + ":" + (s < 10 ? "0" + s : "" + s);
    }

    function parseMinutes(str) {
        const m = /^(\d{1,2}):(\d{2})$/.exec(String(str ?? "").trim());
        if (!m) return -1;
        const h = parseInt(m[1], 10);
        const min = parseInt(m[2], 10);
        if (h < 0 || h > 23 || min < 0 || min > 59) return -1;
        return h * 60 + min;
    }

    function nowMinutes() {
        const d = new Date(root.now > 0 ? root.now * 1000 : Date.now());
        return d.getHours() * 60 + d.getMinutes();
    }

    function dayStamp() {
        const d = new Date();
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate();
    }

    function normalize(raw) {
        const empty = { "text": "", "done": false, "remind": "", "reminded": false, "duration": 0 };
        if (!raw || typeof raw !== "object") {
            empty.text = String(raw ?? "");
            return empty;
        }
        return {
            "text": String(raw.text ?? ""),
            "done": raw.done === true,
            "remind": root.parseMinutes(raw.remind) >= 0 ? String(raw.remind) : "",
            "reminded": raw.reminded === true,
            "duration": root.parseDuration(raw.duration),
        };
    }

    function save() {
        root.list = root.list.slice(0);
        dailyFileView.setText(JSON.stringify({ "lastReset": root.lastReset, "items": root.list }));
    }

    // ----------------------------------------------------------- изменения
    function addItem(text, remind, duration) {
        const txt = String(text ?? "").trim();
        if (txt.length === 0) return;
        const rm = root.parseMinutes(remind) >= 0 ? String(remind) : "";
        root.list.push({
            "text": txt,
            "done": false,
            "remind": rm,
            // Если время уже прошло — не напоминаем сегодня, чтобы не спамить.
            "reminded": rm !== "" && root.nowMinutes() >= root.parseMinutes(rm),
            "duration": root.parseDuration(duration),
        });
        save();
    }

    function removeItem(index) {
        if (index < 0 || index >= root.list.length) return;
        if (root.timerIndex === index) root.stopTimer();
        else if (root.timerIndex > index) root.timerIndex = root.timerIndex - 1;
        root.list.splice(index, 1);
        save();
    }

    // ------------------------------------------------------------- таймер
    function startTimer(index) {
        const item = root.list[index];
        const mins = item ? root.parseDuration(item.duration) : 0;
        if (mins <= 0) return;
        const ms = Date.now();
        root.now = ms / 1000;
        root.timerIndex = index;
        root.timerTotal = mins * 60;
        root.timerEndAt = ms + root.timerTotal * 1000;
    }

    function stopTimer() {
        root.timerIndex = -1;
        root.timerTotal = 0;
        root.timerEndAt = 0;
    }

    function finishTimer() {
        const item = root.list[root.timerIndex];
        root.notifyTimer(item);
        root.stopTimer();
    }

    function notifyTimer(item) {
        Quickshell.execDetached([
            "notify-send",
            "-a", "Shell",
            "-u", "normal",
            Translation.tr("Timer finished"),
            (item ? (item.text ?? "") : "")
        ]);
        Todo.playAlarmSound();
    }

    function toggle(index) {
        const item = root.list[index];
        if (!item) return;
        item.done = !item.done;
        if (item.done) item.reminded = true;
        save();
    }

    function setRemind(index, remind) {
        const item = root.list[index];
        if (!item) return;
        item.remind = root.parseMinutes(remind) >= 0 ? String(remind) : "";
        item.reminded = false;
        save();
    }

    // ---------------------------------------------------- сброс дня / напоминания
    function checkDay() {
        const stamp = root.dayStamp();
        if (root.lastReset === stamp) return;
        for (let i = 0; i < root.list.length; i++) {
            root.list[i].done = false;
            root.list[i].reminded = false;
        }
        root.lastReset = stamp;
        save();
    }

    function checkReminders() {
        const nowMin = root.nowMinutes();
        let changed = false;
        for (let i = 0; i < root.list.length; i++) {
            const item = root.list[i];
            const rm = root.parseMinutes(item.remind);
            if (item && !item.done && !item.reminded && rm >= 0 && nowMin >= rm) {
                item.reminded = true;
                root.notifyReminder(item);
                changed = true;
            }
        }
        if (changed) save();
    }

    // Просрочен ли пункт: время напоминания уже прошло, а пункт не отмечен.
    function isOverdue(item) {
        if (!item || item.done) return false;
        const rm = root.parseMinutes(item.remind);
        if (rm < 0) return false;
        return root.nowMinutes() >= rm;
    }

    function notifyReminder(item) {
        Quickshell.execDetached([
            "notify-send",
            "-a", "Shell",
            "-u", "normal",
            Translation.tr("Daily task"),
            (item.text ?? "")
        ]);
        Todo.playAlarmSound();
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: false
        onTriggered: {
            root.now = Date.now() / 1000;
            if (root.timerIndex >= 0 && root.now * 1000 >= root.timerEndAt) {
                root.finishTimer();
            }
            root.checkDay();
            root.checkReminders();
        }
    }

    Component.onCompleted: {
        root.now = Date.now() / 1000;
        refresh();
    }

    function refresh() {
        dailyFileView.reload();
    }

    FileView {
        id: dailyFileView
        path: Qt.resolvedUrl(root.filePath)
        onLoaded: {
            try {
                const parsed = JSON.parse(dailyFileView.text());
                root.list = Array.isArray(parsed.items) ? parsed.items.map(root.normalize) : [];
                root.lastReset = String(parsed.lastReset ?? "");
            } catch (e) {
                console.log("[Daily] Invalid JSON, starting empty: " + e);
                root.list = [];
                root.lastReset = "";
            }
            root.checkDay();
        }
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                console.log("[Daily] File not found, creating new file.");
                root.list = [];
                root.checkDay();
            } else {
                console.log("[Daily] Error loading file: " + error);
            }
        }
    }
}
