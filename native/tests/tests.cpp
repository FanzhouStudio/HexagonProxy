#include "main_window.h"
#include "layouts.h"
#include <QNetworkProxy>
#include <QTcpServer>
#include <QtTest>
using namespace hexagon;
class NativeTests : public QObject {
    Q_OBJECT
  private slots:
    void initTestCase() {
        QFontDatabase::addApplicationFont(qEnvironmentVariable("WINDIR") + "/Fonts/msyh.ttc");
    }
    void diskBounds() {
        QCOMPARE(linuxDiskBytes(1), qint64(1073741824) - 16777216);
        QVERIFY(linuxDiskBytes(10) < qint64(10) * 1073741824);
        QVERIFY_EXCEPTION_THROWN(linuxDiskBytes(0), std::runtime_error);
        QVERIFY_EXCEPTION_THROWN(linuxDiskBytes(11), std::runtime_error);
    }
    void identity() {
        QVERIFY(AccountsService::sameIdentity({{"account_id", "a"}, {"email", "A@b.com"}},
                                              {{"account_id", "a"}, {"email", "a@b.com"}}));
        QVERIFY(!AccountsService::sameIdentity({{"account_id", "a"}}, {{"account_id", "b"}}));
    }
    void windowsCoreAssets() {
        auto asset = [](QString name) {
            return QJsonObject{{"name", name},
                               {"browser_download_url",
                                "https://github.com/MetaCubeX/mihomo/releases/download/v1.2.3/" + name},
                               {"digest", "sha256:" + QString(64, 'a')}};
        };
        QCOMPARE(selectWindowsCore({asset("mihomo-windows-amd64-v3-v1.2.3.zip"),
                                    asset("mihomo-windows-amd64-compatible-v1.2.3.zip")})
                     .value("name")
                     .toString(),
                 QString("mihomo-windows-amd64-compatible-v1.2.3.zip"));
        QVERIFY(!selectWindowsCore({asset("mihomo-windows-amd64-compatible-v1.2.3.gz")}).isEmpty());
        QVERIFY(selectWindowsCore({asset("mihomo-linux-amd64-v1.2.3.gz")}).isEmpty());
        auto html = QByteArray("<li><a "
                               "href=\"/MetaCubeX/mihomo/releases/download/v1.2.3/"
                               "mihomo-windows-amd64-compatible-v1.2.3.zip\">core</a><span>sha256:") +
                    QByteArray(64, 'a') + "</span></li>";
        QCOMPARE(coreAssetsFromHtml(html).size(), 1);
        QVERIFY(!selectWindowsCore(coreAssetsFromHtml(html)).isEmpty());
        html.replace("sha256:", "unverified:");
        QVERIFY(selectWindowsCore(coreAssetsFromHtml(html)).isEmpty());
    }
    void listPagination() {
        QWidget host;
        QVBoxLayout layout(&host);
        auto table = new PagedTree;
        layout.addWidget(table);
        auto row = new QHBoxLayout;
        layout.addLayout(row);
        table->previous = new QPushButton("上一页");
        table->next = new QPushButton("下一页");
        table->counter = new QLabel;
        row->addWidget(table->previous);
        row->addWidget(table->counter);
        row->addWidget(table->next);
        for (int i = 0; i < 60; ++i)
            new QTreeWidgetItem(table, {QString("model %1").arg(i)});
        host.resize(600, 320);
        host.show();
        QTest::qWait(30);
        table->paginate();
        QVERIFY(table->perPage < 60);
        QVERIFY(!table->topLevelItem(0)->isHidden());
        QVERIFY(table->topLevelItem(table->perPage)->isHidden());
        table->setCurrentItem(table->topLevelItem(0));
        table->page = 1;
        table->paginate();
        QVERIFY(table->topLevelItem(0)->isHidden());
        QVERIFY(!table->topLevelItem(table->perPage)->isHidden());
        QCOMPARE(table->currentItem(), table->topLevelItem(table->perPage));
        table->page = 100;
        table->paginate();
        QVERIFY(!table->next->isEnabled());
        table->clear();
        table->paginate();
        QCOMPARE(table->page, 0);
    }
    void liveCoreDownload() {
        if (qEnvironmentVariable("HEXAGON_LIVE_DOWNLOAD") != "1")
            QSKIP("Enable real official download integration");
        QTemporaryDir dir;
        Storage s(dir.path(), dir.path() + "/old");
        s.importLegacy();
        ProxyService service(s);
        for (bool releasePage : {false, true}) {
            service.downloadCore(releasePage);
            QTRY_VERIFY_WITH_TIMEOUT(!service.busy, 240000);
            QVERIFY2(service.lastError.isEmpty(), qPrintable(service.lastError));
            QVERIFY(!service.downloading);
        }
        QVERIFY(QFileInfo(service.corePath()).size() > 1000000);
        QProcess core;
        hiddenProcess(&core);
        core.start(service.corePath(), {"-v"});
        QVERIFY(core.waitForFinished(10000));
        QCOMPARE(core.exitCode(), 0);
        QVERIFY(core.readAllStandardOutput().toLower().contains("mihomo"));
        QTcpServer mixed, controller;
        QVERIFY(mixed.listen(QHostAddress::LocalHost, 0));
        QVERIFY(controller.listen(QHostAddress::LocalHost, 0));
        s.settings["mixed_port"] = mixed.serverPort();
        s.settings["controller_port"] = controller.serverPort();
        mixed.close();
        controller.close();
        service.start();
        QTRY_VERIFY_WITH_TIMEOUT(service.connected || !service.lastError.isEmpty(), 20000);
        QVERIFY2(service.connected, qPrintable(service.lastError));
        service.stop();
        QTRY_COMPARE_WITH_TIMEOUT(service.process.state(), QProcess::NotRunning, 5000);
    }
    void linuxDirectorySelection() {
        QTemporaryDir dir;
        Storage s(dir.path() + "/config", dir.path() + "/old");
        s.importLegacy();
        LinuxWorkspace service(s);
        const auto original = service.root();
        writeBytes(original + "/keep.txt", "original");
        const auto selected = dir.path() + QString::fromUtf8("/Linux 工作区 custom");
        QVERIFY(service.setDirectory(selected));
        QCOMPARE(service.root(), QDir(selected).canonicalPath());
        QCOMPARE(readBytes(original + "/keep.txt"), QByteArray("original"));
        service.busy = true;
        QVERIFY(!service.setDirectory(original));
        service.busy = false;
        const auto foreign = dir.path() + "/foreign";
        writeBytes(foreign + "/linux.qcow2", "foreign-data");
        QVERIFY(!service.setDirectory(foreign));
        QCOMPARE(readBytes(foreign + "/linux.qcow2"), QByteArray("foreign-data"));
        Storage reloaded(s.root, dir.path() + "/old");
        QCOMPARE(reloaded.linuxRoot(), service.root());
    }
    void profile() {
        auto p = profileFromText("vless://abc@example.com:443?security=tls&sni=example.com#demo");
        QCOMPARE(QString::fromStdString(p["proxies"][0]["name"].as<std::string>()), QString("demo"));
        QJsonObject routing{
            {"enabled", true},
            {"rules", QJsonArray{QJsonObject{
                          {"process_name", "example.exe"}, {"enabled", true}, {"target", "direct"}}}}};
        auto bytes = makeRuntimeProfile({}, 7891, 19091, "secret", false, routing);
        auto yaml = YAML::Load(bytes.toStdString());
        QCOMPARE(yaml["mixed-port"].as<int>(), 7891);
        QCOMPARE(QString::fromStdString(yaml["rules"][3].as<std::string>()),
                 QString("PROCESS-NAME,example.exe,DIRECT"));
        QVERIFY_EXCEPTION_THROWN(makeRuntimeProfile({}, 7890, 7890, "", false, {}), std::runtime_error);
    }
    void legacyImport() {
        QTemporaryDir dir;
        auto old = dir.path() + "/old", now = dir.path() + "/new";
        writeObject(old + "/codex_profiles.json",
                    {{"accounts",
                      QJsonArray{QJsonObject{{"id", "a"}, {"name", "old"}, {"snapshot_path", "C:/saved/a"}}}},
                     {"selected_id", "a"}});
        writeBytes(old + "/proxy_settings.cfg", "[network]\nmixed_port=7892\ncontroller_port=19092\n");
        Storage s(now, old);
        s.importLegacy();
        QCOMPARE(s.mixedPort(), 7892);
        QCOMPARE(readObject(s.file("codex_profiles.json")).value("selected_id").toString(), QString("a"));
        QVERIFY(QFile::exists(old + "/codex_profiles.json"));
        s.settings["mixed_port"] = 8000;
        s.saveSettings();
        s.importLegacy();
        QCOMPARE(s.mixedPort(), 8000);
    }
    void recoverLegacyProviderSubscription() {
        QTemporaryDir dir;
        const auto old = dir.path() + "/old";
        Storage store(dir.path() + "/new", old);
        const auto index = QString("profiles/library/index.json");
        const auto provider = QString("runtime/providers/library/old-v2.txt");
        const QByteArray direct = "proxies: []\nproxy-groups: []\n";
        const QByteArray legacy =
            "proxy-providers:\n  old-v2:\n    type: file\n    path: ./providers/library/old-v2.txt\n";
        const QJsonObject oldEntry{{"id", "old"}, {"type", "v2"}, {"config_file", "old.yaml"}};
        const QJsonObject newEntry{{"id", "new"}, {"type", "local"}, {"config_file", "new.yaml"}};
        QVERIFY(
            writeObject(old + "/" + index, {{"active_id", "old"}, {"subscriptions", QJsonArray{oldEntry}}}));
        QVERIFY(writeBytes(old + "/profiles/library/old.yaml", legacy));
        QVERIFY(writeBytes(old + "/profiles/active.yaml", legacy));
        QVERIFY(writeBytes(old + "/" + provider, "test-cached-provider"));
        QVERIFY(
            writeObject(store.file(index), {{"active_id", "new"}, {"subscriptions", QJsonArray{newEntry}}}));
        QVERIFY(writeBytes(store.file("profiles/library/new.yaml"), direct));
        QVERIFY(writeBytes(store.file("profiles/active.yaml"), direct));
        store.settings["migration_version"] = 1;
        store.importLegacy();
        auto recovered = readObject(store.file(index));
        QCOMPARE(recovered.value("active_id").toString(), QString("old"));
        QCOMPARE(recovered.value("subscriptions").toArray().size(), 2);
        QCOMPARE(readBytes(store.file(provider)), QByteArray("test-cached-provider"));
        QCOMPARE(readBytes(store.file("profiles/active.yaml")), legacy);
        QCOMPARE(readBytes(store.file("profiles/active.yaml.before-migration")), direct);
        store.importLegacy();
        QCOMPARE(readObject(store.file(index)), recovered);
    }
    void uiControlsPersist() {
        QTemporaryDir dir;
        Storage s(dir.path() + "/new", dir.path() + "/empty");
        s.importLegacy();
        MainWindow w(s, true);
        w.show();
        QTest::qWait(100);
        auto min = w.findChild<QPushButton *>("minimizeButton");
        QVERIFY(min);
        auto id = min;
        auto count = w.findChildren<QWidget *>().size();
        QTest::mouseMove(min, min->rect().center());
        QTest::qWait(100);
        QCOMPARE(w.findChild<QPushButton *>("minimizeButton"), id);
        QCOMPARE(w.findChildren<QWidget *>().size(), count);
        auto font = w.findChild<QSlider *>("fontScaleSlider");
        QVERIFY(font);
        font->setValue(200);
        QTest::qWait(150);
        QCOMPARE(w.findChild<QPushButton *>("minimizeButton"), id);
        auto disk = w.findChild<QSlider *>("diskCapacitySlider");
        QCOMPARE(disk->minimum(), 1);
        QCOMPARE(disk->maximum(), 10);
    }
    void hoverPaintPersists() {
        QTemporaryDir dir;
        Storage s(dir.path(), dir.path() + "/old");
        s.importLegacy();
        MainWindow w(s, true);
        w.show();
        QTest::qWait(100);
        auto pages = w.findChild<QStackedWidget *>("pages");
        QVERIFY(pages);

        for (auto name : {"minimizeButton", "closeButton", "exitButton"}) {
            auto b = w.findChild<QPushButton *>(name);
            QVERIFY(b);
            auto id = b;
            b->setAttribute(Qt::WA_UnderMouse, false);
            QEvent leave(QEvent::Leave);
            QApplication::sendEvent(b, &leave);
            auto normal = b->grab().toImage().pixelColor(15, 6);
            QElapsedTimer timer;
            timer.start();
            const auto point = b->rect().center();
            // Drive the widget directly so the test works even when the app
            // starts hidden or another application owns the desktop cursor.
            b->setAttribute(Qt::WA_UnderMouse, true);
            QEnterEvent enter(point, b->mapTo(&w, point), b->mapToGlobal(point));
            QApplication::sendEvent(b, &enter);
            QTest::qWait(60);
            auto hover = b->grab().toImage().pixelColor(15, 6);
            QVERIFY2(hover != normal, name);
            QVERIFY(timer.elapsed() < 200);
            QTest::qWait(1400);
            QCOMPARE(b->grab().toImage().pixelColor(15, 6), hover);
            QCOMPARE(w.findChild<QPushButton *>(name), id);
            b->setAttribute(Qt::WA_UnderMouse, false);
            QApplication::sendEvent(b, &leave);
        }
    }

