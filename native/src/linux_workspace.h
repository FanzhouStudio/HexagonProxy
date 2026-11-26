#pragma once
#include "jobs.h"
#include <QFutureWatcher>
#include <QTcpSocket>
namespace hexagon {
QByteArray seedInitramfs(const QByteArray &base, const QByteArray &init, const QByteArray &guest,
                         const QString &password, const QString &token);
qint64 linuxDiskBytes(int capacity);
class LinuxWorkspace : public QObject {
    Q_OBJECT
  public:
    LinuxWorkspace(Storage &storage, QObject *parent = nullptr);
    Storage &store;
    QProcess vm;
    QTimer poll;
    bool busy = false, ready = false, stopping = false;
    QString status = "尚未安装", error;
    int capacity = 10, webPort = 0, controlPort = 0;
    QString root() const {
        return store.linuxRoot();
    }
    QString disk() const {
        return root() + "/linux.qcow2";
    }
    bool running() const {
        return vm.state() != QProcess::NotRunning;
    }
    bool installed() const {
        return QFile::exists(disk());
    }
    void start(int gigabytes);
    void stop();
    void reset();
    bool copyPassword();
    void open();
    bool setDirectory(const QString &directory);
    QJsonObject snapshot() const;
  signals:
    void changed();
    void logged(QString text);
    void openRequested(QUrl url);

  private:
    Http http;
    QString password, token, tail;
    QFutureWatcher<QJsonObject> worker;
    QTcpSocket control;
    bool cancelStartup = false, healthPending = false;
    qint64 offset = 0;
    QElapsedTimer bootTime;
    void launch(bool install);
    void monitor();
    void fail(const QString &message);
};
} // namespace hexagon
