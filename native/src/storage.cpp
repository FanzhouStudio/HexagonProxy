#include "storage.h"
#include <QSaveFile>
#include <yaml-cpp/yaml.h>
namespace hexagon {
QString resourcePath(const QString &relative) {
    const auto configured = qEnvironmentVariable("HEXAGON_RESOURCE_DIR");
    return QDir(configured.isEmpty() ? QCoreApplication::applicationDirPath() + "/resources" : configured)
        .filePath(relative);
}
QByteArray readBytes(const QString &path) {
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
}
QJsonObject readObject(const QString &path, QString *error) {
    QJsonParseError parse;
    auto data = readBytes(path);
    if (data.startsWith("\xef\xbb\xbf"))
        data.remove(0, 3);
    auto doc = QJsonDocument::fromJson(data, &parse);
    if (!doc.isObject() && QFile::exists(path) && error)
        *error = QString("无法读取 %1：%2").arg(QFileInfo(path).fileName(), parse.errorString());
    return doc.object();
}
bool writeBytes(const QString &path, const QByteArray &bytes, QString *error) {
    if (!QDir().mkpath(QFileInfo(path).absolutePath())) {
        if (error)
            *error = "无法创建数据目录";
        return false;
    }
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly) || f.write(bytes) != bytes.size() || !f.commit()) {
        if (error)
            *error = f.errorString();
        return false;
    }
    return true;
}
bool writeObject(const QString &path, const QJsonObject &o, QString *e) {
    return writeBytes(path, QJsonDocument(o).toJson(QJsonDocument::Indented), e);
}
QString randomId() {
    return QUuid::createUuid().toString(QUuid::Id128);
}
QString legacyValue(const QString &file, const QString &key, const QString &fallback) {
    QSettings s(file, QSettings::IniFormat);
    return s.value(key, fallback).toString();
}
Storage::Storage(QString overrideRoot, QString overrideLegacy) {
    auto roaming = qEnvironmentVariable("APPDATA");
    if (roaming.isEmpty())
        roaming = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
    root = overrideRoot.isEmpty() ? QDir(roaming).filePath("FanzhouStudio/HexagonProxy") : overrideRoot;
    legacy =
        overrideLegacy.isEmpty() ? QDir(roaming).filePath("Godot/app_userdata/HexagonProxy") : overrideLegacy;
    QDir().mkpath(root);
    QString parseError;
    settings = readObject(file("settings.json"), &parseError);
    if (!parseError.isEmpty())
        throw std::runtime_error(parseError.toStdString());
}
QString Storage::linuxRoot() const {
    return settings.value("linux_path").toString(file("linux_workspace"));
}
void Storage::importLegacy() {
    if (settings.value("migration_version").toInt() >= 1) {
        migrateSubscriptions();
        return;
    }
    auto copyFile = [&](const QString &name) {
        const QString src = QDir(legacy).filePath(name), dest = file(name);
        if (QFile::exists(src) && !QFile::exists(dest)) {
            QDir().mkpath(QFileInfo(dest).absolutePath());
            if (!QFile::copy(src, dest))
                throw std::runtime_error("旧数据导入失败，原文件未修改");
        }
    };
    for (const auto &name : {"codex_profiles.json", "application_routing.json",
                             "terminal_command_presets.json", "node_failover.json"})
        copyFile(name);
    for (const auto &folder : {"profiles", "runtime/providers", "runtime/rules"}) {
        const QString source = QDir(legacy).filePath(folder);
        QDirIterator it(source, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            auto p = it.next();
            if (it.fileInfo().isSymLink())
                continue;
            auto relative = QDir(legacy).relativeFilePath(p);
            if (relative.endsWith(".json") || relative.endsWith(".yaml") || relative.endsWith(".yml") ||
                relative.endsWith(".mrs"))
                copyFile(relative);
        }
    }
    const auto oldAccounts = QDir(legacy).filePath("runtime/antigravity-proxy/accounts");
    if (QFile::exists(oldAccounts + "/index.json")) {
        QString parseError;
        auto index = readObject(oldAccounts + "/index.json", &parseError);
        if (!parseError.isEmpty())
            throw std::runtime_error(parseError.toStdString());
        auto entries = index.value("entries").toArray();
        for (qsizetype i = 0; i < entries.size(); ++i) {
            auto e = entries[i].toObject();
            e["helper_root"] = oldAccounts;
            entries[i] = e;
        }
        index["entries"] = entries;
        QString error;
        if (!writeObject(runtime("antigravity-proxy/accounts/index.json"), index, &error))
            throw std::runtime_error(error.toStdString());
        settings["antigravity_default_root"] = oldAccounts;
    }
    if (QDir(QDir(legacy).filePath("runtime/antigravity-proxy/installations")).exists())
        settings["antigravity_state_root"] = QDir(legacy).filePath("runtime/antigravity-proxy/installations");
    if (QFile::exists(QDir(legacy).filePath("runtime/mihomo.exe")))
        settings["core_source"] = QDir(legacy).filePath("runtime/mihomo.exe");
    if (QFile::exists(QDir(legacy).filePath("linux_workspace/linux.qcow2")))
        settings["linux_path"] = QDir(legacy).filePath("linux_workspace");
    settings["mixed_port"] =
        legacyValue(QDir(legacy).filePath("proxy_settings.cfg"), "network/mixed_port", "7890").toInt();
    settings["controller_port"] =
        legacyValue(QDir(legacy).filePath("proxy_settings.cfg"), "network/controller_port", "19090").toInt();
    settings["theme"] = legacyValue(QDir(legacy).filePath("ui_theme.cfg"), "ui/theme", "qq_warm");
    settings["font_percent"] = qBound(
        100, legacyValue(QDir(legacy).filePath("ui_theme.cfg"), "ui/font_size_percent", "150").toInt(), 200);
    settings["antigravity_exe"] =
        legacyValue(QDir(legacy).filePath("antigravity_proxy.cfg"), "antigravity/executable",
                    qEnvironmentVariable("LOCALAPPDATA") + "/Programs/antigravity/Antigravity.exe");
    settings["show_pet"] =
        legacyValue(QDir(legacy).filePath("settings.cfg"), "desktop_pet/visible", "true") == "true";
    settings["migration_version"] = 1;
    QString error;
    if (!saveSettings(&error))
        throw std::runtime_error(error.toStdString());
    migrateSubscriptions();
}
static bool hasProxyNodes(const QByteArray &bytes) {
    try {
        const auto profile = YAML::Load(bytes.toStdString());
        if (!profile.IsMap())
            return false;
        const auto nodes = profile["proxies"];
        const auto providers = profile["proxy-providers"];
        return (nodes && nodes.size() > 0) || (providers && providers.size() > 0);
    } catch (const YAML::Exception &) {
        // Preserve an existing profile if we cannot classify it.
        return !bytes.isEmpty();
    }
}
void Storage::migrateSubscriptions() {
    if (settings.value("migration_version").toInt() >= 2)
        return;

    const QString indexPath = "profiles/library/index.json";
    QString error;
    const auto oldIndex = readObject(QDir(legacy).filePath(indexPath), &error);
    auto index = readObject(file(indexPath), &error);
    if (!error.isEmpty())
        throw std::runtime_error(error.toStdString());

    const auto oldEntries = oldIndex.value("subscriptions").toArray();
    auto entries = index.value("subscriptions").toArray();
    QSet<QString> existingIds;
    for (const auto &entry : std::as_const(entries))
        existingIds.insert(entry.toObject().value("id").toString());

    auto copyIfMissing = [&](const QString &relative) {
        const auto source = QDir(legacy).filePath(relative);
        if (QFileInfo(source).isFile() && !QFileInfo(source).isSymLink() && !QFile::exists(file(relative))) {
            const auto data = readBytes(source);
            if (data.isEmpty() || !writeBytes(file(relative), data, &error))
                throw std::runtime_error("无法迁移旧版订阅文件：" + error.toStdString());
        }
    };
    // Older V2 subscriptions use .txt provider files in Mihomo's runtime directory.
    const QString providerDir = "runtime/providers";
    QDirIterator providers(QDir(legacy).filePath(providerDir), QDir::Files | QDir::NoSymLinks,
                           QDirIterator::Subdirectories);
    while (providers.hasNext()) {
        const auto path = providers.next();
        if (path.endsWith(".txt", Qt::CaseInsensitive) || path.endsWith(".yaml", Qt::CaseInsensitive) ||
            path.endsWith(".yml", Qt::CaseInsensitive))
            copyIfMissing(QDir(legacy).relativeFilePath(path));
    }

    QString recoveredActive;
    for (const auto &value : oldEntries) {
        const auto entry = value.toObject();
        const auto id = entry.value("id").toString();
        const auto config = entry.value("config_file").toString();
        if (id.isEmpty() || config.isEmpty() || QFileInfo(config).fileName() != config)
            continue;
        const QString relative = "profiles/library/" + config;
        copyIfMissing(relative);
        if (!QFile::exists(file(relative)))
            continue;
        if (!existingIds.contains(id)) {
            entries.append(entry);
            existingIds.insert(id);
        }
        if (oldIndex.value("active_id").toString() == id && hasProxyNodes(readBytes(file(relative))))
            recoveredActive = id;
    }

    const QString activePath = file("profiles/active.yaml");
    if (!recoveredActive.isEmpty() && !hasProxyNodes(readBytes(activePath))) {
        const auto oldActive = readBytes(QDir(legacy).filePath("profiles/active.yaml"));
        if (!oldActive.isEmpty() && hasProxyNodes(oldActive)) {
            const auto current = readBytes(activePath);
            if (!current.isEmpty() && !QFile::exists(activePath + ".before-migration") &&
                !writeBytes(activePath + ".before-migration", current, &error))
                throw std::runtime_error(error.toStdString());
            if (!writeBytes(activePath, oldActive, &error))
                throw std::runtime_error(error.toStdString());
            index["active_id"] = recoveredActive;
        }
    }
    if (!oldEntries.isEmpty()) {
        index["subscriptions"] = entries;
        if (!writeObject(file(indexPath), index, &error))
            throw std::runtime_error(error.toStdString());
    }
    settings["migration_version"] = 2;
    if (!saveSettings(&error))
        throw std::runtime_error(error.toStdString());
}
bool Storage::saveSettings(QString *error) {
    return writeObject(file("settings.json"), settings, error);
}
} // namespace hexagon
