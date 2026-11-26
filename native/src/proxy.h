#pragma once
#include "jobs.h"
#include <QTimer>
#include <yaml-cpp/yaml.h>
namespace hexagon {
YAML::Node profileFromText(const QByteArray &text);
QByteArray makeRuntimeProfile(const QByteArray &source, int mixed, int controller, const QString &secret,
                              bool tun, const QJsonObject &routing);
QJsonObject selectWindowsCore(const QJsonArray &assets);
QJsonArray coreAssetsFromHtml(const QByteArray &html);
class ProxyService : public QObject {
    Q_OBJECT
  public:
    ProxyService(Storage &storage, QObject *parent = nullptr);
    Storage &store;
    Http api, downloads;
    QProcess process;
    QTimer poll, failoverTimer;
    bool busy = false, connected = false, systemEnabled = false, tunEnabled = false, downloading = false;
    QString mode = "rule", lastError;
    QJsonObject proxies, connections;
    void start(bool useSystemProxy = false);
    void stop();
    void shutdown();
    void downloadCore(bool releasePage = false);
    void request(const QString &endpoint, const QByteArray &method, const QJsonObject &body, JsonCallback cb);
    void refresh();
    void setMode(const QString &value);
    void selectNode(const QString &group, const QString &node);
    void testNode(const QString &node, JsonCallback cb);
    bool setSystemProxy(bool enable, QString *error = nullptr);
    void importSubscription(const QString &name, const QString &source);
    void activateSubscription(const QString &id);
    void removeSubscription(const QString &id);
    void refreshSubscription(const QString &id);
    void checkFailover();
    void toggleBackup(const QString &group, const QString &node);
    QJsonObject subscriptions() const;
    QString corePath() const;
    QString controlSecret() const;
  signals:
    void changed();
    void nodesChanged();
    void subscriptionsChanged();
    void logged(QString message);
    void trafficChanged(QJsonObject state);

  private:
    void launchPrepared();
    void fail(const QString &message);
    void installDownloadedCore(const QString &url, const QString &digest, const QString &name);
    void downloadCoreFromReleasePage(const QString &apiError);
    QString coreOutput;
    bool wantRunning = false;
    bool enableSystemProxyOnConnect = false;
    int healthFailures = 0;
    quint64 generation = 0;
    bool probePending = false;
    int nodeFailures = 0;
    QElapsedTimer lastSwitch;
    void tryBackup(QStringList candidates, int index, QString group, QString current, quint64 epoch);
};
} // namespace hexagon
