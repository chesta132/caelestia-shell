pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// Resolution / refresh rate / scale (+ forget) for a single monitor
ColumnLayout {
    id: root

    required property string name
    readonly property var mon: Displays.byName(name)
    readonly property var resolutions: mon ? Displays.resolutionsOf(mon) : []
    readonly property string currentRes: mon ? `${mon.width}x${mon.height}` : ""
    readonly property var refreshRates: mon ? Displays.refreshRatesOf(mon, mon.width, mon.height) : []
    readonly property var scales: {
        const base = [0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3];
        const cur = mon?.scale ?? 1;
        // Keep a custom scale (e.g. set in hyprland.conf) selectable
        return base.some(s => Math.abs(s - cur) < 0.005) ? base : [...base, cur].sort((a, b) => a - b);
    }

    function formatHz(hz: real): string {
        return Tr.tr("%1 Hz").arg(hz.toFixed(2).replace(/\.?0+$/, ""));
    }

    function formatScale(s: real): string {
        return `${Math.round(s * 100)}%`;
    }

    // Closest available refresh rate to `hz` for a given resolution
    function bestRate(w: int, h: int, hz: real): real {
        const rates = Displays.refreshRatesOf(mon, w, h);
        return rates.reduce((best, r) => Math.abs(r - hz) < Math.abs(best - hz) ? r : best, rates[0] ?? hz);
    }

    spacing: Tokens.spacing.extraSmall / 2
    visible: !!mon && mon.ready

    SectionHeader {
        text: root.mon ? (root.mon.label === root.name ? root.name : `${root.mon.label} (${root.name})`) : root.name
    }

    RowButton {
        visible: !!root.mon?.disabled
        first: true
        last: true
        icon: "power_settings_new"
        text: Tr.tr("Disabled")
        subtext: Tr.tr("Click to enable this monitor")
        onClicked: Displays.enable(root.name)
    }

    SelectRow {
        visible: !root.mon?.disabled
        first: true
        label: Tr.tr("Resolution")
        fallbackText: root.currentRes
        menuItems: resItems.instances
        active: resItems.instances.find(i => i.value === root.currentRes) ?? null
        onSelected: item => {
            const res = root.resolutions.find(r => r.id === item.value);
            if (res && root.mon)
                Displays.setMode(root.name, res.w, res.h, root.bestRate(res.w, res.h, root.mon.refresh));
        }

        Variants {
            id: resItems

            model: root.resolutions

            MenuItem {
                required property var modelData

                text: modelData.label
                value: modelData.id
            }
        }
    }

    SelectRow {
        visible: !root.mon?.disabled
        label: Tr.tr("Refresh rate")
        fallbackText: root.mon ? root.formatHz(root.mon.refresh) : ""
        menuItems: rateItems.instances
        active: rateItems.instances.find(i => Math.abs(i.value - (root.mon?.refresh ?? 0)) < 0.05) ?? null
        onSelected: item => {
            if (root.mon)
                Displays.setMode(root.name, root.mon.width, root.mon.height, item.value);
        }

        Variants {
            id: rateItems

            model: root.refreshRates

            MenuItem {
                required property real modelData

                text: root.formatHz(modelData)
                value: modelData
            }
        }
    }

    SelectRow {
        visible: !root.mon?.disabled
        last: !mirrorRow.visible && !disableRow.visible
        label: Tr.tr("Scale")
        fallbackText: root.mon ? root.formatScale(root.mon.scale) : ""
        menuItems: scaleItems.instances
        active: scaleItems.instances.find(i => Math.abs(i.value - (root.mon?.scale ?? 1)) < 0.005) ?? null
        onSelected: item => Displays.setScale(root.name, item.value)

        Variants {
            id: scaleItems

            model: root.scales

            MenuItem {
                required property real modelData

                text: root.formatScale(modelData)
                value: modelData
            }
        }
    }

    RowButton {
        id: mirrorRow

        visible: !root.mon?.disabled && !!root.mon?.mirrorOf
        last: !disableRow.visible
        icon: "cast"
        text: Tr.tr("Mirroring %1").arg(root.mon?.mirrorOf ?? "")
        subtext: Tr.tr("Click to stop mirroring and place it to the right")
        onClicked: Displays.unmirror(root.name)
    }

    RowButton {
        id: disableRow

        // Never the built-in display or the last active one
        visible: !!root.mon && !root.mon.disabled && !root.mon.builtin && Displays.activeCount > 1
        last: true
        icon: "power_settings_new"
        text: Tr.tr("Disable this monitor")
        subtext: Tr.tr("Turn it off. You can enable it again from here")
        onClicked: Displays.disable(root.name)
    }
}
