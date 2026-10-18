// orbit - a planet app launcher for Wayland (and X11)

#include "backend.h"
#include "commands.h"
#include "host.h"
#include "icons.h"

#include <QFileInfo>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QSurfaceFormat>

#include <cstdio>
#include <cstring>
#include <unistd.h>

static const char *usage = R"(orbit - a planet app launcher

usage: orbit [-c FILE] [command]

  toggle            open or close (default). Talks to a running orbit, or
                    starts one that exits again when closed
  open | close      explicit open / close
  daemon [-F]       stay in memory for instant opening (-F: don't detach)
  reload            re-read orbit.conf and the theme file
  kill              stop a running orbit
  init [-f]         write ~/.config/orbit/orbit.conf and copy the planets
  planets           list the planets orbit can find
  import-caelestia  seed launch history from caelestia's apps.sqlite
  doctor            check the setup

options:
  -c, --config FILE   use another orbit.conf
  -v, --version       print the version
  -h, --help          this text
)";

static void err(const char *msg)
{
    std::fprintf(stderr, "orbit: %s\n", msg);
}

int main(int argc, char **argv)
{
    QString configPath = qEnvironmentVariable("ORBIT_CONFIG");
    QString command = QStringLiteral("toggle");
    QStringList rest;
    for (int i = 1; i < argc; ++i) {
        const QString a = QString::fromLocal8Bit(argv[i]);
        if (a == u"-h" || a == u"--help") {
            std::fputs(usage, stdout);
            return 0;
        } else if (a == u"-v" || a == u"--version") {
            std::printf("orbit %s\n", ORBIT_VERSION);
            return 0;
        } else if (a == u"-c" || a == u"--config") {
            if (++i >= argc) {
                err("-c needs a file");
                return 2;
            }
            configPath = QFileInfo(QString::fromLocal8Bit(argv[i])).absoluteFilePath();
        } else if (command == u"toggle" && rest.isEmpty() && !a.startsWith(u'-')) {
            command = a;
            rest << QString(); // marks that a command was given
        } else {
            rest << a;
        }
    }
    rest.removeAll(QString());
    const bool customConfig = !configPath.isEmpty();
    if (configPath.isEmpty())
        configPath = Commands::defaultConfigPath();

    // Commands that only talk to a running instance or touch files
    if (command == u"init")
        return Commands::init(configPath, rest.contains(QStringLiteral("-f")), false);
    if (command == u"planets")
        return Commands::planets(configPath);
    if (command == u"import-caelestia") {
        QCoreApplication core(argc, argv); // Qt Sql needs an application object
        return Commands::importCaelestia(configPath);
    }
    if (command == u"doctor") {
        QGuiApplication probe(argc, argv); // so the icon theme detection sees the platform theme
        return Commands::doctor(configPath);
    }
    if (command == u"reload" || command == u"close" || command == u"kill" || command == u"quit") {
        QString reply;
        const bool running = Commands::sendCommand(command == u"kill" ? QStringLiteral("quit") : command, &reply);
        if (command == u"kill") {
            std::puts(running ? "orbit: stopped" : "orbit: not running");
            return 0;
        }
        if (!running) {
            if (command == u"close")
                return 0; // nothing open, nothing to close
            err("no orbit running");
            return 1;
        }
        return 0;
    }
    if (command == u"isopen") {
        QString reply;
        if (!Commands::sendCommand(QStringLiteral("isopen"), &reply)) {
            std::puts("false");
            return 1;
        }
        std::puts(qPrintable(reply));
        return reply == u"true" ? 0 : 1;
    }
    if (command != u"toggle" && command != u"open" && command != u"daemon") {
        std::fprintf(stderr, "orbit: unknown command '%s' (see orbit --help)\n", qPrintable(command));
        return 2;
    }

    // toggle/open: hand over to a running instance if there is one
    const bool daemon = command == u"daemon";
    if (!daemon) {
        QString reply;
        if (Commands::sendCommand(command, &reply))
            return 0;
    } else {
        QString reply;
        if (Commands::sendCommand(QStringLiteral("ping"), &reply)) {
            err("a daemon is already running");
            return 1;
        }
        if (!rest.contains(QStringLiteral("-F")) && !rest.contains(QStringLiteral("--foreground"))) {
            // Detach like a classic daemon: the parent returns at once
            const pid_t pid = fork();
            if (pid < 0) {
                err("fork failed");
                return 1;
            }
            if (pid > 0)
                return 0;
            setsid();
            if (FILE *n = std::freopen("/dev/null", "r", stdin))
                (void)n;
        }
    }

    // First run of the standalone launcher: give the user their own config + planets
    if (!customConfig && !QFileInfo::exists(configPath))
        Commands::init(configPath, false, true);

    if (Commands::confValue(configPath, QStringLiteral("renderer")) == u"software")
        QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);

    // Per-pixel transparency for the window (needed on X11 too)
    QSurfaceFormat fmt = QSurfaceFormat::defaultFormat();
    fmt.setAlphaBufferSize(8);
    QSurfaceFormat::setDefaultFormat(fmt);

    QGuiApplication::setDesktopFileName(QStringLiteral("orbit"));
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("orbit"));
    QGuiApplication::setApplicationVersion(QStringLiteral(ORBIT_VERSION));
    QGuiApplication::setQuitOnLastWindowClosed(false);

    Icons::setup(Commands::confValue(configPath, QStringLiteral("icon_theme")));

    Host host(configPath, !daemon);
    QString error;
    if (!host.listen(&error)) {
        // Lost a race with another instance starting: just pass the command on
        QString reply;
        if (!daemon && Commands::sendCommand(command, &reply))
            return 0;
        err(qPrintable(error));
        return 1;
    }

    Backend backend;
    QQmlApplicationEngine engine;
    host.setEngine(&engine);
    engine.addImageProvider(QStringLiteral("orbiticon"), new IconProvider);
    engine.rootContext()->setContextProperty(QStringLiteral("orbitBackend"), &backend);
    engine.rootContext()->setContextProperty(QStringLiteral("orbitHost"), &host);

    // ORBIT_QML_DIR runs the QML from a checkout instead of the copy built in;
    // ORBIT_MAIN_QML swaps the window for another file (used by the tests)
    const QString qmlDir = qEnvironmentVariable("ORBIT_QML_DIR");
    QUrl main = qmlDir.isEmpty() ? QUrl(QStringLiteral("qrc:/orbit/Main.qml")) : QUrl::fromLocalFile(qmlDir + QStringLiteral("/Main.qml"));
    if (qEnvironmentVariableIsSet("ORBIT_MAIN_QML"))
        main = QUrl::fromLocalFile(QFileInfo(qEnvironmentVariable("ORBIT_MAIN_QML")).absoluteFilePath());
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.load(main);
    if (engine.rootObjects().isEmpty())
        return 1;
    return app.exec();
}
