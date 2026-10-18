#include "icons.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QIcon>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>

namespace Icons {

namespace {

QString configHome()
{
    const QString c = qEnvironmentVariable("XDG_CONFIG_HOME");
    return c.isEmpty() ? QDir::homePath() + QStringLiteral("/.config") : c;
}

// Not every platform plugin fills QIcon::themeSearchPaths() (offscreen, some
// X11 setups), so the XDG locations are always added by hand
QStringList searchPaths()
{
    QStringList paths;
    const QString dataHome = qEnvironmentVariable("XDG_DATA_HOME", QDir::homePath() + QStringLiteral("/.local/share"));
    paths << QDir::homePath() + QStringLiteral("/.icons") << dataHome + QStringLiteral("/icons");
    QString dataDirs = qEnvironmentVariable("XDG_DATA_DIRS");
    if (dataDirs.isEmpty())
        dataDirs = QStringLiteral("/usr/local/share:/usr/share");
    for (const QString &d : dataDirs.split(u':', Qt::SkipEmptyParts))
        paths << d + QStringLiteral("/icons");
    for (const QString &p : QIcon::themeSearchPaths())
        paths << p;
    paths.removeDuplicates();
    return paths;
}

bool themeInstalled(const QString &name)
{
    if (name.isEmpty())
        return false;
    for (const QString &base : searchPaths())
        if (QFileInfo(base + u'/' + name + QStringLiteral("/index.theme")).exists())
            return true;
    return false;
}

QString iniValue(const QString &file, const QString &key)
{
    if (!QFileInfo::exists(file))
        return {};
    QSettings s(file, QSettings::IniFormat);
    return s.value(key).toString().trimmed();
}

} // namespace

QPair<QString, QString> detectTheme(const QString &configured)
{
    if (!configured.isEmpty())
        return {configured, QStringLiteral("orbit.conf")};
    const QString envTheme = qEnvironmentVariable("ORBIT_ICON_THEME");
    if (!envTheme.isEmpty())
        return {envTheme, QStringLiteral("$ORBIT_ICON_THEME")};

    // KDE and qt6ct sessions hand Qt the right theme through the platform plugin
    const QString platform = QIcon::themeName();
    if (!platform.isEmpty() && platform != u"hicolor" && themeInstalled(platform))
        return {platform, QStringLiteral("Qt platform theme")};

    for (const char *f : {"/qt6ct/qt6ct.conf", "/qt5ct/qt5ct.conf"}) {
        const QString t = iniValue(configHome() + QLatin1String(f), QStringLiteral("Appearance/icon_theme"));
        if (themeInstalled(t))
            return {t, QLatin1String(f).mid(1)};
    }
    const QString kde = iniValue(configHome() + QStringLiteral("/kdeglobals"), QStringLiteral("Icons/Theme"));
    if (themeInstalled(kde))
        return {kde, QStringLiteral("kdeglobals")};
    // Plasma's default when kdeglobals has no [Icons] entry
    if (qEnvironmentVariable("XDG_CURRENT_DESKTOP").contains(u"KDE", Qt::CaseInsensitive) && themeInstalled(QStringLiteral("breeze")))
        return {QStringLiteral("breeze"), QStringLiteral("KDE default")};

    if (!QStandardPaths::findExecutable(QStringLiteral("gsettings")).isEmpty()) {
        QProcess p;
        p.start(QStringLiteral("gsettings"), {QStringLiteral("get"), QStringLiteral("org.gnome.desktop.interface"), QStringLiteral("icon-theme")});
        if (p.waitForFinished(800)) {
            QString t = QString::fromUtf8(p.readAllStandardOutput()).trimmed();
            t.remove(u'\'');
            if (t != u"hicolor" && t != u"Adwaita" && themeInstalled(t))
                return {t, QStringLiteral("gsettings")};
        }
    }
    const QString gtk = iniValue(configHome() + QStringLiteral("/gtk-3.0/settings.ini"), QStringLiteral("Settings/gtk-icon-theme-name"));
    if (themeInstalled(gtk))
        return {gtk, QStringLiteral("gtk-3.0/settings.ini")};

    for (const char *t : {"Papirus-Dark", "Papirus", "breeze-dark", "breeze", "Adwaita"})
        if (themeInstalled(QLatin1String(t)))
            return {QLatin1String(t), QStringLiteral("installed fallback")};
    return {QStringLiteral("hicolor"), QStringLiteral("fallback")};
}

void setup(const QString &configured)
{
    QIcon::setThemeSearchPaths(searchPaths());
    const QString dataHome = qEnvironmentVariable("XDG_DATA_HOME", QDir::homePath() + QStringLiteral("/.local/share"));
    // Icon=foo may also live loose in pixmaps
    QIcon::setFallbackSearchPaths({QStringLiteral("/usr/share/pixmaps"), dataHome + QStringLiteral("/pixmaps")});
    QIcon::setThemeName(detectTheme(configured).first);
    QIcon::setFallbackThemeName(QStringLiteral("hicolor"));
}

} // namespace Icons

IconProvider::IconProvider()
    : QQuickImageProvider(QQuickImageProvider::Pixmap)
{
}

QPixmap IconProvider::requestPixmap(const QString &id, QSize *size, const QSize &requestedSize)
{
    const QSize want = requestedSize.isValid() && !requestedSize.isEmpty() ? requestedSize : QSize(64, 64);
    QString name = QUrl::fromPercentEncoding(id.toUtf8());

    QIcon icon;
    if (name.startsWith(u'/')) {
        if (QFileInfo::exists(name))
            icon = QIcon(name);
    } else if (!name.isEmpty()) {
        icon = QIcon::fromTheme(name);
        // Some entries say Icon=foo.png although the spec wants a bare name
        if (icon.isNull() && name.contains(u'.')) {
            const QString bare = name.section(u'.', 0, -2);
            icon = QIcon::fromTheme(bare);
            if (icon.isNull())
                for (const QString &dir : QIcon::fallbackSearchPaths())
                    if (QFileInfo::exists(dir + u'/' + name)) {
                        icon = QIcon(dir + u'/' + name);
                        break;
                    }
        }
    }
    if (icon.isNull())
        icon = QIcon::fromTheme(QStringLiteral("application-x-executable"));

    QPixmap pm = icon.isNull() ? QPixmap() : icon.pixmap(want);
    if (pm.isNull()) {
        pm = QPixmap(want);
        pm.fill(Qt::transparent);
    }
    if (size)
        *size = pm.size();
    return pm;
}
