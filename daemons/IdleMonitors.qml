pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import Caelestia.Config
import Caelestia.Services
import qs.services
import qs.modules.lock

Scope {
    id: root

    required property Lock lock
    readonly property bool hasPlayer: Players.list.some(p => p.isPlaying)
    // Desktops have no battery, so there is no "charging" state: they always use the regular timeouts
    readonly property bool isCharging: UPower.displayDevice.isLaptopBattery && !UPower.onBattery
    readonly property bool enabled: !(GlobalConfig.general.idle.inhibitWhenAudio && hasPlayer)

    function setDpms(on: bool): void {
        if (Hypr.usingLua)
            Hypr.dispatch(`hl.dsp.dpms({ action = "${on ? "enable" : "disable"}" })`);
        else
            Hypr.dispatch(on ? "dpms on" : "dpms off");
    }

    // Timeout in seconds for the current power state, 0 when disabled
    function timeoutFor(node: var): int {
        const t = isCharging ? node.timeoutCharging : node.timeout;
        return t > 0 ? t : 0;
    }

    Connections {
        function onAboutToSleep(): void {
            if (GlobalConfig.general.idle.lockBeforeSleep)
                root.lock.lock.locked = true;
        }

        function onResumed(): void {
            // The idle monitor doesn't reliably report activity across a suspend, so the
            // return action can be missed and the outputs stay off. Always turn them back on.
            root.setDpms(true);
            dpmsRetry.restart();
        }

        function onLockRequested(): void {
            root.lock.lock.locked = true;
        }

        function onUnlockRequested(): void {
            root.lock.lock.unlock();
        }

        target: SessionManager
    }

    // Outputs can still be coming back up right after resume, so try once more
    Timer {
        id: dpmsRetry

        interval: 1000
        onTriggered: root.setDpms(true)
    }

    // Always respects wayland idle inhibitors (wake locks, fullscreen video, etc.)
    component Monitor: IdleMonitor {
        required property int seconds

        enabled: root.enabled && seconds > 0
        timeout: Math.max(1, seconds)
        respectInhibitors: true
    }

    Monitor {
        seconds: root.timeoutFor(GlobalConfig.general.idle.lock)
        onIsIdleChanged: {
            if (isIdle)
                root.lock.lock.locked = true;
        }
    }

    Monitor {
        seconds: root.timeoutFor(GlobalConfig.general.idle.display)
        onIsIdleChanged: root.setDpms(!isIdle)
        onEnabledChanged: {
            // Don't leave the screens off if the timeout gets disabled or inhibited while idle
            if (!enabled)
                root.setDpms(true);
        }
    }

    Monitor {
        seconds: root.timeoutFor(GlobalConfig.general.idle.sleep)
        onIsIdleChanged: {
            if (isIdle)
                SessionManager.suspendThenHibernate();
        }
    }
}
