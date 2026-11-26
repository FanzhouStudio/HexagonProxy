#pragma once
#include <QtWidgets>
#include <functional>
#include <memory>
class NativeTests;
namespace hexagon {
class WebWorkspace : public QWidget {
    Q_OBJECT
  public:
    explicit WebWorkspace(QWidget *parent = nullptr);
    ~WebWorkspace() override;
    void navigateLocal(const QUrl &url, const QString &profileDirectory);
    void clear(const QString &message = "工作区尚未启动，请到环境设置中安装或启动。");
    void reload();
    QUrl url() const {
        return currentUrl;
    }
  signals:
    void loaded();
    void failed(QString error);

  protected:
    void resizeEvent(QResizeEvent *event) override;
    void moveEvent(QMoveEvent *event) override;
    void showEvent(QShowEvent *event) override;
    void hideEvent(QHideEvent *event) override;
    void focusInEvent(QFocusEvent *event) override;

  private:
    friend class ::NativeTests;
    struct Impl;
    std::shared_ptr<Impl> state;
    QUrl currentUrl;
    QString profilePath;
    QLabel *placeholder;
    bool comInitialized = false;
    void updateBounds();
    void installBranding();
    void inspectPageForTest(const QString &script, std::function<void(QByteArray)> callback);
    void report(long error);
};
} // namespace hexagon
