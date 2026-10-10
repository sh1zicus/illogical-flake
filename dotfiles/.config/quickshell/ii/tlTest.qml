import qs.modules.ii.todoWindow
import qs
import QtQuick
import Quickshell

FloatingWindow {
    implicitWidth: 560
    implicitHeight: 690
    TaskList {
        anchors.fill: parent
        taskList: [
            {"content": "Прогресс задача", "done": false, "priority": "low", "type": "progress", "current": 3, "total": 10, "originalIndex": 0},
            { "content": "Код", "done": false, "priority": "high", "type": "code", "code": "fn main() {\n    println!(\"hi\");\n}", "originalIndex": 1 },
            { "content": "Чеклист", "done": false, "priority": "medium", "type": "checklist", "items": [{"text": "первый", "done": true}, {"text": "второй", "done": false}], "originalIndex": 2 },
            { "content": "Готовая задача", "done": true, "priority": "none", "type": "text", "originalIndex": 3 }
        ]
    }
}
