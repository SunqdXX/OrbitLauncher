#include "commands.h"

#include "host.h"
#include "icons.h"

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QTextStream>
#include <QtGlobal>

#include <cstdio>
#include <cstring>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace Commands {

namespace {

void out(const QString &s)
{
    std::fputs(qPrintable(s + u'\n'), stdout);
}

QString expandHome(QString p)
{
    if (p == u"~")
        return QDir::homePath();
    if (p.startsWith(QStringLiteral("~/")))
        p.replace(0, 1, QDir::homePath());
    p.replace(QStringLiteral("$HOME"), QDir::homePath());
    return p;
}

} // namespace

QString configHome()
{
    const QString c = qEnvironmentVariable("XDG_CONFIG_HOME");
    return c.isEmpty() ? QDir::homePath() + QStringLiteral("/.config") : c;
}

QString defaultConfigPath()
{
    return configHome() + QStringLiteral("/orbit/orbit.conf");
}

QString confValue(const QString &configPath, const QString &key)
{
    QFile f(configPath);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    QString value;
    static const QRegularExpression trailing(QStringLiteral("\\s+#.*$"));
    QTextStream in(&f);
    while (!in.atEnd()) {
        const QString line = in.readLine().trimmed();
        const qsizetype eq = line.indexOf(u'=');
        if (eq <= 0 || line.startsWith(u'#'))
            continue;
        if (line.left(eq).trimmed().replace(u'-', u'_').toLower() != key)
            continue;
        QString v = line.mid(eq + 1).trimmed();
        v.remove(trailing);
        if (v.size() >= 2 && (v.front() == u'"' || v.front() == u'\'') && v.back() == v.front())
            v = v.mid(1, v.size() - 2);
        value = v;
    }
    return value;
}

QString stateDir(const QString &configPath)
{
    const QString s = expandHome(confValue(configPath, QStringLiteral("state_dir")));
    if (!s.isEmpty())
        return s;
    QString base = qEnvironmentVariable("XDG_STATE_HOME");
    if (base.isEmpty())
        base = QDir::homePath() + QStringLiteral("/.local/state");
    return base + QStringLiteral("/orbit");
}

bool sendCommand(const QString &command, QString *reply)
{
    const QByteArray path = QFile::encodeName(Host::socketPath());
    sockaddr_un addr{};
    if (size_t(path.size()) >= sizeof(addr.sun_path))
        return false;
    addr.sun_family = AF_UNIX;
    std::memcpy(addr.sun_path, path.constData(), path.size());
    const int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0)
        return false;
    if (::connect(fd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) != 0) {
        ::close(fd);
        return false;
    }
    const QByteArray msg = command.toUtf8() + '\n';
    if (::write(fd, msg.constData(), msg.size()) != msg.size()) {
        ::close(fd);
        return false;
    }
    QByteArray buf;
    char chunk[256];
    ssize_t n;
    timeval tv{2, 0};
    ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    while ((n = ::read(fd, chunk, sizeof(chunk))) > 0)
        buf.append(chunk, n);
    ::close(fd);
    if (reply)
        *reply = QString::fromUtf8(buf).trimmed();
    return true;
}

int init(const QString &configPath, bool force, bool quiet)
{
    const QString dir = QFileInfo(configPath).absolutePath();
    QDir().mkpath(dir);
    const QString planetsDir = dir + QStringLiteral("/planets");

    if (QFileInfo::exists(configPath) && !force) {
        if (!quiet)
            out(QStringLiteral("orbit: %1 already exists (use 'orbit init -f' to overwrite)").arg(configPath));
    } else {
        if (QFileInfo::exists(configPath)) {
            const QString backup = configPath + QStringLiteral(".bak-") + QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd-HHmmss"));
            QFile::copy(configPath, backup);
        }
        QFile tmpl(QStringLiteral(":/orbit/orbit.conf"));
        if (!tmpl.open(QIODevice::ReadOnly | QIODevice::Text))
            return 1;
        QString text = QString::fromUtf8(tmpl.readAll());
        static const QRegularExpression planetsLine(QStringLiteral("^planets_dir\\s*=.*$"), QRegularExpression::MultilineOption);
        text.replace(planetsLine, QStringLiteral("planets_dir = ") + planetsDir);
        QSaveFile f(configPath);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) {
            out(QStringLiteral("orbit: cannot write %1").arg(configPath));
            return 1;
        }
        f.write(text.toUtf8());
        f.commit();
        if (!quiet)
            out(QStringLiteral("orbit: wrote %1").arg(configPath));
    }

    QDir().mkpath(planetsDir);
    int copied = 0;
    QDirIterator it(QStringLiteral(":/orbit/Orbit/planets"), QDir::Files);
    while (it.hasNext()) {
        const QString src = it.next();
        const QString dst = planetsDir + u'/' + QFileInfo(src).fileName();
        if (QFileInfo::exists(dst))
            continue;
        if (QFile::copy(src, dst)) {
            QFile::setPermissions(dst, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ReadGroup | QFileDevice::ReadOther);
            ++copied;
        }
    }
    if (!quiet)
        out(QStringLiteral("orbit: copied %1 planet(s) to %2").arg(copied).arg(planetsDir));
    return 0;
}