    void legacyPageInteractions() {
        QTemporaryDir dir;
        Storage s(dir.path(), dir.path() + "/old");
        s.importLegacy();
        s.settings["theme"] = "midnight";
        const QJsonObject imported{{"id", "fixture"}, {"type", "v2"}, {"name", "工作订阅"}};
        QVERIFY(writeObject(s.file("profiles/library/index.json"),
                            {{"active_id", "fixture"}, {"subscriptions", QJsonArray{imported}}}));
        const QJsonObject first{
            {"id", "personal"}, {"name", "个人账号"}, {"usage", QJsonObject{{"weekly", 17}}}};
        const QJsonObject second{
            {"id", "work"}, {"name", "工作账号"}, {"usage", QJsonObject{{"weekly", 74}}}};
        QVERIFY(writeObject(s.file("codex_profiles.json"),
                            {{"selected_id", "personal"}, {"accounts", QJsonArray{first, second}}}));
        MainWindow w(s, true);
        w.resize(1536, 816);
        w.show();
        w.proxy.proxies["六角选择"] =
            QJsonObject{{"now", "Tokyo"}, {"all", QJsonArray{"Tokyo", "Singapore", "Osaka"}}};
        emit w.proxy.nodesChanged();
        auto navigation = w.findChild<QListWidget *>("navigation");
        auto pages = w.findChild<QStackedWidget *>("pages");
        auto buttonOnPage = [&](const QString &text) -> QPushButton * {
            for (auto button : pages->currentWidget()->findChildren<QPushButton *>())
                if (button->text() == text && button->isVisibleTo(&w))
                    return button;
            return nullptr;
        };
        QCOMPARE(w.findChild<QComboBox *>("themeChoice")->currentData().toString(), QString("midnight"));
        QTRY_VERIFY(w.findChild<QPlainTextEdit *>("dashboardLog")->isVisibleTo(&w));
        QVERIFY(w.findChild<QWidget *>("trafficPlot")->isVisibleTo(&w));
        for (int index : {0, 1, 2, 4, 6, 7, 8}) {
            navigation->setCurrentRow(index);
            QTest::qWait(90);
            if (index == 1) {
                for (const auto &text : {QString("全部测速"), QString("选择"), QString("☆ 备选")})
                    QVERIFY2(buttonOnPage(text), qPrintable(text));
                buttonOnPage("☆ 备选")->click();
                QTRY_VERIFY(buttonOnPage("★ 备选"));
            } else if (index == 2) {
                QVERIFY(buttonOnPage("导入 V2"));
                QVERIFY(buttonOnPage("使用中"));
            } else if (index == 4) {
                QVERIFY(buttonOnPage("选择目录"));
                QVERIFY(buttonOnPage("保存命令"));
                QVERIFY(buttonOnPage("运行 / 发送"));
            } else if (index == 6) {
                QVERIFY(buttonOnPage("授权添加账号"));
                QVERIFY(buttonOnPage("查额度"));
                QVERIFY(buttonOnPage("切换"));
            } else if (index == 7) {
                QVERIFY(buttonOnPage("选择程序"));
                QVERIFY(buttonOnPage("切换"));
                QVERIFY(buttonOnPage("查看额度"));
            } else if (index == 8) {
                QVERIFY(buttonOnPage("应用窗口"));
                QVERIFY(buttonOnPage("检查并下载最新内核"));
                QVERIFY(buttonOnPage("保存端口"));
            }
            w.grab().save(resourcePath(QString("build/legacy-ui-page-%1.png").arg(index)));
        }
    }

