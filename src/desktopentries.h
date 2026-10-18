#pragma once

#include <QStringList>
#include <QVariantList>

// Freedesktop desktop entry scanning, without any toolkit beyond QtCore.
namespace DesktopEntries {

// Every application entry visible to this user, as maps with the keys the QML
// side expects: id name genericName comment icon execString command
// workingDirectory runInTerminal categories keywords startupClass noDisplay
QVariantList scan();

// The directories scanned, highest priority first
QStringList applicationDirs();

// Split an Exec value into argv, expanding field codes (exposed for tests)
QStringList parseExec(const QString &exec, const QString &name, const QString &icon, const QString &file);

} // namespace DesktopEntries
