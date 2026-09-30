import QtQuick
import QtQuick.Layouts
import qs.modules.common

ToolbarButton {
    id: iconBtn
    required property string iconText

    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    // Подсветка при наведении — как у включённой кнопки (например,
    // «Консоль»), иначе пилюли теряются на фоне плашки.
    colBackgroundHover: Appearance.colors.colSecondaryContainer
    colRipple: Appearance.colors.colSecondaryContainerActive
    property color colText: (toggled || hovered)
        ? Appearance.colors.colOnSecondaryContainer
        : Appearance.colors.colOnSurfaceVariant

    // Размер иконки/подписи и зазор между ними. Уменьшаются в компактных
    // местах (например, в плашке git-статуса внизу дерева).
    property int iconSize: 22
    property int fontPixelSize: 0 // 0 — размер Appearance по умолчанию
    property int contentSpacing: 6

    // Control сам растягивает contentItem на доступную область и сдвигает
    // его на padding, поэтому иконка с подписью центрируются внутри
    // обёртки: иначе Row прижимает их к левому краю кнопки.
    contentItem: Item {
        implicitWidth: btnRow.implicitWidth
        implicitHeight: btnRow.implicitHeight

        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: iconBtn.contentSpacing

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                iconSize: iconBtn.iconSize
                text: iconBtn.iconText
                color: iconBtn.colText
            }
            StyledText {
                visible: iconBtn.iconText.length > 0 && iconBtn.text.length > 0
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: iconBtn.fontPixelSize > 0
                    ? iconBtn.fontPixelSize
                    : Appearance.font.pixelSize.default
                color: iconBtn.colText
                text: iconBtn.text
            }
        }
    }
}
