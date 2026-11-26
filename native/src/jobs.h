#pragma once
#include "storage.h"
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QProcess>

namespace hexagon {
using JsonCallback = std::function<void(QJsonObject)>;
using BytesCallback = std::function<void(QByteArray, QString)>;
void hiddenProcess(QProcess *process);
void runProcess(QObject *owner, const QString &program, const QStringList &args,
                std::function<void(int, QByteArray, QByteArray)> callback, int timeoutMs = 120000,
                const QString &workingDirectory = {});
class HelperRunner : public QObject {
    Q_OBJECT
  public:
    explicit HelperRunner(Storage &storage, QObject *parent = nullptr) : QObject(parent), store(storage) {}
    void run(const QString &helper, QStringList args, JsonCallback callback, int timeout = 120000);
    Storage &store;
};
class Http : public QObject {
    Q_OBJECT
  public:
    explicit Http(QObject *parent = nullptr);
    void get(QUrl url, BytesCallback callback, int timeout = 30000, bool systemProxy = false);
    void request(QUrl url, const QByteArray &method, const QByteArray &body,
                 const QList<QNetworkReply::RawHeaderPair> &headers, BytesCallback callback,
                 int timeout = 10000);
    QNetworkAccessManager manager;
};
} // namespace hexagon
