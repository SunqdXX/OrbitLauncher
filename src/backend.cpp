#include "backend.h"

#include "desktopentries.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QSaveFile>
#include <QUrl>

#include <unistd.h>

namespace {

QPair<qint64, qint64> stamp(const QString &path)
{
    const QFileInfo fi(path);
    if (!fi.exists())
        return {-1, -1};
    return {fi.lastModified().toMSecsSinceEpoch(), fi.size()};
}

} // namespace

Backend::Backend(QObject *parent)
    : QObject(parent)
{
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(60);
    connect(&m_debounce, &QTimer::timeout, this, &Backend::checkWatched);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_debounce, qOverload<>(&QTimer::start));
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, &m_debounce, qOverload<>(&QTimer::start));
}

QVariantList Backend::apps()
{
    // First read scans quietly: emitting from inside a getter is a binding loop
    if (!m_loaded) {
        m_apps = DesktopEntries::scan();
        m_loaded = true;
    }
    return m_apps;
}

void Backend::refreshApps()
{
    QVariantList fresh = DesktopEntries::scan();
    const bool changed = !m_loaded || fresh != m_apps;
    m_apps = std::move(fresh);
    m_loaded = true;
    if (changed)
        emit appsChanged();
}

QString Backend::iconUrl(const QString &name) const
{
    return QStringLiteral("image://orbiticon/") + QString::fromUtf8(QUrl::toPercentEncoding(name.isEmpty() ? QStringLiteral("application-x-executable") : name));
}

QString Backend::env(const QString &name) const
{
    return qEnvironmentVariable(name.toUtf8().constData());
}

void Backend::exec(const QStringList &command, const QString &workingDirectory)
{
    if (command.isEmpty())
        return;
    QString wd = workingDirectory;
    if (wd.isEmpty() || !QFileInfo(wd).isDir())
        wd = QDir::homePath();
    // startDetached double-forks: the app outlives us and is never our zombie
    if (!QProcess::startDetached(command.first(), command.mid(1), wd))
        qWarning("orbit: failed to start %s", qPrintable(command.join(u' ')));
}

void Backend::mkdirs(const QString &path)
{
    if (!path.isEmpty())
        QDir().mkpath(path);
}

QString Backend::readFile(const QString &path) const
{
    if (path.isEmpty())
        return {};
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    return QString::fromUtf8(f.readAll());
}

bool Backend::writeFile(const QString &path, const QString &text)
{
    if (path.isEmpty())
        return false;
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile f(path); // write to a temp file, then rename over: never a half-written file
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;
    f.write(text.toUtf8());
    const bool ok = f.commit();
    if (ok && m_stamps.contains(path))
        m_stamps[path] = stamp(path); // our own write is not an external change
    return ok;
}

void Backend::watch(const QString &path)
{
    if (path.isEmpty() || m_stamps.contains(path))
        return;
    m_stamps.insert(path, stamp(path));
    const QString dir = QFileInfo(path).absolutePath();
    if (QFileInfo(dir).isDir() && !m_watcher.directories().contains(dir))
        m_watcher.addPath(dir);
    if (QFileInfo::exists(path))
        m_watcher.addPath(path);
}

void Backend::checkWatched()
{
    for (auto it = m_stamps.begin(); it != m_stamps.end(); ++it) {
        const auto now = stamp(it.key());
        if (now == it.value())
            continue;
        it.value() = now;
        // Re-arm the file watch: a rename-over replaced the inode we watched
        if (now.first >= 0 && !m_watcher.files().contains(it.key()))
            m_watcher.addPath(it.key());
        emit fileChanged(it.key());
    }
}

int Backend::processId() const
{
    return int(QCoreApplication::applicationPid());
}
