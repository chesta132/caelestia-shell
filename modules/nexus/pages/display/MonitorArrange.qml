pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

// Drag monitors to arrange them. Dropping one onto the middle of another mirrors it.
Item {
    id: root

    // Monitors that own a spot in the layout (mirrors are drawn on top of their target)
    readonly property var placed: Displays.list.filter(m => m.active && !m.mirrorOf)
    readonly property var bounds: {
        const p = placed;
        if (p.length === 0)
            return {
                x: 0,
                y: 0,
                w: 1920,
                h: 1080
            };
        const minX = Math.min(...p.map(m => m.x));
        const minY = Math.min(...p.map(m => m.y));
        const maxX = Math.max(...p.map(m => m.x + m.logicalW));
        const maxY = Math.max(...p.map(m => m.y + m.logicalH));
        const padX = Math.max(...p.map(m => m.logicalW)) * 0.6;
        const padY = Math.max(...p.map(m => m.logicalH)) * 0.6;
        return {
            x: minX - padX,
            y: minY - padY,
            w: maxX - minX + padX * 2,
            h: maxY - minY + padY * 2
        };
    }
    readonly property real fit: Math.min(width / bounds.w, height / bounds.h)
    readonly property real offX: (width - bounds.w * fit) / 2 - bounds.x * fit
    readonly property real offY: (height - bounds.h * fit) / 2 - bounds.y * fit

    // True while any tile is pressed or dragged. The page uses this to stop its flickable from
    // stealing the drag (and scrolling) while a monitor is being moved.
    readonly property bool blockFlick: busyCount > 0
    property int busyCount
    property string hoverTarget // Monitor currently under the dragged one's centre (mirror candidate)

    readonly property real snapThreshold: 48 // logical px

    // Where the dragged monitor will land: a mirror target, or a snapped rect (logical coords)
    property var hintRect: null

    implicitHeight: 380
    clip: true

    function logicalRect(mon: var): var {
        if (mon.mirrorOf) {
            // Draw mirrors stacked on top of their target, slightly offset so both stay visible
            const t = Displays.byName(mon.mirrorOf);
            if (t)
                return {
                    x: t.x + 12 / fit,
                    y: t.y + 12 / fit,
                    w: mon.logicalW,
                    h: mon.logicalH
                };
        }
        return {
            x: mon.x,
            y: mon.y,
            w: mon.logicalW,
            h: mon.logicalH
        };
    }

    function overlaps(a: var, b: var): bool {
        return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
    }

    function clamp(v: real, lo: real, hi: real): real {
        return Math.max(lo, Math.min(hi, v));
    }

    // Monitor whose central area the rect's centre lies in -> would mirror it
    function mirrorTargetFor(name: string, r: var): string {
        // A monitor that others mirror can't itself become a mirror (no chains)
        if (Displays.list.some(m => m.mirrorOf === name))
            return "";

        const cx = r.x + r.w / 2;
        const cy = r.y + r.h / 2;
        for (const o of placed) {
            if (o.name === name)
                continue;
            if (cx > o.x + o.logicalW * 0.25 && cx < o.x + o.logicalW * 0.75 && cy > o.y + o.logicalH * 0.25 && cy < o.y + o.logicalH * 0.75)
                return o.name;
        }
        return "";
    }

    // Nearest valid position that touches an edge of another monitor without overlapping any
    function snapPosition(name: string, r: var): var {
        const others = placed.filter(o => o.name !== name);
        if (others.length === 0)
            return {
                x: 0,
                y: 0
            };

        const T = snapThreshold;
        const cands = [];

        const alignAxis = (free, candidates) => {
            for (const c of candidates)
                if (Math.abs(c - free) <= T)
                    return c;
            return free;
        };

        for (const o of others) {
            const minOvX = Math.min(r.w, o.logicalW) * 0.25;
            const minOvY = Math.min(r.h, o.logicalH) * 0.25;

            // Left / right of o
            for (const x of [o.x + o.logicalW, o.x - r.w]) {
                const free = clamp(r.y, o.y - r.h + minOvY, o.y + o.logicalH - minOvY);
                const y = alignAxis(free, [o.y, o.y + o.logicalH - r.h, o.y + (o.logicalH - r.h) / 2]);
                cands.push({
                    x,
                    y
                });
            }

            // Above / below o
            for (const y of [o.y + o.logicalH, o.y - r.h]) {
                const free = clamp(r.x, o.x - r.w + minOvX, o.x + o.logicalW - minOvX);
                const x = alignAxis(free, [o.x, o.x + o.logicalW - r.w, o.x + (o.logicalW - r.w) / 2]);
                cands.push({
                    x,
                    y
                });
            }
        }

        let best = null;
        let bestDist = Infinity;
        for (const c of cands) {
            const rect = {
                x: c.x,
                y: c.y,
                w: r.w,
                h: r.h
            };
            if (others.some(o => overlaps(rect, {
                    x: o.x,
                    y: o.y,
                    w: o.logicalW,
                    h: o.logicalH
                })))
                continue;

            const d = Math.hypot(c.x - r.x, c.y - r.y);
            if (d < bestDist) {
                bestDist = d;
                best = {
                    x: Math.round(c.x),
                    y: Math.round(c.y)
                };
            }
        }
        return best;
    }

    function drop(name: string, r: var): void {
        const mon = Displays.byName(name);
        if (!mon)
            return;

        const target = mirrorTargetFor(name, r);
        if (target) {
            if (mon.mirrorOf !== target)
                Displays.setMirror(name, target);
            return;
        }

        const pos = snapPosition(name, r);
        if (!pos)
            return;

        // Normalise so the top-left-most monitor sits at 0,0
        const others = placed.filter(o => o.name !== name);
        const minX = Math.min(pos.x, ...others.map(o => o.x));
        const minY = Math.min(pos.y, ...others.map(o => o.y));

        const positions = {
            [name]: {
                x: pos.x - minX,
                y: pos.y - minY
            }
        };
        if (minX !== 0 || minY !== 0)
            for (const o of others)
                positions[o.name] = {
                    x: o.x - minX,
                    y: o.y - minY
                };

        // Skip no-ops
        const changed = Object.keys(positions).filter(n => {
            const m = Displays.byName(n);
            return mon.mirrorOf && n === name || m.x !== positions[n].x || m.y !== positions[n].y;
        });
        if (changed.length === 0)
            return;

        const patch = {};
        for (const n of changed)
            patch[n] = positions[n];
        Displays.setPositions(patch);
    }

    // Landing hint while dragging (extend position)
    Rectangle {
        visible: !!root.hintRect && !root.hoverTarget
        x: root.hintRect ? root.hintRect.x * root.fit + root.offX : 0
        y: root.hintRect ? root.hintRect.y * root.fit + root.offY : 0
        width: root.hintRect ? root.hintRect.w * root.fit : 0
        height: root.hintRect ? root.hintRect.h * root.fit : 0
        radius: Tokens.rounding.small
        color: Qt.alpha(Colours.palette.m3primary, 0.15)
        border.width: 2
        border.color: Qt.alpha(Colours.palette.m3primary, 0.6)
    }

    Repeater {
        model: Displays.monitorNames

        StyledRect {
            id: tile

            required property string modelData
            readonly property var mon: Displays.byName(modelData)
            readonly property var rect: mon ? root.logicalRect(mon) : null
            readonly property bool dragging: dragHandler.active
            readonly property bool busy: press.pressed || dragHandler.active
            readonly property bool isMirror: !!mon?.mirrorOf
            readonly property bool isHoverTarget: root.hoverTarget === modelData
            property point lastDrag

            // Position the dragged tile would have (in logical coordinates)
            function draggedRect(): var {
                return {
                    x: rect.x + lastDrag.x / root.fit,
                    y: rect.y + lastDrag.y / root.fit,
                    w: rect.w,
                    h: rect.h
                };
            }

            visible: !!mon && mon.active
            x: rect ? rect.x * root.fit + root.offX + (dragging ? lastDrag.x : 0) : 0
            y: rect ? rect.y * root.fit + root.offY + (dragging ? lastDrag.y : 0) : 0
            width: rect ? rect.w * root.fit : 0
            height: rect ? rect.h * root.fit : 0
            z: dragging ? 100 : isMirror ? 2 : 1
            scale: dragging ? 1.03 : 1
            opacity: dragging ? 0.85 : 1

            radius: Tokens.rounding.small
            color: isHoverTarget ? Colours.palette.m3primaryContainer : isMirror ? Colours.palette.m3tertiaryContainer : Colours.palette.m3secondaryContainer
            border.width: isHoverTarget || dragging ? 2 : 1
            border.color: isHoverTarget || dragging ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

            onBusyChanged: root.busyCount += busy ? 1 : -1
            Component.onDestruction: {
                if (busy)
                    root.busyCount--;
            }

            Behavior on x {
                enabled: !tile.dragging

                Anim {}
            }

            Behavior on y {
                enabled: !tile.dragging

                Anim {}
            }

            Behavior on scale {
                Anim {}
            }

            Behavior on opacity {
                Anim {}
            }

            TapHandler {
                id: press

                // Grab early so the flickable is already blocked before the drag threshold is reached
                gesturePolicy: TapHandler.WithinBounds
            }

            HoverHandler {
                enabled: Displays.activeCount > 1
                cursorShape: dragHandler.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            }

            DragHandler {
                id: dragHandler

                target: null // Tile position is derived, not dragged directly
                enabled: Displays.activeCount > 1
                // Nothing (including the page's Flickable) may take the drag over from us
                grabPermissions: PointerHandler.CanTakeOverFromAnything

                onTranslationChanged: {
                    if (!active)
                        return;
                    const baseX = tile.rect.x * root.fit + root.offX;
                    const baseY = tile.rect.y * root.fit + root.offY;
                    // Keep the tile's centre inside (so it can be pushed past an edge to go above/left of everything)
                    tile.lastDrag = Qt.point(root.clamp(translation.x, -baseX - tile.width / 2, root.width - baseX - tile.width / 2), root.clamp(translation.y, -baseY - tile.height / 2, root.height - baseY - tile.height / 2));

                    const r = tile.draggedRect();
                    root.hoverTarget = root.mirrorTargetFor(tile.modelData, r);
                    if (root.hoverTarget) {
                        root.hintRect = null;
                    } else {
                        const pos = root.snapPosition(tile.modelData, r);
                        root.hintRect = pos ? {
                            x: pos.x,
                            y: pos.y,
                            w: r.w,
                            h: r.h
                        } : null;
                    }
                }
                onActiveChanged: {
                    if (active) {
                        tile.lastDrag = Qt.point(0, 0);
                        return;
                    }

                    const r = tile.draggedRect();
                    root.hoverTarget = "";
                    root.hintRect = null;
                    root.drop(tile.modelData, r);
                    tile.lastDrag = Qt.point(0, 0);
                }
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - Tokens.padding.small * 2
                spacing: 0

                MaterialIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tile.isMirror ? "cast" : tile.mon?.builtin ? "laptop" : "desktop_windows"
                    color: tile.isMirror ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.modelData
                    color: tile.isMirror ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSecondaryContainer
                    font: Tokens.font.label.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: tile.height > 64
                    text: tile.isMirror ? Tr.tr("Mirroring %1").arg(tile.mon?.mirrorOf ?? "") : `${tile.mon?.width ?? 0}×${tile.mon?.height ?? 0}`
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }
            }
        }
    }
}