int planets(const QString &configPath)
{
    QString dir = expandHome(confValue(configPath, QStringLiteral("planets_dir")));
    if (dir.isEmpty())
        dir = QStringLiteral(":/orbit/Orbit/planets");
    out(QStringLiteral("planets in %1:").arg(dir.startsWith(u':') ? QStringLiteral("(built in)") : dir));
    QStringList names;
    QDirIterator it(dir, {QStringLiteral("*.png"), QStringLiteral("*.jpg"), QStringLiteral("*.jpeg"), QStringLiteral("*.webp"), QStringLiteral("*.svg")}, QDir::Files);
    while (it.hasNext())
        names << QFileInfo(it.next()).completeBaseName();
    names.sort();
    names.removeDuplicates();
    for (const QString &n : std::as_const(names))
        out(QStringLiteral("  ") + n);
    out(QStringLiteral("  auto     (follows the theme's key colour)"));
    out(QStringLiteral("  random   (a new one each time it opens)"));
    return 0;
}

int importCaelestia(const QString &configPath)
{
    QString base = qEnvironmentVariable("XDG_STATE_HOME");
    if (base.isEmpty())
        base = QDir::homePath() + QStringLiteral("/.local/state");
    const QString dbPath = base + QStringLiteral("/caelestia/apps.sqlite");
    if (!QFileInfo::exists(dbPath)) {
        out(QStringLiteral("orbit: no caelestia history at %1").arg(dbPath));
        return 1;
    }
    QJsonObject history;
    {
        auto db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), QStringLiteral("caelestia"));
        db.setDatabaseName(dbPath);
        db.setConnectOptions(QStringLiteral("QSQLITE_OPEN_READONLY"));
        if (!db.open()) {
            out(QStringLiteral("orbit: cannot open %1 (is the Qt SQLite driver installed?)").arg(dbPath));
            return 1;
        }
        QSqlQuery tables(QStringLiteral("SELECT name FROM sqlite_master WHERE type='table' LIMIT 1"), db);
        if (!tables.next()) {
            out(QStringLiteral("orbit: %1 has no tables").arg(dbPath));
            return 1;
        }
        QSqlQuery q(QStringLiteral("SELECT id, frequency FROM \"%1\"").arg(tables.value(0).toString()), db);
        while (q.next())
            if (q.value(1).toInt() > 0)
                history.insert(q.value(0).toString(), q.value(1).toInt());
        db.close();
    }
    QSqlDatabase::removeDatabase(QStringLiteral("caelestia"));

    const QString dir = stateDir(configPath);
    QDir().mkpath(dir);
    QSaveFile f(dir + QStringLiteral("/history.json"));
    if (!f.open(QIODevice::WriteOnly)) {
        out(QStringLiteral("orbit: cannot write %1/history.json").arg(dir));
        return 1;
    }
    f.write(QJsonDocument(history).toJson(QJsonDocument::Compact));
    f.commit();
    out(QStringLiteral("orbit: imported %1 app(s) into %2/history.json").arg(history.size()).arg(dir));
    return 0;
}

int doctor(const QString &configPath)
{
    auto ok = [](const QString &s) { out(QStringLiteral("  ok  ") + s); };
    auto info = [](const QString &s) { out(QStringLiteral("  --  ") + s); };
    auto bad = [](const QString &s) { out(QStringLiteral("  !!  ") + s); };

    out(QStringLiteral("orbit %1 (Qt %2)").arg(QStringLiteral(ORBIT_VERSION), QString::fromLatin1(qVersion())));
    const QString session = qEnvironmentVariable("XDG_SESSION_TYPE");
    const bool wayland = qEnvironmentVariableIsSet("WAYLAND_DISPLAY");
    info(QStringLiteral("session: %1, desktop: %2").arg(session.isEmpty() ? QStringLiteral("?") : session, qEnvironmentVariable("XDG_CURRENT_DESKTOP", QStringLiteral("?"))));
#ifdef ORBIT_HAVE_LAYER_SHELL
    if (wayland)
        ok(QStringLiteral("layer-shell: built in, Wayland session"));
    else
        info(QStringLiteral("layer-shell: built in, but this is not a Wayland session (plain window is used)"));
#else
    info(QStringLiteral("layer-shell: not built in (plain window is used)"));
#endif
    if (wayland && !QFileInfo::exists(QStringLiteral(QT_PLUGINS_DIR "/platforms/libqwayland.so")) && !QFileInfo::exists(QStringLiteral(QT_PLUGINS_DIR "/platforms/libqwayland-generic.so")))
        bad(QStringLiteral("Qt Wayland plugin missing: install qt6-wayland, or orbit falls back to X11"));
    if (QFileInfo::exists(configPath))
        ok(QStringLiteral("config: ") + configPath);
    else
        info(QStringLiteral("config: %1 missing (created on first run, or 'orbit init')").arg(configPath));
    const auto theme = Icons::detectTheme(confValue(configPath, QStringLiteral("icon_theme")));
    ok(QStringLiteral("icon theme: %1 (%2)").arg(theme.first, theme.second));
    info(QStringLiteral("renderer: %1").arg(confValue(configPath, QStringLiteral("renderer")).isEmpty() ? QStringLiteral("gl") : confValue(configPath, QStringLiteral("renderer"))));
    QString reply;
    if (sendCommand(QStringLiteral("ping"), &reply))
        ok(QStringLiteral("running instance: %1 (socket %2)").arg(reply, Host::socketPath()));
    else
        info(QStringLiteral("running instance: none (socket %1)").arg(Host::socketPath()));
    return 0;
}

} // namespace Commands
