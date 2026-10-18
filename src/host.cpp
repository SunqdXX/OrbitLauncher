#include "host.h"

#include <QCursor>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QLocalServer>
#include <QLocalSocket>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QScreen>
#include <QTimer>

#ifdef ORBIT_HAVE_LAYER_SHELL
#include <LayerShellQt/Window>
#endif

#ifdef __GLIBC__
#include <malloc.h>
#endif

Host::Host(const QString &configPath, bool oneshot, QObject *parent)
    : QObject(parent)
    , m_configPath(configPath)
    , m_oneshot(oneshot)
{
#ifdef ORBIT_HAVE_LAYER_SHELL
    m_layerShell = QGuiApplication::platformName() == u"wayland" && qEnvironmentVariable("ORBIT_NO_LAYER_SHELL") != u"1";
#else
    m_layerShell = false;
#endif
}

bool Host::onHyprland() const
{
    return qEnvironmentVariableIsSet("HYPRLAND_INSTANCE_SIGNATURE");
}

QString Host::socketPath()
{
    const QString override = qEnvironmentVariable("ORBIT_SOCKET");
    if (!override.isEmpty())
        return override;
    QString dir = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (dir.isEmpty())
        dir = QDir::tempPath();
    QString display = qEnvironmentVariable("WAYLAND_DISPLAY");
    if (display.isEmpty())
        display = qEnvironmentVariable("DISPLAY").remove(u':');
    return dir + QStringLiteral("/orbit-") + (display.isEmpty() ? QStringLiteral("0") : display) + QStringLiteral(".sock");
}

bool Host::listen(QString *error)
{
    const QString path = socketPath();
    m_server = new QLocalServer(this);
    m_server->setSocketOptions(QLocalServer::UserAccessOption);
    if (!m_server->listen(path)) {
        // A dead instance can leave the socket file behind: only then take it over
        QLocalSocket probe;
        probe.connectToServer(path);
        if (probe.waitForConnected(200)) {
            if (error)
                *error = QStringLiteral("another orbit is already running");
            return false;
        }
        QLocalServer::removeServer(path);
        if (!m_server->listen(path)) {
            if (error)
                *error = m_server->errorString();
            return false;
        }
    }
    connect(m_server, &QLocalServer::newConnection, this, [this] {
        while (QLocalSocket *s = m_server->nextPendingConnection()) {
            connect(s, &QLocalSocket::disconnected, s, &QObject::deleteLater);
            connect(s, &QLocalSocket::readyRead, s, [this, s] {
                if (!s->canReadLine())
                    return;
                const QString reply = handle(QString::fromUtf8(s->readLine()).trimmed());
                s->write(reply.toUtf8() + '\n');
                s->flush();
                s->disconnectFromServer();
            });
        }
    });
    return true;
}

QString Host::handle(const QString &command)
{
    if (command == u"toggle")
        emit toggleRequested();
    else if (command == u"open")
        emit openRequested();
    else if (command == u"close")
        emit closeRequested();
    else if (command == u"reload")
        emit reloadRequested();
    else if (command == u"isopen")
        return m_open ? QStringLiteral("true") : QStringLiteral("false");
    else if (command == u"ping")
        return m_oneshot ? QStringLiteral("oneshot") : QStringLiteral("daemon");
    else if (command == u"quit")
        QTimer::singleShot(0, qApp, &QCoreApplication::quit);
    else
        return QStringLiteral("error: unknown command");
    return QStringLiteral("ok");
}

static QScreen *findScreen(const QString &want)
{
    const QString w = want.trimmed().toLower();
    if (w.isEmpty())
        return nullptr;
    for (QScreen *s : QGuiApplication::screens()) {
        const QString desc = (s->manufacturer() + u' ' + s->model() + u' ' + s->serialNumber()).toLower();
        if (s->name().toLower() == w || desc.contains(w))
            return s;
    }
    return nullptr;
}

void Host::prepareWindow(QQuickWindow *window, const QString &layer, const QString &scope, bool fullscreen, const QString &monitor)
{
    if (!window)
        return;
    QScreen *wanted = findScreen(monitor);

#ifdef ORBIT_HAVE_LAYER_SHELL
    if (m_layerShell) {
        auto *ls = LayerShellQt::Window::get(window);
        ls->setScope(scope.isEmpty() ? QStringLiteral("orbit") : scope);
        ls->setLayer(layer == u"top" ? LayerShellQt::Window::LayerTop : LayerShellQt::Window::LayerOverlay);
        ls->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
        ls->setExclusiveZone(-1); // centre on the whole output, ignoring panels
        using A = LayerShellQt::Window;
        ls->setAnchors(fullscreen ? A::Anchors(A::AnchorTop | A::AnchorBottom | A::AnchorLeft | A::AnchorRight) : A::Anchors(A::AnchorNone));
        ls->setCloseOnDismissed(false);
#if ORBIT_LAYER_SHELL_ACTIVE_SCREEN
        if (wanted)
            ls->setScreen(wanted);
        else
            ls->setWantsToBeOnActiveScreen(true); // the compositor's focused output
#else
        if (wanted)
            window->setScreen(wanted);
        else
            ls->setScreenConfiguration(LayerShellQt::Window::ScreenFromCompositor);
#endif
        return;
    }
#endif

    // No layer-shell (X11, or a compositor without it): a borderless window on
    // the screen under the pointer, centred, kept above everything else
    QScreen *screen = wanted ? wanted : QGuiApplication::screenAt(QCursor::pos());
    if (!screen)
        screen = QGuiApplication::primaryScreen();
    window->setScreen(screen);
    window->setFlags(Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint | Qt::Dialog);
    const QRect g = screen->geometry();
    if (fullscreen) {
        window->setGeometry(g);
    } else {
        window->setPosition(g.x() + (g.width() - window->width()) / 2, g.y() + (g.height() - window->height()) / 2);
    }
}

void Host::dismissed()
{
    if (m_oneshot) {
        QTimer::singleShot(0, qApp, &QCoreApplication::quit);
        return;
    }
    // Daemon: the launcher is unloaded; give the memory back to the system
    QTimer::singleShot(200, this, [this] {
        if (m_engine)
            m_engine->collectGarbage();
        for (QWindow *w : QGuiApplication::topLevelWindows())
            if (auto *qw = qobject_cast<QQuickWindow *>(w))
                qw->releaseResources();
#ifdef __GLIBC__
        malloc_trim(0);
#endif
    });
}
