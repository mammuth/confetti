// Confetti overlay. Run: qs -p shell.qml   Fire: qs -p shell.qml ipc call confetti shoot confetti
import QtQuick
import QtQuick.Particles
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root

    // max random tilt of each cannon per press, degrees
    readonly property real aimJitter: 10

    // Presets, fired by name. Per preset:
    //   perSide  flakes per cannon per press
    //   images   flake images (any aspect ratio), picked at random
    //   colors   tints, picked at random; omit to keep the image's own colors (emoji)
    //   weights  classes picked at random; drag: higher = floatier, slower fall
    //            (terminal speed = 750 / drag px/s), size/sizeVar in px
    //   tilt     random start rotation, degrees
    //   spin     random rotation speed, degrees/s
    readonly property var presets: ({
        confetti: {
            perSide: 30,
            images: ["flake.png"],
            colors: ["#ff4766", "#ffd12e", "#48c7ff", "#72f26b", "#eb61f2", "#ff8a3d", "#ffffff"],
            weights: [
                { drag: 3.4, size: 11, sizeVar: 4 },
                { drag: 2.4, size: 16, sizeVar: 5 },
                { drag: 1.6, size: 23, sizeVar: 7 }
            ],
            tilt: 180,
            spin: 540
        },
        pepe: {
            perSide: 5,
            images: ["pepe.png"],
            weights: [
                { drag: 2.6, size: 44, sizeVar: 8 },
                { drag: 1.8, size: 58, sizeVar: 6 }
            ],
            tilt: 25,
            spin: 60
        },
        bomb: {
            perSide: 4,
            images: ["bomb.png"],
            weights: [
                { drag: 1.5, size: 52, sizeVar: 12 }
            ],
            tilt: 40,
            spin: 120
        },
        bikestick: {
            perSide: 4,
            images: ["bikestick.png"],
            weights: [
                { drag: 2.2, size: 56, sizeVar: 8 }
            ],
            tilt: 20,
            spin: 45
        },
        pog: {
            perSide: 6,
            images: ["pog.png"],
            weights: [
                { drag: 2.6, size: 42, sizeVar: 8 },
                { drag: 1.8, size: 50, sizeVar: 6 }
            ],
            tilt: 30,
            spin: 90
        },
        "100": {
            perSide: 6,
            images: ["100.png"],
            weights: [
                { drag: 2.6, size: 44, sizeVar: 8 },
                { drag: 1.8, size: 56, sizeVar: 8 }
            ],
            tilt: 25,
            spin: 60
        }
    })
    readonly property string defaultPreset: "confetti"

    // every image x color x weight combination becomes one particle group
    readonly property var kinds: {
        const out = [];
        for (const name in presets) {
            const p = presets[name];
            for (const image of p.images)
                for (const color of (p.colors ?? ["white"]))
                    for (const weight of p.weights)
                        out.push({ preset: name, image, color, weight, tilt: p.tilt, spin: p.spin });
        }
        return out;
    }

    signal fired(string preset, real amount)

    function fire(preset, amount) {
        if (!(preset in presets)) {
            console.warn("confetti: unknown preset", preset, "- have:", Object.keys(presets).join(", "));
            return;
        }
        fired(preset, amount);
    }

    IpcHandler {
        target: "confetti"
        function fire(): void { root.fire(root.defaultPreset, 1) }
        function shoot(preset: string): void { root.fire(preset, 1) }
        function burst(preset: string, amount: real): void { root.fire(preset, amount) }
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
            property var pending: []

            function shoot(preset, amount) {
                win.leftAim = -60 + (Math.random() - 0.5) * 2 * root.aimJitter;
                win.rightAim = -120 + (Math.random() - 0.5) * 2 * root.aimJitter;
                // each flake gets a random image/color/weight of the preset
                const pool = [];
                for (let i = 0; i < flakes.count; i++)
                    if (root.kinds[i].preset === preset) pool.push(flakes.itemAt(i));
                const n = Math.max(1, Math.round(root.presets[preset].perSide * amount));
                for (let i = 0; i < n; i++) {
                    pool[Math.floor(Math.random() * pool.length)].leftGun.burst(1);
                    pool[Math.floor(Math.random() * pool.length)].rightGun.burst(1);
                }
            }

            Connections {
                target: root
                function onFired(preset, amount) {
                    const focused = Hyprland.focusedMonitor;
                    if (focused && focused.name !== win.modelData.name) return;
                    win.lastFire = Date.now();
                    if (win.visible && !warmup.running) {
                        win.shoot(preset, amount);
                        return;
                    }
                    win.pending.push({ preset, amount });
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
                    for (const p of win.pending) win.shoot(p.preset, p.amount);
                    win.pending = [];
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
                model: root.kinds

                Item {
                    id: flake
                    required property var modelData
                    required property int index
                    readonly property string group: "k" + index
                    readonly property var weight: modelData.weight
                    // launch speed scales with drag so all weights reach similar heights
                    readonly property real launch: win.modelData.height * weight.drag * 1.0
                    // particles are square; squash to the image's aspect ratio
                    readonly property real aspect: probe.implicitHeight > 0 ? probe.implicitWidth / probe.implicitHeight : 1
                    property alias leftGun: leftCannon
                    property alias rightGun: rightCannon
                    anchors.fill: parent

                    Image {
                        id: probe
                        visible: false
                        source: Qt.resolvedUrl(flake.modelData.image)
                    }

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
                        source: Qt.resolvedUrl(flake.modelData.image)
                        color: flake.modelData.color
                        rotationVariation: flake.modelData.tilt
                        rotationVelocityVariation: flake.modelData.spin
                        xVector: PointDirection { x: Math.min(1, flake.aspect) }
                        yVector: PointDirection { y: Math.min(1, 1 / flake.aspect) }
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
