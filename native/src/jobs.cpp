#include "jobs.h"
#include <QtNetwork>
#include <windows.h>
namespace hexagon {
void hiddenProcess(QProcess *p) {
    p->setCreateProcessArgumentsModifier(
        [](QProcess::CreateProcessArguments *a) { a->flags |= CREATE_NO_WINDOW; });
}
void runProcess(QObject *owner, const QString &program, const QStringList &args,
                std::function<void(int, QByteArray, QByteArray)> cb, int timeout, const QString &working) {
    auto p = new QProcess(owner);
    hiddenProcess(p);
    if (!working.isEmpty())
        p->setWorkingDirectory(working);
    auto env = QProcessEnvironment::systemEnvironment();
    env.remove("PSModulePath");
    p->setProcessEnvironment(env);
    auto done = std::make_shared<bool>(false);
    auto out = std::make_shared<QByteArray>();
    auto err = std::make_shared<QByteArray>();
    QObject::connect(p, &QProcess::readyReadStandardOutput, p, [p, out] {
        out->append(p->readAllStandardOutput());
        if (out->size() > 4 * 1024 * 1024)
            out->remove(0, out->size() - 4 * 1024 * 1024);
    });
    QObject::connect(p, &QProcess::readyReadStandardError, p, [p, err] {
        err->append(p->readAllStandardError());
        if (err->size() > 16384)
            err->remove(0, err->size() - 16384);
    });
    auto finish = [=](int code) {
        if (*done)
            return;
        *done = true;
        out->append(p->readAllStandardOutput());
        err->append(p->readAllStandardError());
        cb(code, *out, *err);
        p->deleteLater();
    };
    QObject::connect(p, &QProcess::finished, p, [finish](int code, QProcess::ExitStatus) { finish(code); });
    QObject::connect(p, &QProcess::errorOccurred, p, [finish](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart)
            finish(-1);
    });
    if (timeout > 0)
        QTimer::singleShot(timeout, p, [p, done] {
            if (!*done)
                p->kill();
        });
    p->start(program, args);
}
void HelperRunner::run(const QString &helper, QStringList args, JsonCallback cb, int timeout) {
    const QString script = resourcePath("scripts/" + helper);
    const QString result = store.runtime("jobs/" + randomId() + ".json");
    QDir().mkpath(QFileInfo(result).absolutePath());
    QStringList all = {"-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "RemoteSigned",
                       "-File",   script};
    all << args << "-ResultPath" << result;
    // Transaction helpers must finish their own rollback. Timeout is handled by
    // their implementation, rather than killing midway through a file swap.
    Q_UNUSED(timeout);
    runProcess(
        this, "powershell.exe", all,
        [=](int code, QByteArray, QByteArray err) {
            QString parseError;
            auto value = readObject(result, &parseError);
            QFile::remove(result);
            QFile::remove(result + ".progress");
            if (value.isEmpty())
                value = {{"ok", false},
                         {"message", QString("操作助手退出（%1）：%2 %3")
                                         .arg(code)
                                         .arg(QString::fromUtf8(err).left(1500), parseError)}};
            cb(value);
        },
        0);
}
Http::Http(QObject *parent) : QObject(parent), manager(this) {
    manager.setProxy(QNetworkProxy::NoProxy);
}
void Http::get(QUrl url, BytesCallback cb, int timeout, bool systemProxy) {
    bool usesProxy = false;
    if (systemProxy) {
        QNetworkProxyQuery query(url);
        const auto p = QNetworkProxyFactory::systemProxyForQuery(query);
        manager.setProxy(p.isEmpty() ? QNetworkProxy::NoProxy : p.first());
        usesProxy = manager.proxy().type() != QNetworkProxy::NoProxy;
    } else
        manager.setProxy(QNetworkProxy::NoProxy);
    request(
        url, "GET", {}, {},
        [this, url, cb = std::move(cb), timeout, usesProxy](QByteArray data, QString error) {
            if (usesProxy && !error.isEmpty()) {
                manager.setProxy(QNetworkProxy::NoProxy);
                request(
                    url, "GET", {}, {},
                    [cb, error](QByteArray direct, QString failure) {
                        cb(direct, failure.isEmpty()
                                       ? QString()
                                       : "系统代理请求失败：" + error + "；直连重试失败：" + failure);
                    },
                    timeout);
            } else
                cb(data, error);
        },
        timeout);
}
void Http::request(QUrl url, const QByteArray &method, const QByteArray &body,
                   const QList<QNetworkReply::RawHeaderPair> &headers, BytesCallback cb, int timeout) {
    QNetworkRequest req(url);
    req.setTransferTimeout(timeout);
    req.setHeader(QNetworkRequest::UserAgentHeader, "HexagonProxy/0.5.4");
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    for (const auto &h : headers)
        req.setRawHeader(h.first, h.second);
    auto r = manager.sendCustomRequest(req, method, body);
    connect(r, &QNetworkReply::finished, this, [r, cb = std::move(cb)] {
        const auto data = r->isOpen() ? r->readAll() : QByteArray();
        const int status = r->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        QString error;
        if (r->error() != QNetworkReply::NoError || status >= 400)
            error = QString("%1：%2（HTTP %3）").arg(r->url().host(), r->errorString()).arg(status);
        cb(data, error);
        r->deleteLater();
    });
}
} // namespace hexagon
