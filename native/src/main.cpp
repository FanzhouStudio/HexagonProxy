#include "main_window.h"
#include <QLockFile>
using namespace hexagon;
int main(int argc, char **argv) {
    QApplication app(argc, argv);
    app.setApplicationName("HexagonProxy");
    app.setOrganizationName("FanzhouStudio");
    app.setApplicationVersion("0.5.4");
    app.setQuitOnLastWindowClosed(false);
    try {
        Storage storage(qEnvironmentVariable("HEXAGON_DATA_DIR"), qEnvironmentVariable("HEXAGON_LEGACY_DIR"));
        QLockFile lock(storage.file("native.lock"));
        lock.setStaleLockTime(0);
        const bool smoke = app.arguments().contains("--smoke-test");
        if (!smoke && !lock.tryLock(50)) {
            QMessageBox::information(nullptr, "HexagonProxy", "C++ 客户端已经运行，请从托盘打开。");
            return 0;
        }
        storage.importLegacy();
        auto launcher = qEnvironmentVariable("HEXAGON_LAUNCHER");
        if (!launcher.isEmpty()) {
            storage.settings["launcher_path"] = launcher;
            storage.saveSettings();
        }
        MainWindow window(storage, smoke);
        if (!app.arguments().contains("--tray-start"))
            window.show();
        if (smoke)
            QTimer::singleShot(1000, &window, [&window] { window.requestClose(true); });
        for (const auto &argument : app.arguments())
            if (argument.startsWith("--preview=")) {
                const auto output = argument.mid(10);
                QTimer::singleShot(350, &window, [&window, output] {
                    auto nav = window.findChild<QListWidget *>("navigation");
                    nav->setCurrentRow(5);
                    QTimer::singleShot(150, &window, [&window, output] { window.grab().save(output); });
                });
            }
        return app.exec();
    } catch (const std::exception &e) {
        QMessageBox::critical(nullptr, "HexagonProxy", QString::fromUtf8(e.what()));
        return 1;
    }
}
