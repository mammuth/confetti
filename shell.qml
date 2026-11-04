// Confetti overlay. Run: qs -p shell.qml   Fire: qs -p shell.qml ipc call confetti fire
import QtQuick
import QtQuick.Particles
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root

    // flakes per side per press
    readonly property int perSide: 30
    // max random tilt of each cannon per press, degrees
    readonly property real aimJitter: 10
    readonly property var colors: ["#ff4766", "#ffd12e", "#48c7ff", "#72f26b", "#eb61f2", "#ff8a3d", "#ffffff"]
    // drag: higher = floatier, slower fall (terminal speed = 750 / drag px/s)
    readonly property var weights: [
        { drag: 3.4, size: 11, sizeVar: 4 },
        { drag: 2.4, size: 16, sizeVar: 5 },
        { drag: 1.6, size: 23, sizeVar: 7 }
    ]

    signal fired(real amount)

    IpcHandler {
        target: "confetti"
        function fire(): void { root.fired(1) }
        function burst(amount: real): void { root.fired(amount) }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            property double lastFire: 0
            // per-press cannon aim, jittered each fire
            property real leftAim: -60
            property real rightAim: -120

            screen: modelData
            visible: false
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}  // click-through
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "confetti"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // presses queued while the overlay warms up
            property real pending: 0

            function shoot(amount) {
                win.leftAim = -60 + (Math.random() - 0.5) * 2 * root.aimJitter;
                win.rightAim = -120 + (Math.random() - 0.5) * 2 * root.aimJitter;
                // each flake gets a random color/weight
                const n = Math.max(1, Math.round(root.perSide * amount));
                for (let i = 0; i < n; i++) {
                    flakes.itemAt(Math.floor(Math.random() * flakes.count)).leftGun.burst(1);
                    flakes.itemAt(Math.floor(Math.random() * flakes.count)).rightGun.burst(1);
                }
            }

            Connections {
                target: root
                function onFired(amount) {
                    const focused = Hyprland.focusedMonitor;
                    if (focused && focused.name !== win.modelData.name) return;
                    win.lastFire = Date.now();
                    if (win.visible && !warmup.running) {
                        win.shoot(amount);
                        return;
                    }
                    win.pending += amount;
                    if (warmup.running) return;
                    // ImageParticle only applies color/spin once its render node exists,
                    // so prime every group off-screen, then fire a few frames later
                    win.visible = true;
                    for (let i = 0; i < flakes.count; i++) flakes.itemAt(i).leftGun.burst(1, -5000, -5000);
                    warmup.start();
                }
            }

            Timer {
                id: warmup
                interval: 80
                onTriggered: {
                    win.shoot(win.pending);
                    win.pending = 0;
                }
            }

            // hide + pause once everything is gone
            Timer {
                interval: 1000
                repeat: true
                running: win.visible
                onTriggered: if (sys.empty && Date.now() - win.lastFire > 2000) win.visible = false
            }

            ParticleSystem {
                id: sys
                anchors.fill: parent
                paused: !win.visible
            }

            Gravity {
                system: sys
                anchors.fill: parent
                anchors.margins: -2000
                angle: 90
                magnitude: 750
            }

            // per-flake sideways drift + speed jitter
            Wander {
                system: sys
                anchors.fill: parent
                anchors.margins: -2000
                xVariance: 420
                yVariance: 60
                pace: 450
            }

            Repeater {
                id: flakes
                model: root.colors.length * root.weights.length

                Item {
                    id: flake
                    required property int index
                    readonly property string group: "c" + index
                    readonly property string tint: root.colors[index % root.colors.length]
                    readonly property var weight: root.weights[Math.floor(index / root.colors.length)]
                    // launch speed scales with drag so all weights reach similar heights
                    readonly property real launch: win.modelData.height * weight.drag * 1.0
                    property alias leftGun: leftCannon
                    property alias rightGun: rightCannon
                    anchors.fill: parent

                    // air drag: kills launch speed, caps fall speed
                    Friction {
                        system: sys
                        groups: [flake.group]
                        anchors.fill: parent
                        anchors.margins: -2000
                        factor: flake.weight.drag
                    }

                    ImageParticle {
                        system: sys
                        groups: [flake.group]
                        source: Qt.resolvedUrl("flake.png")
                        color: flake.tint
                        rotationVariation: 180
                        rotationVelocityVariation: 540
                    }

                    // bottom-left cannon, aims up-right
                    Emitter {
                        id: leftCannon
                        system: sys
                        group: flake.group
                        enabled: false
                        x: -10
                        y: win.modelData.height - 20
                        width: 30
                        height: 30
                        lifeSpan: 5000
                        lifeSpanVariation: 800
                        size: flake.weight.size
                        sizeVariation: flake.weight.sizeVar
                        velocity: AngleDirection {
                            angle: win.leftAim
                            angleVariation: 22
                            magnitude: flake.launch
                            magnitudeVariation: flake.launch * 0.25
                        }
                    }

                    // bottom-right cannon, aims up-left
                    Emitter {
                        id: rightCannon
                        system: sys
                        group: flake.group
                        enabled: false
                        x: win.modelData.width - 20
                        y: win.modelData.height - 20
                        width: 30
                        height: 30
                        lifeSpan: 5000
                        lifeSpanVariation: 800
                        size: flake.weight.size
                        sizeVariation: flake.weight.sizeVar
                        velocity: AngleDirection {
                            angle: win.rightAim
                            angleVariation: 22
                            magnitude: flake.launch
                            magnitudeVariation: flake.launch * 0.25
                        }
                    }
                }
            }
        }
    }
}
