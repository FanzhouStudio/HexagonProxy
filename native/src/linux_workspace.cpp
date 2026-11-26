#include "linux_workspace.h"
#include <QApplication>
#include <QClipboard>
#include <QtConcurrent>
#include <QtNetwork>
#include <limits>
namespace hexagon {
qint64 linuxDiskBytes(int cap) {
    if (cap < 1 || cap > 10)
        throw std::runtime_error("磁盘容量必须为 1～10 GB");
    return qint64(cap) * 1073741824 - 16 * 1024 * 1024;
}
static void cpioEntry(QByteArray &bytes, const QByteArray &name, const QByteArray &data, int mode) {
    bytes += "070701";
    for (auto v : {1, mode, 0, 0, 1, 0, int(data.size()), 0, 0, 0, 0, int(name.size() + 1), 0})
        bytes += QByteArray::number(v, 16).rightJustified(8, '0');
    bytes += name;
    bytes += '\0';
    while (bytes.size() % 4)
        bytes += '\0';
    bytes += data;
    while (bytes.size() % 4)
        bytes += '\0';
}
static quint32 crc32(const QByteArray &b) {
    quint32 c = 0xffffffff;
    for (unsigned char v : b) {
        c ^= v;
        for (int i = 0; i < 8; ++i)
            c = (c >> 1) ^ (0xedb88320u & quint32(-int(c & 1)));
    }
    return ~c;
}
static QByteArray gzip(const QByteArray &data) {
    auto z = qCompress(data, 9);
    QByteArray g = QByteArray::fromHex("1f8b08000000000000ff");
    g += z.mid(6, z.size() - 10);
    for (quint32 value : {crc32(data), quint32(data.size())})
        for (int i = 0; i < 4; ++i)
            g += char((value >> (8 * i)) & 0xff);
    return g;
}
QByteArray seedInitramfs(const QByteArray &base, const QByteArray &init, const QByteArray &guest,
                         const QString &password, const QString &token) {
    if (!QRegularExpression("^[a-f0-9]{32}$").match(password).hasMatch() ||
        !QRegularExpression("^[a-f0-9]{48}$").match(token).hasMatch())
        throw std::runtime_error("Linux 凭据格式无效，未启动");
    QByteArray archive;
    cpioEntry(archive, "init", init, 0100755);
    cpioEntry(archive, "hexagon/guest-init", guest, 0100755);
    cpioEntry(archive, "hexagon/seed.env",
              QString("LOGIN_PASSWORD='%1'\nCONTROL_TOKEN='%2'\n").arg(password, token).toUtf8(), 0100600);
    cpioEntry(archive, "TRAILER!!!", {}, 0);
    return base + gzip(archive);
}
static QByteArray execute(const QString &program, const QStringList &args, const QString &working = {}) {
    QProcess p;
    hiddenProcess(&p);
    if (!working.isEmpty())
        p.setWorkingDirectory(working);
    p.start(program, args);
    if (!p.waitForStarted(10000))
        throw std::runtime_error(p.errorString().toStdString());
    p.waitForFinished(-1);
    auto out = p.readAllStandardOutput(), err = p.readAllStandardError();
    if (p.exitCode() != 0)
        throw std::runtime_error(QString::fromUtf8(err + out).left(2000).toStdString());
    return out;
}
static int availablePort(int exclude = 0) {
    QTcpServer s;
    for (int i = 0; i < 20; ++i) {
        if (!s.listen(QHostAddress::LocalHost, 0))
            continue;
        auto port = s.serverPort();
        s.close();
        if (port != exclude)
            return port;
    }
    return 0;
}
LinuxWorkspace::LinuxWorkspace(Storage &s, QObject *parent)
    : QObject(parent), store(s), vm(this), poll(this), http(this), worker(this), control(this) {
    auto config = readObject(root() + "/native-vm.json");
    auto old = root() + "/settings.cfg";
    capacity =
        qBound(1, config.value("capacity").toInt(legacyValue(old, "disk/capacity_gb", "10").toInt()), 10);
    password = config.value("password").toString(legacyValue(old, "login/password"));
    token = config.value("token").toString(legacyValue(old, "control/token"));
    if (installed())
        status = "已安装 · 已停止";
    hiddenProcess(&vm);
    poll.setInterval(1000);
    connect(&poll, &QTimer::timeout, this, &LinuxWorkspace::monitor);
    connect(&vm, &QProcess::readyReadStandardError, this,
            [this] { tail = (tail + QString::fromUtf8(vm.readAllStandardError())).right(2000); });
    connect(&vm, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            poll.stop();
            busy = false;
            fail("QEMU 无法启动：" + vm.errorString());
        }
    });
    connect(&vm, &QProcess::finished, this, [this](int code, QProcess::ExitStatus) {
        poll.stop();
        control.abort();
        ready = false;
        busy = false;
        if (stopping) {
            stopping = false;
            status = "已停止 · 文件已保留";
            error.clear();
            emit changed();
        } else
            fail(QString("QEMU 已退出（%1），系统盘保留。\n%2").arg(code).arg(tail.right(1600)));
    });
    connect(&worker, &QFutureWatcher<QJsonObject>::finished, this, [this] {
        auto result = worker.result();
        busy = false;
        if (!result.value("ok").toBool()) {
            fail(result.value("message").toString());
            return;
        }
        capacity = result.value("capacity").toInt();
        if (cancelStartup) {
            status = "已停止 · 准备结果已保留";
            emit changed();
            return;
        }
        launch(result.value("install").toBool());
    });
    connect(&control, &QTcpSocket::connected, this, [this] {
        control.write("shutdown:" + token.toUtf8() + "\n");
        control.flush();
    });
    connect(&control, &QTcpSocket::errorOccurred, this, [this](QAbstractSocket::SocketError) {
        if (stopping) {
            stopping = false;
            busy = false;
            fail("关闭指令未送达，系统盘未被强制断电。请稍后重试。");
        }
    });
}
QJsonObject LinuxWorkspace::snapshot() const {
    return {
        {"capacity", capacity}, {"running", running()},     {"ready", ready},
        {"busy", busy},         {"installed", installed()}, {"status", status},
        {"error", error},       {"path", root()},           {"disk_bytes", double(QFileInfo(disk()).size())}};
}
void LinuxWorkspace::fail(const QString &text) {
    error = text;
    emit logged(text);
    emit changed();
}
void LinuxWorkspace::start(int cap) {
    if (busy || running())
        return;
    if (cap < 1 || cap > 10) {
        fail("容量必须为 1～10 GB");
        return;
    }
    if (installed() && cap < capacity) {
        fail("已有系统盘不能缩小，请选择当前容量或更大容量");
        return;
    }
    if (!installed() && !QFile::exists(root() + "/native-vm.json")) {
        password = randomId();
        token = randomId() + randomId().left(16);
    }
    if (password.isEmpty()) {
        if (installed()) {
            fail("本地登录凭据缺失，系统盘已保留，请恢复设置或明确重建系统盘");
            return;
        }
        password = randomId();
        token = randomId() + randomId().left(16);
    }
    busy = true;
    cancelStartup = false;
    error.clear();
    status = "正在校验和准备离线环境…";
    emit changed();
    const auto dir = root(), resources = resourcePath("");
    const auto pass = password, key = token;
    const int previous = capacity;
    worker.setFuture(QtConcurrent::run([dir, resources, pass, key, cap, previous] {
        try {
            QDir().mkpath(dir);
            const auto runtime = dir + "/runtime";
            QDir().mkpath(runtime);
            if (!QFile::exists(runtime + "/.verified")) {
                const auto zip = QDir(resources).filePath("third_party/linux_runtime/runtime.zip");
                if (!QFile::exists(zip))
                    throw std::runtime_error("离线运行包缺失，请使用完整的 HexagonProxy.exe");
                auto names =
                    QString::fromUtf8(execute("tar.exe", {"-tf", zip})).split('\n', Qt::SkipEmptyParts);
                for (auto name : names) {
                    name = name.trimmed().replace('\\', '/');
                    if (QDir::isAbsolutePath(name) || name.contains(':') || name.split('/').contains(".."))
                        throw std::runtime_error("运行包路径校验失败");
                }
                execute("tar.exe", {"-xf", zip, "-C", runtime});
                auto manifest = readObject(runtime + "/manifest.json");
                if (!manifest.value("files").isArray())
                    throw std::runtime_error("运行包清单无效");
                for (const auto &v : manifest.value("files").toArray()) {
                    auto item = v.toObject();
                    auto name = item.value("path").toString();
                    if (QDir::isAbsolutePath(name) || name.contains(':') || name.contains('\\') ||
                        name.split('/').contains(".."))
                        throw std::runtime_error("运行包清单路径无效");
                    QFile f(runtime + "/" + name);
                    if (!f.open(QIODevice::ReadOnly) || f.size() != qint64(item.value("size").toDouble()))
                        throw std::runtime_error(("运行文件缺失：" + name).toStdString());
                    QCryptographicHash hash(QCryptographicHash::Sha256);
                    if (!hash.addData(&f) ||
                        hash.result().toHex() != item.value("sha256").toString().toLatin1())
                        throw std::runtime_error(("文件摘要不匹配：" + name).toStdString());
                }
                QString e;
                if (!writeBytes(runtime + "/.verified", "native-1", &e))
                    throw std::runtime_error(e.toStdString());
            }
            auto img = runtime + "/qemu/qemu-img.exe";
            auto measured =
                QJsonDocument::fromJson(execute(img, {"measure", "--output=json", "-O", "qcow2", "-o",
                                                      "cluster_size=65536,lazy_refcounts=on", "--size",
                                                      QString::number(linuxDiskBytes(cap))}))
                    .object();
            if (!measured.contains("fully-allocated") ||
                measured.value("fully-allocated").toDouble() > double(qint64(cap) * 1073741824))
                throw std::runtime_error("磁盘元数据使最大占用超出容量预算，未创建");
            const bool fresh = !QFile::exists(dir + "/linux.qcow2");
            QString e;
            bool install = fresh || QFile::exists(dir + "/needs-install");
            if (fresh) {
                if (!writeBytes(dir + "/needs-install", "1", &e))
                    throw std::runtime_error(e.toStdString());
                execute(img,
                        {"create", "-f", "qcow2", "-o", "cluster_size=65536,lazy_refcounts=on",
                         "linux.qcow2.partial", QString::number(linuxDiskBytes(cap))},
                        dir);
                if (!QFile::rename(dir + "/linux.qcow2.partial", dir + "/linux.qcow2"))
                    throw std::runtime_error("无法保存新系统盘");
            } else if (cap > previous)
                execute(img, {"resize", "linux.qcow2", QString::number(linuxDiskBytes(cap))}, dir);
            if (!writeObject(dir + "/native-vm.json", {{"capacity", cap}, {"password", pass}, {"token", key}},
                             &e))
                throw std::runtime_error(e.toStdString());
            const auto seeded =
                seedInitramfs(readBytes(runtime + "/initramfs.gz"),
                              readBytes(QDir(resources).filePath("scripts/linux/init.sh")),
                              readBytes(QDir(resources).filePath("scripts/linux/guest-init.sh")), pass, key);
            if (!writeBytes(dir + "/native-initramfs.gz", seeded, &e))
                throw std::runtime_error(e.toStdString());
            return QJsonObject{{"ok", true}, {"capacity", cap}, {"install", install}};
        } catch (const std::exception &e) {
            return QJsonObject{{"ok", false}, {"message", QString::fromUtf8(e.what())}};
        }
    }));
}
void LinuxWorkspace::launch(bool install) {
    webPort = availablePort();
    controlPort = availablePort(webPort);
    if (!webPort || !controlPort) {
        fail("无法分配本地工作区端口");
        return;
    }
    auto runtime = root() + "/runtime";
    // QEMU's Windows argv conversion can corrupt non-ASCII absolute paths.
    // CreateProcessW sets the Unicode working directory; all QEMU file args
    // remain relative ASCII paths within that directory.
    vm.setWorkingDirectory(root());
    QStringList args = {
        "-name",
        "HexagonProxy Linux",
        "-machine",
        "q35",
        "-accel",
        "tcg,thread=multi",
        "-smp",
        "2",
        "-m",
        "512",
        "-display",
        "none",
        "-monitor",
        "none",
        "-no-reboot",
        "-L",
        "runtime/qemu/share",
        "-kernel",
        "runtime/vmlinuz",
        "-initrd",
        "native-initramfs.gz",
        "-append",
        QString("console=ttyS0 panic=5") + (install ? " hexagon.install=1" : ""),
        "-drive",
        "file=linux.qcow2,format=qcow2,if=virtio,discard=unmap",
        "-netdev",
        QString("user,id=net0,hostfwd=tcp:127.0.0.1:%1-:80").arg(webPort),
        "-device",
        "virtio-net-pci,netdev=net0",
        "-serial",
        "file:native-serial.log",
        "-chardev",
        QString("socket,id=control,host=127.0.0.1,port=%1,server=on,wait=off").arg(controlPort),
        "-serial",
        "chardev:control"};
    if (install)
        args << "-drive"
             << "file=runtime/rootfs.tar.gz,format=raw,if=virtio,readonly=on";
    writeBytes(root() + "/native-serial.log", {});
    offset = 0;
    tail.clear();
    busy = true;
    stopping = false;
    ready = false;
    status = install ? "首次初始化系统盘…" : "Linux 正在启动…";
    vm.start(runtime + "/qemu/qemu-system-x86_64.exe", args);
    bootTime.start();
    poll.start();
    emit changed();
}
void LinuxWorkspace::monitor() {
    QFile f(root() + "/native-serial.log");
    if (f.open(QIODevice::ReadOnly)) {
        f.seek(offset);
        auto text = QString::fromUtf8(f.read(65536));
        offset = f.pos();
        tail = (tail + text).right(2000);
        for (auto line : text.split('\n'))
            if (line.contains("HEXAGON_ERROR:")) {
                error = line.trimmed();
                busy = false;
                emit changed();
            }
    }
    if (stopping || ready || healthPending || !running())
        return;
    if (bootTime.elapsed() > 180000 && error.isEmpty()) {
        busy = false;
        fail("启动仍未完成，请查看 native-serial.log；磁盘未被强制终止");
    }
    healthPending = true;
    http.get(
        QUrl(QString("http://127.0.0.1:%1/").arg(webPort)),
        [this](QByteArray data, QString e) {
            healthPending = false;
            if (!ready && !stopping && running() && e.isEmpty() && data.contains("html")) {
                ready = true;
                busy = false;
                error.clear();
                status = "运行中 · HexagonLinux 已就绪";
                QFile::remove(root() + "/needs-install");
                emit changed();
            }
        },
        1500);
}
void LinuxWorkspace::stop() {
    if (worker.isRunning()) {
        cancelStartup = true;
        status = "正在等待磁盘准备完成…";
        emit changed();
        return;
    }
    if (!running() || stopping)
        return;
    stopping = true;
    ready = false;
    busy = true;
    status = "正在保存文件并关闭 Linux…";
    emit changed();
    control.abort();
    control.connectToHost(QHostAddress::LocalHost, controlPort);
}
void LinuxWorkspace::reset() {
    if (busy || running())
        return;
    for (const auto &name :
         {"linux.qcow2", "linux.qcow2.partial", "needs-install", "native-initramfs.gz", "native-vm.json"}) {
        auto p = root() + "/" + name;
        if (QFile::exists(p) && !QFile::remove(p)) {
            fail("无法删除工作区文件：" + QString(name));
            return;
        }
    }
    password.clear();
    token.clear();
    status = "尚未安装";
    error.clear();
    emit changed();
}
bool LinuxWorkspace::copyPassword() {
    if (password.isEmpty())
        return false;
    QApplication::clipboard()->setText(password);
    return true;
}
void LinuxWorkspace::open() {
    if (ready)
        emit openRequested(QUrl(QString("http://127.0.0.1:%1/").arg(webPort)));
}
bool LinuxWorkspace::setDirectory(const QString &directory) {
    if (busy || running()) {
        fail("请先停止工作区，再更改安装目录");
        return false;
    }
    if (directory.trimmed().isEmpty()) {
        fail("请选择安装目录");
        return false;
    }
    QString selected = QDir::cleanPath(QFileInfo(directory).absoluteFilePath());
    if (!QDir().mkpath(selected)) {
        fail("无法创建所选安装目录");
        return false;
    }
    selected = QDir(selected).canonicalPath();
    if (selected.isEmpty()) {
        fail("所选目录无法访问");
        return false;
    }
    if (QFile::exists(selected + "/linux.qcow2") && !QFile::exists(selected + "/native-vm.json") &&
        !QFile::exists(selected + "/settings.cfg")) {
        fail("此目录已有未识别的磁盘，未覆盖。请选择新的空目录或已有 HexagonProxy 工作区。");
        return false;
    }
    const auto probe = selected + "/.hexagon-write-" + randomId() + ".tmp";
    QString e;
    if (!writeBytes(probe, "test", &e)) {
        fail("所选目录不可写：" + e);
        return false;
    }
    QFile::remove(probe);
    auto old = store.settings;
    store.settings["linux_path"] = selected;
    if (!store.saveSettings(&e)) {
        store.settings = old;
        fail(e);
        return false;
    }
    auto config = readObject(root() + "/native-vm.json");
    auto legacy = root() + "/settings.cfg";
    capacity =
        qBound(1, config.value("capacity").toInt(legacyValue(legacy, "disk/capacity_gb", "10").toInt()), 10);
    password = config.value("password").toString(legacyValue(legacy, "login/password"));
    token = config.value("token").toString(legacyValue(legacy, "control/token"));
    ready = false;
    error.clear();
    status = installed() ? "已选择现有工作区 · 已停止" : "尚未安装";
    emit changed();
    emit logged("安装目录已切换，原目录及文件保留");
    return true;
}
} // namespace hexagon
