#pragma once

#include <QQuickImageProvider>
#include <QString>

namespace Icons {

// Decide the icon theme: orbit.conf, $ORBIT_ICON_THEME, the platform theme,
// then the desktop's own settings (qt6ct, kdeglobals, GTK), then whatever
// common theme is installed. Returns the chosen name and where it came from.
QPair<QString, QString> detectTheme(const QString &configured);

// Apply the theme and the search paths (incl. /usr/share/pixmaps)
void setup(const QString &configured);

} // namespace Icons

// image://orbiticon/<name or absolute path>
class IconProvider : public QQuickImageProvider
{
public:
    IconProvider();
    QPixmap requestPixmap(const QString &id, QSize *size, const QSize &requestedSize) override;
};
