#pragma once
#include "accounts.h"
#include "linux_workspace.h"
#include "proxy.h"
#include "web_workspace.h"
#include <QtWidgets>
namespace hexagon {
class CardPager;
class TrafficPlot : public QWidget {
  public:
    using QWidget::QWidget;
    QList<double> values;
    QColor accent;
    void push(double value) {
        values.append(value);
        while (values.size() > 90)
            values.removeFirst();
        update();
    }

  protected:
    void paintEvent(QPaintEvent *) override;
};
class MainWindow : public QMainWindow {
    Q_OBJECT
  public:
    MainWindow(Storage &storage, bool testMode = false);
    Storage &store;
    ProxyService proxy;
    AccountsService accounts;
    LinuxWorkspace linux;
    void applyTheme();
    void showPage(int index);
    void appendLog(const QString &text);
    void requestClose(bool exit);

  protected:
    void closeEvent(QCloseEvent *event) override;
    bool nativeEvent(const QByteArray &type, void *message, qintptr *result) override;

  private:
    QWidget *shell = nullptr, *pet = nullptr;
    QListWidget *navigation = nullptr;
    QStackedWidget *pages = nullptr;
    QLabel *title = nullptr, *statusPill = nullptr, *notification = nullptr;
    QLabel *activeSubscription = nullptr, *dashboardStatus = nullptr;
    QButtonGroup *modeButtons = nullptr;
    QPlainTextEdit *logView = nullptr, *terminalOutput = nullptr;
    QTextEdit *terminalInput = nullptr;
    QProcess terminalProcess;
    QTimer terminalFlush, fontDebounce;
    QByteArray terminalBuffer;
    QLineEdit *terminalDirectory = nullptr;
    QComboBox *shellChoice = nullptr, *presetChoice = nullptr;
    QPushButton *connectButton = nullptr, *terminalRun = nullptr, *terminalStop = nullptr;
    QLabel *speedLabel = nullptr, *uploadLabel = nullptr, *totalLabel = nullptr, *connectionLabel = nullptr;
    TrafficPlot *plot = nullptr;
    qint64 lastDownload = -1, lastUpload = -1;
    QElapsedTimer trafficTime;
    QTreeWidget *routingTree = nullptr;
    CardPager *nodeCards = nullptr, *subscriptionCards = nullptr, *codexCards = nullptr,
              *antigravityCards = nullptr;
    QLabel *currentNode = nullptr;
    QPushButton *batchTest = nullptr;
    QQueue<QPair<QString, QString>> pendingTests;
    QHash<QString, QHash<QString, QString>> nodeDelays;
    QHash<QString, QPointer<QLabel>> nodeDelayLabels;
    int runningTests = 0;
    void runNodeTests();
    QLineEdit *nodeFilter = nullptr;
    QComboBox *groupChoice = nullptr;
    QLineEdit *subscriptionName = nullptr, *subscriptionSource = nullptr, *codexName = nullptr,
              *antigravityName = nullptr, *antigravityExe = nullptr;
    QTreeWidget *quotaTree = nullptr;
    QLabel *accountMessage = nullptr, *proxyMessage = nullptr, *codexStatus = nullptr;
    QDialog *quotaDialog = nullptr;
    QLabel *quotaMessage = nullptr;
    QSlider *diskSlider = nullptr, *fontSlider = nullptr;
    QTabWidget *linuxTabs = nullptr;
    WebWorkspace *linuxWeb = nullptr;
    QLineEdit *linuxDirectory = nullptr;
    QPushButton *linuxChooseDirectory = nullptr, *linuxApplyDirectory = nullptr;
    QLabel *diskLabel = nullptr, *diskStatus = nullptr, *diskUsage = nullptr, *diskError = nullptr,
           *fontLabel = nullptr;
    QPushButton *diskStart = nullptr, *diskStop = nullptr, *diskOpen = nullptr, *diskReset = nullptr;
    QComboBox *themes = nullptr, *closeChoice = nullptr;
    QSpinBox *mixedSpin = nullptr, *controllerSpin = nullptr;
    QCheckBox *systemCheck = nullptr, *tunCheck = nullptr, *petCheck = nullptr, *startupCheck = nullptr;
    QLabel *coreStatus = nullptr;
    QSystemTrayIcon tray;
    bool quitting = false, testMode = false, backendsStopping = false, terminalStopPending = false;
    QTimer closeDeadline;
    QJsonObject theme;
    QList<QJsonObject> themeCatalog;
    QByteArray codexViewKey, antiViewKey;
    QString selectedQuota;
    QWidget *page(const QString &heading, const QString &description, QVBoxLayout **layout);
    QWidget *card(QVBoxLayout *parent, const QString &heading, QVBoxLayout **layout);
    QPushButton *button(QLayout *layout, const QString &text, std::function<void()> callback,
                        bool primary = false);
    void buildDashboard();
    void buildNodes();
    void buildSubscriptions();
    void buildRouting();
    void buildTerminal();
    void buildLinux();
    void buildCodex();
    void buildAntigravity();
    void buildSettings();
    void releasePort(int port);
    void refreshProxy();
    void refreshNodes();
    void refreshSubscriptions();
    void refreshRouting();
    void refreshAccounts();
    void refreshLinux();
    void refreshQuotas();
    void refreshPresets();
    void runTerminal();
    void stopTerminal();
    void createPet();
    void fitNavigation();
    void resizeEvent(QResizeEvent *event) override;
    void updateTraffic(QJsonObject state);
    QString selectedId(QTreeWidget *tree) const;
    void showMessage(const QString &text, bool ok = false);
    void saveSettings();
    bool confirm(const QString &title, const QString &text);
};
} // namespace hexagon
