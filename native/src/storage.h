#pragma once
#include <QtCore>
#include <functional>

namespace hexagon {
QString resourcePath(const QString &relative);
QByteArray readBytes(const QString &path);
QJsonObject readObject(const QString &path, QString *error = nullptr);
bool writeBytes(const QString &path, const QByteArray &bytes, QString *error = nullptr);
bool writeObject(const QString &path, const QJsonObject &object, QString *error = nullptr);
QString randomId();
QString legacyValue(const QString &file, const QString &key, const QString &fallback = {});
class Storage {
  public:
    explicit Storage(QString overrideRoot = {}, QString overrideLegacy = {});
    QString root, legacy;
    QJsonObject settings;
    QString file(const QString &name) const {
        return QDir(root).filePath(name);
    }
    QString runtime(const QString &name = {}) const {
        return file("runtime/" + name);
    }
    QString linuxRoot() const;
    void importLegacy();

    bool saveSettings(QString *error = nullptr);
    int mixedPort() const {
        return settings.value("mixed_port").toInt(7890);
    }
    int controllerPort() const {
        return settings.value("controller_port").toInt(19090);
    }

  private:
    void migrateSubscriptions();
};
} // namespace hexagon
