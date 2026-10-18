#pragma once

#include <QString>

namespace Commands {

QString configHome();
QString defaultConfigPath();
QString stateDir(const QString &configPath);

// Last `key = value` in an orbit.conf, comments and quotes stripped
QString confValue(const QString &configPath, const QString &key);

// Send one command to a running orbit. Returns false if none is listening.
bool sendCommand(const QString &command, QString *reply);

int init(const QString &configPath, bool force, bool quiet);
int planets(const QString &configPath);
int importCaelestia(const QString &configPath);
int doctor(const QString &configPath);

} // namespace Commands
