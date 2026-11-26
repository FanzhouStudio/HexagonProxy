#pragma once
#include "jobs.h"
namespace hexagon {
class AccountsService : public QObject {
    Q_OBJECT
  public:
    AccountsService(Storage &storage, QObject *parent = nullptr);
    Storage &store;
    HelperRunner helper;
    QJsonObject codexIndex, antigravityIndex, antigravityProxyState;
    bool busy = false;
    QString error;
    QJsonArray codexAccounts() const {
        return codexIndex.value("accounts").toArray();
    }
    QJsonArray antigravityAccounts() const;
    QString codexSelected() const {
        return codexIndex.value("selected_id").toString("default");
    }
    QString antigravityDefault() const {
        return antigravityIndex.value("default_account").toString("default");
    }
    QString activeCodexHome() const;
    void codexAction(const QString &action, const QString &id = {}, const QString &name = {},
                     const QString &importPath = {});
    void removeCodex(const QString &id);
    void addAntigravity(const QString &name);
    void removeAntigravity(const QString &id);
    void setAntigravityDefault(const QString &id);
    void antigravityAction(const QString &action, const QString &id);
    void antigravityProxyAction(const QString &action);
    bool saveCodex();
    bool saveAntigravity();
    static bool sameIdentity(QJsonObject a, QJsonObject b);
    static QString resultMessage(QJsonObject result);
  signals:
    void changed();
    void message(QString text, bool ok);
    void logged(QString text);

  private:
    QString managedRoot() const;
    QString relatedHomes(const QString &exclude = {}) const;
    QString antigravityRoot() const;
    QJsonObject codexEntry(const QString &id) const;
    QJsonObject antigravityEntry(const QString &id) const;
    QJsonObject newCodex(const QString &name) const;
    void callCodex(const QString &action, const QJsonObject &args, JsonCallback cb);
    void captureCodex(const QString &name, JsonCallback cb);
    bool storeCodex(QJsonObject account, QJsonObject info, const QString &name);
    void finish(QJsonObject result);
};
} // namespace hexagon
