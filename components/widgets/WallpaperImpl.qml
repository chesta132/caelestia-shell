import QtQuick
import Caelestia
import Caelestia.Config
import Caelestia.Multimedia
import Caelestia.Shaders
import Caelestia.State
import qs.services

Item {
    id: root

    // Screen this wallpaper is on; falls back to the focused monitor
    property var screen

    readonly property var parallax: Config.background.parallax
    readonly property bool parallaxActive: parallax.enabled && parallax.amount > 0
    readonly property bool parallaxHorizontal: parallax.axis === ParallaxAxis.Horizontal
    readonly property var monitor: screen ? Hypr.monitorFor(screen) : Hypr.focusedMonitor
    // Workspaces 1-10 are the 10 steps; anything past 10 wraps back around and specials stay put
    readonly property int wsStep: {
        const id = monitor?.activeWorkspace?.id ?? 1;
        return id >= 1 ? (id - 1) % 10 : 0;
    }
    readonly property real parallaxProgress: wsStep / 9

    readonly property transitionShader shader: {
        CUtils.dependency(Config.background.wallpaperTransition);
        let transition = CUtils.enumToString(Config.background, "wallpaperTransition");
        if (!transition)
            return Shaders.crossfade;

        transition = transition[0].toLowerCase() + transition.slice(1);
        return Shaders[transition] ?? Shaders.crossfade;
    }

    property string source: Wallpapers.current
    property ShaderEffectSource currentCapture: capture1
    property real transitionProgress: 1

    onSourceChanged: {
        transitionAnim.stop();

        if (transitionProgress < 1) {
            currentCapture = currentCapture === capture1 ? capture2 : capture1;
            currentCapture.sourceItem = transition;
        } else {
            currentCapture.sourceItem = view;
        }

        currentCapture.visible = true;
        currentCapture.scheduleUpdate();
    }

    Component.onCompleted: {
        live.source = source;
        if (introEnabled && live.ready)
            introAnim.start();
    }

    // Intro: the wallpaper opens from the top, smaller and transparent
    property bool introEnabled: true
    property real introProgress: introEnabled ? 0 : 1

    NumberAnimation {
        id: introAnim

        target: root
        property: "introProgress"
        from: 0
        to: 1
        duration: 700
        easing.type: Easing.OutCubic
    }

    NumberAnimation on transitionProgress {
        id: transitionAnim

        running: false
        duration: root.shader.duration * Tokens.anim.durations.scale
        easing: root.shader.easing
        to: 1
    }

    ShaderEffectSource {
        id: capture1

        anchors.fill: parent
        live: false
        visible: false

        onScheduledUpdateCompleted: {
            visible = false;
            transition.from = this;
            root.transitionProgress = 0;
            live.source = root.source;
            if (live.ready)
                transitionAnim.start();
        }
    }

    ShaderEffectSource {
        id: capture2

        anchors.fill: parent
        live: false
        visible: false

        onScheduledUpdateCompleted: {
            visible = false;
            transition.from = this;
            root.transitionProgress = 0;
            live.source = root.source;
            if (live.ready)
                transitionAnim.start();
        }
    }

    Item {
        id: view

        anchors.fill: parent
        clip: true

        // Intro starts transparent above the screen, then settles
        opacity: root.introProgress

        transform: Translate {
            y: -0.35 * view.height * (1 - root.introProgress)
        }

        Visual {
            id: live

            // Oversized by 2 * amount so the pan never reveals an edge.
            // Higher workspaces move the viewport right/down, so the image itself drifts left/up.
            width: parent.width
            height: parent.height
            x: root.parallaxActive && root.parallaxHorizontal ? (0.5 - root.parallaxProgress) * 2 * root.parallax.amount * width : 0
            y: root.parallaxActive && !root.parallaxHorizontal ? (0.5 - root.parallaxProgress) * 2 * root.parallax.amount * height : 0
            scale: root.parallaxActive ? 1 + 2 * root.parallax.amount : 1

            // Deliberately slower than the workspace switch and without overshoot
            Behavior on x {
                NumberAnimation {
                    duration: 900
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on y {
                NumberAnimation {
                    duration: 900
                    easing.type: Easing.OutCubic
                }
            }

            playing: PersistentState.wallpaperPlaying
            animate: false
            layer.enabled: true

            onReadyChanged: {
                if (ready && source === root.source) {
                    transitionAnim.start();
                    if (root.introEnabled && root.introProgress === 0)
                        introAnim.start();
                }
            }
        }
    }

    ShaderEffect {
        id: transition

        property Item from
        property Item to: view
        property real progress: root.transitionProgress

        anchors.fill: parent
        visible: root.transitionProgress < 1
        fragmentShader: root.shader.url
    }
}
