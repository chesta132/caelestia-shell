pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components.controls
import qs.modules.nexus.common

ColumnLayout {
    id: root

    // Timeout in seconds, <= 0 means never
    property int value
    property string label
    property bool first
    property bool last

    // Custom stays selected while editing, even if the typed value matches a quick option
    property bool customPicked
    readonly property bool isNever: value <= 0
    readonly property bool isCustom: !isNever && (customPicked || !items.slice(1, -1).some(i => i.value === value))

    readonly property list<MenuItem> items: [
        MenuItem {
            readonly property bool selected: root.isNever

            value: 0
            text: Tr.trCtx("Never", "idle timeout")
            icon: selected ? "check" : ""
            activeIcon: "block"
        },
        MenuItem {
            readonly property bool selected: !root.isCustom && root.value === value

            value: 300
            text: Tr.trN("%n minute", "%n minutes", 5)
            icon: selected ? "check" : ""
            activeIcon: "timer"
        },
        MenuItem {
            readonly property bool selected: !root.isCustom && root.value === value

            value: 600
            text: Tr.trN("%n minute", "%n minutes", 10)
            icon: selected ? "check" : ""
            activeIcon: "timer"
        },
        MenuItem {
            readonly property bool selected: !root.isCustom && root.value === value

            value: 900
            text: Tr.trN("%n minute", "%n minutes", 15)
            icon: selected ? "check" : ""
            activeIcon: "timer"
        },
        MenuItem {
            readonly property bool selected: !root.isCustom && root.value === value

            value: 1800
            text: Tr.trN("%n minute", "%n minutes", 30)
            icon: selected ? "check" : ""
            activeIcon: "timer"
        },
        MenuItem {
            readonly property bool selected: root.isCustom

            value: -1
            text: Tr.trCtx("Custom", "idle timeout")
            icon: selected ? "check" : ""
            activeIcon: "edit"
        }
    ]

    signal moved(value: int)

    Layout.fillWidth: true
    spacing: Tokens.spacing.extraSmall / 2
    z: select.z // Keep the open menu above the rows below

    onValueChanged: {
        if (isNever)
            customPicked = false;
    }

    SelectRow {
        id: select

        first: root.first
        last: root.last && !root.isCustom
        label: root.label
        menuItems: root.items
        active: root.items.find(i => i.selected) ?? root.items[0]
        onSelected: item => {
            if (item.value < 0) {
                root.customPicked = true;
                if (root.value <= 0)
                    root.moved(60);
            } else {
                root.customPicked = false;
                root.moved(item.value);
            }
        }
    }

    TextFieldRow {
        visible: root.isCustom
        last: root.last
        label: Tr.tr("Custom")
        subtext: Tr.tr("In seconds")
        smallField: true
        value: String(root.value)
        validator: IntValidator {
            bottom: 1
            top: 604800
        }
        onEditingFinished: v => {
            const n = parseInt(v);
            if (n > 0 && n !== root.value)
                root.moved(n);
        }
    }
}
