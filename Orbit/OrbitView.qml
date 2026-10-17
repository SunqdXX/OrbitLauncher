pragma ComponentBehavior: Bound

import QtQuick

// The whole launcher as a plain Item: planet, orbiting apps and search bar.
// Embed it in any panel/drawer of your own shell; OrbitWindow wraps it in a
// ready-made layer-shell window.
Item {
    id: root

    required property OrbitConfig config
    property OrbitApps apps: OrbitApps {
        config: root.config
    }

    // Height the view may grow to; the sphere fits inside it like the original
    property real maxHeight: 1450

    signal requestClose
    signal launched(var entry)

    readonly property real padding: config.padding
    readonly property var results: apps.search(search.text)
    readonly property var orbitApps: results.slice(0, Math.max(1, config.maxApps))
    readonly property bool searching: search.text.length > 0
    property int selected: 0

    readonly property alias sphere: sphere
    readonly property alias searchField: search

    readonly property real sphereSide: config.size > 0 ? config.size : Math.max(config.minSize, Math.min(maxHeight - 160, config.maxSize))

    implicitWidth: sphereSide + padding * 2
    implicitHeight: sphereSide + searchWrapper.implicitHeight + padding * 3

    onResultsChanged: selected = 0

    function launch(entry: var): void {
        if (!entry)
            return;
        apps.launch(entry);
        launched(entry);
        if (config.closeOnLaunch)
            requestClose();
    }

    function move(delta: int): void {
        const n = orbitApps.length;
        if (n === 0)
            return;
        if (!navigating) {
            navigating = true;
            if (!searching) {
                selected = 0;
                return;
            }
        }
        selected = ((selected + delta) % n + n) % n;
    }

    // Arrow keys work without typing too; the orbit then turns like a search
    property bool navigating: false

    // Clear state so the next open starts fresh
    function reset(): void {
        search.text = "";
        selected = 0;
        navigating = false;
    }

    function focusSearch(): void {
        search.forceActiveFocus();
    }

    FontLoader {
        // Bundled so the look survives on systems without Google Sans Flex
        source: root.config.fontFamily === "Google Sans Flex" && Qt.fontFamilies().indexOf("Google Sans Flex") < 0 ? Qt.resolvedUrl("fonts/GoogleSansFlex.ttf") : ""
    }

    OrbitSphere {
        id: sphere

        anchors.top: parent.top
        anchors.topMargin: root.padding
        anchors.horizontalCenter: parent.horizontalCenter

        width: root.sphereSide
        height: root.sphereSide

        config: root.config
        apps: root.orbitApps
        searching: root.searching || root.navigating
        selected: root.selected
        active: root.visible

        onLaunched: entry => root.launch(entry)
    }

    Rectangle {
        id: searchWrapper

        color: root.config.cSearch
        radius: height / 2

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        width: root.sphereSide * Math.max(0.1, Math.min(1, root.config.searchWidth))

        implicitHeight: root.config.searchHeight > 0 ? root.config.searchHeight : Math.max(searchIcon.implicitHeight, searchBox.implicitHeight, clearIcon.implicitHeight)

        OrbitIcon {
            id: searchIcon

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: root.padding

            name: "search"
            color: root.config.cIcon
            pointSize: root.config.iconFontSize
        }

        // A bare TextInput: QtQuick.Controls would cost ~30 MB for the same look
        Item {
            id: searchBox

            anchors.left: searchIcon.right
            anchors.right: clearIcon.left
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter

            implicitHeight: search.contentHeight + root.config.searchPadding * 2
            height: implicitHeight

            Text {
                anchors.fill: search
                visible: !search.text && !search.preeditText
                text: root.config.placeholder
                color: root.config.cPlaceholder
                font: search.font
                renderType: Text.NativeRendering
                textFormat: Text.PlainText
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }

            TextInput {
                id: search

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                clip: true
                color: root.config.cText
                selectionColor: Qt.alpha(root.config.cPrimary, 0.35)
                selectedTextColor: root.config.cText
                selectByMouse: true
                font.family: root.config.fontFamily
                font.pointSize: root.config.fontSize
                font.variableAxes: ({
                        "ROND": 25,
                        "opsz": root.config.fontSize,
                        "wght": 400
                    })
                renderType: TextInput.NativeRendering
                verticalAlignment: TextInput.AlignVCenter

                cursorDelegate: Rectangle {
                    id: cursor

                    property bool disableBlink

                    width: 2
                    color: root.config.cPrimary
                    radius: 2

                    Connections {
                        function onCursorPositionChanged(): void {
                            if (search.activeFocus) {
                                cursor.opacity = 1;
                                cursor.disableBlink = true;
                                enableBlink.restart();
                            }
                        }

                        target: search
                    }

                    Timer {
                        id: enableBlink

                        interval: 100
                        onTriggered: cursor.disableBlink = false
                    }

                    Timer {
                        running: search.activeFocus && !cursor.disableBlink
                        repeat: true
                        triggeredOnStart: true
                        interval: 500
                        onTriggered: parent.opacity = parent.opacity === 1 ? 0 : 1
                    }

                    Binding {
                        when: !search.activeFocus
                        cursor.opacity: 0
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: root.config.anim("standardSmall").duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: root.config.anim("standardSmall").curve
                        }
                    }
                }

                onTextChanged: root.navigating = false
                onAccepted: root.launch(root.orbitApps[root.searching || root.navigating ? root.selected : 0])

                Keys.onEscapePressed: root.requestClose()
                Keys.onUpPressed: root.move(-1)
                Keys.onDownPressed: root.move(1)
                Keys.onTabPressed: root.move(1)
                Keys.onBacktabPressed: root.move(-1)
                Keys.onPressed: event => {
                    if (event.modifiers & Qt.ControlModifier) {
                        if (event.key === Qt.Key_J || event.key === Qt.Key_N) {
                            root.move(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_K || event.key === Qt.Key_P) {
                            root.move(-1);
                            event.accepted = true;
                        }
                    }
                }
            }
        }

        OrbitIcon {
            id: clearIcon

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: root.padding

            width: search.text ? implicitWidth : implicitWidth / 2
            opacity: {
                if (!search.text)
                    return 0;
                if (clearMouse.pressed)
                    return 0.7;
                if (clearMouse.containsMouse)
                    return 0.8;
                return 1;
            }

            name: "close"
            color: root.config.cIcon
            pointSize: root.config.iconFontSize

            MouseArea {
                id: clearMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: search.text ? Qt.PointingHandCursor : undefined
                onClicked: search.text = ""
            }

            Behavior on width {
                NumberAnimation {
                    duration: root.config.anim("standardSmall").duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.config.anim("standardSmall").curve
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: root.config.anim("standardSmall").duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.config.anim("standardSmall").curve
                }
            }
        }
    }
}
