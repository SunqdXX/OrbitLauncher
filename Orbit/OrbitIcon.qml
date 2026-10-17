import QtQuick

// A Material Symbols Rounded glyph. Uses the font when it is installed (the
// original look); otherwise draws the same outline from embedded SVG paths.
Item {
    id: root

    property string name: "search"
    property color color: "#a9abb5"
    property real pointSize: 16

    readonly property bool hasFont: _fontCache.has
    readonly property var _paths: ({
            search: "M380-320q-109 0-184.5-75.5T120-580q0-109 75.5-184.5T380-840q109 0 184.5 75.5T640-580q0 44-14 83t-38 69l224 224q11 11 11 28t-11 28q-11 11-28 11t-28-11L532-372q-30 24-69 38t-83 14Zm0-80q75 0 127.5-52.5T560-580q0-75-52.5-127.5T380-760q-75 0-127.5 52.5T200-580q0 75 52.5 127.5T380-400Z",
            close: "M480-424 284-228q-11 11-28 11t-28-11q-11-11-11-28t11-28l196-196-196-196q-11-11-11-28t11-28q11-11 28-11t28 11l196 196 196-196q11-11 28-11t28 11q11 11 11 28t-11 28L536-480l196 196q11 11 11 28t-11 28q-11 11-28 11t-28-11L480-424Z"
        })

    implicitWidth: hasFont ? glyph.implicitWidth : svgSize
    implicitHeight: hasFont ? glyph.implicitHeight : svgSize

    readonly property real svgSize: Math.round(pointSize * 4 / 3 * 1.5)

    QtObject {
        id: _fontCache

        readonly property bool has: Qt.fontFamilies().indexOf("Material Symbols Rounded") >= 0
    }

    Text {
        id: glyph

        anchors.centerIn: parent
        visible: root.hasFont
        text: root.name
        color: root.color
        renderType: Text.NativeRendering
        textFormat: Text.PlainText
        font.family: "Material Symbols Rounded"
        font.pointSize: root.pointSize
        font.variableAxes: ({
                "FILL": 0,
                "GRAD": -25,
                "opsz": root.pointSize,
                "wght": 400
            })
    }

    Image {
        anchors.centerIn: parent
        visible: !root.hasFont
        width: root.svgSize
        height: root.svgSize
        sourceSize: Qt.size(width, height)
        source: root.hasFont ? "" : "data:image/svg+xml;utf8," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 -960 960 960"><path fill="${root.color}" d="${root._paths[root.name] ?? ""}"/></svg>`)
    }
}
