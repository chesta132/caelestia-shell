pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import Caelestia.Config
import Caelestia.I18n
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var idle: GlobalConfig.general.idle
    readonly property bool hasBattery: UPower.displayDevice.isLaptopBattery

    readonly property list<var> profiles: [
        {
            profile: PowerProfile.PowerSaver,
            icon: "energy_savings_leaf",
            label: Tr.trCtx("Power saver", "power profile")
        },
        {
            profile: PowerProfile.Balanced,
            icon: "balance",
            label: Tr.trCtx("Balanced", "power profile")
        },
        {
            profile: PowerProfile.Performance,
            icon: "rocket_launch",
            label: Tr.trCtx("Performance", "power profile")
        }
    ]
    readonly property list<var> availableProfiles: profiles.filter(p => p.profile !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile)

    title: Tr.tr("Power")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Power strategy
        SectionHeader {
            first: true
            text: Tr.tr("Power strategy")
        }

        Repeater {
            model: root.availableProfiles

            RowButton {
                required property var modelData
                required property int index

                first: index === 0
                last: index === root.availableProfiles.length - 1
                icon: modelData.icon
                text: modelData.label
                trailingIcon: PowerProfiles.profile === modelData.profile ? "check" : ""
                onClicked: PowerProfiles.profile = modelData.profile
            }
        }

        // Timeouts
        SectionHeader {
            text: Tr.tr("Timeouts")
        }

        TimeoutRow {
            first: true
            label: Tr.tr("Lock")
            value: root.idle.lock.timeout
            onMoved: v => root.idle.lock.timeout = v
        }

        TimeoutRow {
            label: Tr.tr("Turn off display")
            value: root.idle.display.timeout
            onMoved: v => root.idle.display.timeout = v
        }

        TimeoutRow {
            last: true
            label: Tr.tr("Sleep")
            value: root.idle.sleep.timeout
            onMoved: v => root.idle.sleep.timeout = v
        }

        // While charging (only meaningful when there's a battery)
        SectionHeader {
            visible: root.hasBattery
            text: Tr.tr("While charging")
        }

        TimeoutRow {
            visible: root.hasBattery
            first: true
            label: Tr.tr("Lock")
            value: root.idle.lock.timeoutCharging
            onMoved: v => root.idle.lock.timeoutCharging = v
        }

        TimeoutRow {
            visible: root.hasBattery
            label: Tr.tr("Turn off display")
            value: root.idle.display.timeoutCharging
            onMoved: v => root.idle.display.timeoutCharging = v
        }

        TimeoutRow {
            visible: root.hasBattery
            last: true
            label: Tr.tr("Sleep")
            value: root.idle.sleep.timeoutCharging
            onMoved: v => root.idle.sleep.timeoutCharging = v
        }

        // Behaviour
        SectionHeader {
            text: Tr.tr("Behaviour")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Lock before sleep")
            checked: root.idle.lockBeforeSleep
            onToggled: root.idle.lockBeforeSleep = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Stay awake while playing media")
            checked: root.idle.inhibitWhenAudio
            onToggled: root.idle.inhibitWhenAudio = checked
        }
    }
}
