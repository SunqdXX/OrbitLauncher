// Unit tests inside the orbit binary: ORBIT_MAIN_QML=tests/unit/native.qml orbit daemon -F
import QtQuick

UnitTests {
    backend: orbitBackend
    onDone: Qt.quit()
}
