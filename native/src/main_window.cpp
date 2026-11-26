#include "main_window.h"
#include "layouts.h"
#include <QSvgRenderer>
#include <QTcpServer>
#include <windows.h>
#include <windowsx.h>
namespace hexagon {
static QColor color(QString v) {
    if (v.size() == 9)
        v = "#" + v.right(2) + v.mid(1, 6);
    return QColor(v);
}
static QString cssColor(QColor c) {
    return QString("rgba(%1,%2,%3,%4)").arg(c.red()).arg(c.green()).arg(c.blue()).arg(c.alpha());
}
static QIcon railIcon(int kind, QColor color) {
    QPixmap pixmap(48, 48);
    pixmap.setDevicePixelRatio(2);
    pixmap.fill(Qt::transparent);
    QPainter p(&pixmap);
    p.setRenderHint(QPainter::Antialiasing);
    p.setPen(QPen(color, 1.6, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
    if (kind == 0) {
        QPainterPath path;
        path.moveTo(3, 11);
        path.lineTo(12, 3);
        path.lineTo(21, 11);
        path.moveTo(5, 10);
        path.lineTo(5, 21);
        path.lineTo(10, 21);
        path.lineTo(10, 15);
        path.lineTo(15, 15);
        path.lineTo(15, 21);
        path.lineTo(19, 21);
        path.lineTo(19, 10);
        p.drawPath(path);
    } else if (kind == 1) {
        p.drawLine(6, 8, 18, 8);
        p.drawLine(6, 8, 12, 19);
        p.drawLine(18, 8, 12, 19);
        for (auto point : {QPoint(6, 8), QPoint(18, 8), QPoint(12, 19)})
            p.drawEllipse(point, 3, 3);
    } else if (kind == 4) {
        p.drawRoundedRect(QRectF(2, 4, 20, 16), 2, 2);
        p.drawLine(6, 9, 9, 12);
        p.drawLine(9, 12, 6, 15);
        p.drawLine(12, 15, 17, 15);
    } else if (kind == 5) {
        p.drawRoundedRect(QRectF(2, 3, 20, 15), 2, 2);
        p.drawLine(12, 18, 12, 22);
        p.drawLine(7, 22, 17, 22);
    } else if (kind == 7) {
        p.drawLine(5, 19, 19, 5);
        p.drawLine(9, 5, 19, 5);
        p.drawLine(19, 5, 19, 15);
    } else {
        p.drawEllipse(QPointF(12, 12), 6, 6);
        p.drawEllipse(QPointF(12, 12), 2, 2);
        for (int i = 0; i < 8; ++i) {
            p.save();
            p.translate(12, 12);
            p.rotate(i * 45);
            p.drawLine(0, 7, 0, 10);
            p.restore();
        }
    }
    return QIcon(pixmap);
}
static QString bytesText(double value) {
    static QStringList units = {"B", "KB", "MB", "GB", "TB"};
    int unit = 0;
    while (value >= 1024 && unit < 4) {
        value /= 1024;
        ++unit;
    }
    return QString::number(value, 'f', unit ? 1 : 0) + " " + units[unit];
}
static QLabel *label(const QString &text, QWidget *parent = nullptr) {
    auto l = new QLabel(text, parent);
    l->setWordWrap(true);
    l->setTextFormat(Qt::PlainText);
    l->setSizePolicy(QSizePolicy::Preferred, QSizePolicy::Minimum);
    return l;
}
static QWidget *actionRow(QVBoxLayout *layout, ActionLayout **row) {
    auto w = new QWidget;
    *row = new ActionLayout(w);
    (*row)->setContentsMargins(0, 0, 0, 0);
    (*row)->setSpacing(8);
    layout->addWidget(w);
    return w;
}
static QTreeWidget *tree(const QStringList &headers, QVBoxLayout *layout) {
    auto t = new PagedTree;
    auto group = new QWidget;
    auto column = new QVBoxLayout(group);
    column->setContentsMargins(0, 0, 0, 0);
    column->addWidget(t, 1);
    auto footer = new QHBoxLayout;
    column->addLayout(footer);
    t->previous = new QPushButton("上一页");
    t->next = new QPushButton("下一页");
    t->counter = new QLabel;
    footer->addWidget(t->previous);
    footer->addWidget(t->counter, 1, Qt::AlignCenter);
    footer->addWidget(t->next);
    QObject::connect(t->previous, &QPushButton::clicked, t, [t] {
        --t->page;
        t->paginate();
    });
    QObject::connect(t->next, &QPushButton::clicked, t, [t] {
        ++t->page;
        t->paginate();
    });
    t->setHeaderLabels(headers);
    t->setRootIsDecorated(false);
    t->setAlternatingRowColors(true);
    t->setUniformRowHeights(true);
    t->setSelectionMode(QAbstractItemView::SingleSelection);
    t->header()->setSectionResizeMode(QHeaderView::Stretch);
    t->setTextElideMode(Qt::ElideRight);
    t->header()->setStretchLastSection(true);
    t->setMinimumHeight(100);
    layout->addWidget(group, 1);
    return t;
}
static void updateRows(QTreeWidget *view, const QList<QPair<QString, QStringList>> &rows) {
    const auto selected =
        view->currentItem() ? view->currentItem()->data(0, Qt::UserRole).toString() : QString();
    QSignalBlocker blocker(view);
    QHash<QString, QTreeWidgetItem *> existing;
    for (int i = 0; i < view->topLevelItemCount(); ++i) {
        auto item = view->topLevelItem(i);
        existing[item->data(0, Qt::UserRole).toString()] = item;
    }
    QSet<QString> keep;
    for (const auto &row : rows) {
        keep.insert(row.first);
        auto item = existing.value(row.first);
        if (!item) {
            item = new QTreeWidgetItem(view);
            item->setData(0, Qt::UserRole, row.first);
        }
        for (int col = 0; col < row.second.size(); ++col)
            if (item->text(col) != row.second[col])
                item->setText(col, row.second[col]);
        if (row.first == selected)
            view->setCurrentItem(item);
    }
    for (auto it = existing.begin(); it != existing.end(); ++it)
        if (!keep.contains(it.key()))
            delete it.value();
    if (auto paged = dynamic_cast<PagedTree *>(view))
        paged->paginate();
}

class ChromeButton : public QPushButton {
  public:
    using QPushButton::QPushButton;

  protected:
    void enterEvent(QEnterEvent *event) override {
        QPushButton::enterEvent(event);
        setPointerOver(true);
    }
    void leaveEvent(QEvent *event) override {
        QPushButton::leaveEvent(event);
        setPointerOver(false);
    }

  private:
    void setPointerOver(bool over) {
        if (property("chromeHover").toBool() == over)
            return;
        setProperty("chromeHover", over);
        style()->unpolish(this);
        style()->polish(this);
        update();
    }
};

class TitleBar : public QFrame {
  public:
    using QFrame::QFrame;

  protected:
    void mousePressEvent(QMouseEvent *e) override {
        if (e->button() == Qt::LeftButton && window()->windowHandle())
            window()->windowHandle()->startSystemMove();
    }
    void mouseDoubleClickEvent(QMouseEvent *e) override {
        if (e->button() == Qt::LeftButton) {
            if (window()->isMaximized())
                window()->showNormal();
            else
                window()->showMaximized();
        }
    }
};
class Pet : public QLabel {
  public:
    using QLabel::QLabel;
    QPoint drag;

  protected:
    void mousePressEvent(QMouseEvent *e) override {
        if (e->button() == Qt::LeftButton)
            drag = e->globalPosition().toPoint() - frameGeometry().topLeft();
    }
    void mouseMoveEvent(QMouseEvent *e) override {
        if (e->buttons() & Qt::LeftButton)
            move(e->globalPosition().toPoint() - drag);
    }
    void contextMenuEvent(QContextMenuEvent *e) override {
        QMenu menu;
        menu.addAction("隐藏六角恐龙", this, &QWidget::hide);
        menu.exec(e->globalPos());
    }
};
void TrafficPlot::paintEvent(QPaintEvent *) {
    QPainter p(this);
    p.setRenderHint(QPainter::Antialiasing);
    QRectF r = rect().adjusted(14, 12, -14, -20);
    p.setPen(QPen(palette().color(QPalette::Mid), 1));
    for (int i = 1; i < 4; ++i)
        p.drawLine(r.left(), r.top() + r.height() * i / 4, r.right(), r.top() + r.height() * i / 4);
    if (values.size() < 2)
        return;
    double max = std::max(1024.0, *std::max_element(values.begin(), values.end()));
    QPainterPath line;
    for (int i = 0; i < values.size(); ++i) {
        QPointF point(r.left() + r.width() * i / std::max(89, int(values.size() - 1)),
                      r.bottom() - r.height() * values[i] / max);
        if (i == 0)
            line.moveTo(point);
        else
            line.lineTo(point);
    }
    auto area = line;
    area.lineTo(line.currentPosition().x(), r.bottom());
    area.lineTo(r.left(), r.bottom());
    area.closeSubpath();
    QColor fill = accent;
    fill.setAlpha(35);
    p.fillPath(area, fill);
    p.setPen(QPen(accent, 2));
    p.drawPath(line);
}
MainWindow::MainWindow(Storage &s, bool testing)
    : store(s), proxy(s, this), accounts(s, this), linux(s, this), terminalProcess(this), terminalFlush(this),
      fontDebounce(this), tray(this), testMode(testing) {
    setObjectName("HexagonProxyMainWindow");
    setWindowTitle("HexagonProxy " + QCoreApplication::applicationVersion());
    setWindowIcon(QIcon(":/brand/app_icon.png"));
    setWindowFlags(Qt::Window | Qt::FramelessWindowHint);
    const auto available = screen()->availableGeometry();
    setMinimumSize(qMin(900, available.width()), qMin(500, available.height()));
    resize(qMin(1536, available.width()), qMin(864, available.height()));
    move(available.center() - rect().center());
    shell = new QWidget;
    shell->setObjectName("shell");
    setCentralWidget(shell);
    auto root = new QHBoxLayout(shell);
    root->setContentsMargins(0, 0, 0, 0);
    root->setSpacing(0);
    auto rail = new QFrame;
    rail->setObjectName("rail");
    rail->setFixedWidth(52);
    auto railLayout = new QVBoxLayout(rail);
    railLayout->setContentsMargins(8, 20, 8, 16);
    root->addWidget(rail);
    for (const auto &entry : QList<QPair<QString, int>>{{"⌂", 0}, {"◇", 1}, {">_", 4}, {"▣", 5}, {"↗", 7}}) {
        auto b = new QPushButton(entry.first);
        b->setFixedSize(36, 40);
        b->setObjectName("railButton");
        b->setText("");
        b->setProperty("railTarget", entry.second);
        b->setIconSize(QSize(22, 22));
        connect(b, &QPushButton::clicked, this, [this, entry] { navigation->setCurrentRow(entry.second); });
        railLayout->addWidget(b);
    }
    railLayout->addStretch();
    auto settingsShortcut = button(railLayout, "", [this] { navigation->setCurrentRow(8); });
    settingsShortcut->setObjectName("railButton");
    settingsShortcut->setProperty("railTarget", 8);
    settingsShortcut->setIconSize(QSize(22, 22));
    auto side = new QFrame;
    side->setObjectName("sidebar");
    side->setFixedWidth(220);
    auto sideLayout = new QVBoxLayout(side);
    sideLayout->setContentsMargins(14, 22, 14, 14);
    auto brand = new QHBoxLayout;
    auto mascot = new QLabel;
    mascot->setPixmap(QIcon(":/brand/ui/axolotl_mark.svg").pixmap(32, 32));
    brand->addWidget(mascot);
    auto brandName = new QLabel("HexagonProxy");
    brandName->setObjectName("brandName");
    brandName->setFont(QFont("Microsoft YaHei UI", 12));
    brand->addWidget(brandName);
    sideLayout->addLayout(brand);
    sideLayout->addSpacing(12);
    auto workspaceCaption = label("工作台");
    workspaceCaption->setFont(QFont("Microsoft YaHei UI", 12));
    sideLayout->addWidget(workspaceCaption);
    navigation = new QListWidget;
    navigation->setObjectName("navigation");
    navigation->setFrameShape(QFrame::NoFrame);
    navigation->addItems(
        {"总览", "节点", "订阅", "分流", "终端", "HexagonLinux", "Codex 账号", "Antigravity", "设置"});
    sideLayout->addWidget(navigation, 1);
    auto powered = label("Mihomo powered");
    powered->setFont(QFont("Microsoft YaHei UI", 10));
    sideLayout->addWidget(powered);
    root->addWidget(side);
    auto content = new QWidget;
    auto contentLayout = new QVBoxLayout(content);
    contentLayout->setContentsMargins(20, 12, 20, 14);
    contentLayout->setSpacing(12);
    root->addWidget(content, 1);
    auto top = new TitleBar;
    auto topLayout = new QHBoxLayout(top);
    topLayout->setContentsMargins(0, 0, 0, 0);
    title = new QLabel("网络总览");
    title->setObjectName("pageTitle");
    title->setSizePolicy(QSizePolicy::Ignored, QSizePolicy::Preferred);
    title->setMinimumWidth(60);
    title->setAttribute(Qt::WA_TransparentForMouseEvents);
    topLayout->addWidget(title, 1);
    statusPill = new QLabel("●  代理未连接");
    statusPill->setObjectName("statusPill");
    statusPill->setFixedWidth(190);
    topLayout->addWidget(statusPill);
    auto windowAction = [&](const QString &text, const QString &name, auto callback) {
        auto control = new ChromeButton(text);
        control->setObjectName(name);
        control->setCursor(Qt::PointingHandCursor);
        connect(control, &QPushButton::clicked, this, callback);
        topLayout->addWidget(control);
    };
    windowAction("最小化", "minimizeButton", [this] { showMinimized(); });
    windowAction("关闭", "closeButton", [this] { requestClose(false); });
    windowAction("退出", "exitButton", [this] { requestClose(true); });
    contentLayout->addWidget(top);
    notification = label("");
    notification->setObjectName("notification");
    notification->setTextFormat(Qt::RichText);
    notification->setMaximumHeight(72);
    connect(notification, &QLabel::linkActivated, this, [this] {
        QMessageBox box(this);
        box.setWindowTitle("操作详情");
        box.setText("完整操作信息");
        box.setDetailedText(notification->property("details").toString());
        box.exec();
    });
    notification->hide();
    contentLayout->addWidget(notification);
    pages = new QStackedWidget;
    pages->setObjectName("pages");
    contentLayout->addWidget(pages, 1);
    buildDashboard();
    buildNodes();
    buildSubscriptions();
    buildRouting();
    buildTerminal();
    buildLinux();
    buildCodex();
    buildAntigravity();
    buildSettings();
    connect(navigation, &QListWidget::currentRowChanged, this, &MainWindow::showPage);
    connect(&proxy, &ProxyService::changed, this, &MainWindow::refreshProxy);
    connect(&proxy, &ProxyService::nodesChanged, this, &MainWindow::refreshNodes);
    connect(&proxy, &ProxyService::subscriptionsChanged, this, &MainWindow::refreshSubscriptions);
    connect(&proxy, &ProxyService::logged, this, [this](QString text) {
        appendLog(text);
        if (!proxy.lastError.isEmpty())
            showMessage(text);
    });
    connect(&proxy, &ProxyService::trafficChanged, this, &MainWindow::updateTraffic);
    connect(&accounts, &AccountsService::changed, this, &MainWindow::refreshAccounts);
    connect(&accounts, &AccountsService::message, this, [this](QString text, bool ok) {
        accountMessage->setText(text);
        showMessage(text, ok);
    });
    connect(&accounts, &AccountsService::logged, this, &MainWindow::appendLog);
    connect(&linux, &LinuxWorkspace::changed, this, [this] {
        refreshLinux();
        if (quitting && !linux.running() && !linux.busy)
            close();
    });
    connect(&linux, &LinuxWorkspace::logged, this, &MainWindow::appendLog);
    fontDebounce.setSingleShot(true);
    fontDebounce.setInterval(100);
    connect(&fontDebounce, &QTimer::timeout, this, [this] {
        store.settings["font_percent"] = fontSlider->value();
        saveSettings();
        applyTheme();
    });
    auto menu = new QMenu(this);
    menu->addAction("打开 HexagonProxy", this, [this] {
        showNormal();
        raise();
        activateWindow();
    });
    menu->addAction("连接 / 断开代理", this, [this] {
        if (proxy.connected)
            proxy.stop();
        else
            proxy.start(true);
    });
    menu->addSeparator();
    menu->addAction("退出", this, [this] { requestClose(true); });
    tray.setContextMenu(menu);
    tray.setIcon(windowIcon());
    tray.setToolTip("HexagonProxy");
    connect(&tray, &QSystemTrayIcon::activated, this, [this](QSystemTrayIcon::ActivationReason reason) {
        if (reason == QSystemTrayIcon::Trigger || reason == QSystemTrayIcon::DoubleClick) {
            showNormal();
            raise();
            activateWindow();
        }
    });
    if (!testMode)
        tray.show();
    closeDeadline.setSingleShot(true);
    closeDeadline.setInterval(30000);
    connect(&closeDeadline, &QTimer::timeout, this, [this] {
        if (quitting && (linux.running() || linux.busy)) {
            quitting = false;
            showMessage("Linux 仍在保存或初始化，退出已取消。请稍后停止工作区再退出。");
        }
    });
    createPet();
    applyTheme();
    refreshProxy();
    refreshLinux();
    refreshSubscriptions();
    refreshRouting();
    refreshAccounts();
    navigation->setCurrentRow(0);
    appendLog("HexagonProxy C++ 客户端已就绪");
    if (!accounts.error.isEmpty())
        showMessage(accounts.error);
    if (!testMode) {
        auto intro = new QFrame(shell);
        intro->setProperty("surface", true);
        intro->setAttribute(Qt::WA_TransparentForMouseEvents);
        intro->setFixedSize(260, 170);
        intro->move((width() - 260) / 2, (height() - 170) / 2);
        auto column = new QVBoxLayout(intro);
        auto mark = new QLabel;
        mark->setAlignment(Qt::AlignCenter);
        mark->setPixmap(QIcon(":/brand/ui/axolotl_mark.svg").pixmap(84, 84));
        column->addWidget(mark);
        auto caption = label("HexagonProxy");
        caption->setAlignment(Qt::AlignCenter);
        column->addWidget(caption);
        intro->show();
        intro->raise();
        QTimer::singleShot(180, intro, [intro] {
            auto effect = new QGraphicsOpacityEffect(intro);
            intro->setGraphicsEffect(effect);
            auto fade = new QPropertyAnimation(effect, "opacity", intro);
            fade->setDuration(300);
            fade->setStartValue(1.0);
            fade->setEndValue(0.0);
            QObject::connect(fade, &QPropertyAnimation::finished, intro, &QObject::deleteLater);
            fade->start();
        });
    }
}
QWidget *MainWindow::page(const QString &heading, const QString &description, QVBoxLayout **layout) {
    auto w = new QWidget;
    *layout = new QVBoxLayout(w);
    (*layout)->setContentsMargins(0, 0, 0, 0);
    (*layout)->setSpacing(12);
    Q_UNUSED(heading);
    Q_UNUSED(description);
    pages->addWidget(w);
    return w;
}
QWidget *MainWindow::card(QVBoxLayout *parent, const QString &heading, QVBoxLayout **layout) {
    auto frame = new QFrame;
    frame->setProperty("surface", true);
    *layout = new QVBoxLayout(frame);
    (*layout)->setContentsMargins(16, 12, 16, 14);
    (*layout)->setSpacing(10);
    if (!heading.isEmpty()) {
        auto h = label(heading);
        h->setObjectName("sectionTitle");
        (*layout)->addWidget(h);
    }
    parent->addWidget(frame);
    return frame;
}
QPushButton *MainWindow::button(QLayout *layout, const QString &text, std::function<void()> cb,
                                bool primary) {
    auto b = new QPushButton(text);
    b->setCursor(Qt::PointingHandCursor);
    if (primary)
        b->setProperty("primary", true);
    connect(b, &QPushButton::clicked, this, std::move(cb));
    layout->addWidget(b);
    return b;
}
void MainWindow::showMessage(const QString &text, bool ok) {
    notification->setProperty("details", text);
    notification->setToolTip(text);
    auto summary = text.section('\n', 0, 0);
    if (summary.size() > 90)
        summary = summary.left(90) + "…";
    notification->setText(summary.toHtmlEscaped() + " <a href='details'>查看详情</a>");
    notification->setProperty("success", ok);
    notification->style()->unpolish(notification);
    notification->style()->polish(notification);
    notification->setVisible(!text.isEmpty());
}
void MainWindow::appendLog(const QString &text) {
    if (logView)
        logView->appendPlainText(QDateTime::currentDateTime().toString("HH:mm:ss  ") + text);
}
bool MainWindow::confirm(const QString &heading, const QString &text) {
    return QMessageBox::question(this, heading, text, QMessageBox::Yes | QMessageBox::No, QMessageBox::No) ==
           QMessageBox::Yes;
}
void MainWindow::saveSettings() {
    QString e;
    if (!store.saveSettings(&e))
        showMessage("设置保存失败：" + e);
}
QString MainWindow::selectedId(QTreeWidget *view) const {
    return view->currentItem() ? view->currentItem()->data(0, Qt::UserRole).toString() : QString();
}
void MainWindow::showPage(int i) {
    if (i < 0 || i >= pages->count())
        return;
    pages->setCurrentIndex(i);
    const QStringList names = {"网络总览",     "节点路线",   "订阅管理",    "应用分流", "内置终端",
                               "HexagonLinux", "Codex 账号", "Antigravity", "偏好设置"};
    title->setText(names[i]);
    if (i == 1 && proxy.connected)
        proxy.request("/proxies", "GET", {}, [this](QJsonObject p) {
            proxy.proxies = p.value("proxies").toObject();
            refreshNodes();
        });
    if (i == 7 && !testMode && !accounts.busy)
        accounts.antigravityProxyAction("inspect");
}

void MainWindow::buildDashboard() {
    QVBoxLayout *layout;
    page({}, {}, &layout);
    auto panels = new AdaptivePanels(830, 2);
    panels->setObjectName("dashboardPanels");
    layout->addWidget(panels, 1);
    auto overview = panels->addPanel("连接与流量");
    auto sidebar = panels->addPanel("运行记录");
    panels->setColumnStretch(0, 2);
    QVBoxLayout *section;
    card(overview, "", &section);
    auto connection = new QHBoxLayout;
    section->addLayout(connection);
    auto caption = label("网络连接");
    caption->setObjectName("sectionTitle");
    connection->addWidget(caption, 1);
    connectButton = button(connection, "一键连接", [this] {
        if (proxy.connected || proxy.busy)
            proxy.stop();
        else
            proxy.start(true);
    });
    connectButton->setCheckable(true);
    connectButton->setLayoutDirection(Qt::RightToLeft);
    connectButton->setIconSize(QSize(28, 16));
    connectButton->setObjectName("connectToggle");
    ActionLayout *row;
    actionRow(section, &row);
    row->addWidget(label("代理模式"));
    modeButtons = new QButtonGroup(this);
    const QList<QPair<QString, QString>> entries{{"规则", "rule"}, {"全局", "global"}, {"直连", "direct"}};
    for (const auto &entry : entries) {
        auto mode = button(row, entry.first, [this, value = entry.second] { proxy.setMode(value); });
        mode->setCheckable(true);
        mode->setProperty("proxyMode", entry.second);
        modeButtons->addButton(mode);
    }

    auto stats = new QHBoxLayout;
    stats->setSpacing(8);
    overview->addLayout(stats);
    auto stat = [&](const QString &heading) {
        auto tile = new QFrame;
        tile->setProperty("surface", true);
        auto column = new QVBoxLayout(tile);
        column->setContentsMargins(10, 7, 10, 7);
        column->setSpacing(3);
        column->addWidget(label(heading));
        auto value = label("—");
        value->setObjectName("statValue");
        column->addWidget(value);
        stats->addWidget(tile, 1);
        return value;
    };
    speedLabel = stat("↓ 下载");
    uploadLabel = stat("↑ 上传");
    connectionLabel = stat("连接");
    totalLabel = stat("Σ 流量");
    speedLabel->setText("0 B/s");
    uploadLabel->setText("0 B/s");
    connectionLabel->setText("0");
    totalLabel->setText("0 B");

    auto plotCard = card(overview, "实时流量", &section);
    overview->setStretchFactor(plotCard, 1);
    plot = new TrafficPlot;
    plot->setObjectName("trafficPlot");
    plot->setMinimumHeight(65);
    section->addWidget(plot, 1);

    card(sidebar, "", &section);
    dashboardStatus = label("代理未连接");
    dashboardStatus->setAlignment(Qt::AlignCenter);
    section->addWidget(dashboardStatus);
    auto petMark = new QLabel;
    petMark->setAlignment(Qt::AlignCenter);
    petMark->setPixmap(QIcon(":/brand/ui/axolotl_mark.svg").pixmap(52, 52));
    section->addWidget(petMark);
    activeSubscription = label("");
    activeSubscription->setAlignment(Qt::AlignCenter);
    section->addWidget(activeSubscription);
    auto logCard = card(sidebar, "运行记录", &section);
    sidebar->setStretchFactor(logCard, 1);
    logView = new QPlainTextEdit;
    logView->setObjectName("dashboardLog");
    logView->setReadOnly(true);
    logView->setMaximumBlockCount(1200);
    section->addWidget(logView, 1);
}

void MainWindow::buildNodes() {
    QVBoxLayout *layout, *controls;
    page({}, {}, &layout);
    card(layout, "选择守护路线", &controls);
    ActionLayout *row;
    actionRow(controls, &row);
    currentNode = label("当前节点 · —");
    row->addWidget(currentNode, 1);
    auto guard = new QCheckBox("自动故障切换");
    guard->setChecked(readObject(store.file("node_failover.json")).value("enabled").toBool(true));
    row->addWidget(guard);
    groupChoice = new QComboBox;
    groupChoice->setSizeAdjustPolicy(QComboBox::AdjustToMinimumContentsLengthWithIcon);
    groupChoice->setMinimumContentsLength(8);
    row->addWidget(groupChoice);
    nodeFilter = new QLineEdit;
    nodeFilter->setPlaceholderText("搜索节点");
    row->addWidget(nodeFilter, 1);
    batchTest = button(row, "全部测速", [this] {
        const auto group = groupChoice->currentText();
        const auto nodes = proxy.proxies.value(group).toObject().value("all").toArray();
        for (const auto &node : nodes)
            pendingTests.enqueue({group, node.toString()});
        runNodeTests();
    });
    button(row, "刷新", [this] {
        proxy.request("/proxies", "GET", {}, [this](QJsonObject response) {
            if (!response.value("ok").toBool()) {
                showMessage(response.value("message").toString());
                return;
            }
            proxy.proxies = response.value("proxies").toObject();
            refreshNodes();
        });
    });
    nodeCards = new CardPager(335, 3);
    nodeCards->setObjectName("nodeCards");
    layout->addWidget(nodeCards, 1);
    connect(guard, &QCheckBox::toggled, this, [this](bool on) {
        auto state = readObject(store.file("node_failover.json"));
        state["enabled"] = on;
        QString error;
        if (!writeObject(store.file("node_failover.json"), state, &error))
            showMessage(error);
    });
    connect(groupChoice, &QComboBox::currentTextChanged, this, &MainWindow::refreshNodes);
    connect(nodeFilter, &QLineEdit::textChanged, this, &MainWindow::refreshNodes);
    refreshNodes();
}
void MainWindow::runNodeTests() {
    while (proxy.connected && runningTests < 4 && !pendingTests.isEmpty()) {
        const auto [group, node] = pendingTests.dequeue();
        ++runningTests;
        proxy.testNode(node, [this, group, node](QJsonObject response) {
            --runningTests;
            const auto delay = response.value("delay").toInt();
            nodeDelays[group][node] = delay > 0 ? QString::number(delay) + " ms" : "不可达";
            if (groupChoice->currentText() == group) {
                auto value = nodeDelayLabels.value(node);
                if (value)
                    value->setText(nodeDelays[group][node]);
            }
            runNodeTests();
        });
    }
    batchTest->setEnabled(proxy.connected && runningTests == 0 && pendingTests.isEmpty());
}
void MainWindow::refreshNodes() {
    QSignalBlocker block(groupChoice);
    const auto previous = groupChoice->currentText();
    QStringList groups;
    for (auto it = proxy.proxies.begin(); it != proxy.proxies.end(); ++it)
        if (it.value().toObject().value("all").isArray())
            groups << it.key();
    QStringList shown;
    for (int i = 0; i < groupChoice->count(); ++i)
        shown << groupChoice->itemText(i);
    if (groups != shown) {
        groupChoice->clear();
        groupChoice->addItems(groups);
        const auto preferred = groupChoice->findText(previous);
        groupChoice->setCurrentIndex(preferred >= 0 ? preferred : qMax(0, groupChoice->findText("六角选择")));
    }
    const auto groupName = groupChoice->currentText();
    const auto group = proxy.proxies.value(groupName).toObject();
    const auto selected = group.value("now").toString();
    currentNode->setText("当前节点 · " + (selected.isEmpty() ? "—" : selected));
    currentNode->setToolTip(selected);
    batchTest->setEnabled(proxy.connected && group.value("all").toArray().size() > 0 && runningTests == 0 &&
                          pendingTests.isEmpty());
    QSet<QString> backups;
    for (auto value : readObject(store.file("node_failover.json")).value("backups").toArray()) {
        const auto backup = value.toObject();
        if (backup.value("group") == groupName)
            backups.insert(backup.value("node").toString());
    }
    QList<QWidget *> cards;
    nodeDelayLabels.clear();
    for (auto value : group.value("all").toArray()) {
        const auto name = value.toString();
        if (!name.contains(nodeFilter->text(), Qt::CaseInsensitive))
            continue;
        auto frame = new QFrame;
        frame->setProperty("surface", true);
        frame->setProperty("selectedCard", selected == name);
        auto layout = new QVBoxLayout(frame);
        layout->setContentsMargins(14, 10, 14, 10);
        layout->setSpacing(6);
        auto nodeName = label(name);
        nodeName->setToolTip(name);
        layout->addWidget(nodeName);
        ActionLayout *row;
        actionRow(layout, &row);
        const auto history = proxy.proxies.value(name).toObject().value("history").toArray();
        const auto last = history.isEmpty() ? 0 : history.last().toObject().value("delay").toInt();
        auto delay = label(
            nodeDelays.value(groupName).value(name, last > 0 ? QString::number(last) + " ms" : "未测速"));
        delay->setObjectName("statValue");
        nodeDelayLabels.insert(name, delay);
        row->addWidget(delay, 1);
        button(row, "测", [this, groupName, name] {
            pendingTests.enqueue({groupName, name});
            runNodeTests();
        })->setEnabled(proxy.connected);
        button(row, backups.contains(name) ? "★ 备选" : "☆ 备选",
               [this, groupName, name] { proxy.toggleBackup(groupName, name); });
        button(row, selected == name ? "已选" : "选择", [this, groupName, name] {
            proxy.selectNode(groupName, name);
        })->setEnabled(proxy.connected && selected != name);
        cards.append(frame);
    }
    nodeCards->setCards(std::move(cards),
                        proxy.connected ? "没有匹配的节点" : "连接代理后显示当前订阅的节点");
}

void MainWindow::buildSubscriptions() {
    QVBoxLayout *layout;
    page({}, {}, &layout);
    auto panels = new AdaptivePanels(850, 1, 620);
    layout->addWidget(panels, 1);
    auto import = panels->addPanel("导入");
    auto saved = panels->addPanel("已导入");
    panels->setRowStretch(1, 1);
    QVBoxLayout *section;
    card(import, "订阅地址", &section);
    subscriptionName = new QLineEdit;
    subscriptionName->setPlaceholderText("订阅名称（可选）");
    section->addWidget(subscriptionName);
    ActionLayout *row;
    actionRow(section, &row);
    subscriptionSource = new QLineEdit;
    subscriptionSource->setPlaceholderText("https://…");
    row->addWidget(subscriptionSource, 1);
    button(
        row, "添加订阅",
        [this] {
            const auto source = subscriptionSource->text().trimmed();
            const QUrl url(source);
            if ((url.scheme() != "http" && url.scheme() != "https") || url.host().isEmpty()) {
                showMessage("请输入有效的 HTTP / HTTPS 订阅地址");
                return;
            }
            proxy.importSubscription(subscriptionName->text(), source);
        },
        true);
    card(import, "V2 分享链接", &section);
    auto links = new QPlainTextEdit;
    links->setPlaceholderText("每行一条分享链接，例如 vless://…");
    links->setFixedHeight(84);
    section->addWidget(links);
    actionRow(section, &row);
    button(row, "导入 V2", [this, links] {
        if (!links->toPlainText().trimmed().isEmpty())
            proxy.importSubscription(subscriptionName->text(), links->toPlainText());
    });
    button(row, "导入本地 YAML", [this] {
        const auto path =
            QFileDialog::getOpenFileName(this, "选择代理配置", {}, "代理配置 (*.yaml *.yml *.txt)");
        if (!path.isEmpty())
            proxy.importSubscription(subscriptionName->text(), path);
    });

    auto listCard = card(saved, "已导入的订阅", &section);
    saved->setStretchFactor(listCard, 1);
    subscriptionCards = new CardPager;
    subscriptionCards->setObjectName("subscriptionCards");
    section->addWidget(subscriptionCards, 1);
}
void MainWindow::refreshSubscriptions() {
    const auto index = proxy.subscriptions();
    QList<QWidget *> cards;
    QString activeName;
    for (const auto &value : index.value("subscriptions").toArray()) {
        const auto entry = value.toObject();
        const auto id = entry.value("id").toString();
        const auto type = entry.value("type").toString();
        const auto name = entry.value("name").toString("订阅");
        const bool active = index.value("active_id") == id;
        if (active)
            activeName = name;
        auto frame = new QFrame;
        frame->setProperty("surface", true);
        frame->setProperty("selectedCard", active);
        auto layout = new QVBoxLayout(frame);
        layout->setContentsMargins(12, 8, 12, 8);
        layout->setSpacing(6);
        layout->addWidget(label(name));
        const auto kind = type == "http" ? "HTTP 订阅" : type == "v2" ? "V2 分享链接" : "本地配置";
        layout->addWidget(label(QString(kind) + (active ? " · 当前使用" : "")));
        ActionLayout *row;
        actionRow(layout, &row);
        button(row, active ? "使用中" : "切换", [this, id] {
            proxy.activateSubscription(id);
        })->setEnabled(!active);
        if (!entry.value("url").toString().isEmpty() || type == "http")
            button(row, "刷新订阅", [this, id] { proxy.refreshSubscription(id); });
        button(row, "删除", [this, id] {
            if (confirm("删除订阅", "删除此订阅入口？"))
                proxy.removeSubscription(id);
        })->setEnabled(!active);
        cards.append(frame);
    }
    activeSubscription->setText(activeName.isEmpty() ? "内置直连配置" : activeName);
    subscriptionCards->setCards(std::move(cards), "还没有导入订阅");
}
void MainWindow::buildRouting() {
    QVBoxLayout *layout;
    page("应用分流", "为 Windows 应用选择代理或直连，修改后下次连接生效。", &layout);
    ActionLayout *row;
    actionRow(layout, &row);
    button(
        row, "添加应用",
        [this] {
            auto path = QFileDialog::getOpenFileName(this, "选择应用", {}, "Windows 应用 (*.exe)");
            if (path.isEmpty())
                return;
            auto state = readObject(store.file("application_routing.json"));
            auto items = state.value("rules").toArray();
            for (auto a : items)
                if (a.toObject()
                        .value("process_name")
                        .toString()
                        .compare(QFileInfo(path).fileName(), Qt::CaseInsensitive) == 0) {
                    showMessage("此程序已在分流列表中");
                    return;
                }
            items.append(QJsonObject{{"id", randomId()},
                                     {"path", path},
                                     {"display_name", QFileInfo(path).completeBaseName()},
                                     {"process_name", QFileInfo(path).fileName()},
                                     {"target", "proxy"},
                                     {"enabled", true}});
            state["rules"] = items;
            state["enabled"] = true;
            QString e;
            if (!writeObject(store.file("application_routing.json"), state, &e))
                showMessage(e);
            refreshRouting();
        },
        true);
    for (const auto &target : QStringList{"proxy", "direct", "delete"})
        button(row,
               target == "proxy"    ? "走代理"
               : target == "direct" ? "直连"
                                    : "删除",
               [this, target] {
                   auto id = selectedId(routingTree);
                   if (id.isEmpty())
                       return;
                   auto state = readObject(store.file("application_routing.json"));
                   auto items = state.value("rules").toArray();
                   for (qsizetype i = 0; i < items.size(); ++i) {
                       auto r = items[i].toObject();
                       if (r.value("id") != id)
                           continue;
                       if (target == "delete")
                           items.removeAt(i);
                       else {
                           r["target"] = target;
                           items[i] = r;
                       }
                       break;
                   }
                   state["rules"] = items;
                   QString e;
                   if (!writeObject(store.file("application_routing.json"), state, &e))
                       showMessage(e);
                   refreshRouting();
               });
    routingTree = tree({"程序", "进程名", "策略"}, layout);
}
void MainWindow::refreshRouting() {
    QList<QPair<QString, QStringList>> rows;
    for (auto v : readObject(store.file("application_routing.json")).value("rules").toArray()) {
        auto r = v.toObject();
        rows.append({r.value("id").toString(),
                     {r.value("display_name").toString(), r.value("process_name").toString(),
                      r.value("target") == "direct" ? "直连" : "走代理"}});
    }
    updateRows(routingTree, rows);
}
void MainWindow::buildTerminal() {
    QVBoxLayout *layout;
    page("终端", "命令在独立进程运行，输出按批次显示，不阻塞窗口交互。", &layout);
    QVBoxLayout *options, *console, *input;
    card(layout, "", &options);
    ActionLayout *row;
    actionRow(options, &row);
    shellChoice = new QComboBox;
    shellChoice->addItems({"PowerShell", "CMD"});
    row->addWidget(label("运行目录"));
    terminalDirectory = new QLineEdit(
        store.settings.value("terminal_directory").toString(qEnvironmentVariable("USERPROFILE")));
    row->addWidget(terminalDirectory, 1);
    button(row, "选择目录", [this] {
        auto p = QFileDialog::getExistingDirectory(this, "终端工作目录", terminalDirectory->text());
        if (!p.isEmpty()) {
            terminalDirectory->setText(p);
            store.settings["terminal_directory"] = p;
            saveSettings();
        }
    });
    button(row, "重置", [this] {
        terminalDirectory->setText(QDir::homePath());
        store.settings["terminal_directory"] = terminalDirectory->text();
        saveSettings();
    });
    row->addWidget(shellChoice);
    auto outputCard = card(layout, "", &console);
    layout->setStretchFactor(outputCard, 1);
    actionRow(console, &row);
    row->addWidget(label("输出"), 1);
    button(row, "清空", [this] { terminalOutput->clear(); });
    terminalOutput = new QPlainTextEdit;
    terminalOutput->setObjectName("terminalOutput");
    terminalOutput->setReadOnly(true);
    terminalOutput->setMaximumBlockCount(4000);
    terminalOutput->setMinimumHeight(60);
    terminalOutput->setPlainText("Hexagon Terminal 已就绪。");
    console->addWidget(terminalOutput, 1);
    card(layout, "命令输入", &input);
    terminalInput = new QTextEdit;
    terminalInput->setAcceptRichText(false);
    terminalInput->setPlaceholderText("输入命令；进程运行时可向其标准输入发送文本");
    terminalInput->setFixedHeight(70);
    input->addWidget(terminalInput);
    actionRow(input, &row);
    terminalRun = button(row, "运行 / 发送", [this] { runTerminal(); }, true);
    terminalStop = button(row, "停止", [this] { stopTerminal(); });
    button(row, "清空输入", [this] { terminalInput->clear(); });
    actionRow(input, &row);
    presetChoice = new QComboBox;
    row->addWidget(presetChoice, 1);
    button(row, "保存命令", [this] {
        bool ok;
        auto name = QInputDialog::getText(this, "保存常用命令", "命令名称", QLineEdit::Normal, {}, &ok);
        if (!ok || name.trimmed().isEmpty() || terminalInput->toPlainText().trimmed().isEmpty())
            return;
        auto state = readObject(store.file("terminal_command_presets.json"));
        auto items = state.value("presets").toArray();
        items.append(QJsonObject{{"id", randomId()},
                                 {"name", name.trimmed()},
                                 {"shell", shellChoice->currentIndex() == 0 ? "powershell" : "cmd"},
                                 {"command", terminalInput->toPlainText()}});
        state["version"] = 1;
        state["presets"] = items;
        QString e;
        if (!writeObject(store.file("terminal_command_presets.json"), state, &e))
            showMessage(e);
        refreshPresets();
    });
    button(row, "删除预设", [this] {
        auto id = presetChoice->currentData().toString();
        if (id.isEmpty() || !confirm("删除常用命令", "删除此命令预设？"))
            return;
        auto state = readObject(store.file("terminal_command_presets.json"));
        auto items = state.value("presets").toArray();
        for (qsizetype i = 0; i < items.size(); ++i)
            if (items[i].toObject().value("id") == id) {
                items.removeAt(i);
                break;
            }
        state["presets"] = items;
        writeObject(store.file("terminal_command_presets.json"), state);
        refreshPresets();
    });
    connect(presetChoice, qOverload<int>(&QComboBox::activated), this, [this](int i) {
        auto id = presetChoice->itemData(i).toString();
        for (auto p : readObject(store.file("terminal_command_presets.json")).value("presets").toArray()) {
            auto v = p.toObject();
            if (v.value("id") == id) {
                terminalInput->setPlainText(v.value("command").toString());
                shellChoice->setCurrentIndex(v.value("shell") == "cmd" ? 1 : 0);
            }
        }
    });
    hiddenProcess(&terminalProcess);
    auto env = QProcessEnvironment::systemEnvironment();
    env.remove("PSModulePath");
    terminalProcess.setProcessEnvironment(env);
    connect(&terminalProcess, &QProcess::readyReadStandardOutput, this,
            [this] { terminalBuffer += terminalProcess.readAllStandardOutput(); });
    connect(&terminalProcess, &QProcess::readyReadStandardError, this,
            [this] { terminalBuffer += terminalProcess.readAllStandardError(); });
    terminalFlush.setInterval(100);
    connect(&terminalFlush, &QTimer::timeout, this, [this] {
        if (terminalBuffer.isEmpty())
            return;
        QString text = QString::fromUtf8(terminalBuffer);
        terminalBuffer.clear();
        text.remove(QRegularExpression("\\x1b\\[[0-?]*[ -/]*[@-~]"));
        auto cursor = terminalOutput->textCursor();
        cursor.movePosition(QTextCursor::End);
        cursor.insertText(text);
        terminalOutput->setTextCursor(cursor);
    });
    terminalFlush.start();
    connect(&terminalProcess, &QProcess::finished, this, [this](int code, QProcess::ExitStatus) {
        terminalBuffer += "\n[进程退出 " + QByteArray::number(code) + "]\n";
        terminalStop->setEnabled(false);
    });
    connect(&terminalProcess, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart)
            showMessage("终端启动失败：" + terminalProcess.errorString());
    });
    terminalStop->setEnabled(false);
    refreshPresets();
}
void MainWindow::runTerminal() {
    auto text = terminalInput->toPlainText();
    if (text.trimmed().isEmpty())
        return;
    if (terminalProcess.state() != QProcess::NotRunning) {
        terminalProcess.write(text.toUtf8() + "\n");
        return;
    }
    if (!QDir(terminalDirectory->text()).exists()) {
        showMessage("终端工作目录不存在");
        return;
    }
    terminalProcess.setWorkingDirectory(terminalDirectory->text());
    if (shellChoice->currentIndex() == 0)
        terminalProcess.start("powershell.exe",
                              {"-NoLogo", "-NoProfile", "-Command",
                               "[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);" + text});
    else
        terminalProcess.start("cmd.exe", {"/d", "/s", "/c", "chcp 65001 >nul & " + text});
    terminalStop->setEnabled(true);
}
void MainWindow::stopTerminal() {
    if (terminalProcess.state() == QProcess::NotRunning || terminalStopPending)
        return;
    terminalStopPending = true;
    auto pid = terminalProcess.processId();
    runProcess(
        this, "taskkill.exe", {"/PID", QString::number(pid), "/T", "/F"},
        [this](int, QByteArray, QByteArray) {
            terminalStopPending = false;
            if (quitting)
                QTimer::singleShot(0, this, [this] { close(); });
        },
        10000);
}
void MainWindow::refreshPresets() {
    QSignalBlocker block(presetChoice);
    presetChoice->clear();
    presetChoice->addItem("常用命令", QString());
    for (auto v : readObject(store.file("terminal_command_presets.json")).value("presets").toArray()) {
        auto p = v.toObject();
        presetChoice->addItem(p.value("name").toString(), p.value("id"));
    }
}
void MainWindow::buildLinux() {
    auto pageRoot = new QWidget;
    auto outer = new QVBoxLayout(pageRoot);
    outer->setContentsMargins(0, 0, 0, 0);
    pages->addWidget(pageRoot);
    linuxTabs = new QTabWidget;
    linuxTabs->setObjectName("linuxWorkspaceTabs");
    outer->addWidget(linuxTabs, 1);
    auto workspace = new QWidget;
    auto webLayout = new QVBoxLayout(workspace);
    webLayout->setContentsMargins(0, 8, 0, 0);
    ActionLayout *tools;
    actionRow(webLayout, &tools);
    button(tools, "环境设置", [this] { linuxTabs->setCurrentIndex(1); });
    button(tools, "刷新页面", [this] { linuxWeb->reload(); });
    button(tools, "复制登录密码", [this] {
        if (linux.copyPassword())
            showMessage("已复制密码，登录用户名 root", true);
        else
            showMessage("请先安装并启动工作区");
    });
    button(tools, "停止工作区", [this] { linux.stop(); });
    tools->addStretch();
    linuxWeb = new WebWorkspace;
    webLayout->addWidget(linuxWeb, 1);
    linuxTabs->addTab(workspace, "工作区");
    connect(linuxWeb, &WebWorkspace::failed, this, [this](QString e) { showMessage(e); });
    connect(&linux, &LinuxWorkspace::openRequested, this, [this](QUrl url) {
        linuxWeb->navigateLocal(url, linux.root() + "/webview");
        linuxTabs->setCurrentIndex(0);
    });
    auto layout = tabPage(linuxTabs, "安装与启动");
    auto maintenance = tabPage(linuxTabs, "磁盘与维护");
    linuxTabs->setCurrentIndex(1);
    QVBoxLayout *section;
    card(layout, "运行环境", &section);
    diskStatus = label("");
    diskStatus->setObjectName("sectionTitle");
    section->addWidget(diskStatus);
    section->addWidget(label("安装目录"));
    ActionLayout *directoryRow;
    actionRow(section, &directoryRow);
    linuxDirectory = new QLineEdit(linux.root());
    linuxDirectory->setObjectName("linuxInstallDirectory");
    directoryRow->addWidget(linuxDirectory, 1);
    linuxChooseDirectory = button(directoryRow, "选择目录", [this] {
        auto selected =
            QFileDialog::getExistingDirectory(this, "选择 HexagonLinux 安装目录", linuxDirectory->text());
        if (!selected.isEmpty())
            linuxDirectory->setText(selected);
    });
    linuxApplyDirectory = button(directoryRow, "应用目录", [this] {
        if (linux.setDirectory(linuxDirectory->text())) {
            diskSlider->setValue(linux.capacity);
            showMessage("安装目录已切换，原目录及文件保留", true);
        }
    });
    section->addWidget(
        label("可指定安装路径或选择已有工作区。更改目录不会搬移或删除原磁盘；选择空目录会新建工作区。"));
    auto installSection = section;
    card(maintenance, "系统盘与维护", &section);
    diskLabel = label("");
    section->addWidget(diskLabel);
    diskSlider = new QSlider(Qt::Horizontal);
    diskSlider->setObjectName("diskCapacitySlider");
    diskSlider->setRange(1, 10);
    diskSlider->setValue(linux.capacity);
    section->addWidget(diskSlider);
    connect(diskSlider, &QSlider::valueChanged, this,
            [this](int n) { diskLabel->setText(QString("系统盘上限：%1 GB").arg(n)); });
    diskUsage = label("");
    section->addWidget(diskUsage);
    section->addWidget(label("动态增长，停止后可扩容；已有系统盘不能缩小。"));
    auto diskSection = section;
    section = installSection;
    ActionLayout *row;
    actionRow(section, &row);
    diskStart = button(
        row, "安装并启动",
        [this] {
            const int requested = diskSlider->value();
            if (QDir::cleanPath(linuxDirectory->text()) != QDir::cleanPath(linux.root()) &&
                !linux.setDirectory(linuxDirectory->text()))
                return;
            linux.start(requested);
        },
        true);
    diskStop = button(row, "停止工作区", [this] { linux.stop(); });
    diskOpen = button(row, "进入工作区", [this] { linux.open(); });
    section = diskSection;
    actionRow(section, &row);
    button(row, "复制登录密码", [this] {
        if (linux.copyPassword())
            showMessage("已复制本机工作区登录密码；用户名 root", true);
        else
            showMessage("尚未生成登录密码，请先安装并启动工作区");
    });
    button(row, "数据目录", [this] {
        QDir().mkpath(linux.root());
        QDesktopServices::openUrl(QUrl::fromLocalFile(linux.root()));
    });
    diskReset = button(row, "重建系统盘", [this] {
        if (confirm("重建系统盘",
                    "将删除 Linux 内的全部文件、程序和登录信息。Windows 项目及其他账号数据不会被删除。"))
            linux.reset();
    });
    diskError = label("");
    diskError->setObjectName("errorText");
    installSection->addWidget(diskError);
    button(maintenance, "使用说明", [this] {
        QMessageBox::information(this, "HexagonLinux",
                                 "工作区在软件内显示；登录用户 "
                                 "root，密码由本机随机生成。切换页面保留终端，停止时保存磁盘。\n系统盘 1～10 "
                                 "GB，停止后可扩容；QEMU、只读资源及页面缓存另占空间。\n默认分配 512 MB "
                                 "内存、2 个虚拟 CPU，采用软件模拟。");
    });
    maintenance->addStretch();
    layout->addStretch();
}
void MainWindow::refreshLinux() {
    if (linux.ready) {
        QUrl url(QString("http://127.0.0.1:%1/").arg(linux.webPort));
        if (linuxWeb->url() != url) {
            linuxWeb->navigateLocal(url, linux.root() + "/webview");
            linuxTabs->setCurrentIndex(0);
        }
    } else if ((linux.stopping || !linux.running()) && !linuxWeb->url().isEmpty())
        linuxWeb->clear(linux.error.isEmpty() ? "工作区已停止，文件已保留。请到环境设置启动。" : linux.error);
    const bool idle = !linux.busy && !linux.running();
    linuxDirectory->setEnabled(idle);
    linuxChooseDirectory->setEnabled(idle);
    linuxApplyDirectory->setEnabled(idle);
    if (linux.running())
        diskSlider->setValue(linux.capacity);
    diskStatus->setText(linux.status);
    diskLabel->setText(QString("系统盘上限：%1 GB").arg(diskSlider->value()));
    diskUsage->setText("镜像文件：" + bytesText(QFileInfo(linux.disk()).size()) + " · 按实际数据增长");
    diskUsage->setToolTip(linux.root());
    diskError->setText(linux.error);
    diskSlider->setEnabled(!linux.busy && !linux.running());
    diskStart->setEnabled(!linux.busy && !linux.running());
    diskStart->setText(linux.installed() ? "启动 / 应用扩容" : "安装并启动");
    diskStop->setEnabled((linux.running() || linux.busy) && !linux.stopping);
    diskOpen->setEnabled(linux.ready);
    diskReset->setEnabled(linux.installed() && !linux.busy && !linux.running());
}

void MainWindow::buildCodex() {
    QVBoxLayout *layout, *section;
    page({}, {}, &layout);
    card(layout, "Codex 桌面账号", &section);
    codexStatus = label("");
    section->addWidget(codexStatus);
    ActionLayout *row;
    actionRow(section, &row);
    codexName = new QLineEdit;
    codexName->setPlaceholderText("账号备注，例如工作号 / 备用号");
    row->addWidget(codexName, 1);
    button(row, "新建账号配置", [this] { accounts.codexAction("prepare", {}, codexName->text()); });
    actionRow(section, &row);
    button(row, "授权添加账号", [this] { accounts.codexAction("login", {}, codexName->text()); }, true);
    button(row, "启动当前配置", [this] { accounts.codexAction("launch", accounts.codexSelected()); });
    button(row, "刷新状态", [this] { accounts.codexAction("inspect"); });
    button(row, "导入 auth.json", [this] {
        const auto path = QFileDialog::getOpenFileName(this, "选择 Codex 登录文件", {}, "登录文件 (*.json)");
        if (!path.isEmpty())
            accounts.codexAction("import", {}, codexName->text(), path);
    });
    button(row, "保存为独立账号", [this] { accounts.codexAction("capture", {}, codexName->text()); });
    button(row, "恢复中断切换", [this] { accounts.codexAction("recover"); });
    auto accountsCard = card(layout, "账号配置", &section);
    layout->setStretchFactor(accountsCard, 1);
    codexCards = new CardPager;
    codexCards->setObjectName("codexCards");
    section->addWidget(codexCards, 1);
}
void MainWindow::buildAntigravity() {
    QVBoxLayout *layout;
    page("账号与连接", "共享项目和对话，分别管理 Antigravity 登录和模型额度。", &layout);
    QVBoxLayout *section;
    auto panels = new AdaptivePanels(920, 2);
    layout->addWidget(panels, 1);
    auto connectionTab = panels->addPanel("网络连接");
    auto accountTab = panels->addPanel("账号管理");
    panels->showPanel(1);
    auto connectionCard = card(connectionTab, "网络连接", &section);
    connectionTab->setStretchFactor(connectionCard, 1);
    antigravityExe = new QLineEdit(store.settings.value("antigravity_exe").toString());
    section->addWidget(label("应用程序"));
    section->addWidget(antigravityExe);
    ActionLayout *row;
    actionRow(section, &row);
    button(row, "选择程序", [this] {
        auto p = QFileDialog::getOpenFileName(this, "选择 Antigravity", antigravityExe->text(),
                                              "Windows 应用 (*.exe)");
        if (!p.isEmpty()) {
            antigravityExe->setText(p);
            store.settings["antigravity_exe"] = p;
            saveSettings();
        }
    });
    button(row, "启用 / 同步端口", [this] {
        store.settings["antigravity_exe"] = antigravityExe->text();
        saveSettings();
        accounts.antigravityProxyAction("enable");
    });
    button(row, "通过代理启动", [this] {
        if (!proxy.connected) {
            showMessage("请先连接代理");
            return;
        }
        accounts.antigravityAction("launch", accounts.antigravityDefault());
    });
    button(row, "卸载并恢复", [this] { accounts.antigravityProxyAction("disable"); });
    button(row, "刷新状态", [this] { accounts.antigravityProxyAction("inspect"); });
    proxyMessage = label("");
    section->addWidget(proxyMessage);
    section->addWidget(label("通过本地 SOCKS5 代理连接，无需启用 TUN。"));
    section->addStretch(1);
    auto accountCard = card(accountTab, "账号管理", &section);
    accountTab->setStretchFactor(accountCard, 1);
    antigravityName = new QLineEdit;
    antigravityName->setPlaceholderText("账号备注（可选）");
    section->addWidget(antigravityName);
    actionRow(section, &row);
    button(row, "添加账号并登录", [this] { accounts.addAntigravity(antigravityName->text()); }, true);
    accountMessage = label("");
    section->addWidget(accountMessage);
    antigravityCards = new CardPager;
    antigravityCards->setObjectName("antigravityCards");
    section->addWidget(antigravityCards, 1);
    quotaDialog = new QDialog(this);
    quotaDialog->setWindowTitle("Antigravity 账号额度");
    quotaDialog->resize(800, 475);
    auto quotaLayout = new QVBoxLayout(quotaDialog);
    quotaMessage = label("");
    quotaLayout->addWidget(quotaMessage);
    quotaTree = tree({"模型", "剩余额度", "重置时间"}, quotaLayout);
}

void MainWindow::refreshAccounts() {
    const auto codexKey = QJsonDocument(accounts.codexIndex).toJson(QJsonDocument::Compact);
    if (codexKey != codexViewKey) {
        codexViewKey = codexKey;
        QList<QWidget *> cards;
        QString currentName;
        for (auto value : accounts.codexAccounts()) {
            const auto account = value.toObject();
            const auto id = account.value("id").toString();
            const auto usage = account.value("usage").toObject();
            const auto name = account.value("name").toString("Codex 账号");
            const bool current = accounts.codexSelected() == id;
            if (current)
                currentName = name;
            auto frame = new QFrame;
            frame->setProperty("surface", true);
            frame->setProperty("selectedCard", current);
            auto layout = new QVBoxLayout(frame);
            layout->setContentsMargins(12, 8, 12, 8);
            layout->setSpacing(4);
            layout->addWidget(label(name + (current ? " · 当前账号" : "")));
            const auto email = account.value("email").toString();
            const auto plan = usage.value("plan").toString();
            if (!email.isEmpty() || !plan.isEmpty()) {
                const auto details = QStringList{email, plan};
                layout->addWidget(label(details.filter(QRegularExpression(".+")).join(" · ")));
            }
            for (const auto &key : {QString("five_hour"), QString("weekly")}) {
                const auto remaining = usage.value(key).toDouble(-1);
                if (remaining < 0)
                    continue;
                auto bar = new QProgressBar;
                bar->setRange(0, 100);
                bar->setValue(qRound(remaining));
                bar->setFormat(key == "weekly" ? "每周剩余 %p%" : "5 小时剩余 %p%");
                layout->addWidget(bar);
                const auto reset = usage.value(key + "_reset").toVariant().toLongLong();
                if (reset > 0) {
                    const auto when =
                        QDateTime::fromSecsSinceEpoch(reset).toLocalTime().toString("yyyy-MM-dd HH:mm");
                    layout->addWidget(label("恢复 " + when));
                }
            }
            ActionLayout *row;
            actionRow(layout, &row);
            button(row, current ? "使用中" : "切换", [this, id] {
                accounts.codexAction("switch", id);
            })->setEnabled(!current);
            button(row, "查额度", [this, id] { accounts.codexAction("usage", id); });
            button(row, "移除", [this, id] {
                if (confirm("移除账号入口", "移除这个账号入口？本地登录备份和对话仍会保留。"))
                    accounts.removeCodex(id);
            })->setEnabled(!current);
            cards.append(frame);
        }
        codexStatus->setText(currentName.isEmpty() ? "当前配置 · —" : "当前配置 · " + currentName);
        codexCards->setCards(std::move(cards), "还没有保存账号");
    }
    const auto antiKey = QJsonDocument(accounts.antigravityIndex).toJson(QJsonDocument::Compact);
    if (antiKey != antiViewKey) {
        antiViewKey = antiKey;
        QList<QWidget *> cards;
        for (auto value : accounts.antigravityAccounts()) {
            const auto account = value.toObject();
            const auto id = account.value("id").toString();
            const bool isDefault = accounts.antigravityDefault() == id;
            const bool recent = accounts.antigravityIndex.value("selected").toString() == id;
            auto frame = new QFrame;
            frame->setProperty("surface", true);
            frame->setProperty("selectedCard", recent);
            auto layout = new QVBoxLayout(frame);
            layout->setContentsMargins(12, 8, 12, 8);
            layout->setSpacing(4);
            layout->addWidget(
                label(account.value("name").toString("Antigravity 账号") + (isDefault ? " · 默认" : "")));
            const auto email = account.value("email").toString();
            if (!email.isEmpty() || recent)
                layout->addWidget(label(email + (recent ? " · 最近打开" : "")));
            ActionLayout *row;
            actionRow(layout, &row);
            button(row, "切换", [this, id] { accounts.antigravityAction("launch", id); }, true);
            button(row, "刷新登录与额度", [this, id] { accounts.antigravityAction("quota", id); });
            if (!isDefault) {
                button(row, "设为默认", [this, id] { accounts.setAntigravityDefault(id); });
                button(row, "删除", [this, id] {
                    if (confirm("删除账号入口", "删除该账号入口和额度缓存？本地登录备份和项目仍会保留。"))
                        accounts.removeAntigravity(id);
                });
            }
            const auto count = accounts.antigravityIndex.value("quotas")
                                   .toObject()
                                   .value(id)
                                   .toObject()
                                   .value("models")
                                   .toArray()
                                   .size();
            button(row, count ? QString("查看额度 · %1").arg(count) : "查看额度", [this, id] {
                selectedQuota = id;
                refreshQuotas();
                quotaDialog->show();
                quotaDialog->raise();
            });
            cards.append(frame);
        }
        antigravityCards->setCards(std::move(cards), "还没有保存账号");
        refreshQuotas();
    }
    codexCards->setEnabled(!accounts.busy);
    antigravityCards->setEnabled(!accounts.busy);
    if (accounts.busy)
        accountMessage->setText("正在处理账号操作…");
    proxyMessage->setText(
        QString("独立代理：%1\n当前代理 · SOCKS5 127.0.0.1:%2")
            .arg(accounts.antigravityProxyState.value("installed").toBool() ? "已启用" : "未启用")
            .arg(store.mixedPort()));
}
void MainWindow::refreshQuotas() {
    auto q = accounts.antigravityIndex.value("quotas").toObject().value(selectedQuota).toObject();
    QList<QPair<QString, QStringList>> rows;
    for (auto v : q.value("models").toArray()) {
        auto m = v.toObject();
        rows.append(
            {m.value("name").toString(),
             {m.value("name").toString(), QString::number(m.value("remaining").toDouble(), 'f', 1) + "%",
              m.value("reset").toString()}});
    }
    updateRows(quotaTree, rows);
    for (int i = 0; i < quotaTree->topLevelItemCount(); ++i) {
        auto item = quotaTree->topLevelItem(i);
        auto bar = qobject_cast<QProgressBar *>(quotaTree->itemWidget(item, 1));
        if (!bar) {
            bar = new QProgressBar;
            bar->setRange(0, 1000);
            bar->setFormat("剩余 %p%");
            quotaTree->setItemWidget(item, 1, bar);
        }
        bar->setValue(qRound(item->text(1).remove('%').toDouble() * 10));
    }
    quotaMessage->setText(q.isEmpty() ? "尚未查询额度。请从账号卡片刷新登录与额度。"
                                      : "上次查询：" + q.value("checked_at").toString());
}

void MainWindow::releasePort(int port) {
    if (proxy.busy || proxy.process.state() != QProcess::NotRunning) {
        showMessage("请先断开代理，再检查占用");
        return;
    }
    const QStringList arguments{
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "RemoteSigned",
        "-File",
        resourcePath("scripts/windows_port_helper.ps1"),
        "-Port",
        QString::number(port),
        "-CallerPid",
        QString::number(QCoreApplication::applicationPid()),
        "-ProtectedNames",
        "system;registry;smss;csrss;wininit;services;lsass;winlogon;svchost;hexagonproxy;unknown"};
    auto inspect = arguments;
    inspect << "-Action" << "inspect";
    runProcess(
        this, "powershell.exe", inspect,
        [this, port, arguments](int exitCode, QByteArray out, QByteArray) {
            const auto result = QJsonDocument::fromJson(out).object();
            if (exitCode != 0 || !result.value("ok").toBool()) {
                showMessage("端口占用检查失败");
                return;
            }
            QStringList owners, pids;
            bool protectedOwner = false;
            for (const auto &value : result.value("processes").toArray()) {
                const auto owner = value.toObject();
                const auto pid = QString::number(owner.value("pid").toInt());
                owners << owner.value("name").toString() + " (PID " + pid + ")";
                pids << pid;
                protectedOwner = protectedOwner || owner.value("protected").toBool();
            }
            if (owners.isEmpty()) {
                showMessage(QString("端口 %1 当前可用").arg(port), true);
                return;
            }
            if (protectedOwner) {
                showMessage("端口由受保护的进程占用，请选择其他端口");
                return;
            }
            if (!confirm("释放端口",
                         QString("结束以下进程以释放端口 %1？\n%2").arg(port).arg(owners.join('\n'))))
                return;
            if (proxy.busy || proxy.process.state() != QProcess::NotRunning) {
                showMessage("代理状态已变化，请先断开后重试");
                return;
            }
            auto release = arguments;
            release << "-Action" << "release" << "-Pids" << pids.join(',');
            runProcess(
                this, "powershell.exe", release,
                [this, port](int code, QByteArray output, QByteArray) {
                    const auto result = QJsonDocument::fromJson(output).object();
                    if (code == 0 && result.value("released").toBool()) {
                        showMessage(QString("端口 %1 已释放").arg(port), true);
                        return;
                    }
                    const auto reason = result.value("message_code").toString();
                    showMessage(reason == "changed"
                                    ? "端口占用进程已变化，请重新检查"
                                    : "端口释放失败（" + (reason.isEmpty() ? "权限或进程状态" : reason) +
                                          "）");
                },
                12000);
        },
        12000);
}

void MainWindow::buildSettings() {
    QVBoxLayout *layout;
    page("偏好设置", "界面、连接和 Windows 集成。", &layout);
    QVBoxLayout *section;
    auto panels = new AdaptivePanels(900, 2, 590);
    panels->setObjectName("settingsPanels");
    layout->addWidget(panels, 1);
    auto appearance = panels->addPanel("界面");
    auto windows = panels->addPanel("窗口");
    auto core = panels->addPanel("内核与启动");
    panels->setRowStretch(1, 1);
    auto network = panels->addPanel("连接");
    card(appearance, "界面与阅读", &section);
    auto f = new QFormLayout;
    section->addLayout(f);
    themes = new QComboBox;
    themes->setObjectName("themeChoice");
    auto catalog =
        QJsonDocument::fromJson(readBytes(":/brand/ui/themes.json")).object().value("themes").toArray();
    for (auto v : catalog) {
        auto t = v.toObject();
        themeCatalog << t;
        themes->addItem(t.value("name").toString(), t.value("id").toString());
    }
    themes->setCurrentIndex(std::max(0, themes->findData(store.settings.value("theme").toString("qq_warm"))));
    f->addRow("色系主题", themes);
    fontSlider = new QSlider(Qt::Horizontal);
    fontSlider->setObjectName("fontScaleSlider");
    fontSlider->setRange(100, 200);
    fontSlider->setValue(store.settings.value("font_percent").toInt(150));
    fontLabel = label(QString::number(fontSlider->value()) + "%");
    auto fontRow = new QHBoxLayout;
    fontRow->addWidget(fontSlider, 1);
    fontRow->addWidget(fontLabel);
    f->addRow("字号大小", fontRow);
    connect(themes, qOverload<int>(&QComboBox::currentIndexChanged), this, [this] {
        store.settings["theme"] = themes->currentData().toString();
        saveSettings();
        applyTheme();
    });
    connect(fontSlider, &QSlider::valueChanged, this, [this](int value) {
        fontLabel->setText(QString::number(value) + "%");
        fontDebounce.start();
    });
    card(core, "Mihomo 内核", &section);
    coreStatus = label("");
    section->addWidget(coreStatus);
    ActionLayout *row;
    actionRow(section, &row);
    button(row, "检查并下载最新内核", [this] { proxy.downloadCore(); }, true);
    button(row, "重启内核", [this] {
        if (proxy.downloading) {
            showMessage("请等待内核下载完成");
            return;
        }
        const bool useSystemProxy = proxy.systemEnabled;
        if (proxy.process.state() == QProcess::NotRunning) {
            if (!proxy.busy)
                proxy.start(false);
            return;
        }
        const auto connection = std::make_shared<QMetaObject::Connection>();
        *connection = connect(&proxy.process, &QProcess::finished, this, [this, connection, useSystemProxy] {
            disconnect(*connection);
            QTimer::singleShot(0, this, [this, useSystemProxy] {
                if (!quitting)
                    proxy.start(useSystemProxy);
            });
        });
        proxy.stop();
    });
    button(row, "打开运行目录", [this] {
        QDir().mkpath(store.runtime());
        QDesktopServices::openUrl(QUrl::fromLocalFile(store.runtime()));
    });
    card(network, "连接设置", &section);
    systemCheck = new QCheckBox("Windows 系统代理");
    tunCheck = new QCheckBox("TUN 全局接管（需要管理员权限）");
    section->addWidget(systemCheck);
    section->addWidget(tunCheck);
    connect(systemCheck, &QCheckBox::toggled, this, [this](bool checked) {
        QString e;
        if (!proxy.setSystemProxy(checked, &e)) {
            QSignalBlocker b(systemCheck);
            systemCheck->setChecked(proxy.systemEnabled);
            showMessage(e);
        }
    });
    connect(tunCheck, &QCheckBox::toggled, this, [this](bool on) {
        if (proxy.busy) {
            QSignalBlocker b(tunCheck);
            tunCheck->setChecked(proxy.tunEnabled);
            return;
        }
        proxy.tunEnabled = on;
        if (on)
            proxy.setSystemProxy(false);
        if (proxy.process.state() != QProcess::NotRunning) {
            auto connection = std::make_shared<QMetaObject::Connection>();
            *connection = connect(&proxy.process, &QProcess::finished, this, [this, connection] {
                disconnect(*connection);
                QTimer::singleShot(200, &proxy, [this] { proxy.start(true); });
            });
            proxy.stop();
        }
    });
    f = new QFormLayout;
    section->addLayout(f);
    mixedSpin = new QSpinBox;
    mixedSpin->setRange(1024, 65535);
    mixedSpin->setValue(store.mixedPort());
    controllerSpin = new QSpinBox;
    controllerSpin->setRange(1024, 65535);
    controllerSpin->setValue(store.controllerPort());
    auto portRow = [this](QSpinBox *spin, QSpinBox *other) {
        auto widget = new QWidget;
        auto row = new ActionLayout(widget);
        row->setContentsMargins(0, 0, 0, 0);
        row->addWidget(spin, 1);
        button(row, "随机", [this, spin, other] {
            QTcpServer socket;
            if (socket.listen(QHostAddress::LocalHost, 0) && socket.serverPort() != other->value())
                spin->setValue(socket.serverPort());
            else
                showMessage("未找到可用端口，请重试");
        });
        button(row, "释放占用", [this, spin] { releasePort(spin->value()); });
        return widget;
    };
    f->setRowWrapPolicy(QFormLayout::WrapLongRows);
    f->addRow("本地混合端口", portRow(mixedSpin, controllerSpin));
    f->addRow("控制接口端口", portRow(controllerSpin, mixedSpin));
    button(section, "保存端口", [this] {
        if (proxy.process.state() != QProcess::NotRunning) {
            showMessage("请先断开代理再修改端口");
            return;
        }
        if (mixedSpin->value() == controllerSpin->value()) {
            showMessage("两个端口不能相同");
            return;
        }
        QTcpServer a, b;
        if (!a.listen(QHostAddress::LocalHost, mixedSpin->value()) ||
            !b.listen(QHostAddress::LocalHost, controllerSpin->value())) {
            showMessage("所选端口已被占用");
            return;
        }
        store.settings["mixed_port"] = mixedSpin->value();
        store.settings["controller_port"] = controllerSpin->value();
        saveSettings();
        showMessage("端口已保存，下次连接生效", true);
    });
    card(windows, "窗口显示", &section);
    auto maximize = new QCheckBox("最大化显示（适应屏幕）");
    section->addWidget(maximize);
    connect(maximize, &QCheckBox::toggled, this, [this](bool checked) {
        if (checked)
            showMaximized();
        else
            showNormal();
    });
    actionRow(section, &row);
    row->addWidget(label("窗口分辨率"));
    auto sizes = new QComboBox;
    for (const auto size :
         {QSize(1280, 720), QSize(1440, 810), QSize(1600, 900), QSize(1920, 1080), QSize(2560, 1440)})
        sizes->addItem(QString("%1 × %2").arg(size.width()).arg(size.height()), size);
    sizes->setCurrentIndex(2);
    row->addWidget(sizes);
    button(row, "应用窗口", [this, sizes, maximize] {
        maximize->setChecked(false);
        showNormal();
        const auto available = screen()->availableGeometry();
        resize(sizes->currentData().toSize().boundedTo(available.size()));
        move(available.center() - rect().center());
    });
    card(core, "关闭窗口与启动", &section);
    closeChoice = new QComboBox;
    closeChoice->addItems({"每次询问", "最小化到托盘", "退出程序"});
    closeChoice->setCurrentIndex(store.settings.value("close_behavior").toInt());
    f = new QFormLayout;
    section->addLayout(f);
    f->addRow("关闭主窗口", closeChoice);
    connect(closeChoice, qOverload<int>(&QComboBox::currentIndexChanged), this, [this](int i) {
        store.settings["close_behavior"] = i;
        saveSettings();
    });
    petCheck = new QCheckBox("显示六角恐龙桌面宠物");
    petCheck->setChecked(store.settings.value("show_pet").toBool());
    section->addWidget(petCheck);
    connect(petCheck, &QCheckBox::toggled, this, [this](bool on) {
        store.settings["show_pet"] = on;
        saveSettings();
        if (pet)
            pet->setVisible(on);
    });
    startupCheck = new QCheckBox("登录 Windows 后启动到托盘");
    startupCheck->setChecked(store.settings.value("autostart").toBool());
    section->addWidget(startupCheck);
    connect(startupCheck, &QCheckBox::toggled, this, [this](bool on) {
        QSettings reg("HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
                      QSettings::NativeFormat);
        if (on)
            reg.setValue(
                "HexagonProxy",
                '"' +
                    store.settings.value("launcher_path").toString(QCoreApplication::applicationFilePath()) +
                    "\" --tray-start");
        else
            reg.remove("HexagonProxy");
        reg.sync();
        if (reg.status() != QSettings::NoError) {
            showMessage("无法保存开机启动设置");
            return;
        }
        store.settings["autostart"] = on;
        saveSettings();
    });
    actionRow(section, &row);
    button(row, "打开数据目录", [this] { QDesktopServices::openUrl(QUrl::fromLocalFile(store.root)); });
    button(row, "关于", [this] {
        QMessageBox::information(this, "HexagonProxy",
                                 "HexagonProxy 0.5.4 · C++ / Qt Widgets\n六角恐龙，守护每一次连接");
    });
    appearance->addStretch();
    core->addStretch();
    network->addStretch();
    windows->addStretch();
}
static QIcon switchMark(QColor color, bool checked) {
    QPixmap pixels(56, 32);
    pixels.setDevicePixelRatio(2);
    pixels.fill(Qt::transparent);
    QPainter painter(&pixels);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.setPen(Qt::NoPen);
    color.setAlpha(checked ? 255 : 95);
    painter.setBrush(color);
    painter.drawRoundedRect(QRectF(0, 1, 28, 14), 7, 7);
    painter.setBrush(Qt::white);
    painter.drawEllipse(QRectF(checked ? 15 : 2, 3, 10, 10));
    return QIcon(pixels);
}
void MainWindow::refreshProxy() {
    if (!connectButton)
        return;
    connectButton->setEnabled(!proxy.downloading);
    connectButton->setChecked(proxy.connected || (proxy.busy && !proxy.downloading));
    connectButton->setIcon(switchMark(plot->accent, connectButton->isChecked()));
    for (auto mode : modeButtons->buttons()) {
        mode->setChecked(mode->property("proxyMode").toString() == proxy.mode);
        mode->setEnabled(proxy.connected);
    }
    dashboardStatus->setText(proxy.connected ? "代理内核已连接" : proxy.busy ? "正在启动…" : "代理未连接");
    if (!proxy.connected) {
        pendingTests.clear();
        batchTest->setEnabled(false);
    }
    connectButton->setText(proxy.busy ? "取消连接" : proxy.connected ? "断开连接" : "一键连接");
    statusPill->setText(proxy.connected ? (proxy.systemEnabled || proxy.tunEnabled ? "● 已连接" : "● 仅内核")
                        : proxy.downloading ? "● 下载中…"
                        : proxy.busy        ? "● 连接中…"
                                            : "● 未连接");
    if (systemCheck) {
        QSignalBlocker block(systemCheck);
        systemCheck->setChecked(proxy.systemEnabled);
    }
    if (coreStatus)
        coreStatus->setText(proxy.downloading                 ? "正在查询、下载并验证 Mihomo，请稍候…"
                            : QFile::exists(proxy.corePath()) ? "Mihomo 内核已安装"
                                                              : "尚未安装，请下载最新内核。");
    if (quitting)
        QTimer::singleShot(0, this, [this] { close(); });
}
void MainWindow::updateTraffic(QJsonObject c) {
    auto down = qint64(c.value("downloadTotal").toDouble()), up = qint64(c.value("uploadTotal").toDouble());
    double seconds = trafficTime.isValid() ? trafficTime.restart() / 1000.0 : 2.0;
    if (!trafficTime.isValid())
        trafficTime.start();
    double ds = lastDownload >= 0 ? std::max<qint64>(0, down - lastDownload) / std::max(0.01, seconds) : 0,
           us = lastUpload >= 0 ? std::max<qint64>(0, up - lastUpload) / std::max(0.01, seconds) : 0;
    lastDownload = down;
    lastUpload = up;
    speedLabel->setText(bytesText(ds) + "/s");
    uploadLabel->setText(bytesText(us) + "/s");
    totalLabel->setText(bytesText(down + up));
    connectionLabel->setText(QString::number(c.value("connections").toArray().size()));
    if (pages->currentIndex() == 0)
        plot->push(ds);
}
void MainWindow::applyTheme() {
    theme = {};
    for (const auto &t : themeCatalog)
        if (t.value("id") == themes->currentData().toString())
            theme = t;
    auto colors = theme.value("colors").toObject();
    auto c = [&](const QString &role, const QString &fallback) {
        return cssColor(color(colors.value(role).toString(fallback)));
    };
    const auto text = c("text", "#fffaf3"), surface = c("surface", "#48453f"), muted = c("muted", "#ddd9d2"),
               accent = c("accent", "#d4b77b"), border = c("border", "#555149"),
               input = c("input", "#56524b"), hover = c("surface2", "#514e48"), nav = c("sidebar", "#403d37"),
               rail = c("rail", "#393630"), danger = c("danger", "#f09a96"),
               primary = c("primary_text", "#302c24");
    QString background = surface;
    auto gradient = theme.value("background_gradient").toArray();
    if (gradient.size() == 4)
        background =
            QString("qlineargradient(x1:0,y1:0,x2:1,y2:1,stop:0 %1,stop:0.35 %2,stop:0.7 %3,stop:1 %4)")
                .arg(cssColor(color(gradient[0].toString())), cssColor(color(gradient[1].toString())),
                     cssColor(color(gradient[2].toString())), cssColor(color(gradient[3].toString())));
    QFont font("Microsoft YaHei UI");
    font.setPointSizeF(10.0 * fontSlider->value() / 100.0);
    QApplication::setFont(font);
    setFont(font);
    auto palette = QApplication::palette();
    auto textColor = color(colors.value("text").toString("#fffaf3"));
    palette.setColor(QPalette::Window, color(colors.value("surface").toString("#48453f")));
    palette.setColor(QPalette::Base, color(colors.value("input").toString("#56524b")));
    palette.setColor(QPalette::AlternateBase, color(colors.value("surface2").toString("#514e48")));
    palette.setColor(QPalette::WindowText, textColor);
    palette.setColor(QPalette::Text, textColor);
    palette.setColor(QPalette::ButtonText, textColor);
    palette.setColor(QPalette::Button, color(colors.value("input").toString("#56524b")));
    palette.setColor(QPalette::Highlight, color(colors.value("accent").toString("#d4b77b")));
    palette.setColor(QPalette::HighlightedText, color(colors.value("primary_text").toString("#302c24")));
    palette.setColor(QPalette::ToolTipBase, palette.color(QPalette::Window));
    palette.setColor(QPalette::ToolTipText, textColor);
    QApplication::setPalette(palette);
    for (auto shortcut : findChildren<QPushButton *>("railButton")) {
        auto target = shortcut->property("railTarget").toInt();
        shortcut->setIcon(railIcon(target, textColor));
        shortcut->setToolTip(navigation->item(target)->text());
    }
    if (auto sidebar = findChild<QFrame *>("sidebar"))
        sidebar->setFixedWidth(190 + (fontSlider->value() - 100) / 2);
    navigation->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    navigation->setFont(font);
    navigation->setProperty("requestedPointSize", font.pointSizeF());
    for (int i = 0; i < navigation->count(); ++i)
        navigation->item(i)->setFont(font);
    QTimer::singleShot(0, navigation, [this] { fitNavigation(); });
    for (auto heading : findChildren<QLabel *>()) {
        auto role = heading->objectName();
        if (role == "heading" || role == "pageTitle" || role == "sectionTitle") {
            auto display = font;
            display.setPointSizeF(font.pointSizeF() * (role == "heading" ? 1.4 : 1.12));
            display.setWeight(QFont::Medium);
            heading->setFont(display);
            auto effect = qobject_cast<QGraphicsDropShadowEffect *>(heading->graphicsEffect());
            if (!effect) {
                effect = new QGraphicsDropShadowEffect(heading);
                effect->setOffset(0, 1);
                effect->setBlurRadius(1);
                heading->setGraphicsEffect(effect);
            }
            effect->setColor(textColor.lightness() > 128 ? QColor(0, 0, 0, 90) : QColor(255, 255, 255, 100));
        }
    }
    QString style =
        QString(R"(
        QWidget { color:%1; } QWidget#shell { background:%2; }
        QFrame#rail { background:%3; } QFrame#sidebar { background:%4; border-right:1px solid %5; }
        QFrame[surface="true"] { background:%6; border:1px solid %5; border-radius:8px; }
        QLabel { background:transparent; } QLabel#heading { font-weight:500; }
        QLabel#pageTitle, QLabel#sectionTitle { font-weight:500; }
        QLabel#brandName { font-weight:500; } QLabel#statusPill { color:%7; border:1px solid %5; padding:8px 12px; border-radius:7px; }
        QLabel#notification { background:%6; color:%8; padding:10px; border-radius:6px; }
        QLabel#notification[success="true"] { color:%7; } QLabel#errorText { color:%8; }
        QPushButton { background:%9; border:1px solid %5; border-radius:6px; padding:7px 12px; }
        QPushButton:hover, QPushButton[chromeHover="true"] { background:%10; border-color:%7; } QPushButton:pressed { background:%4; }
        QFrame[selectedCard="true"] { background:%10; border:1px solid %7; } QLabel#statValue { color:%7; }
        QPushButton:checked { background:%10; color:%7; border-color:%7; }
        QPushButton#connectToggle { color:%7; }
        QPushButton[primary="true"] { background:%7; color:%11; border-color:%7; }
        QPushButton:disabled { color:%12; background:%6; } QPushButton#exitButton { color:%8; }
        QListWidget#navigation { background:transparent; border:0; outline:0; }
        QListWidget#navigation::item { padding:7px 8px; margin:1px 0; border-radius:6px; }
        QListWidget#navigation::item:selected { background:%10; color:%1; } QListWidget#navigation::item:hover { background:%9; color:%1; }
        QLineEdit,QTextEdit,QPlainTextEdit,QSpinBox,QComboBox { background:%9; border:1px solid %5; padding:7px; border-radius:5px; selection-background-color:%7; }
        QTreeWidget { background:%6; alternate-background-color:%9; border:1px solid %5; border-radius:5px; }
        QTreeWidget::item { padding:7px 5px; } QTreeWidget::item:selected { background:%10; color:%1; }
        QHeaderView::section { background:%4; color:%1; border:0; border-bottom:1px solid %5; padding:9px; }
        QScrollArea { background:transparent; border:0; } QScrollArea>QWidget>QWidget { background:transparent; }
        QScrollBar:vertical { background:transparent; width:8px; margin:0; } QScrollBar::handle:vertical { background:%5; border-radius:4px; min-height:35px; }
        QScrollBar::add-line:vertical,QScrollBar::sub-line:vertical { height:0; }
        QProgressBar { background:%9; border:0; border-radius:4px; text-align:center; min-height:20px; } QProgressBar::chunk { background:%7; border-radius:4px; }
        QSlider::groove:horizontal { background:%5; height:5px; border-radius:2px; } QSlider::sub-page:horizontal { background:%7; border-radius:2px; }
        QSlider::handle:horizontal { background:%7; border:2px solid %1; width:13px; margin:-6px 0; border-radius:8px; }
        QTabWidget::pane { border:0; } QTabBar::tab { background:%6; color:%1; padding:8px 16px; border-bottom:2px solid transparent; } QTabBar::tab:selected { color:%7; border-bottom:2px solid %7; }
        QCheckBox { spacing:8px; padding:6px 0; } QMenu { background:%4; color:%1; border:1px solid %5; padding:5px; } QMenu::item { padding:8px 16px; } QMenu::item:selected { background:%10; }
    )")
            .arg(text, background, rail, nav, border, surface, accent, danger, input, hover, primary, muted);
    setStyleSheet(style);
    if (tray.contextMenu())
        tray.contextMenu()->setStyleSheet(style);
    plot->accent = color(colors.value("accent").toString("#d4b77b"));
    plot->update();
    refreshProxy();
    QTimer::singleShot(0, this, [this] {
        for (auto widget : pages->currentWidget()->findChildren<QWidget *>()) {
            if (auto panels = dynamic_cast<AdaptivePanels *>(widget))
                panels->arrange();
            if (auto cards = dynamic_cast<CardPager *>(widget))
                cards->arrange();
        }
    });
}
void MainWindow::fitNavigation() {
    if (!navigation)
        return;
    auto font = navigation->font();
    const auto requested = navigation->property("requestedPointSize").toDouble();
    if (requested <= 0)
        return;
    auto sample = font;
    sample.setPointSizeF(requested);
    const int target = qMin(qRound(requested * navigation->logicalDpiY() / 72.0),
                            qMax(13, navigation->viewport()->height() / qMax(1, navigation->count()) - 20));
    font.setPixelSize(qMax(13, target));
    if (navigation->font() != font) {
        navigation->setFont(font);
        for (int i = 0; i < navigation->count(); ++i)
            navigation->item(i)->setFont(font);
    }
}
void MainWindow::resizeEvent(QResizeEvent *event) {
    QMainWindow::resizeEvent(event);
    if (navigation)
        QTimer::singleShot(0, navigation, [this] { fitNavigation(); });
}
void MainWindow::createPet() {
    auto p = new Pet(nullptr, Qt::Tool | Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint);
    p->setAttribute(Qt::WA_TranslucentBackground);
    p->setPixmap(QIcon(":/brand/ui/axolotl_mark.svg").pixmap(96, 96));
    p->setFixedSize(96, 96);
    p->move(screen()->availableGeometry().bottomRight() - QPoint(130, 150));
    pet = p;
    if (!testMode && store.settings.value("show_pet").toBool())
        p->show();
    connect(this, &QObject::destroyed, p, &QObject::deleteLater);
}
void MainWindow::requestClose(bool exit) {
    if (exit) {
        quitting = true;
        close();
        return;
    }
    int behavior = store.settings.value("close_behavior").toInt();
    if (behavior == 0) {
        QMessageBox box(this);
        box.setWindowTitle("关闭 HexagonProxy");
        box.setText("关闭主窗口后如何处理？");
        auto background = box.addButton("后台运行", QMessageBox::AcceptRole);
        auto end = box.addButton("退出程序", QMessageBox::DestructiveRole);
        box.addButton("取消", QMessageBox::RejectRole);
        box.exec();
        if (box.clickedButton() == background) {
            hide();
            return;
        }
        if (box.clickedButton() != end)
            return;
        quitting = true;
        close();
    } else if (behavior == 1)
        hide();
    else {
        quitting = true;
        close();
    }
}
void MainWindow::closeEvent(QCloseEvent *event) {
    if (!quitting) {
        event->ignore();
        QTimer::singleShot(0, this, [this] { requestClose(false); });
        return;
    }
    if (accounts.busy) {
        quitting = false;
        event->ignore();
        showMessage("账号事务仍在处理中，请等待完成后退出，以保留恢复记录。");
        return;
    }
    if (linux.running() || linux.busy) {
        event->ignore();
        linux.stop();
        if (!closeDeadline.isActive())
            closeDeadline.start();
        return;
    }
    if (proxy.process.state() != QProcess::NotRunning || terminalProcess.state() != QProcess::NotRunning ||
        terminalStopPending) {
        event->ignore();
        if (!backendsStopping) {
            backendsStopping = true;
            proxy.shutdown();
            stopTerminal();
        }
        QTimer::singleShot(150, this, [this] {
            if (quitting)
                close();
        });
        return;
    }
    if (pet)
        pet->hide();
    tray.hide();
    event->accept();
    QTimer::singleShot(0, qApp, &QCoreApplication::quit);
}
bool MainWindow::nativeEvent(const QByteArray &type, void *message, qintptr *result) {
    auto msg = static_cast<MSG *>(message);
    if (msg->message == WM_NCHITTEST && !isMaximized()) {
        RECT r;
        GetWindowRect(reinterpret_cast<HWND>(winId()), &r);
        POINT p = {GET_X_LPARAM(msg->lParam), GET_Y_LPARAM(msg->lParam)};
        int edge = qRound(6 * devicePixelRatioF());
        bool left = p.x < r.left + edge, right = p.x >= r.right - edge, top = p.y < r.top + edge,
             bottom = p.y >= r.bottom - edge;
        if (top || bottom || left || right) {
            *result = top      ? (left    ? HTTOPLEFT
                                  : right ? HTTOPRIGHT
                                          : HTTOP)
                      : bottom ? (left    ? HTBOTTOMLEFT
                                  : right ? HTBOTTOMRIGHT
                                          : HTBOTTOM)
                      : left   ? HTLEFT
                               : HTRIGHT;
            return true;
        }
    }
    return QMainWindow::nativeEvent(type, message, result);
}
} // namespace hexagon
