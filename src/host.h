#pragma once

#include <QObject>
#include <QPointer>
#include <QString>

class QLocalServer;
class QQmlApplicationEngine;
class QQuickWindow;

// Owns the launcher window's placement (layer-shell or a plain window), the
// command socket and the process lifetime. Exposed to QML as `orbitHost`.
class Host : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString configPath READ configPath CONSTANT)
    Q_PROPERTY(bool layerShell READ layerShell CONSTANT)
    Q_PROPERTY(bool oneshot READ oneshot CONSTANT)
    Q_PROPERTY(bool onHyprland READ onHyprland CONSTANT)

public:
    Host(const QString &configPath, bool oneshot, QObject *parent = nullptr);

    QString configPath() const { return m_configPath; }
    bool layerShell() const { return m_layerShell; }
    bool oneshot() const { return m_oneshot; }
    bool onHyprland() const;

    // Start answering `orbit toggle` etc. on the socket
    bool listen(QString *error);
    void setEngine(QQmlApplicationEngine *engine) { m_engine = engine; }

    // Called from QML right before the window is shown
    Q_INVOKABLE void prepareWindow(QQuickWindow *window, const QString &layer, const QString &scope, bool fullscreen, const QString &monitor);
    // QML reports the open state so `isopen` can answer
    Q_INVOKABLE void setOpen(bool open) { m_open = open; }
    // The close animation finished
    Q_INVOKABLE void dismissed();

    static QString socketPath();

signals:
    void openRequested();
    void closeRequested();
    void toggleRequested();
    void reloadRequested();

private:
    QString handle(const QString &command);

    QString m_configPath;
    bool m_oneshot;
    bool m_layerShell;
    bool m_open = false;
    QLocalServer *m_server = nullptr;
    QQmlApplicationEngine *m_engine = nullptr;
};