    void layoutBounds() {
        QTemporaryDir dir;
        Storage s(dir.path(), dir.path() + "/old");
        s.importLegacy();
        MainWindow w(s, true);
        w.show();
        auto slider = w.findChild<QSlider *>("fontScaleSlider");
        auto nav = w.findChild<QListWidget *>("navigation");
        auto pages = w.findChild<QStackedWidget *>("pages");
        for (int scale : {100, 150, 200}) {
            slider->setValue(scale);
            QTest::qWait(130);
            for (auto size : {QSize(1536, 816), QSize(1280, 672), QSize(1093, 566), QSize(2048, 1104)}) {
                w.resize(size);
                QTest::qWait(30);
                QCOMPARE(w.size(), size);
                for (int page = 0; page < 9; ++page) {
                    nav->setCurrentRow(page);
                    QTest::qWait(10);
                    auto current = pages->currentWidget();
                    auto verify = [&] {
                        QTest::qWait(10);
                        for (auto button : current->findChildren<QPushButton *>())
                            if (button->isVisibleTo(&w)) {
                                auto r = QRect(button->mapTo(&w, QPoint()), button->size());
                                QVERIFY2(w.rect().contains(r),
                                         qPrintable(QString("%1% %2x%3 page %4 clipped: %5 %6,%7 %8x%9")
                                                        .arg(scale)
                                                        .arg(size.width())
                                                        .arg(size.height())
                                                        .arg(page)
                                                        .arg(button->text())
                                                        .arg(r.x())
                                                        .arg(r.y())
                                                        .arg(r.width())
                                                        .arg(r.height())));
                            }
                    };
                    for (auto tabs : current->findChildren<QTabWidget *>()) {
                        for (int t = 0; t < tabs->count(); ++t) {
                            tabs->setCurrentIndex(t);
                            verify();
                        }
                        tabs->setCurrentIndex(0);
                    }
                    for (auto tabs : current->findChildren<QTabBar *>()) {
                        if (!tabs->isVisibleTo(&w) || qobject_cast<QTabWidget *>(tabs->parentWidget()))
                            continue;
                        for (int t = 0; t < tabs->count(); ++t) {
                            tabs->setCurrentIndex(t);
                            verify();
                        }
                        tabs->setCurrentIndex(0);
                    }
                    verify();
                    QVERIFY(current->findChildren<QScrollArea *>().empty());
                    if (size == QSize(1536, 816) && scale == 150)
                        w.grab().save(resourcePath(QString("build/repaired-page-%1.png").arg(page)));
                }
                QVERIFY2(nav->visualItemRect(nav->item(8)).bottom() <= nav->viewport()->height(),
                         "navigation must not scroll to reach Settings");
            }
        }
    }
    void corruptMetadataPreserved() {
        QTemporaryDir dir;
        writeBytes(dir.path() + "/settings.json", "{broken");
        QVERIFY_THROWS_EXCEPTION(std::runtime_error, Storage(dir.path(), dir.path() + "/old"));
        QCOMPARE(readBytes(dir.path() + "/settings.json"), QByteArray("{broken"));
    }
    void accountMetadataOnlyRemoval() {
        QTemporaryDir dir;
        Storage s(dir.path(), dir.path() + "/old");
        s.importLegacy();
        auto path = s.runtime("antigravity-proxy/accounts");
        writeObject(path + "/index.json",
                    {{"original_visible", true},
                     {"default_account", "b"},
                     {"entries", QJsonArray{QJsonObject{{"id", "b"}, {"name", "new"}}}}});
        writeBytes(path + "/default/auth.txt", "retain");
        AccountsService accounts(s);
        accounts.removeAntigravity("default");
        QVERIFY(!accounts.antigravityIndex.value("original_visible").toBool());
        QCOMPARE(readBytes(path + "/default/auth.txt"), QByteArray("retain"));
        accounts.removeAntigravity("b");
        QCOMPARE(accounts.antigravityAccounts().size(), 1);
    }
    void liveCore() {
        if (qEnvironmentVariable("HEXAGON_LIVE_CORE") != "1")
            QSKIP("Enable HEXAGON_LIVE_CORE for real Mihomo integration");
        QTemporaryDir dir;
        Storage s(dir.path(), dir.path() + "/old");
        const auto old = s.legacy;
        const QByteArray profile =
            "proxy-providers:\n  legacy:\n    type: file\n    path: ./providers/library/legacy.txt\n"
            "proxy-groups:\n  - name: Test\n    type: select\n    use: [legacy]\n"
            "rules:\n  - MATCH,DIRECT\n";
        QVERIFY(writeBytes(old + "/profiles/active.yaml", profile));
        QVERIFY(writeBytes(old + "/profiles/library/legacy.yaml", profile));
        QVERIFY(writeObject(
            old + "/profiles/library/index.json",
            {{"active_id", "legacy"},
             {"subscriptions",
              QJsonArray{QJsonObject{{"id", "legacy"}, {"type", "v2"}, {"config_file", "legacy.yaml"}}}}}));
        QVERIFY(writeBytes(old + "/runtime/providers/library/legacy.txt",
                           "ss://YWVzLTEyOC1nY206dGVzdA@127.0.0.1:12345#Imported-A\n"
                           "ss://YWVzLTEyOC1nY206dGVzdA@127.0.0.1:12346#Imported-B\n"));
        s.importLegacy();
        QTcpServer mixed, controller;
        QVERIFY(mixed.listen(QHostAddress::LocalHost, 0));
        QVERIFY(controller.listen(QHostAddress::LocalHost, 0));
        s.settings["mixed_port"] = mixed.serverPort();
        s.settings["controller_port"] = controller.serverPort();
        mixed.close();
        controller.close();
        s.settings["core_source"] = qEnvironmentVariable("HEXAGON_TEST_CORE");
        ProxyService service(s);
        const auto stopCore = qScopeGuard([&] {
            service.stop();
            if (service.process.state() != QProcess::NotRunning)
                service.process.waitForFinished(3000);
        });
        service.start();
        QTRY_VERIFY_WITH_TIMEOUT(service.connected || !service.lastError.isEmpty(), 30000);
        QVERIFY2(service.connected, qPrintable(service.lastError));
        bool done = false;
        QJsonObject version;
        service.request("/version", "GET", {}, [&](QJsonObject r) {
            version = r;
            done = true;
        });
        QTRY_VERIFY_WITH_TIMEOUT(done, 5000);
        QVERIFY(version.value("ok").toBool());
        QTRY_VERIFY_WITH_TIMEOUT(service.proxies.contains("Test"), 5000);
        const auto group = service.proxies.value("Test").toObject().value("all").toArray();
        QCOMPARE(group, QJsonArray({"Imported-A", "Imported-B"}));
        QTcpServer origin;
        QVERIFY(origin.listen(QHostAddress::LocalHost, 0));
        connect(&origin, &QTcpServer::newConnection, &origin, [&] {
            auto socket = origin.nextPendingConnection();
            connect(socket, &QTcpSocket::readyRead, socket, [socket] {
                socket->readAll();
                socket->write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK");
                socket->disconnectFromHost();
            });
        });
        QNetworkAccessManager client;
        client.setProxy(QNetworkProxy(QNetworkProxy::HttpProxy, "127.0.0.1", quint16(s.mixedPort())));
        auto reply =
            client.get(QNetworkRequest(QUrl(QString("http://127.0.0.1:%1/").arg(origin.serverPort()))));
        QTRY_VERIFY_WITH_TIMEOUT(reply->isFinished(), 5000);
        QCOMPARE(reply->error(), QNetworkReply::NoError);
        QCOMPARE(reply->readAll(), QByteArray("OK"));
        service.stop();
        QTRY_COMPARE_WITH_TIMEOUT(service.process.state(), QProcess::NotRunning, 5000);
    }
    void liveLinux() {
        if (qEnvironmentVariable("HEXAGON_LIVE_LINUX") != "1")
            QSKIP("Enable HEXAGON_LIVE_LINUX for real QEMU integration");
        QTemporaryDir dir;
        Storage s(dir.path(), dir.path() + "/old");
        s.importLegacy();
        LinuxWorkspace service(s);
        QVERIFY(service.setDirectory(dir.path() + QString::fromUtf8("/自选 Linux 目录")));
        service.start(1);
        const auto stopGuest = qScopeGuard([&] {
            if (service.running()) {
                QEventLoop loop;
                connect(&service.vm, &QProcess::finished, &loop, &QEventLoop::quit);
                service.stop();
                QTimer::singleShot(15000, &loop, &QEventLoop::quit);
                loop.exec();
            }
        });
        QTRY_VERIFY_WITH_TIMEOUT(service.ready || (!service.busy && !service.error.isEmpty()), 150000);
        QVERIFY2(service.ready, qPrintable(service.error));
        auto vm = readObject(service.root() + "/native-vm.json");
        if (qEnvironmentVariable("HEXAGON_LIVE_WEB") == "1") {
            WebWorkspace embedded;
            embedded.resize(900, 650);
            embedded.show();
            QSignalSpy loaded(&embedded, &WebWorkspace::loaded), failed(&embedded, &WebWorkspace::failed);
            embedded.navigateLocal(QUrl(QString("http://127.0.0.1:%1/").arg(service.webPort)),
                                   dir.path() + "/test-webview");
            QTRY_VERIFY_WITH_TIMEOUT(!loaded.empty() || !failed.empty(), 20000);
            QVERIFY2(failed.empty(), failed.empty() ? "" : qPrintable(failed.first().first().toString()));
            QVERIFY(!loaded.empty());
            auto hasBrand = [&](const QString &selector, const QString &label) {
                auto result = std::make_shared<QByteArray>();
                const auto script = QString(R"JS((() => {
                    const logo = document.querySelector('%1');
                    return document.title.includes('HexagonLinux') &&
                           logo?.alt === 'HexagonLinux' && logo.naturalWidth > 0 &&
                           logo.getAttribute('src') === '/__hexagonlinux/axolotl.svg' &&
                           (!'%2' || document.querySelector('%2')?.textContent.includes('HexagonLinux'));
                })())JS")
                                        .arg(selector, label);
                embedded.inspectPageForTest(script, [result](QByteArray response) { *result = response; });
                for (int i = 0; i < 10 && result->isEmpty(); ++i)
                    QTest::qWait(10);
                return *result == "true";
            };
            QTRY_VERIFY_WITH_TIMEOUT(hasBrand("img.login-logo", ".hexagonlinux-login-name"), 10000);
            const auto credentials =
                QJsonDocument(QJsonObject{{"username", "root"}, {"password", vm.value("password")}})
                    .toJson(QJsonDocument::Compact);
            const auto signIn = QString(R"JS((() => {
                const credentials = %1;
                const form = document.querySelector('.login-form');
                form.querySelector('[name=username]').value = credentials.username;
                form.querySelector('[name=password]').value = credentials.password;
                form.requestSubmit();
            })())JS")
                                    .arg(QString::fromUtf8(credentials));
            embedded.inspectPageForTest(signIn, [](QByteArray) {});
            QTRY_VERIFY_WITH_TIMEOUT(hasBrand(".brand-button img.brand", ""), 20000);
            embedded.inspectPageForTest("document.querySelector('.brand-button').click()", [](QByteArray) {});
            QTRY_VERIFY_WITH_TIMEOUT(hasBrand("img.about-logo", ".hexagonlinux-credit"), 10000);
            embedded.clear();
        }
        Http http;
        QString base = QString("http://127.0.0.1:%1").arg(service.webPort), failure;
        auto login = request(
            http, base + "/api/login", "POST",
            QJsonDocument(QJsonObject{{"username", "root"}, {"password", vm.value("password")}}).toJson(),
            {{"X-Tuxee-Client", "web"}, {"Content-Type", "application/json"}, {"Origin", base.toUtf8()}},
            &failure);
        QVERIFY2(failure.isEmpty(), qPrintable(failure));
        auto csrf = QJsonDocument::fromJson(login).object().value("csrf").toString();
        QVERIFY(!csrf.isEmpty());
        auto upload = request(
            http, base + "/api/upload?path=/root/native-check.txt", "POST", "native-persistent-file",
            {{"X-Tuxee-CSRF", csrf.toUtf8()}, {"Origin", base.toUtf8()}, {"X-Tuxee-Size", "22"}}, &failure);
        Q_UNUSED(upload);
        QVERIFY2(failure.isEmpty(), qPrintable(failure));
        service.stop();
        QTRY_VERIFY_WITH_TIMEOUT(!service.running(), 15000);
        service.start(10);
        QTRY_VERIFY_WITH_TIMEOUT(service.ready || (!service.busy && !service.error.isEmpty()), 90000);
        QVERIFY2(service.ready, qPrintable(service.error));
        base = QString("http://127.0.0.1:%1").arg(service.webPort);
        login = request(
            http, base + "/api/login", "POST",
            QJsonDocument(QJsonObject{{"username", "root"}, {"password", vm.value("password")}}).toJson(),
            {{"X-Tuxee-Client", "web"}, {"Content-Type", "application/json"}, {"Origin", base.toUtf8()}},
            &failure);
        QVERIFY2(failure.isEmpty(), qPrintable(failure));
        auto file =
            request(http, base + "/api/download?path=/root/native-check.txt", "GET", {}, {}, &failure);
        QCOMPARE(file, QByteArray("native-persistent-file"));
        QVERIFY(QFileInfo(service.disk()).size() < qint64(10) * 1073741824);
        service.stop();
        QTRY_VERIFY_WITH_TIMEOUT(!service.running(), 15000);
    }
    void liveEmbeddedWorkspace() {
        if (qEnvironmentVariable("HEXAGON_LIVE_WEB") != "1")
            QSKIP("Enable HEXAGON_LIVE_WEB for real WebView2 integration");
        QTemporaryDir dir;
        QTcpServer server;
        QVERIFY(server.listen(QHostAddress::LocalHost, 0));
        connect(&server, &QTcpServer::newConnection, &server, [&] {
            while (server.hasPendingConnections()) {
                auto socket = server.nextPendingConnection();
                connect(socket, &QTcpSocket::readyRead, socket, [socket] {
                    socket->readAll();
                    QByteArray html = "<!doctype html><title>Hexagon native workspace "
                                      "test</title><body>embedded workspace</body>";
                    socket->write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: " +
                                  QByteArray::number(html.size()) + "\r\nConnection: close\r\n\r\n" + html);
                    socket->disconnectFromHost();
                });
                connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            }
        });
        WebWorkspace web;
        web.resize(800, 600);
        web.show();
        QSignalSpy loaded(&web, &WebWorkspace::loaded), failed(&web, &WebWorkspace::failed);
        web.navigateLocal(QUrl(QString("http://127.0.0.1:%1/").arg(server.serverPort())), dir.path());
        QTRY_VERIFY_WITH_TIMEOUT(!loaded.empty() || !failed.empty(), 30000);
        QVERIFY2(failed.empty(), failed.empty() ? "" : qPrintable(failed.first().first().toString()));
        QVERIFY(!loaded.empty());
        web.hide();
        web.show();
        web.reload();
        QTRY_VERIFY_WITH_TIMEOUT(loaded.size() >= 2, 10000);
        web.clear();
        QVERIFY(web.url().isEmpty());
    }

  private:
    QByteArray request(Http &http, const QString &url, const QByteArray &method, const QByteArray &body,
                       const QList<QNetworkReply::RawHeaderPair> &headers, QString *failure) {
        QEventLoop loop;
        QByteArray result;
        bool done = false;
        http.request(
            QUrl(url), method, body, headers,
            [&](QByteArray data, QString error) {
                result = data;
                *failure = error;
                done = true;
                loop.quit();
            },
            15000);
        QTimer::singleShot(17000, &loop, &QEventLoop::quit);
        loop.exec();
        if (!done)
            *failure = "request timed out";
        return result;
    }
};
QTEST_MAIN(NativeTests)
#include "tests.moc"
