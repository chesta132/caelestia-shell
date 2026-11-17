pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common
import qs.modules.nexus.pages.display

PageBase {
    id: root

    title: Tr.tr("Display")

    // Don't let the page scroll while a monitor is being dragged
    flickable.interactive: !arrange.blockFlick

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Arrange
        SectionHeader {
            first: true
            text: Tr.tr("Arrange")
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: arrangeLayout.implicitHeight + Tokens.padding.large * 2
            first: true
            last: true

            ColumnLayout {
                id: arrangeLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                MonitorArrange {
                    id: arrange

                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Displays.activeCount > 1 ? Tr.tr("Drag to arrange. Drop a display on the middle of another to mirror it.") : Tr.tr("Connect another display to arrange them.")
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    wrapMode: Text.WordWrap
                }
            }
        }

        // Per-monitor settings
        Repeater {
            model: Displays.monitorNames

            MonitorSection {
                required property string modelData

                Layout.fillWidth: true
                name: modelData
            }
        }

        // Saved monitors
        NavRow {
            Layout.topMargin: Tokens.spacing.largeIncreased
            first: true
            last: true
            icon: "bookmark"
            text: Tr.tr("Saved monitors")
            subtext: Tr.tr("Forget monitors that have saved settings")
            onClicked: root.nState.openSubPage(1)
        }
    }
}
