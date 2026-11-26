#include "accounts.h"
namespace hexagon {
AccountsService::AccountsService(Storage &s, QObject *p) : QObject(p), store(s), helper(s, this) {
    codexIndex = readObject(store.file("codex_profiles.json"), &error);
    if (codexIndex.isEmpty() && error.isEmpty())
        codexIndex = {
            {"version", 4},
            {"selected_id", "default"},
            {"accounts", QJsonArray{QJsonObject{{"id", "default"},
                                                {"name", "默认账号"},
                                                {"snapshot_path", managedRoot() + "/accounts/default"}}}}};
    antigravityIndex = readObject(antigravityRoot() + "/index.json", &error);
    if (antigravityIndex.isEmpty())
        antigravityIndex = {{"original_visible", true},
                            {"default_account", "default"},
                            {"selected", "default"},
                            {"entries", QJsonArray{}},
                            {"quotas", QJsonObject{}}};
}
QString AccountsService::managedRoot() const {
    return qEnvironmentVariable("USERPROFILE") + "/.codex-profiles/HexagonProxy";
}
QString AccountsService::activeCodexHome() const {
    auto active = codexIndex.value("active_home").toString();
    if (active.isEmpty())
        active = qEnvironmentVariable("CODEX_HOME");
    return active.isEmpty() ? qEnvironmentVariable("USERPROFILE") + "/.codex" : active;
}
QString AccountsService::antigravityRoot() const {
    return store.runtime("antigravity-proxy/accounts");
}
QJsonObject AccountsService::codexEntry(const QString &id) const {
    for (const auto &a : codexAccounts())
        if (a.toObject().value("id") == id)
            return a.toObject();
    return {};
}
QJsonObject AccountsService::antigravityEntry(const QString &id) const {
    for (const auto &a : antigravityAccounts())
        if (a.toObject().value("id") == id)
            return a.toObject();
    return {};
}
QJsonArray AccountsService::antigravityAccounts() const {
    auto entries = antigravityIndex.value("entries").toArray();
    if (antigravityIndex.value("original_visible").toBool(true))
        entries.prepend(QJsonObject{
            {"id", "default"},
            {"name", "原有账号"},
            {"helper_root", store.settings.value("antigravity_default_root").toString(antigravityRoot())}});
    return entries;
}
QString AccountsService::relatedHomes(const QString &exclude) const {
    QStringList homes;
    for (const auto &a : codexAccounts()) {
        auto p = a.toObject();
        if (p.value("id") != exclude && !p.value("snapshot_path").toString().isEmpty())
            homes << p.value("snapshot_path").toString();
    }
    return homes.join('|');
}
QJsonObject AccountsService::newCodex(const QString &name) const {
    auto id = randomId();
    return {{"id", id},
            {"name", name},
            {"snapshot_path", managedRoot() + "/accounts/" + id},
            {"created_at", QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}};
}
bool AccountsService::saveCodex() {
    QString e;
    if (!writeObject(store.file("codex_profiles.json"), codexIndex, &e)) {
        error = e;
        emit message(e, false);
        return false;
    }
    return true;
}
bool AccountsService::saveAntigravity() {
    QString e;
    if (!writeObject(antigravityRoot() + "/index.json", antigravityIndex, &e)) {
        error = e;
        emit message(e, false);
        return false;
    }
    return true;
}
bool AccountsService::sameIdentity(QJsonObject a, QJsonObject b) {
    auto aid = a.value("account_id").toString(), bid = b.value("account_id").toString();
    auto ae = a.value("email").toString().toLower(), be = b.value("email").toString().toLower();
    return !aid.isEmpty() && !bid.isEmpty() ? aid == bid && (ae.isEmpty() || be.isEmpty() || ae == be)
                                            : !ae.isEmpty() && ae == be;
}
QString AccountsService::resultMessage(QJsonObject r) {
    if (!r.value("message").toString().isEmpty())
        return r.value("message").toString();
    const auto c = r.value("message_code").toString();
    static const QHash<QString, QString> messages = {
        {"browser_failed", "无法打开默认浏览器"},
        {"reauthorization_required", "授权已失效，请重新进行官方登录，原登录备份保留"},
        {"auth_refresh_pending", "请先在 Codex 中使用当前账号，再刷新额度"},
        {"cli_missing", "未找到 Codex CLI，请安装官方 CLI 或导入 auth.json"},
        {"current_auth_unavailable", "无法可靠备份当前登录，请使用文件凭据存储后再切换"},
        {"snapshot_missing", "目标账号登录备份不完整，请重新导入"},
        {"recovery_required", "发现中断的切换，请先恢复"},
        {"state_changed", "账号被其他实例切换，请刷新列表后重试"},
        {"not_installed", "未找到目标桌面程序，请检查安装路径"},
        {"running", "请先完整退出 Antigravity，再修改独立代理"},
        {"proxy_unavailable", "本地代理未监听，请先连接代理"},
        {"usage_forbidden", "额度接口拒绝访问，请检查账号权限和网络"},
        {"api_usage_unsupported", "API Key 账号没有 ChatGPT 订阅额度"},
        {"switch_rolled_back", "切换失败，已恢复原账号"},
        {"rollback_failed", "恢复未完成，请保留账号备份并使用恢复功能"},
        {"enabled", "独立代理已启用，下次启动 Antigravity 生效"},
        {"disabled", "独立代理已卸载，原文件已恢复"},
        {"busy", "另一个实例正在处理账号操作，请稍后重试"}};
    if (messages.contains(c))
        return messages.value(c);
    if (r.value("ok").toBool())
        return "操作完成";
    return QString("操作失败：%1%2")
        .arg(c.isEmpty() ? QString("未返回错误代码") : c, r.contains("error_type")
                                                              ? QString("（%1，第 %2 行）")
                                                                    .arg(r.value("error_type").toString())
                                                                    .arg(r.value("error_line").toInt())
                                                              : QString());
}
void AccountsService::finish(QJsonObject r) {
    busy = false;
    auto text = resultMessage(r);
    emit changed();
    emit message(text, r.value("ok").toBool());
    emit logged(text);
}
void AccountsService::callCodex(const QString &action, const QJsonObject &args, JsonCallback cb) {
    QStringList flags = {"-Action", action, "-ActiveHome", activeCodexHome()};
    for (auto it = args.begin(); it != args.end(); ++it)
        flags << "-" + it.key() << it.value().toString();
    helper.run("windows_codex_profile_helper.ps1", flags, std::move(cb), action == "login" ? 920000 : 120000);
}
bool AccountsService::storeCodex(QJsonObject target, QJsonObject info, const QString &name) {
    auto items = codexAccounts();
    qsizetype existing = -1;
    for (qsizetype i = 0; i < items.size(); ++i)
        if (sameIdentity(items[i].toObject(), info)) {
            existing = i;
            break;
        }
    if (existing >= 0) {
        auto previous = items[existing].toObject();
        previous["snapshot_path"] = target.value("snapshot_path");
        target = previous;
    }
    if (!sameIdentity(target.value("usage_identity").toObject(), info)) {
        target["usage"] = QJsonObject{};
        target["usage_identity"] = QJsonObject{};
    }
    for (auto it = info.begin(); it != info.end(); ++it)
        target[it.key()] = it.value();
    if (!name.trimmed().isEmpty())
        target["name"] = name.trimmed().left(60);
    if (target.value("name").toString().isEmpty())
        target["name"] = info.value("email").toString("已保存账号");
    if (existing >= 0)
        items[existing] = target;
    else
        items.append(target);
    auto before = codexIndex;
    codexIndex["accounts"] = items;
    if (!saveCodex()) {
        codexIndex = before;
        return false;
    }
    return true;
}
void AccountsService::captureCodex(const QString &name, JsonCallback cb) {
    auto fresh = newCodex(name);
    callCodex("capture", {{"CodexHome", fresh.value("snapshot_path")}, {"RelatedHomes", relatedHomes()}},
              [this, fresh, name, cb](QJsonObject r) {
                  if (r.value("ok").toBool() && !storeCodex(fresh, r.value("account").toObject(), name))
                      r = {{"ok", false}, {"message", "当前登录已备份，但账号索引未能保存。原账号未覆盖。"}};
                  cb(r);
              });
}
void AccountsService::codexAction(const QString &action, const QString &id, const QString &name,
                                  const QString &importPath) {
    if (busy) {
        emit message("请等待当前账号操作完成", false);
        return;
    }
    if (!error.isEmpty()) {
        emit message(error, false);
        return;
    }
    busy = true;
    emit changed();
    if (action == "capture") {
        captureCodex(name, [this](QJsonObject r) { finish(r); });
        return;
    }
    if (action == "prepare") {
        const auto label = name.trimmed().left(40);
        if (label.isEmpty()) {
            finish({{"ok", false}, {"message", "请先输入账号备注。"}});
            return;
        }
        const auto profile = newCodex(label);
        callCodex("prepare", {{"CodexHome", profile.value("snapshot_path")}},
                  [this, profile](QJsonObject result) {
                      if (result.value("ok").toBool()) {
                          const auto previous = codexIndex;
                          auto entries = codexAccounts();
                          entries.append(profile);
                          codexIndex["accounts"] = entries;
                          if (!saveCodex()) {
                              codexIndex = previous;
                              result = {{"ok", false}, {"message", error}};
                          } else {
                              result["message"] = "账号配置已创建。切换后请在 Codex 中完成官方登录。";
                          }
                      }
                      finish(result);
                  });
        return;
    }
    if (action == "login" || action == "import") {
        auto fresh = newCodex(name);
        QJsonObject args{{"CodexHome", fresh.value("snapshot_path")}, {"RelatedHomes", relatedHomes()}};
        if (action == "import")
            args["ImportPath"] = importPath;
        callCodex(action, args, [this, fresh, name](QJsonObject r) {
            if (r.value("ok").toBool() && !storeCodex(fresh, r.value("account").toObject(), name))
                r = {{"ok", false}, {"message", "登录已保存在独立目录，但索引保存失败"}};
            finish(r);
        });
        return;
    }
    if (action == "switch") {
        auto target = codexEntry(id);
        if (target.isEmpty()) {
            finish({{"ok", false}, {"message", "账号不存在"}});
            return;
        }
        callCodex("inspect", {}, [this, id, target](QJsonObject state) {
            if (!state.value("ok").toBool()) {
                finish(state);
                return;
            }
            auto perform = [this, id, target] {
                auto pending = codexIndex;
                pending["selected_id"] = id;
                const auto file = store.file("codex-switch-" + randomId() + ".json");
                QString e;
                if (!writeObject(file, pending, &e)) {
                    finish({{"ok", false}, {"message", e}});
                    return;
                }
                callCodex("switch",
                          {{"CodexHome", target.value("snapshot_path")},
                           {"CurrentSnapshot", codexEntry(codexSelected()).value("snapshot_path")},
                           {"RelatedHomes", relatedHomes(id)},
                           {"IndexPath", store.file("codex_profiles.json")},
                           {"PendingIndex", file},
                           {"ExpectedProfileId", codexSelected()}},
                          [this, file](QJsonObject r) {
                              QFile::remove(file);
                              codexIndex = readObject(store.file("codex_profiles.json"));
                              finish(r);
                          });
            };
            auto live = state.value("account").toObject();
            if (live.value("login_present").toBool() && !sameIdentity(codexEntry(codexSelected()), live)) {
                captureCodex({}, [this, perform, live](QJsonObject captured) {
                    if (!captured.value("ok").toBool()) {
                        finish(captured);
                        return;
                    }
                    for (const auto &a : codexAccounts())
                        if (sameIdentity(a.toObject(), live)) {
                            codexIndex["selected_id"] = a.toObject().value("id");
                            break;
                        }
                    if (!saveCodex()) {
                        finish({{"ok", false}, {"message", "无法保存当前账号状态，未切换"}});
                        return;
                    }
                    perform();
                });
            } else
                perform();
        });
        return;
    }
    QJsonObject args;
    if (action == "usage" || action == "launch")
        args = {{"CodexHome", codexEntry(id.isEmpty() ? codexSelected() : id).value("snapshot_path")},
                {"RelatedHomes", relatedHomes(id)}};
    callCodex(action, args, [this, action, id](QJsonObject r) {
        if (action == "usage" && r.value("ok").toBool()) {
            auto items = codexAccounts();
            for (qsizetype i = 0; i < items.size(); ++i) {
                auto a = items[i].toObject();
                if (a.value("id") != id)
                    continue;
                if (!sameIdentity(a, r.value("account").toObject())) {
                    r = {{"ok", false}, {"message", "额度返回身份与该账号不一致，原缓存未覆盖"}};
                    break;
                }
                a["usage"] = r.value("usage");
                a["usage_identity"] = r.value("account");
                items[i] = a;
            }
            codexIndex["accounts"] = items;
            saveCodex();
        }
        finish(r);
    });
}
void AccountsService::removeCodex(const QString &id) {
    if (!error.isEmpty()) {
        emit message(error, false);
        return;
    }
    if (busy)
        return;
    if (id == codexSelected() || codexAccounts().size() <= 1) {
        emit message("请先切换到其他账号，至少保留一个账号入口", false);
        return;
    }
    auto items = codexAccounts();
    for (qsizetype i = 0; i < items.size(); ++i)
        if (items[i].toObject().value("id") == id) {
            items.removeAt(i);
            break;
        }
    auto old = codexIndex;
    codexIndex["accounts"] = items;
    if (!saveCodex())
        codexIndex = old;
    emit changed();
}
void AccountsService::addAntigravity(const QString &name) {
    if (!error.isEmpty()) {
        emit message(error, false);
        return;
    }
    if (busy)
        return;
    auto entry = QJsonObject{
        {"id", randomId()}, {"name", name.trimmed().isEmpty() ? QString("新账号") : name.trimmed().left(60)}};
    auto old = antigravityIndex;
    auto entries = old.value("entries").toArray();
    entries.append(entry);
    antigravityIndex["entries"] = entries;
    if (!saveAntigravity()) {
        antigravityIndex = old;
        return;
    }
    emit changed();
    antigravityAction("launch", entry.value("id").toString());
}
void AccountsService::setAntigravityDefault(const QString &id) {
    if (!error.isEmpty()) {
        emit message(error, false);
        return;
    }
    if (busy || antigravityEntry(id).isEmpty())
        return;
    auto old = antigravityIndex;
    antigravityIndex["default_account"] = id;
    if (!saveAntigravity())
        antigravityIndex = old;
    emit changed();
}
void AccountsService::removeAntigravity(const QString &id) {
    if (!error.isEmpty()) {
        emit message(error, false);
        return;
    }
    if (busy)
        return;
    if (id == antigravityDefault()) {
        emit message("请先把其他账号设为默认，再删除此入口", false);
        return;
    }
    auto old = antigravityIndex;
    if (id == "default")
        antigravityIndex["original_visible"] = false;
    else {
        auto items = antigravityIndex.value("entries").toArray();
        for (qsizetype i = 0; i < items.size(); ++i)
            if (items[i].toObject().value("id") == id) {
                items.removeAt(i);
                break;
            }
        antigravityIndex["entries"] = items;
    }
    auto quotas = antigravityIndex.value("quotas").toObject();
    quotas.remove(id);
    antigravityIndex["quotas"] = quotas;
    if (!saveAntigravity())
        antigravityIndex = old;
    emit changed();
    emit message("已删除账号入口，本地登录备份、项目和对话保留", true);
}
void AccountsService::antigravityAction(const QString &action, const QString &id) {
    if (!error.isEmpty()) {
        emit message(error, false);
        return;
    }
    if (busy)
        return;
    auto entry = antigravityEntry(id);
    if (entry.isEmpty())
        return;
    busy = true;
    emit changed();
    QString root = entry.value("helper_root").toString(antigravityRoot());
    helper.run(
        "windows_antigravity_accounts_helper.ps1",
        {"-Action", action, "-Root", root, "-AccountId", id, "-ExePath",
         store.settings.value("antigravity_exe").toString()},
        [this, action, id](QJsonObject r) {
            if (action == "launch" && r.value("ok").toBool())
                antigravityIndex["selected"] = id;
            if (action == "quota") {
                if (r.value("ok").toBool()) {
                    auto q = antigravityIndex.value("quotas").toObject();
                    q[id] = r;
                    antigravityIndex["quotas"] = q;
                }
                auto entries = antigravityIndex.value("entries").toArray();
                for (qsizetype i = 0; i < entries.size(); ++i) {
                    auto a = entries[i].toObject();
                    if (a.value("id") != id)
                        continue;
                    if (r.contains("email"))
                        a["email"] = r["email"];
                    if (r.contains("logged_in"))
                        a["logged_in"] = r["logged_in"];
                    a["quota_error"] = r.value("ok").toBool() ? QString() : resultMessage(r);
                    entries[i] = a;
                }
                antigravityIndex["entries"] = entries;
            }
            saveAntigravity();
            finish(r);
        },
        0);
}
void AccountsService::antigravityProxyAction(const QString &action) {
    if (!error.isEmpty()) {
        emit message(error, false);
        return;
    }
    if (busy)
        return;
    busy = true;
    emit changed();
    helper.run("windows_antigravity_proxy_helper.ps1",
               {"-Action", action, "-ExePath", store.settings.value("antigravity_exe").toString(),
                "-ProxyPort", QString::number(store.mixedPort()), "-PayloadDirectory",
                resourcePath("third_party/antigravity-proxy"), "-StateRoot",
                store.settings.value("antigravity_state_root")
                    .toString(store.runtime("antigravity-proxy/installations"))},
               [this](QJsonObject r) {
                   if (r.value("ok").toBool())
                       antigravityProxyState = r;
                   finish(r);
               });
}
} // namespace hexagon
