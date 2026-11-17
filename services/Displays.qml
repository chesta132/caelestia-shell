pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia
import Caelestia.I18n
import qs.utils

// Display (monitor) management: new-monitor detection + toasts, persistent per-monitor
// config, and applying mode/scale/position/mirror to Hyprland.
Singleton {
    id: root

    // Saved per-monitor configs, keyed by stable monitor key (see keyOf)
    // { mode: "1920x1080@60.00", scale: 1, x: 0, y: 0, mirrorOf: "<key>" | "" }
    property var saved: ({})
    readonly property bool loaded: file.loaded

    // Raw output of `hyprctl monitors all -j` (includes disabled monitors)
    property var raw: []
    // Normalised view of all connected monitors (including disabled ones)
    readonly property list<var> list: raw.map(m => describe(m))
    readonly property int activeCount: list.filter(m => m.active).length
    // Only changes when monitors are added/removed, so UI repeaters don't rebuild on every refresh
    property var monitorNames: []

    function syncNames(): void {
        const names = raw.map(m => m.name);
        if (JSON.stringify(names) !== JSON.stringify(monitorNames))
            monitorNames = names;
    }

    function describe(ipc: var): var {
        const scale = ipc.scale || 1;
        const rotated = (ipc.transform ?? 0) % 2 === 1;
        const w = ipc.width ?? 0;
        const h = ipc.height ?? 0;
        const disabled = ipc.disabled === true;
        const mirrorRaw = ipc.mirrorOf;
        let mirrorName = "";
        if (mirrorRaw !== undefined && mirrorRaw !== null && mirrorRaw !== "none" && mirrorRaw !== -1) {
            const target = raw.find(o => o.name === String(mirrorRaw) || String(o.id) === String(mirrorRaw));
            mirrorName = target?.name ?? "";
        }

        return {
            name: ipc.name,
            id: ipc.id,
            key: keyOf(ipc),
            label: ipc.model || ipc.description || ipc.name,
            disabled,
            ready: disabled || (w > 0 && h > 0),
            active: !disabled && w > 0 && h > 0, // Part of the layout
            width: w,
            height: h,
            refresh: ipc.refreshRate ?? 60,
            scale,
            x: ipc.x ?? 0,
            y: ipc.y ?? 0,
            logicalW: Math.round((rotated ? h : w) / scale),
            logicalH: Math.round((rotated ? w : h) / scale),
            modes: parseModes(ipc.availableModes ?? []),
            mirrorOf: mirrorName,
            builtin: isBuiltin(ipc.name),
            hasSaved: saved[keyOf(ipc)] !== undefined
        };
    }

    function parseModes(modes: var): var {
        const out = [];
        for (const m of modes) {
            const match = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(m);
            if (match)
                out.push({
                    w: parseInt(match[1]),
                    h: parseInt(match[2]),
                    hz: parseFloat(match[3])
                });
        }
        return out;
    }

    function resolutionsOf(mon: var): var {
        const seen = new Set();
        const out = [];
        for (const m of mon.modes) {
            const id = `${m.w}x${m.h}`;
            if (!seen.has(id)) {
                seen.add(id);
                out.push({
                    id,
                    w: m.w,
                    h: m.h,
                    label: `${m.w} × ${m.h}`
                });
            }
        }
        return out.sort((a, b) => b.w * b.h - a.w * a.h);
    }

    function refreshRatesOf(mon: var, w: int, h: int): var {
        const rates = [];
        for (const m of mon.modes)
            if (m.w === w && m.h === h && !rates.includes(m.hz))
                rates.push(m.hz);
        return rates.sort((a, b) => b - a);
    }

    function isBuiltin(name: string): bool {
        return /^(eDP|LVDS|DSI)/i.test(name);
    }

    function keyOf(ipc: var): string {
        const id = [ipc.make, ipc.model, ipc.serial].filter(s => s && s.length > 0).join(" ");
        if (id)
            return id;
        // Description contains the connector in parens, which can change between ports
        const desc = (ipc.description ?? "").replace(/\s*\([^)]*\)\s*$/, "");
        return desc || ipc.name;
    }

    function byName(name: string): var {
        return list.find(m => m.name === name) ?? null;
    }

    function byKey(key: string): var {
        return list.find(m => m.key === key) ?? null;
    }

    // ---- Applying ----

    function modeString(w: int, h: int, hz: real): string {
        return `${w}x${h}@${hz.toFixed(2)}`;
    }

    // Hyprland 0.57 only reads hyprland.lua, so monitors are configured with hl.monitor() through `hyprctl eval`
    // (the old `keyword monitor` is rejected). hl.monitor() over IPC is additive: omitted fields keep their
    // previous live value, so `disabled` and `mirror` are always sent explicitly, otherwise a monitor would
    // stay disabled / keep mirroring after being re-enabled / un-mirrored.
    function monitorCommand(name: string, mode: string, x: var, y: var, scale: real, mirrorName: string): string {
        const pos = x === null ? "auto" : `${x}x${y}`;
        return `eval hl.monitor({ output = "${name}", disabled = false, mode = "${mode}", position = "${pos}", scale = ${scale}, mirror = "${mirrorName}" })`;
    }

    // Effective config of a connected monitor (current state), as a saveable snapshot
    function snapshot(mon: var): var {
        return {
            mode: modeString(mon.width, mon.height, mon.refresh),
            scale: mon.scale,
            x: mon.x,
            y: mon.y,
            mirrorOf: byName(mon.mirrorOf)?.key ?? "",
            label: mon.label,
            builtin: mon.builtin,
            disabled: false
        };
    }

    // Saved monitors that can be forgotten (never the built-in display)
    readonly property var forgettable: Object.keys(saved).filter(k => !saved[k].builtin && !byKey(k)?.builtin).map(k => ({
                key: k,
                label: saved[k].label || k,
                connected: byKey(k) !== null
            }))

    // patches: { <monitorName>: { mode?, scale?, x?, y?, mirrorOf? (key or "") } }
    // Applies to Hyprland and persists. With `confirm` the change is reverted automatically
    // unless kept within `confirmSeconds` (like Windows' "keep these display settings").
    function update(patches: var, confirm: bool): void {
        const cmds = [];
        const next = Object.assign({}, saved);
        const before = {};

        for (const name of Object.keys(patches)) {
            const mon = byName(name);
            if (!mon)
                continue;

            before[name] = snapshot(mon);
            const cfg = Object.assign(snapshot(mon), patches[name]);
            next[mon.key] = cfg;
            cmds.push(commandFor(mon.name, cfg));
        }

        if (cmds.length === 0)
            return;

        if (confirm) {
            // Keep the oldest state if a change is already awaiting confirmation
            const prev = pending ?? {
                saved: saved,
                snapshots: {}
            };
            for (const name of Object.keys(before))
                if (prev.snapshots[name] === undefined)
                    prev.snapshots[name] = before[name];
            pending = prev;
            countdown = confirmSeconds;
            confirmTimer.restart();
        }

        saved = next;
        save();
        send(cmds);
    }

    // ---- Confirm / revert ----

    readonly property int confirmSeconds: 15
    property var pending: null // { saved, snapshots: { <name>: snapshot } } while awaiting confirmation
    property int countdown

    function keepChanges(): void {
        confirmTimer.stop();
        pending = null;
    }

    function revertChanges(): void {
        confirmTimer.stop();
        const p = pending;
        pending = null;
        if (!p)
            return;

        const cmds = [];
        for (const name of Object.keys(p.snapshots))
            if (byName(name))
                cmds.push(commandFor(name, p.snapshots[name]));

        saved = p.saved;
        save();
        if (cmds.length > 0)
            send(cmds);
    }

    Timer {
        id: confirmTimer

        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown--;
            if (root.countdown <= 0)
                root.revertChanges();
        }
    }

    function disableCommand(name: string): string {
        return `eval hl.monitor({ output = "${name}", disabled = true })`;
    }

    function commandFor(name: string, cfg: var): string {
        if (cfg.disabled)
            return disableCommand(name);
        const target = cfg.mirrorOf ? byKey(cfg.mirrorOf) : null;
        // Mirror target might not be connected anymore, or be the monitor itself
        const mirrorName = target && target.name !== name ? target.name : "";
        return monitorCommand(name, cfg.mode, Math.round(cfg.x ?? 0), Math.round(cfg.y ?? 0), cfg.scale ?? 1, mirrorName);
    }

    function send(cmds: var): void {
        Hypr.extras.batchMessage(cmds);
        refreshTimer.restart();
    }

    function setMode(name: string, w: int, h: int, hz: real): void {
        update({
            [name]: {
                mode: modeString(w, h, hz)
            }
        }, true);
    }

    function setScale(name: string, scale: real): void {
        update({
            [name]: {
                scale
            }
        }, true);
    }

    function setMirror(name: string, targetName: string): void {
        update({
            [name]: {
                mirrorOf: byName(targetName)?.key ?? ""
            }
        }, true);
    }

    // Place monitors at the given logical positions: { <name>: { x, y } }. Also clears mirroring on those.
    function setPositions(positions: var): void {
        const patches = {};
        for (const name of Object.keys(positions))
            patches[name] = {
                x: positions[name].x,
                y: positions[name].y,
                mirrorOf: ""
            };
        update(patches, true);
    }

    // Turn a disabled monitor back on: saved config if there is one, else its preferred mode placed automatically
    function enable(name: string): void {
        const mon = byName(name);
        if (!mon)
            return;

        const cfg = saved[mon.key];
        if (cfg) {
            const next = Object.assign({}, saved);
            next[mon.key] = Object.assign({}, cfg, {
                disabled: false
            });
            saved = next;
            save();
            send([commandFor(name, next[mon.key])]);
        } else {
            send([monitorCommand(name, "preferred", null, null, 1, "")]);
        }
    }

    // Turn a monitor off (never the last active one). Reverts unless kept, like other display changes.
    function disable(name: string): void {
        const mon = byName(name);
        if (!mon || mon.builtin || activeCount <= 1)
            return;
        update({
            [name]: {
                disabled: true
            }
        }, true);
    }

    // Stop mirroring and put the monitor to the right of everything else
    function unmirror(name: string): void {
        const others = list.filter(m => m.name !== name && m.active && !m.mirrorOf);
        const right = others.length > 0 ? Math.max(...others.map(m => m.x + m.logicalW)) : 0;
        setPositions({
            [name]: {
                x: right,
                y: 0
            }
        });
    }

    function forget(key: string): void {
        if (saved[key] === undefined)
            return;
        const next = Object.assign({}, saved);
        delete next[key];
        saved = next;
        save();
    }

    // ---- New monitor handling ----

    property bool initialised
    property var knownNames: ({})
    property int pendingTries

    function processMonitors(): void {
        if (!loaded)
            return;

        const current = list;
        const names = {};
        for (const m of current)
            names[m.name] = m.label;

        // Wait for IPC data of any monitor that was just added
        if (current.some(m => !m.ready) && pendingTries < 10) {
            pendingTries++;
            refresh();
            processTimer.restart();
            return;
        }
        pendingTries = 0;

        if (!initialised) {
            initialised = true;
            knownNames = names;
            // Re-apply persisted configs for monitors that are already connected
            applySavedToConnected();
            return;
        }

        const added = current.filter(m => knownNames[m.name] === undefined);
        // Unplugged (a monitor that was merely disabled stays in `monitors all`, so it isn't listed here)
        const removed = Object.keys(knownNames).filter(n => names[n] === undefined);
        const removedLabels = knownNames;
        knownNames = names;

        for (const name of removed)
            handleRemovedMonitor(name, removedLabels[name]);
        for (const mon of added)
            handleNewMonitor(mon);
    }

    function applySavedToConnected(): void {
        const cmds = [];
        for (const mon of list) {
            const cfg = saved[mon.key];
            if (!cfg || !mon.active || (cfg.disabled && activeCount <= 1))
                continue;
            const cur = snapshot(mon);
            if (JSON.stringify(cur) === JSON.stringify(Object.assign({}, cur, cfg)))
                continue;
            cmds.push(commandFor(mon.name, Object.assign(cur, cfg)));
        }
        if (cmds.length > 0)
            send(cmds);
    }

    // "1920x1080@144.00" -> "1920×1080@144Hz"
    function prettyMode(mode: string): string {
        const m = /^(\d+)x(\d+)@([\d.]+)$/.exec(mode);
        return m ? `${m[1]}×${m[2]}@${parseFloat(m[3])}Hz` : mode;
    }

    function handleRemovedMonitor(name: string, label: string): void {
        Toaster.toast(Tr.tr("%1 disconnected").arg(name), label && label !== name ? label : Tr.tr("Display removed"), "desktop_access_disabled");
    }

    function handleNewMonitor(mon: var): void {
        const cfg = saved[mon.key];
        const title = Tr.tr("%1 connected").arg(mon.name);

        if (mon.disabled) {
            Toaster.toast(title, Tr.tr("Disabled"), "monitor");
        } else if (cfg?.disabled && activeCount > 1) {
            send([commandFor(mon.name, Object.assign(snapshot(mon), cfg))]);
            Toaster.toast(title, Tr.tr("Disabled from config"), "monitor");
        } else if (cfg) {
            send([commandFor(mon.name, Object.assign(snapshot(mon), cfg))]);
            Toaster.toast(title, Tr.tr("%1 applied").arg(prettyMode(cfg.mode ?? snapshot(mon).mode)), "monitor");
        } else {
            // Nothing saved: Hyprland's own monitor rules decide
            Toaster.toast(title, Tr.tr("No saved config, %1").arg(prettyMode(snapshot(mon).mode)), "monitor");
        }
    }

    // ---- Persistence ----

    function save(): void {
        file.setText(JSON.stringify({
            monitors: saved
        }, null, 2));
    }

    Timer {
        id: processTimer

        interval: 600
        onTriggered: root.processMonitors()
    }

    Timer {
        id: refreshTimer

        interval: 300
        onTriggered: root.refresh()
    }

    // ---- Monitor list (hyprctl monitors all -j) ----

    property bool refreshQueued

    function refresh(): void {
        if (listProc.running)
            refreshQueued = true;
        else
            listProc.running = true;
    }

    function parse(text: string): void {
        try {
            raw = JSON.parse(text);
        } catch (e) {
            console.warn("Displays: unable to parse monitors:", e);
            return;
        }
        syncNames();
        processTimer.restart();
    }

    Process {
        id: listProc

        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
        onRunningChanged: {
            if (!running && root.refreshQueued) {
                root.refreshQueued = false;
                running = true;
            }
        }
    }

    Connections {
        function onRawEvent(event: HyprlandEvent): void {
            // Events that change the set or state of monitors
            if (["monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2", "configreloaded"].includes(event.name))
                root.refresh();
        }

        target: Hyprland
    }

    Connections {
        function onConfigReloaded(): void {
            root.applySavedToConnected();
        }

        target: Hypr
    }

    FileView {
        id: file

        property bool loaded

        path: `${Paths.state}/displays.json`
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.saved = data.monitors ?? {};
            } catch (e) {
                console.warn("Displays: unable to parse displays.json:", e);
            }
            loaded = true;
            processTimer.restart();
        }
        onLoadFailed: err => {
            loaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => root.save());
            else
                console.warn("Displays: unable to load displays.json:", err);
            processTimer.restart();
        }
    }

    Component.onCompleted: refresh()
}
