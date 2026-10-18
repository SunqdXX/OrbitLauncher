// Unit tests inside quickshell (plugin mode): qs -p tests/unit
import Quickshell
import "Orbit"

ShellRoot {
    UnitTests {
        backend: QuickshellBackend {}
        onDone: Quickshell.execDetached(["kill", "-TERM", String(Quickshell.processId)])
    }
}
