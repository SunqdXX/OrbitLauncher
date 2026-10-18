#pragma once

#include <QFileSystemWatcher>
#include <QHash>
#include <QObject>
#include <QSet>
#include <QTimer>
#include <QVariantList>

// What the shared QML (Orbit/) needs from its host: desktop entries, icons,
// environment, launching and small file I/O. The quickshell plugin provides the
// same interface in Orbit/QuickshellBackend.qml.
class Backend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString kind READ kind CONSTANT)
    Q_PROPERTY(QVariantList apps READ apps NOTIFY appsChanged)

public:
    explicit Backend(QObject *parent = nullptr);

    QString kind() const { return QStringLiteral("native"); }
    QVariantList apps();

    Q_INVOKABLE void refreshApps();
    Q_INVOKABLE QString iconUrl(const QString &name) const;
    Q_INVOKABLE QString env(const QString &name) const;
    Q_INVOKABLE void exec(const QStringList &command, const QString &workingDirectory);
    Q_INVOKABLE void mkdirs(const QString &path);
    Q_INVOKABLE QString readFile(const QString &path) const;
    Q_INVOKABLE bool writeFile(const QString &path, const QString &text);
    Q_INVOKABLE void watch(const QString &path);
    Q_INVOKABLE int processId() const;

signals:
    void appsChanged();
    void fileChanged(const QString &path);

private:
    void checkWatched();

    QVariantList m_apps;
    bool m_loaded = false;

    // Editors save by replacing the file, which drops a plain file watch, so
    // the parent directories are watched and files compared by mtime/size
    QFileSystemWatcher m_watcher;
    QHash<QString, QPair<qint64, qint64>> m_stamps;
    QTimer m_debounce;
};
