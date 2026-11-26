#include "proxy.h"
#include <QtConcurrent>
#include <utility>
#include <QtNetwork>
#include <windows.h>
#include <wininet.h>
namespace hexagon {
static std::string s(const QString &v) {
    return v.toUtf8().toStdString();
}
static YAML::Node baseProfile() {
    auto p = YAML::Load(
        "mixed-port: 7890\nallow-lan: false\nmode: rule\nlog-level: info\nipv6: false\nunified-delay: "
        "true\ntcp-concurrent: true\nprofile: {store-selected: true}\nproxies: []\nproxy-groups: [{name: "
        "六角选择, type: select, proxies: [DIRECT]}]\nrules: [DOMAIN-SUFFIX,placeholder,DIRECT]\n");
    p["rule-providers"] = YAML::Load("hexagon-cn-domain: {type: file, behavior: domain, format: mrs, path: "
                                     "./rules/geosite-cn.mrs}\nhexagon-cn-ip: {type: file, behavior: ipcidr, "
                                     "format: mrs, path: ./rules/geoip-cn.mrs}\n");
    p["rules"] = YAML::Node(YAML::NodeType::Sequence);
    for (const auto &r : {"DOMAIN,localhost,DIRECT", "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
                          "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve", "IP-CIDR,172.16.0.0/12,DIRECT,no-resolve",
                          "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve", "RULE-SET,hexagon-cn-domain,DIRECT",
                          "RULE-SET,hexagon-cn-ip,DIRECT,no-resolve", "MATCH,六角选择"})
        p["rules"].push_back(r);
    return p;
}
static QByteArray decode64(QByteArray b) {
    b.replace('-', '+');
    b.replace('_', '/');
    while (b.size() % 4)
        b += '=';
    return QByteArray::fromBase64(b);
}
YAML::Node profileFromText(const QByteArray &input) {
    auto bytes = input.trimmed();
    YAML::Node parsed;
    try {
        parsed = YAML::Load(bytes.toStdString());
        if (parsed.IsMap() && (parsed["proxies"] || parsed["proxy-providers"])) {
            if (parsed["proxies"].IsSequence() && !parsed["proxy-groups"]) {
                YAML::Node group;
                group["name"] = "六角选择";
                group["type"] = "select";
                for (const auto &node : parsed["proxies"])
                    if (node["name"].IsScalar())
                        group["proxies"].push_back(node["name"]);
                if (!group["proxies"])
                    group["proxies"].push_back("DIRECT");
                parsed["proxy-groups"].push_back(group);
            }
            if (!parsed["rules"])
                parsed["rules"].push_back(parsed["proxy-groups"].IsSequence() && parsed["proxy-groups"].size()
                                              ? "MATCH," + parsed["proxy-groups"][0]["name"].as<std::string>()
                                              : "MATCH,DIRECT");
            return parsed;
        }
    } catch (const YAML::Exception &) {
    }
    if (!bytes.contains("://"))
        bytes = decode64(bytes).trimmed();
    auto profile = baseProfile();
    YAML::Node nodes(YAML::NodeType::Sequence), names(YAML::NodeType::Sequence);
    QSet<QString> used;
    int counter = 0;
    for (auto line : QString::fromUtf8(bytes).split(QRegularExpression("[\\r\\n]+"), Qt::SkipEmptyParts)) {
        line = line.trimmed();
        if (line.isEmpty() || line.startsWith('#'))
            continue;
        auto u = QUrl(line);
        auto q = QUrlQuery(u);
        QString type = u.scheme().toLower();
        YAML::Node node;
        QString name = u.fragment(QUrl::FullyDecoded);
        if (type == "vmess") {
            auto v = QJsonDocument::fromJson(decode64(line.mid(8).toUtf8())).object();
            if (v.isEmpty())
                throw std::runtime_error("VMess 链接内容无效");
            name = v.value("ps").toString();
            node["type"] = "vmess";
            node["server"] = s(v.value("add").toString());
            node["port"] = v.value("port").toVariant().toInt();
            node["uuid"] = s(v.value("id").toString());
            node["alterId"] = v.value("aid").toVariant().toInt();
            node["cipher"] = "auto";
            const auto net = v.value("net").toString();
            if (net == "ws") {
                node["network"] = "ws";
                node["ws-opts"]["path"] = s(v.value("path").toString("/"));
                node["ws-opts"]["headers"]["Host"] = s(v.value("host").toString());
            } else if (net == "grpc") {
                node["network"] = "grpc";
                node["grpc-opts"]["grpc-service-name"] = s(v.value("path").toString());
            } else if (!net.isEmpty() && net != "tcp")
                throw std::runtime_error("暂不支持此 VMess 传输类型");
            node["tls"] = v.value("tls").toString() == "tls";
            if (!v.value("sni").toString().isEmpty())
                node["servername"] = s(v.value("sni").toString());
        } else if (type == "ss") {
            QString auth = u.userInfo();
            QString host = u.host();
            int port = u.port();
            if (host.isEmpty()) {
                auto decoded = QString::fromUtf8(decode64(line.mid(5).section('#', 0, 0).toUtf8()));
                auto address = QUrl("ss://" + decoded);
                auth = address.userInfo();
                host = address.host();
                port = address.port();
            }
            if (!auth.contains(':'))
                auth = QString::fromUtf8(decode64(auth.toUtf8()));
            if (!auth.contains(':') || host.isEmpty() || port <= 0)
                throw std::runtime_error("Shadowsocks 链接无效");
            node["type"] = "ss";
            node["server"] = s(host);
            node["port"] = port;
            node["cipher"] = s(auth.section(':', 0, 0));
            node["password"] = s(auth.section(':', 1));
            if (q.hasQueryItem("plugin"))
                throw std::runtime_error("带插件的 Shadowsocks 链接请导入完整 Mihomo YAML，避免丢失插件配置");
        } else if (type == "vless" || type == "trojan" || type == "hysteria2" || type == "hy2") {
            const bool hy = type == "hysteria2" || type == "hy2";
            node["type"] = hy ? "hysteria2" : s(type);
            node["server"] = s(u.host());
            node["port"] = u.port(hy ? 443 : 443);
            node[type == "vless" ? "uuid" : "password"] =
                s(QUrl::fromPercentEncoding(u.userInfo(QUrl::FullyEncoded).toUtf8()));
            const QString security = q.queryItemValue("security");
            if (!hy)
                node["tls"] = type == "trojan" || security == "tls" || security == "reality";
            const auto sni = q.queryItemValue("sni");
            if (!sni.isEmpty())
                node[hy ? "sni" : "servername"] = s(sni);
            node["skip-cert-verify"] =
                q.queryItemValue("insecure") == "1" || q.queryItemValue("allowInsecure") == "1";
            if (type == "vless" && !q.queryItemValue("flow").isEmpty())
                node["flow"] = s(q.queryItemValue("flow"));
            if (!q.queryItemValue("fp").isEmpty())
                node["client-fingerprint"] = s(q.queryItemValue("fp"));
            if (security == "reality") {
                node["reality-opts"]["public-key"] = s(q.queryItemValue("pbk"));
                node["reality-opts"]["short-id"] = s(q.queryItemValue("sid"));
            }
            const auto net = q.queryItemValue("type");
            if (net == "ws") {
                node["network"] = "ws";
                node["ws-opts"]["path"] = s(q.queryItemValue("path"));
                node["ws-opts"]["headers"]["Host"] = s(q.queryItemValue("host"));
            } else if (net == "grpc") {
                node["network"] = "grpc";
                node["grpc-opts"]["grpc-service-name"] = s(q.queryItemValue("serviceName"));
            } else if (!net.isEmpty() && net != "tcp")
                throw std::runtime_error("此传输类型请导入完整 Mihomo YAML");
            if (hy && !q.queryItemValue("obfs").isEmpty()) {
                node["obfs"] = s(q.queryItemValue("obfs"));
                node["obfs-password"] = s(q.queryItemValue("obfs-password"));
            }
        } else
            throw std::runtime_error(QString("无法识别的节点协议：%1").arg(type).toStdString());
        if (name.isEmpty())
            name = QString("节点 %1").arg(++counter);
        while (used.contains(name))
            name += " ·";
        used.insert(name);
        node["name"] = s(name);
        node["udp"] = true;
        nodes.push_back(node);
        names.push_back(s(name));
    }
    if (nodes.size() == 0)
        throw std::runtime_error("未找到有效节点或 Mihomo 配置");
    profile["proxies"] = nodes;
    profile["proxy-groups"][0]["proxies"] = names;
    return profile;
}
QByteArray makeRuntimeProfile(const QByteArray &source, int mixed, int controller, const QString &secret,
                              bool tun, const QJsonObject &routing) {
    if (mixed < 1024 || mixed > 65535 || controller < 1024 || controller > 65535 || mixed == controller)
        throw std::runtime_error("代理端口和控制端口必须不同，范围为 1024～65535");
    auto p = source.isEmpty() ? baseProfile() : profileFromText(source);
    p["mixed-port"] = mixed;
    p["external-controller"] = s(QString("127.0.0.1:%1").arg(controller));
    p["secret"] = s(secret);
    p["allow-lan"] = false;
    p["find-process-mode"] = "always";
    p["tun"]["enable"] = tun;
    if (tun) {
        p["tun"]["stack"] = "mixed";
        p["tun"]["auto-route"] = true;
        p["tun"]["auto-detect-interface"] = true;
        p["tun"]["dns-hijack"].push_back("any:53");
        p["dns"]["enable"] = true;
        if (!p["dns"]["enhanced-mode"])
            p["dns"]["enhanced-mode"] = "fake-ip";
        if (!p["dns"]["nameserver"]) {
            p["dns"]["nameserver"].push_back("https://dns.alidns.com/dns-query");
            p["dns"]["nameserver"].push_back("https://1.1.1.1/dns-query");
        }
    }
    YAML::Node rules(YAML::NodeType::Sequence);
    QString routingGroup = "DIRECT";
    if (p["proxy-groups"].IsSequence())
        for (const auto &group : p["proxy-groups"]) {
            if (!group["name"].IsScalar())
                continue;
            const auto name = QString::fromStdString(group["name"].as<std::string>());
            if (routingGroup == "DIRECT" || name == "六角选择")
                routingGroup = name;
            if (name == "六角选择")
                break;
        }
    for (const auto &rule : {"DOMAIN,localhost,DIRECT", "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
                             "IP-CIDR6,::1/128,DIRECT,no-resolve"})
        rules.push_back(rule);
    if (routing.value("enabled").toBool(true))
        for (const auto &value : routing.value("rules").toArray()) {
            auto r = value.toObject();
            auto process = r.value("process_name").toString();
            if (r.value("enabled").toBool(true) && !process.isEmpty() && !process.contains(',') &&
                !process.contains('\n'))
                rules.push_back(s("PROCESS-NAME," + process + "," +
                                  (r.value("target") == "direct" ? QString("DIRECT") : routingGroup)));
        }
    if (p["rules"].IsSequence())
        for (const auto &r : p["rules"])
            rules.push_back(r);
    else
        rules.push_back("MATCH,DIRECT");
    p["rules"] = rules;
    YAML::Emitter out;
    out << p;
    return QByteArray(out.c_str());
}
ProxyService::ProxyService(Storage &storage, QObject *parent)
    : QObject(parent), store(storage), api(this), downloads(this), process(this), poll(this),
      failoverTimer(this) {
    hiddenProcess(&process);
    process.setWorkingDirectory(store.runtime());
    connect(&process, &QProcess::readyReadStandardError, this, [this] {
        coreOutput += QString::fromUtf8(process.readAllStandardError());
        coreOutput = coreOutput.right(6000);
    });
    connect(&process, &QProcess::readyReadStandardOutput, this, [this] {
        const auto text = QString::fromUtf8(process.readAllStandardOutput());
        coreOutput = (coreOutput + text).right(6000);
    });
    connect(&process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            busy = false;
            fail("内核无法启动：" + process.errorString());
        }
    });
    connect(&process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus) {
        const bool crashed = wantRunning;
        connected = false;
        busy = false;
        setSystemProxy(false);
        emit changed();
        if (crashed)
            fail(QString("内核退出（%1）：%2").arg(code).arg(coreOutput.right(1800)));
    });
    connect(&poll, &QTimer::timeout, this, &ProxyService::refresh);
    poll.setInterval(2000);
    auto failover = readObject(store.file("node_failover.json"));
    failoverTimer.setInterval(
        qBound(5, failover.value("settings").toObject().value("probe_interval_sec").toInt(10), 300) * 1000);
    connect(&failoverTimer, &QTimer::timeout, this, &ProxyService::checkFailover);
    if (!store.settings.contains("controller_secret")) {
        store.settings["controller_secret"] = randomId();
        store.saveSettings();
    }
}
QString ProxyService::corePath() const {
    return store.runtime("mihomo.exe");
}
QString ProxyService::controlSecret() const {
    return store.settings.value("controller_secret").toString();
}
void ProxyService::fail(const QString &m) {
    lastError = m;
    emit logged(m);
    emit changed();
}
void ProxyService::start(bool useSystemProxy) {
    if (busy || process.state() != QProcess::NotRunning)
        return;
    QTcpServer a, b;
    if (!a.listen(QHostAddress::LocalHost, store.mixedPort()) ||
        !b.listen(QHostAddress::LocalHost, store.controllerPort())) {
        fail(QString("代理端口 %1 或控制端口 %2 已被占用，请先断开旧版代理后重试。")
                 .arg(store.mixedPort())
                 .arg(store.controllerPort()));
        return;
    }
    if (tunEnabled) {
        BOOL admin = FALSE;
        SID_IDENTIFIER_AUTHORITY nt = SECURITY_NT_AUTHORITY;
        PSID group = nullptr;
        if (AllocateAndInitializeSid(&nt, 2, SECURITY_BUILTIN_DOMAIN_RID, DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0,
                                     0, 0, &group)) {
            CheckTokenMembership(nullptr, group, &admin);
            FreeSid(group);
        }
        if (!admin) {
            fail("TUN 需要管理员权限，请以管理员身份启动 HexagonProxy。");
            return;
        }
    }
    enableSystemProxyOnConnect = useSystemProxy && !tunEnabled;
    busy = true;
    const auto epoch = ++generation;
    lastError.clear();
    emit changed();
    QDir().mkpath(store.runtime());
    if (!QFile::exists(corePath())) {
        auto source = store.settings.value("core_source").toString();
        if (source.isEmpty() || !QFile::exists(source)) {
            busy = false;
            fail("尚未安装 Mihomo 内核，请到设置下载。");
            return;
        }
        auto watcher = new QFutureWatcher<bool>(this);
        connect(watcher, &QFutureWatcher<bool>::finished, this, [this, watcher, epoch] {
            bool ok = watcher->result();
            watcher->deleteLater();
            if (epoch != generation)
                return;
            if (ok)
                launchPrepared();
            else {
                busy = false;
                fail("无法导入旧版内核，原文件未修改。");
            }
        });
        auto target = corePath();
        watcher->setFuture(
            QtConcurrent::run([source, target] { return writeBytes(target, readBytes(source)); }));
    } else
        launchPrepared();
}
void ProxyService::launchPrepared() {
    try {
        for (const auto &name : {"geosite-cn.mrs", "geoip-cn.mrs"}) {
            const auto target = store.runtime("rules/" + QString(name));
            if (!QFile::exists(target)) {
                QString e;
                const auto data = readBytes(resourcePath("third_party/meta-rules-dat/" + QString(name)));
                if (data.isEmpty() || !writeBytes(target, data, &e))
                    throw std::runtime_error(("本地路由资源缺失：" + QString(name) + " " + e).toStdString());
            }
        }
        auto yaml = makeRuntimeProfile(readBytes(store.file("profiles/active.yaml")), store.mixedPort(),
                                       store.controllerPort(), controlSecret(), tunEnabled,
                                       readObject(store.file("application_routing.json")));
        QString error;
        if (!writeBytes(store.runtime("native.yaml"), yaml, &error))
            throw std::runtime_error(error.toStdString());
        const auto epoch = generation;
        runProcess(this, corePath(), {"-t", "-d", store.runtime(), "-f", store.runtime("native.yaml")},
                   [this, epoch](int code, QByteArray out, QByteArray err) {
                       if (epoch != generation)
                           return;
                       if (code != 0) {
                           busy = false;
                           fail("配置校验失败：" + QString::fromUtf8(out + err).right(2000));
                           return;
                       }
                       coreOutput.clear();
                       wantRunning = true;
                       healthFailures = 0;
                       process.start(corePath(), {"-d", store.runtime(), "-f", store.runtime("native.yaml")});
                       poll.start();
                       QTimer::singleShot(400, this, &ProxyService::refresh);
                   });
    } catch (const std::exception &e) {
        busy = false;
        fail(QString::fromUtf8(e.what()));
    }
}
void ProxyService::stop() {
    enableSystemProxyOnConnect = false;
    ++generation;
    const auto epoch = generation;
    wantRunning = false;
    poll.stop();
    failoverTimer.stop();
    probePending = false;
    nodeFailures = 0;
    setSystemProxy(false);
    connected = false;
    busy = false;
    if (process.state() != QProcess::NotRunning) {
        process.terminate();
        QTimer::singleShot(2000, &process, [this, epoch] {
            if (generation == epoch && process.state() != QProcess::NotRunning)
                process.kill();
        });
    }
    emit changed();
}
void ProxyService::shutdown() {
    stop();
}
void ProxyService::request(const QString &endpoint, const QByteArray &method, const QJsonObject &body,
                           JsonCallback cb) {
    api.request(
        QUrl(QString("http://127.0.0.1:%1%2").arg(store.controllerPort()).arg(endpoint)), method,
        body.isEmpty() ? QByteArray() : QJsonDocument(body).toJson(QJsonDocument::Compact),
        {{"Authorization", "Bearer " + controlSecret().toUtf8()}, {"Content-Type", "application/json"}},
        [cb](QByteArray data, QString error) {
            auto value = QJsonDocument::fromJson(data).object();
            value["ok"] = error.isEmpty();
            if (!error.isEmpty())
                value["message"] = error;
            cb(value);
        });
}
void ProxyService::refresh() {
    if (process.state() == QProcess::NotRunning)
        return;
    request("/version", "GET", {}, [this](QJsonObject v) {
        if (!wantRunning || process.state() == QProcess::NotRunning)
            return;
        if (!v.value("ok").toBool()) {
            if (++healthFailures > 8) {
                busy = false;
                fail("控制接口尚未就绪：" + v.value("message").toString() + "\n" + coreOutput.right(700));
            }
            return;
        }
        healthFailures = 0;
        if (!connected) {
            connected = true;
            failoverTimer.start();
            busy = false;
            if (std::exchange(enableSystemProxyOnConnect, false)) {
                QString error;
                if (!setSystemProxy(true, &error))
                    fail("内核已启动，Windows 系统代理未接通：" + error);
            }
            emit logged("Mihomo 控制接口已连接");
            emit changed();
            request("/proxies", "GET", {}, [this](QJsonObject p) {
                proxies = p.value("proxies").toObject();
                emit nodesChanged();
            });
        }
    });
    if (connected)
        request("/connections", "GET", {}, [this](QJsonObject c) {
            if (c.value("ok").toBool()) {
                connections = c;
                emit trafficChanged(c);
            }
        });
}
void ProxyService::setMode(const QString &value) {
    if (!QStringList{"rule", "global", "direct"}.contains(value))
        return;
    request("/configs", "PATCH", {{"mode", value}}, [this, value](QJsonObject r) {
        if (r.value("ok").toBool()) {
            mode = value;
            emit changed();
        } else
            fail(r.value("message").toString());
    });
}
void ProxyService::selectNode(const QString &group, const QString &node) {
    request("/proxies/" + QString::fromLatin1(QUrl::toPercentEncoding(group)), "PUT", {{"name", node}},
            [this, group, node](QJsonObject r) {
                if (!r.value("ok").toBool()) {
                    fail(r.value("message").toString());
                    return;
                }
                auto p = proxies.value(group).toObject();
                p["now"] = node;
                proxies[group] = p;
                emit nodesChanged();
                emit logged("已切换节点：" + node);
            });
}
void ProxyService::testNode(const QString &name, JsonCallback cb) {
    request("/proxies/" + QString::fromLatin1(QUrl::toPercentEncoding(name)) +
                "/delay?timeout=6000&url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204",
            "GET", {}, std::move(cb));
}
void ProxyService::toggleBackup(const QString &group, const QString &node) {
    if (group.isEmpty() || node.isEmpty())
        return;
    auto state = readObject(store.file("node_failover.json"));
    auto items = state.value("backups").toArray();
    bool removed = false;
    for (qsizetype i = 0; i < items.size(); ++i) {
        auto item = items[i].toObject();
        if (item.value("group") == group && item.value("node") == node) {
            items.removeAt(i);
            removed = true;
            break;
        }
    }
    if (!removed)
        items.append(QJsonObject{{"group", group}, {"node", node}});
    state["backups"] = items;
    QString e;
    if (!writeObject(store.file("node_failover.json"), state, &e))
        fail(e);
    else
        emit nodesChanged();
}
void ProxyService::checkFailover() {
    auto state = readObject(store.file("node_failover.json"));
    if (!connected || probePending || !state.value("enabled").toBool(true) || mode == "direct")
        return;
    if (lastSwitch.isValid() &&
        lastSwitch.elapsed() < state.value("settings").toObject().value("cooldown_sec").toInt(30) * 1000)
        return;
    QString group = mode == "global" ? "GLOBAL" : "六角选择";
    if (!proxies.contains(group))
        return;
    auto current = proxies.value(group).toObject().value("now").toString();
    if (current.isEmpty() || current == "DIRECT" || current == "REJECT")
        return;
    probePending = true;
    auto epoch = generation;
    testNode(current, [this, state, group, current, epoch](QJsonObject result) {
        probePending = false;
        if (epoch != generation || proxies.value(group).toObject().value("now").toString() != current)
            return;
        if (result.value("ok").toBool() && result.value("delay").toInt() > 0) {
            nodeFailures = 0;
            return;
        }
        if (++nodeFailures < state.value("settings").toObject().value("failure_threshold").toInt(2))
            return;
        QStringList candidates;
        for (auto value : state.value("backups").toArray()) {
            auto b = value.toObject();
            if (b.value("group") == group && b.value("node") != current)
                candidates << b.value("node").toString();
        }
        if (candidates.isEmpty()) {
            emit logged("当前节点连续探测失败；请在节点页标记备选节点");
            nodeFailures = 0;
            return;
        }
        probePending = true;
        tryBackup(candidates, 0, group, current, epoch);
    });
}
void ProxyService::tryBackup(QStringList candidates, int index, QString group, QString current,
                             quint64 epoch) {
    if (index >= candidates.size() || epoch != generation || !connected ||
        proxies.value(group).toObject().value("now").toString() != current) {
        probePending = false;
        nodeFailures = 0;
        return;
    }
    auto candidate = candidates[index];
    testNode(candidate, [this, candidates, index, group, current, epoch, candidate](QJsonObject result) {
        if (epoch != generation) {
            probePending = false;
            return;
        }
        int delay = result.value("delay").toInt();
        if (result.value("ok").toBool() && delay > 0 && delay <= 5000) {
            probePending = false;
            nodeFailures = 0;
            lastSwitch.start();
            if (proxies.value(group).toObject().value("now").toString() == current) {
                selectNode(group, candidate);
                emit logged("自动故障切换：" + candidate);
            }
            return;
        }
        tryBackup(candidates, index + 1, group, current, epoch);
    });
}
bool ProxyService::setSystemProxy(bool enable, QString *error) {
    if (enable && !connected) {
        if (error)
            *error = "请先连接代理";
        return false;
    }
    if (enable && tunEnabled) {
        if (error)
            *error = "TUN 与系统代理互斥，请先停用 TUN";
        return false;
    }
    QSettings reg("HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings",
                  QSettings::NativeFormat);
    if (enable) {
        if (!systemEnabled) {
            QJsonObject backup;
            for (const auto &k : {"ProxyEnable", "ProxyServer", "ProxyOverride"})
                backup[k] = QJsonObject{{"exists", reg.contains(k)},
                                        {"value", QJsonValue::fromVariant(reg.value(k))}};
            if (!writeObject(store.file("native-proxy-backup.json"), backup, error))
                return false;
        }
        reg.setValue("ProxyEnable", 1);
        reg.setValue("ProxyServer", QString("127.0.0.1:%1").arg(store.mixedPort()));
        reg.setValue("ProxyOverride", "<local>;localhost;127.*;10.*;192.168.*");
    } else if (systemEnabled) {
        const QString ours = QString("127.0.0.1:%1").arg(store.mixedPort());
        if (reg.value("ProxyServer").toString() == ours) {
            const auto backup = readObject(store.file("native-proxy-backup.json"));
            for (const auto &k : {"ProxyEnable", "ProxyServer", "ProxyOverride"}) {
                auto item = backup.value(k).toObject();
                if (item.value("exists").toBool()) {
                    const auto value = item.value("value");
                    if (QLatin1StringView(k) == "ProxyEnable")
                        reg.setValue(k, value.toInt());
                    else
                        reg.setValue(k, value.toString());
                } else
                    reg.remove(k);
            }
        }
    }
    reg.sync();
    if (reg.status() != QSettings::NoError) {
        if (error)
            *error = "Windows 代理设置写入失败";
        return false;
    }
    systemEnabled = enable;
    InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
    InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
    emit changed();
    return true;
}
QJsonObject ProxyService::subscriptions() const {
    return readObject(store.file("profiles/library/index.json"));
}
void ProxyService::importSubscription(const QString &name, const QString &source) {
    auto save = [this, name, source](QByteArray text, QString error) {
        if (!error.isEmpty()) {
            fail(error);
            return;
        }
        try {
            auto p = profileFromText(text);
            YAML::Emitter out;
            out << p;
            auto index = subscriptions();
            auto items = index.value("subscriptions").toArray();
            QString id = randomId();
            QJsonObject item{{"id", id},
                             {"name", name.isEmpty() ? QString("订阅 %1").arg(items.size() + 1) : name},
                             {"type", source.startsWith("http") ? "http" : "local"},
                             {"url", source.startsWith("http") ? source : QString()},
                             {"config_file", id + ".yaml"}};
            QString e;
            if (!writeBytes(store.file("profiles/library/" + id + ".yaml"), QByteArray(out.c_str()), &e))
                throw std::runtime_error(e.toStdString());
            items.append(item);
            index["subscriptions"] = items;
            if (!writeObject(store.file("profiles/library/index.json"), index, &e))
                throw std::runtime_error(e.toStdString());
            emit subscriptionsChanged();
            activateSubscription(id);
        } catch (const std::exception &e) {
            fail(QString::fromUtf8(e.what()));
        }
    };
    if (source.startsWith("https://") || source.startsWith("http://"))
        downloads.get(QUrl(source), save, 60000, true);
    else
        save(QFile::exists(source) ? readBytes(source) : source.toUtf8(), {});
}
void ProxyService::activateSubscription(const QString &id) {
    if (process.state() != QProcess::NotRunning) {
        fail("请先断开代理，再切换订阅配置。");
        return;
    }
    auto index = subscriptions();
    for (const auto &v : index.value("subscriptions").toArray()) {
        auto item = v.toObject();
        if (item.value("id") != id)
            continue;
        const auto file = item.value("config_file").toString();
        if (QFileInfo(file).fileName() != file) {
            fail("订阅配置路径无效");
            return;
        }
        auto data = readBytes(store.file("profiles/library/" + file));
        QString e;
        if (data.isEmpty() || !writeBytes(store.file("profiles/active.yaml"), data, &e)) {
            fail("无法切换订阅：" + e);
            return;
        }
        index["active_id"] = id;
        if (!writeObject(store.file("profiles/library/index.json"), index, &e)) {
            fail(e);
            return;
        }
        emit subscriptionsChanged();
        emit logged("已选择订阅：" + item.value("name").toString());
        return;
    }
}
void ProxyService::removeSubscription(const QString &id) {
    auto index = subscriptions();
    if (index.value("active_id") == id) {
        fail("请先选择其他订阅，再删除当前订阅。");
        return;
    }
    auto items = index.value("subscriptions").toArray();
    for (qsizetype i = 0; i < items.size(); ++i)
        if (items[i].toObject().value("id") == id) {
            items.removeAt(i);
            break;
        }
    index["subscriptions"] = items;
    QString e;
    if (!writeObject(store.file("profiles/library/index.json"), index, &e))
        fail(e);
    else
        emit subscriptionsChanged();
}
void ProxyService::refreshSubscription(const QString &id) {
    for (const auto &v : subscriptions().value("subscriptions").toArray()) {
        auto item = v.toObject();
        if (item.value("id") != id)
            continue;
        const auto url = item.value("url").toString();
        if (url.isEmpty()) {
            fail("本地配置没有可刷新的订阅地址。");
            return;
        }
        downloads.get(
            QUrl(url),
            [this, item, id](QByteArray data, QString e) {
                if (!e.isEmpty()) {
                    fail(e);
                    return;
                }
                try {
                    auto p = profileFromText(data);
                    YAML::Emitter out;
                    out << p;
                    if (!writeBytes(store.file("profiles/library/" + item.value("config_file").toString()),
                                    QByteArray(out.c_str()), &e))
                        throw std::runtime_error(e.toStdString());
                    if (subscriptions().value("active_id") == id && process.state() == QProcess::NotRunning)
                        activateSubscription(id);
                    emit logged("订阅已更新");
                } catch (const std::exception &x) {
                    fail(QString::fromUtf8(x.what()));
                }
            },
            60000, true);
        return;
    }
}

