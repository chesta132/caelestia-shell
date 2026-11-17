import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// "Keep these display settings?" prompt. Changes revert on their own when the countdown ends.
StyledRect {
    id: root

    readonly property bool shown: Displays.pending !== null

    visible: opacity > 0
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.9

    radius: Tokens.rounding.large
    color: Colours.palette.m3secondaryContainer
    implicitWidth: row.implicitWidth + Tokens.padding.large * 2
    implicitHeight: row.implicitHeight + Tokens.padding.large * 2

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    Behavior on scale {
        Anim {}
    }

    RowLayout {
        id: row

        anchors.centerIn: parent
        spacing: Tokens.spacing.large

        MaterialIcon {
            text: "monitor"
            color: Colours.palette.m3onSecondaryContainer
            fontStyle: Tokens.font.icon.medium
        }

        Column {
            StyledText {
                text: Tr.tr("Keep these display settings?")
                color: Colours.palette.m3onSecondaryContainer
                font: Tokens.font.label.large
            }

            StyledText {
                text: Tr.tr("Reverting in %1s").arg(Displays.countdown)
                color: Colours.palette.m3onSecondaryContainer
                opacity: 0.8
                font: Tokens.font.label.small
            }
        }

        TextButton {
            text: Tr.tr("Revert")
            type: TextButton.Tonal
            onClicked: Displays.revertChanges()
        }

        TextButton {
            text: Tr.tr("Keep")
            type: TextButton.Filled
            onClicked: Displays.keepChanges()
        }
    }
}
