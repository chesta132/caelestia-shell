#pragma once

#include <qstring.h>
#include <qstringlist.h>
#include <qvariantlist.h>

#include "settings/objectnode.hpp"
#include "util/i18n.hpp"
#include "common.hpp"

namespace caelestia::shell::config {

using Qt::StringLiterals::operator""_s;
using settings::vmap;
using util::i18n::mark;

class GeneralApps : public settings::ObjectNode {
    CONFIG_NODE(GeneralApps, settings::ObjectNode)

    CONFIG_PROPERTY(QStringList, terminal, { u"foot"_s })
    CONFIG_PROPERTY(QStringList, audio, { u"pwvucontrol"_s })
    CONFIG_PROPERTY(QStringList, playback, { u"mpv"_s })
    CONFIG_PROPERTY(QStringList, explorer, { u"thunar"_s })
};

// Idle timeouts in seconds. A value <= 0 disables that action.
// `timeout` applies on battery (or on desktops without a battery),
// `timeoutCharging` applies while a laptop battery is charging / plugged in.
class GeneralIdleLock : public settings::ObjectNode {
    CONFIG_NODE(GeneralIdleLock, settings::ObjectNode)

    CONFIG_PROPERTY(int, timeout, 180)
    CONFIG_PROPERTY(int, timeoutCharging, 180)
};

class GeneralIdleDisplay : public settings::ObjectNode {
    CONFIG_NODE(GeneralIdleDisplay, settings::ObjectNode)

    CONFIG_PROPERTY(int, timeout, 300)
    CONFIG_PROPERTY(int, timeoutCharging, 0)
};

class GeneralIdleSleep : public settings::ObjectNode {
    CONFIG_NODE(GeneralIdleSleep, settings::ObjectNode)

    CONFIG_PROPERTY(int, timeout, 600)
    CONFIG_PROPERTY(int, timeoutCharging, 0)
};

class GeneralIdle : public settings::ObjectNode {
    CONFIG_NODE(GeneralIdle, settings::ObjectNode)

    CONFIG_PROPERTY(bool, lockBeforeSleep, true)
    CONFIG_PROPERTY(bool, inhibitWhenAudio, true)
    CONFIG_SUBOBJECT(GeneralIdleLock, lock)
    CONFIG_SUBOBJECT(GeneralIdleDisplay, display)
    CONFIG_SUBOBJECT(GeneralIdleSleep, sleep)
};

class GeneralBatteryWarnLevel : public settings::ObjectNode {
    CONFIG_NODE(GeneralBatteryWarnLevel, settings::ObjectNode)

    CONFIG_PROPERTY(int, level, -1)
    CONFIG_PROPERTY(QString, title, {})
    CONFIG_PROPERTY(QString, message, {})
    CONFIG_PROPERTY(QString, icon, {})
    CONFIG_PROPERTY(bool, critical, false)
};
CONFIG_LIST_TYPE(GeneralBatteryWarnLevel, GeneralBatteryWarnList)

class GeneralBattery : public settings::ObjectNode {
    CONFIG_NODE(GeneralBattery, settings::ObjectNode)

    CONFIG_LIST(GeneralBatteryWarnList, warnLevels,
        DEFAULT_ARG({
            vmap({
                { u"level"_s, 20 },
                { u"title"_s, mark(u"Low battery"_s) },
                { u"message"_s, mark(u"You might want to plug in a charger"_s) },
                { u"icon"_s, u"battery_android_frame_2"_s },
            }),
            vmap({
                { u"level"_s, 10 },
                { u"title"_s, mark(u"Did you see the previous message?"_s) },
                { u"message"_s, mark(u"You should probably plug in a charger <b>now</b>"_s) },
                { u"icon"_s, u"battery_android_frame_1"_s },
            }),
            vmap({
                { u"level"_s, 5 },
                { u"title"_s, mark(u"Critical battery level"_s) },
                { u"message"_s, mark(u"PLUG THE CHARGER RIGHT NOW!!"_s) },
                { u"icon"_s, u"battery_android_alert"_s },
                { u"critical"_s, true },
            }),
        }))
    CONFIG_PROPERTY(int, criticalLevel, 3)
};

class GeneralConfig : public settings::ObjectNode {
    CONFIG_NODE(GeneralConfig, settings::ObjectNode)

    CONFIG_GLOBAL_PROPERTY(QString, logo, {})
    CONFIG_GLOBAL_PROPERTY(QString, language, {})
    CONFIG_PROPERTY(bool, showOverFullscreen, false)
    CONFIG_PROPERTY(qreal, mediaGifSpeedAdjustment, 150)
    CONFIG_PROPERTY(qreal, sessionGifSpeed, 0.7)
    CONFIG_GLOBAL_SUBOBJECT(GeneralApps, apps)
    CONFIG_GLOBAL_SUBOBJECT(GeneralIdle, idle)
    CONFIG_GLOBAL_SUBOBJECT(GeneralBattery, battery)
};

} // namespace caelestia::shell::config