QJsonObject selectWindowsCore(const QJsonArray &assets) {
    QJsonObject best;
    int rank = 999;
    for (auto value : assets) {
        auto item = value.toObject();
        auto name = item.value("name").toString();
        const bool archive = name.endsWith(".zip") || name.endsWith(".gz");
        int score = name.startsWith("mihomo-windows-amd64-compatible-") ? 0
                    : name.startsWith("mihomo-windows-amd64-v1-v")      ? 1
                                                                        : 999;
        auto url = QUrl(item.value("browser_download_url").toString());
        auto digest = item.value("digest").toString();
        if (archive && score < rank && url.scheme() == "https" && url.host() == "github.com" &&
            url.path().startsWith("/MetaCubeX/mihomo/releases/download/") &&
            QRegularExpression("^sha256:[a-fA-F0-9]{64}$").match(digest).hasMatch()) {
            rank = score;
            best = item;
        }
    }
    return best;
}
QJsonArray coreAssetsFromHtml(const QByteArray &html) {
    QJsonArray assets;
    for (const auto &block : QString::fromUtf8(html).split("</li>")) {
        auto link = QRegularExpression("href=\"(/MetaCubeX/mihomo/releases/download/[^\"<>]+/([^/\"<>]+))\"")
                        .match(block);
        auto digest = QRegularExpression("sha256:([a-fA-F0-9]{64})").match(block);
        if (link.hasMatch() && digest.hasMatch())
            assets.append(QJsonObject{{"name", link.captured(2)},
                                      {"browser_download_url", "https://github.com" + link.captured(1)},
                                      {"digest", "sha256:" + digest.captured(1)}});
    }
    return assets;
}
void ProxyService::downloadCore(bool releasePage) {
    if (busy || process.state() != QProcess::NotRunning) {
        fail("请先断开代理并等待当前操作完成。");
        return;
    }
    busy = true;
    downloading = true;
    lastError.clear();
    emit changed();
    emit logged("正在查询 Mihomo 官方发布…");
    if (releasePage) {
        downloadCoreFromReleasePage("使用官方发布页通道");
        return;
    }
    downloads.get(
        QUrl("https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"),
        [this](QByteArray data, QString error) {
            auto selected =
                selectWindowsCore(QJsonDocument::fromJson(data).object().value("assets").toArray());
            if (!error.isEmpty() || selected.isEmpty()) {
                downloadCoreFromReleasePage(error.isEmpty() ? "API 返回的资源列表缺少可校验的兼容内核"
                                                            : error);
                return;
            }
            installDownloadedCore(selected.value("browser_download_url").toString(),
                                  selected.value("digest").toString().mid(7),
                                  selected.value("name").toString());
        },
        20000, true);
}
void ProxyService::downloadCoreFromReleasePage(const QString &apiError) {
    emit logged("API 查询未完成，改用 GitHub 官方发布页：" + apiError);
    downloads.get(
        QUrl("https://github.com/MetaCubeX/mihomo/releases/latest"),
        [this, apiError](QByteArray html, QString error) {
            auto tag =
                QRegularExpression("/MetaCubeX/mihomo/releases/expanded_assets/(v[0-9][a-zA-Z0-9.\\-]*)")
                    .match(QString::fromUtf8(html));
            if (!error.isEmpty() || !tag.hasMatch()) {
                busy = false;
                downloading = false;
                fail("查询官方发布失败。API：" + apiError + "；发布页：" +
                     (error.isEmpty() ? "未识别发布标签" : error));
                return;
            }
            downloads.get(
                QUrl("https://github.com/MetaCubeX/mihomo/releases/expanded_assets/" + tag.captured(1)),
                [this](QByteArray assets, QString failure) {
                    auto selected = selectWindowsCore(coreAssetsFromHtml(assets));
                    if (!failure.isEmpty() || selected.isEmpty()) {
                        busy = false;
                        downloading = false;
                        fail("读取官方 Windows x64 下载资源失败：" +
                             (failure.isEmpty() ? "未识别 ZIP/GZIP 地址或 SHA256，请稍后重试" : failure));
                        return;
                    }
                    installDownloadedCore(selected.value("browser_download_url").toString(),
                                          selected.value("digest").toString().mid(7),
                                          selected.value("name").toString());
                },
                20000, true);
        },
        20000, true);
}
void ProxyService::installDownloadedCore(const QString &url, const QString &digest, const QString &name) {
    emit logged("正在下载 Mihomo：" + name);
    downloads.get(
        QUrl(url),
        [this, digest, name](QByteArray data, QString error) {
            if (!error.isEmpty()) {
                busy = false;
                downloading = false;
                fail(error);
                return;
            }
            if (digest.isEmpty() ||
                QString::fromLatin1(QCryptographicHash::hash(data, QCryptographicHash::Sha256).toHex()) !=
                    digest) {
                busy = false;
                downloading = false;
                fail("内核下载缺少校验摘要或 SHA256 不匹配，未安装。");
                return;
            }
            const auto archive =
                store.runtime(name.endsWith(".zip") ? "mihomo-download.zip" : "mihomo-download.gz");
            const auto staged = store.runtime("mihomo-new.exe");
            if (!writeBytes(archive, data, &error)) {
                busy = false;
                downloading = false;
                fail(error);
                return;
            }
            const auto script = store.runtime("expand-core.ps1");
            const QByteArray extraction = R"PS(param([string]$Source,[string]$Target)
$ErrorActionPreference='Stop'
if($Source.EndsWith('.zip')){
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $zip=[IO.Compression.ZipFile]::OpenRead($Source)
 try{
  $entries=@($zip.Entries | Where-Object {$_.Name -match '^mihomo.*\.exe$' -and $_.FullName -eq $_.Name})
  if($entries.Count -ne 1){throw 'ZIP must contain exactly one top-level Mihomo executable'}
  [IO.Compression.ZipFileExtensions]::ExtractToFile($entries[0],$Target,$true)
 }finally{$zip.Dispose()}
}else{
 $i=[IO.File]::OpenRead($Source);$g=[IO.Compression.GzipStream]::new($i,[IO.Compression.CompressionMode]::Decompress)
 $o=[IO.File]::Create($Target);try{$g.CopyTo($o)}finally{$o.Dispose();$g.Dispose();$i.Dispose()}
}
)PS";
            if (!writeBytes(script, extraction, &error)) {
                busy = false;
                downloading = false;
                fail("无法准备内核解压：" + error);
                return;
            }
            runProcess(this, "powershell.exe",
                       {"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "RemoteSigned", "-File", script,
                        "-Source", archive, "-Target", staged},
                       [this, archive, staged](int code, QByteArray, QByteArray err) {
                           QFile::remove(archive);
                           if (code != 0) {
                               busy = false;
                               downloading = false;
                               fail("解压内核失败：" + QString::fromUtf8(err));
                               return;
                           }
                           runProcess(this, staged, {"-v"},
                                      [this, staged](int result, QByteArray out, QByteArray err2) {
                                          busy = false;
                                          downloading = false;
                                          if (result != 0 || !out.toLower().contains("mihomo")) {
                                              QFile::remove(staged);
                                              fail("内核可执行文件验证失败：" + QString::fromUtf8(err2));
                                              return;
                                          }
                                          const auto backup = corePath() + ".previous";
                                          QFile::remove(backup);
                                          if (QFile::exists(corePath()) &&
                                              !QFile::rename(corePath(), backup)) {
                                              fail("旧内核仍被使用，未替换");
                                              return;
                                          }
                                          if (!QFile::rename(staged, corePath())) {
                                              QFile::rename(backup, corePath());
                                              fail("新内核保存失败，旧版已恢复");
                                              return;
                                          }
                                          emit logged("Mihomo 内核已安装并验证");
                                          emit changed();
                                      });
                       });
        },
        180000, true);
}
} // namespace hexagon
