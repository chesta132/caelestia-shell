pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services
import qs.modules.nexus.common

// Saved monitors that can be forgotten (the built-in display is never listed)
PageBase {
    id: root

    title: Tr.tr("Saved monitors")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            visible: Displays.forgettable.length === 0
            text: Tr.tr("No saved monitors")
            color: Colours.palette.m3outline
            font: Tokens.font.label.medium
        }

        Repeater {
            model: Displays.forgettable

            RowButton {
                required property int index
                required property var modelData

                Layout.fillWidth: true
                first: index === 0
                last: index === Displays.forgettable.length - 1
                icon: "delete"
                text: modelData.label
                subtext: modelData.connected ? Tr.tr("Connected. Tap to forget") : Tr.tr("Tap to forget")
                onClicked: Displays.forget(modelData.key)
            }
        }
    }
}
