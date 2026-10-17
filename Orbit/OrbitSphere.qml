pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets

// The orbit: a textured planet with app icons spread over a sphere around it
// (or flat rings for saturn). Drag to spin; while searching it turns the
// selected result to face you.
Item {
    id: root

    required property OrbitConfig config
    required property var apps
    property bool searching: false
    property int selected: 0
    property bool active: visible

    signal launched(var entry)

    readonly property real orbitR: Math.min(width, height) * config.orbitRadius
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property bool rings: config.resolvedOrbitStyle === "rings"

    property real yaw: 0
    property real pitch: config.restPitch
    property real yawVel: 0
    property real pitchVel: 0
    readonly property real maxPitch: 1.35

    property bool dragging: false

    // The first population snaps into place instead of gliding in from one slot
    property bool _settled: false
    Component.onCompleted: Qt.callLater(() => _settled = true)

    // Animated so icons glide when the orbit population changes
    property real fCount: Math.max(1, apps.length)

    Behavior on fCount {
        enabled: root._settled

        NumberAnimation {
            duration: root.config.anim("slowSpatial").duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.config.anim("slowSpatial").curve
        }
    }

    // Evenly distribute points on a unit sphere (Fibonacci lattice, works for fractional i)
    function basePoint(i: real, n: real): var {
        // Flat equatorial rings: two concentric layers with a gap off the planet,
        // even slots on the inner ring, odd on the outer (cos(pi * i) blends fractional i)
        if (rings) {
            const a = (2 * Math.PI * i) / n;
            const r = 1.5 - 0.12 * Math.cos(Math.PI * i);
            return {
                x: r * Math.cos(a),
                y: 0,
                z: r * Math.sin(a)
            };
        }
        const ga = Math.PI * (3 - Math.sqrt(5));
        const y = 1 - (2 * (i + 0.5)) / n;
        const r = Math.sqrt(Math.max(0, 1 - y * y));
        return {
            x: r * Math.cos(ga * i),
            y: y,
            z: r * Math.sin(ga * i)
        };
    }

    // Rotate by yaw (Y axis) then pitch (X axis), +z towards the viewer
    function project(b: var): var {
        const cy_ = Math.cos(yaw), sy_ = Math.sin(yaw);
        const x = b.x * cy_ + b.z * sy_;
        let z = -b.x * sy_ + b.z * cy_;
        const cp = Math.cos(pitch), sp = Math.sin(pitch);
        const y = b.y * cp - z * sp;
        z = b.y * sp + z * cp;
        const persp = 1 + z * 0.12;
        return {
            x: x * persp,
            y: y * persp,
            z: z
        };
    }

    // Orientation that brings the selected slot to face the viewer
    readonly property var frontBase: basePoint(Math.min(selected, Math.max(0, apps.length - 1)), Math.max(1, apps.length))
    readonly property real targetYaw: -Math.atan2(frontBase.x, frontBase.z)
    readonly property real targetPitch: Math.atan2(frontBase.y, Math.hypot(frontBase.x, frontBase.z))

    function angleDiff(a: real, b: real): real {
        let d = (b - a) % (Math.PI * 2);
        if (d > Math.PI)
            d -= Math.PI * 2;
        if (d < -Math.PI)
            d += Math.PI * 2;
        return d;
    }

    function step(dt: real): void {
        dt = Math.min(dt, 0.05);
        if (dragging)
            return;

        if (searching && apps.length > 0) {
            const k = Math.min(1, dt * 6);
            yaw += angleDiff(yaw, targetYaw) * k;
            pitch += (targetPitch - pitch) * k;
            yawVel = 0;
            pitchVel = 0;
        } else {
            yaw += (yawVel + config.idleSpeed) * dt;
            pitch += pitchVel * dt + (config.restPitch - pitch) * Math.min(1, dt * 0.5);
            const decay = Math.exp(-dt * 2);
            yawVel *= decay;
            pitchVel *= decay;
        }
        pitch = Math.max(-maxPitch, Math.min(maxPitch, pitch));
    }

    // Vsync-paced by default; max_fps swaps in a timer to save CPU on high refresh panels
    FrameAnimation {
        running: root.active && root.config.maxFps <= 0
        onTriggered: root.step(frameTime)
    }

    Timer {
        property real last: 0

        running: root.active && root.config.maxFps > 0
        repeat: true
        interval: Math.max(4, Math.round(1000 / Math.max(1, root.config.maxFps)))
        onRunningChanged: last = Date.now()
        onTriggered: {
            const now = Date.now();
            root.step((now - last) / 1000);
            last = now;
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -2
        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        property real lastX
        property real lastY
        property real lastT

        onPressed: mouse => {
            lastX = mouse.x;
            lastY = mouse.y;
            lastT = Date.now();
            root.dragging = true;
            root.yawVel = 0;
            root.pitchVel = 0;
        }
        onReleased: root.dragging = false
        onCanceled: root.dragging = false
        onPositionChanged: mouse => {
            if (!root.dragging)
                return;
            const now = Date.now();
            const dt = Math.max(0.008, (now - lastT) / 1000);
            const k = root.config.dragSensitivity / root.orbitR;
            const dYaw = (mouse.x - lastX) * k;
            const dPitch = (mouse.y - lastY) * k;
            root.yaw += dYaw;
            root.pitch = Math.max(-root.maxPitch, Math.min(root.maxPitch, root.pitch + dPitch));
            root.yawVel = root.yawVel * 0.7 + (dYaw / dt) * 0.3;
            root.pitchVel = root.pitchVel * 0.7 + (dPitch / dt) * 0.3;
            lastX = mouse.x;
            lastY = mouse.y;
            lastT = now;
        }
    }

    // The planet: back-hemisphere icons (z < 0) stack behind it, front ones in front
    Item {
        z: 0
        x: root.cx - root.orbitR
        y: root.cy - root.orbitR
        width: root.orbitR * 2
        height: root.orbitR * 2

        ClippingRectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.config.planetBackground

            Image {
                id: planetImg

                // Try the name as given, then each common extension
                readonly property string base: `${root.config.resolvedPlanetsDir}/${root.config.resolvedPlanet}`
                readonly property list<string> candidates: /\.[a-z0-9]{2,5}$/i.test(root.config.resolvedPlanet) ? [base] : ["jpg", "png", "jpeg", "webp", "svg"].map(e => `${base}.${e}`)
                property int attempt: 0

                onCandidatesChanged: attempt = 0
                onStatusChanged: {
                    if (status === Image.Error) {
                        if (attempt + 1 < candidates.length)
                            attempt++;
                        else
                            console.warn(`orbit: no planet image "${root.config.resolvedPlanet}" in ${root.config.resolvedPlanetsDir}`);
                    }
                }

                anchors.fill: parent
                source: candidates.length ? "file://" + candidates[attempt] : ""
                sourceSize: Qt.size(Math.min(root.config.planetResolution, Math.ceil(width * 1.1)), Math.min(root.config.planetResolution, Math.ceil(height * 1.1)))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                scale: 1.02
                rotation: -root.yaw * root.config.planetSpin
            }
        }

        Canvas {
            anchors.fill: parent
            visible: root.config.vignette
            renderStrategy: Canvas.Cooperative
            onWidthChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                const r = width / 2;
                ctx.reset();
                const g = ctx.createRadialGradient(r, r, r * 0.55, r, r, r);
                g.addColorStop(0, "rgba(4,5,12,0)");
                g.addColorStop(0.8, "rgba(4,5,12,0.3)");
                g.addColorStop(1, "rgba(4,5,12,0.8)");
                ctx.fillStyle = g;
                ctx.beginPath();
                ctx.arc(r, r, r, 0, Math.PI * 2);
                ctx.fill();
            }
        }
    }

    Repeater {
        model: ScriptModel {
            values: root.apps
        }

        Item {
            id: app

            required property DesktopEntry modelData
            required property int index

            property real slot: index

            Behavior on slot {
                NumberAnimation {
                    duration: root.config.anim("slowSpatial").duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.config.anim("slowSpatial").curve
                }
            }

            readonly property var pp: root.project(root.basePoint(slot, root.fCount))
            readonly property real depth: (pp.z + 1) / 2
            readonly property bool inFront: pp.z > 0.05
            readonly property bool highlighted: root.searching && index === root.selected

            x: root.cx + pp.x * root.orbitR - width / 2
            y: root.cy - pp.y * root.orbitR - height / 2
            z: pp.z
            width: root.orbitR * (root.rings ? root.config.ringTileSize : root.config.tileSize)
            height: width
            // Only the hover bump is animated; depth already moves continuously
            property real hoverScale: mouse.containsMouse ? 1.15 : 1
            scale: (0.5 + 0.7 * depth) * hoverScale
            opacity: Math.max(0, Math.min(1, (pp.z + 0.35) * 3)) * (0.35 + 0.65 * depth)
            visible: opacity > 0.001

            Behavior on hoverScale {
                NumberAnimation {
                    duration: root.config.anim("standardSmall").duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.config.anim("standardSmall").curve
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: root.config.tileRadius
                color: Qt.alpha(root.config.cTile, app.highlighted ? 1 : root.config.tileOpacity)
                border.width: app.highlighted ? 2 : 0
                border.color: root.config.cPrimary

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: Math.round(parent.width * root.config.iconScale)
                    source: Quickshell.iconPath(app.modelData?.icon, "image-missing")
                    asynchronous: true
                }
            }

            Rectangle {
                anchors.top: parent.bottom
                anchors.topMargin: 3
                anchors.horizontalCenter: parent.horizontalCenter

                visible: root.config.showLabels && opacity > 0
                implicitWidth: Math.min(label.implicitWidth + 18, root.orbitR * 0.6)
                implicitHeight: label.implicitHeight + 6

                radius: height / 2
                color: root.config.cLabelBackground
                opacity: app.depth > 0.7 || mouse.containsMouse || app.highlighted ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.config.anim("defaultEffects").duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: root.config.anim("defaultEffects").curve
                    }
                }

                Text {
                    id: label

                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, root.orbitR * 0.6 - 18)
                    text: app.modelData?.name ?? ""
                    renderType: Text.NativeRendering
                    textFormat: Text.PlainText
                    font.family: root.config.fontFamily
                    font.pointSize: root.config.labelFontSize
                    font.variableAxes: ({
                            "ROND": 25,
                            "opsz": root.config.labelFontSize,
                            "wght": 400
                        })
                    color: root.config.cLabel
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            MouseArea {
                id: mouse

                anchors.fill: parent
                hoverEnabled: true
                enabled: app.inFront
                cursorShape: Qt.PointingHandCursor
                onClicked: root.launched(app.modelData)
            }
        }
    }
}
