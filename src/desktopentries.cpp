#include "desktopentries.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QLocale>
#include <QSet>
#include <QStandardPaths>
#include <QTextStream>

namespace DesktopEntries {

namespace {

// \s \n \t \r \\ escapes of desktop entry string values
QString unescapeValue(const QString &v)
{
    QString out;
    out.reserve(v.size());
    for (qsizetype i = 0; i < v.size(); ++i) {
        const QChar c = v[i];
        if (c == u'\\' && i + 1 < v.size()) {
            const QChar n = v[++i];
            switch (n.unicode()) {
            case 's': out += u' '; break;
            case 'n': out += u'\n'; break;
            case 't': out += u'\t'; break;
            case 'r': out += u'\r'; break;
            case '\\': out += u'\\'; break;
            default: out += u'\\'; out += n; break;
            }
        } else {
            out += c;
        }
    }
    return out;
}

// Lists are ';'-separated, with '\;' as a literal semicolon
QStringList splitList(const QString &v)
{
    QStringList out;
    QString cur;
    for (qsizetype i = 0; i < v.size(); ++i) {
        const QChar c = v[i];
        if (c == u'\\' && i + 1 < v.size() && v[i + 1] == u';') {
            cur += u';';
            ++i;
        } else if (c == u';') {
            if (!cur.isEmpty())
                out << unescapeValue(cur);
            cur.clear();
        } else {
            cur += c;
        }
    }
    if (!cur.isEmpty())
        out << unescapeValue(cur);
    return out;
}

bool toBool(const QString &v)
{
    return v.trimmed().compare(u"true", Qt::CaseInsensitive) == 0 || v.trimmed() == u"1";
}

// Locale suffixes to try for Key[...], most specific first
QStringList localeKeys()
{
    static const QStringList keys = [] {
        QString loc = qEnvironmentVariable("LC_ALL");
        if (loc.isEmpty())
            loc = qEnvironmentVariable("LC_MESSAGES");
        if (loc.isEmpty())
            loc = qEnvironmentVariable("LANG");
        if (loc.isEmpty())
            loc = QLocale::system().name();
        loc = loc.section(u'.', 0, 0); // drop .UTF-8
        QString modifier;
        if (loc.contains(u'@')) {
            modifier = loc.section(u'@', 1);
            loc = loc.section(u'@', 0, 0);
        }
        const QString lang = loc.section(u'_', 0, 0);
        const QString country = loc.contains(u'_') ? loc.section(u'_', 1) : QString();
        QStringList k;
        if (!country.isEmpty() && !modifier.isEmpty())
            k << lang + u'_' + country + u'@' + modifier;
        if (!country.isEmpty())
            k << lang + u'_' + country;
        if (!modifier.isEmpty())
            k << lang + u'@' + modifier;
        if (!lang.isEmpty() && lang != u"C" && lang != u"POSIX")
            k << lang;
        return k;
    }();
    return keys;
}

QString localized(const QHash<QString, QString> &g, const QString &key)
{
    for (const QString &l : localeKeys()) {
        const auto it = g.constFind(key + u'[' + l + u']');
        if (it != g.constEnd())
            return it.value();
    }
    return g.value(key);
}

bool inPath(const QString &program)
{
    if (program.contains(u'/'))
        return QFileInfo(program).isExecutable();
    return !QStandardPaths::findExecutable(program).isEmpty();
}

QStringList currentDesktops()
{
    static const QStringList d = qEnvironmentVariable("XDG_CURRENT_DESKTOP").split(u':', Qt::SkipEmptyParts);
    return d;
}

bool intersects(const QStringList &a, const QStringList &b)
{
    for (const QString &x : a)
        if (b.contains(x, Qt::CaseInsensitive))
            return true;
    return false;
}

// Reads only the [Desktop Entry] group
QHash<QString, QString> readMainGroup(const QString &path)
{
    QHash<QString, QString> g;
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return g;
    QTextStream in(&f);
    bool inMain = false;
    while (!in.atEnd()) {
        const QString line = in.readLine().trimmed();
        if (line.isEmpty() || line.startsWith(u'#'))
            continue;
        if (line.startsWith(u'[')) {
            if (inMain)
                break; // the main group is done
            inMain = line == u"[Desktop Entry]";
            continue;
        }
        if (!inMain)
            continue;
        const qsizetype eq = line.indexOf(u'=');
        if (eq <= 0)
            continue;
        const QString key = line.left(eq).trimmed();
        if (!g.contains(key)) // first occurrence wins
            g.insert(key, line.mid(eq + 1).trimmed());
    }
    return g;
}

} // namespace

QStringList parseExec(const QString &exec, const QString &name, const QString &icon, const QString &file)
{
    // 1. split into arguments, honouring "double quotes" with \" \` \$ \\ escapes
    QStringList raw;
    QString cur;
    bool quoted = false, any = false;
    for (qsizetype i = 0; i < exec.size(); ++i) {
        const QChar c = exec[i];
        if (quoted) {
            if (c == u'\\' && i + 1 < exec.size() && QStringLiteral("\"`$\\").contains(exec[i + 1])) {
                cur += exec[++i];
            } else if (c == u'"') {
                quoted = false;
            } else {
                cur += c;
            }
        } else if (c == u'"') {
            quoted = true;
            any = true;
        } else if (c == u' ' || c == u'\t') {
            if (any || !cur.isEmpty())
                raw << cur;
            cur.clear();
            any = false;
        } else {
            cur += c;
        }
    }
    if (any || !cur.isEmpty())
        raw << cur;

    // 2. field codes: file/url codes vanish (we never pass files), the rest expand
    QStringList out;
    for (const QString &arg : std::as_const(raw)) {
        if (arg == u"%i") {
            if (!icon.isEmpty())
                out << QStringLiteral("--icon") << icon;
            continue;
        }
        if (arg.size() == 2 && arg[0] == u'%' && QStringLiteral("fFuUdDnNvm").contains(arg[1]))
            continue;
        QString a;
        for (qsizetype i = 0; i < arg.size(); ++i) {
            if (arg[i] == u'%' && i + 1 < arg.size()) {
                const QChar code = arg[++i];
                switch (code.unicode()) {
                case '%': a += u'%'; break;
                case 'c': a += name; break;
                case 'k': a += file; break;
                case 'i': a += icon; break;
                default: break; // %f %u ... and unknown codes are dropped
                }
            } else {
                a += arg[i];
            }
        }
        out << a;
    }
    return out;
}

QStringList applicationDirs()
{
    QStringList dirs;
    QString dataHome = qEnvironmentVariable("XDG_DATA_HOME");
    if (dataHome.isEmpty())
        dataHome = QDir::homePath() + QStringLiteral("/.local/share");
    dirs << dataHome + QStringLiteral("/applications");
    QString dataDirs = qEnvironmentVariable("XDG_DATA_DIRS");
    if (dataDirs.isEmpty())
        dataDirs = QStringLiteral("/usr/local/share:/usr/share");
    for (const QString &d : dataDirs.split(u':', Qt::SkipEmptyParts))
        dirs << QDir::cleanPath(d) + QStringLiteral("/applications");
    dirs.removeDuplicates();
    return dirs;
}

QVariantList scan()
{
    QVariantList out;
    QSet<QString> seen; // ids already decided by a higher priority dir (shown or hidden)

    for (const QString &dir : applicationDirs()) {
        if (!QFileInfo(dir).isDir())
            continue;
        QDirIterator it(dir, {QStringLiteral("*.desktop")}, QDir::Files | QDir::Readable, QDirIterator::Subdirectories | QDirIterator::FollowSymlinks);
        QStringList files;
        while (it.hasNext())
            files << it.next();
        files.sort();

        for (const QString &path : std::as_const(files)) {
            // Desktop file id: path relative to the applications dir, '/' -> '-'
            QString id = QDir(dir).relativeFilePath(path);
            id.chop(8); // ".desktop"
            id.replace(u'/', u'-');
            if (seen.contains(id))
                continue;
            seen.insert(id);

            const auto g = readMainGroup(path);
            if (g.value(QStringLiteral("Type")) != u"Application" || toBool(g.value(QStringLiteral("Hidden"))))
                continue;
            const QString exec = unescapeValue(g.value(QStringLiteral("Exec")));
            if (exec.isEmpty() && !toBool(g.value(QStringLiteral("DBusActivatable"))))
                continue;
            const QString tryExec = unescapeValue(g.value(QStringLiteral("TryExec")));
            if (!tryExec.isEmpty() && !inPath(tryExec))
                continue;

            bool noDisplay = toBool(g.value(QStringLiteral("NoDisplay")));
            const QStringList onlyShowIn = splitList(g.value(QStringLiteral("OnlyShowIn")));
            const QStringList notShowIn = splitList(g.value(QStringLiteral("NotShowIn")));
            if (!onlyShowIn.isEmpty() && !intersects(onlyShowIn, currentDesktops()))
                noDisplay = true;
            if (intersects(notShowIn, currentDesktops()))
                noDisplay = true;

            const QString name = unescapeValue(localized(g, QStringLiteral("Name")));
            if (name.isEmpty())
                continue;
            const QString icon = unescapeValue(localized(g, QStringLiteral("Icon")));

            QStringList command = parseExec(exec, name, icon, path);
            if (command.isEmpty())
                command = {QStringLiteral("gtk-launch"), id}; // DBusActivatable without Exec

            QVariantMap e;
            e.insert(QStringLiteral("id"), id);
            e.insert(QStringLiteral("name"), name);
            e.insert(QStringLiteral("genericName"), unescapeValue(localized(g, QStringLiteral("GenericName"))));
            e.insert(QStringLiteral("comment"), unescapeValue(localized(g, QStringLiteral("Comment"))));
            e.insert(QStringLiteral("icon"), icon);
            e.insert(QStringLiteral("execString"), exec);
            e.insert(QStringLiteral("command"), command);
            e.insert(QStringLiteral("workingDirectory"), unescapeValue(g.value(QStringLiteral("Path"))));
            e.insert(QStringLiteral("runInTerminal"), toBool(g.value(QStringLiteral("Terminal"))));
            e.insert(QStringLiteral("categories"), splitList(g.value(QStringLiteral("Categories"))));
            e.insert(QStringLiteral("keywords"), splitList(localized(g, QStringLiteral("Keywords"))));
            e.insert(QStringLiteral("startupClass"), unescapeValue(g.value(QStringLiteral("StartupWMClass"))));
            e.insert(QStringLiteral("noDisplay"), noDisplay);
            out << e;
        }
    }
    return out;
}

} // namespace DesktopEntries
