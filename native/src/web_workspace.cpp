#include "web_workspace.h"
// clang-format off
#include <windows.h>
#include <unknwn.h>
#include <shlwapi.h>
#include <WebView2.h>
// clang-format on
#include <wrl.h>
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;
namespace hexagon {
struct WebWorkspace::Impl {
    ComPtr<ICoreWebView2Environment> environment;
    ComPtr<ICoreWebView2Controller> controller;
    ComPtr<ICoreWebView2> web;
    bool cancelled = false;
    bool branded = false;
    ~Impl() {
        if (controller)
            controller->Close();
    }
};
static QString brandingScript(const QString &origin) {
    QFile script(":/workspace/workspace_branding.js");
    if (!script.open(QIODevice::ReadOnly))
        return {};
    const auto json = QJsonDocument(QJsonArray{origin}).toJson(QJsonDocument::Compact);
    return QString::fromUtf8(script.readAll())
        .replace("__WORKSPACE_ORIGIN__", QString::fromUtf8(json.mid(1, json.size() - 2)));
}
WebWorkspace::WebWorkspace(QWidget *parent) : QWidget(parent) {
    setObjectName("embeddedLinuxWorkspace");
    setAttribute(Qt::WA_NativeWindow);
    setFocusPolicy(Qt::StrongFocus);
    setMinimumSize(400, 300);
    auto layout = new QVBoxLayout(this);
    placeholder = new QLabel("工作区尚未启动，请到环境设置中安装或启动。", this);
    placeholder->setWordWrap(true);
    placeholder->setAlignment(Qt::AlignCenter);
    layout->addWidget(placeholder);
}
WebWorkspace::~WebWorkspace() {
    clear();
    if (comInitialized)
        CoUninitialize();
}
void WebWorkspace::report(HRESULT error) {
    auto text = QString("内嵌工作区初始化失败（0x%1）。请确认 Windows WebView2 运行组件可用。")
                    .arg(quint32(error), 8, 16, QLatin1Char('0'));
    placeholder->setText(text);
    placeholder->show();
    emit failed(text);
}
void WebWorkspace::clear(const QString &message) {
    if (state) {
        state->cancelled = true;
        if (state->controller)
            state->controller->Close();
        state->web.Reset();
        state->controller.Reset();
        state->environment.Reset();
        state.reset();
    }
    currentUrl = QUrl();
    placeholder->setText(message);
    placeholder->show();
}
void WebWorkspace::navigateLocal(const QUrl &url, const QString &profileDirectory) {
    if (url.scheme() != "http" || url.host() != "127.0.0.1" || url.port() < 1024) {
        emit failed("工作区仅接受本机 Linux 服务地址");
        return;
    }
    if (state && state->web && url == currentUrl) {
        if (state->branded)
            state->web->Navigate(url.toString().toStdWString().c_str());
        return;
    }
    if (!comInitialized) {
        auto result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        if (FAILED(result)) {
            report(result);
            return;
        }
        comInitialized = true;
    }
    clear("正在加载内嵌工作区…");
    currentUrl = url;
    profilePath = profileDirectory;
    QDir().mkpath(profileDirectory);
    auto data = std::make_shared<Impl>();
    state = data;
    QPointer<WebWorkspace> host(this);
    auto hr = CreateCoreWebView2EnvironmentWithOptions(
        nullptr, QDir::toNativeSeparators(profileDirectory).toStdWString().c_str(), nullptr,
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>([host, data](
                                                                                 HRESULT result,
                                                                                 ICoreWebView2Environment *
                                                                                     environment) -> HRESULT {
            if (!host || data->cancelled)
                return S_OK;
            if (FAILED(result) || !environment) {
                host->report(result);
                return S_OK;
            }
            data->environment = environment;
            return environment->CreateCoreWebView2Controller(
                reinterpret_cast<HWND>(host->winId()),
                Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                    [host, data](HRESULT code, ICoreWebView2Controller *controller) -> HRESULT {
                        if (!host || data->cancelled) {
                            if (controller)
                                controller->Close();
                            return S_OK;
                        }
                        if (FAILED(code) || !controller) {
                            host->report(code);
                            return S_OK;
                        }
                        data->controller = controller;
                        controller->get_CoreWebView2(&data->web);
                        if (!data->web) {
                            host->report(E_FAIL);
                            return S_OK;
                        }
                        ComPtr<ICoreWebView2Settings> settings;
                        data->web->get_Settings(&settings);
                        settings->put_AreDevToolsEnabled(FALSE);
                        settings->put_AreDefaultContextMenusEnabled(FALSE);
                        settings->put_IsStatusBarEnabled(FALSE);
                        EventRegistrationToken token;
                        data->web->add_NavigationStarting(
                            Callback<ICoreWebView2NavigationStartingEventHandler>(
                                [host, data](ICoreWebView2 *,
                                             ICoreWebView2NavigationStartingEventArgs *args) -> HRESULT {
                                    if (!host || data->cancelled)
                                        return S_OK;
                                    LPWSTR raw = nullptr;
                                    args->get_Uri(&raw);
                                    auto url = QUrl(QString::fromWCharArray(raw ? raw : L""));
                                    CoTaskMemFree(raw);
                                    if (url.scheme() != "about" &&
                                        (url.scheme() != "http" || url.host() != "127.0.0.1" ||
                                         url.port() != host->currentUrl.port())) {
                                        args->put_Cancel(TRUE);
                                        emit host->failed("已阻止离开本地 Linux 工作区的页面跳转");
                                    }
                                    return S_OK;
                                })
                                .Get(),
                            &token);
                        data->web->add_NewWindowRequested(
                            Callback<ICoreWebView2NewWindowRequestedEventHandler>(
                                [host, data](ICoreWebView2 *,
                                             ICoreWebView2NewWindowRequestedEventArgs *args) -> HRESULT {
                                    args->put_Handled(TRUE);
                                    if (!host || data->cancelled)
                                        return S_OK;
                                    LPWSTR raw = nullptr;
                                    args->get_Uri(&raw);
                                    QUrl url(QString::fromWCharArray(raw ? raw : L""));
                                    CoTaskMemFree(raw);
                                    if (url.scheme() == "http" && url.host() == "127.0.0.1" &&
                                        url.port() == host->currentUrl.port())
                                        data->web->Navigate(url.toString().toStdWString().c_str());
                                    else
                                        emit host->failed("外部链接没有自动打开浏览器");
                                    return S_OK;
                                })
                                .Get(),
                            &token);
                        data->web->add_NavigationCompleted(
                            Callback<ICoreWebView2NavigationCompletedEventHandler>(
                                [host, data](ICoreWebView2 *,
                                             ICoreWebView2NavigationCompletedEventArgs *args) -> HRESULT {
                                    if (!host || data->cancelled)
                                        return S_OK;
                                    BOOL success = FALSE;
                                    args->get_IsSuccess(&success);
                                    if (success) {
                                        host->placeholder->hide();
                                        emit host->loaded();
                                    } else {
                                        COREWEBVIEW2_WEB_ERROR_STATUS error;
                                        args->get_WebErrorStatus(&error);
                                        emit host->failed(QString("内嵌页面加载失败（%1），可刷新页面重试")
                                                              .arg(int(error)));
                                    }
                                    return S_OK;
                                })
                                .Get(),
                            &token);
                        ComPtr<ICoreWebView2_4> downloads;
                        if (SUCCEEDED(data->web.As(&downloads))) {
                            downloads->add_DownloadStarting(
                                Callback<ICoreWebView2DownloadStartingEventHandler>(
                                    [host, data](ICoreWebView2 *,
                                                 ICoreWebView2DownloadStartingEventArgs *args) -> HRESULT {
                                        args->put_Handled(TRUE);
                                        ComPtr<ICoreWebView2Deferral> deferral;
                                        args->GetDeferral(&deferral);
                                        ComPtr<ICoreWebView2DownloadStartingEventArgs> retained = args;
                                        if (!host || data->cancelled) {
                                            args->put_Cancel(TRUE);
                                            deferral->Complete();
                                            return S_OK;
                                        }
                                        QTimer::singleShot(0, host, [host, data, retained, deferral] {
                                            if (!host || data->cancelled) {
                                                retained->put_Cancel(TRUE);
                                                deferral->Complete();
                                                return;
                                            }
                                            LPWSTR suggested = nullptr;
                                            retained->get_ResultFilePath(&suggested);
                                            auto name =
                                                QFileInfo(QString::fromWCharArray(
                                                              suggested ? suggested : L"download.bin"))
                                                    .fileName();
                                            CoTaskMemFree(suggested);
                                            auto output = QFileDialog::getSaveFileName(
                                                host, "从 Linux 保存文件",
                                                QStandardPaths::writableLocation(
                                                    QStandardPaths::DownloadLocation) +
                                                    "/" + name);
                                            if (output.isEmpty())
                                                retained->put_Cancel(TRUE);
                                            else
                                                retained->put_ResultFilePath(
                                                    QDir::toNativeSeparators(output).toStdWString().c_str());
                                            deferral->Complete();
                                        });
                                        return S_OK;
                                    })
                                    .Get(),
                                &token);
                        }
                        host->updateBounds();
                        controller->put_IsVisible(host->isVisible() ? TRUE : FALSE);
                        host->installBranding();
                        return S_OK;
                    })
                    .Get());
        }).Get());
    if (FAILED(hr))
        report(hr);
}
void WebWorkspace::installBranding() {
    const auto data = state;
    const QString origin = QString("http://127.0.0.1:%1").arg(currentUrl.port());
    const auto assetUrl = (origin + "/__hexagonlinux/axolotl.svg").toStdWString();
    const auto script = brandingScript(origin);
    QFile avatar(":/brand/ui/axolotl_mark.svg");
    if (script.isEmpty() || !avatar.open(QIODevice::ReadOnly)) {
        report(E_FAIL);
        return;
    }
    const auto bytes = avatar.readAll();
    EventRegistrationToken token{};
    auto code = data->web->add_WebResourceRequested(
        Callback<ICoreWebView2WebResourceRequestedEventHandler>(
            [data, bytes](ICoreWebView2 *, ICoreWebView2WebResourceRequestedEventArgs *args) -> HRESULT {
                if (data->cancelled)
                    return S_OK;
                ComPtr<IStream> stream;
                stream.Attach(
                    SHCreateMemStream(reinterpret_cast<const BYTE *>(bytes.constData()), UINT(bytes.size())));
                if (!stream)
                    return E_OUTOFMEMORY;
                ComPtr<ICoreWebView2WebResourceResponse> response;
                const auto result = data->environment->CreateWebResourceResponse(
                    stream.Get(), 200, L"OK", L"Content-Type: image/svg+xml\r\nCache-Control: no-store",
                    &response);
                return SUCCEEDED(result) ? args->put_Response(response.Get()) : result;
            })
            .Get(),
        &token);
    if (SUCCEEDED(code))
        code =
            data->web->AddWebResourceRequestedFilter(assetUrl.c_str(), COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
    QPointer<WebWorkspace> host(this);
    if (SUCCEEDED(code))
        code = data->web->AddScriptToExecuteOnDocumentCreated(
            script.toStdWString().c_str(),
            Callback<ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler>(
                [host, data](HRESULT result, LPCWSTR) -> HRESULT {
                    if (!host || data->cancelled)
                        return S_OK;
                    if (FAILED(result)) {
                        host->report(result);
                        return S_OK;
                    }
                    data->branded = true;
                    const auto navigation =
                        data->web->Navigate(host->currentUrl.toString().toStdWString().c_str());
                    if (FAILED(navigation))
                        host->report(navigation);
                    return S_OK;
                })
                .Get());
    if (FAILED(code))
        report(code);
}
void WebWorkspace::updateBounds() {
    if (!state || !state->controller)
        return;
    RECT rect;
    GetClientRect(reinterpret_cast<HWND>(winId()), &rect);
    state->controller->put_Bounds(rect);
    state->controller->NotifyParentWindowPositionChanged();
}
void WebWorkspace::reload() {
    if (state && state->web && state->branded)
        state->web->Reload();
    else if (!currentUrl.isEmpty()) {
        const auto target = currentUrl;
        const auto profile = profilePath;
        navigateLocal(target, profile);
    }
}
void WebWorkspace::inspectPageForTest(const QString &script, std::function<void(QByteArray)> callback) {
    if (state && state->web)
        state->web->ExecuteScript(
            script.toStdWString().c_str(),
            Callback<ICoreWebView2ExecuteScriptCompletedHandler>([callback = std::move(callback)](
                                                                     HRESULT result,
                                                                     LPCWSTR json) -> HRESULT {
                callback(SUCCEEDED(result) && json ? QString::fromWCharArray(json).toUtf8() : QByteArray{});
                return S_OK;
            }).Get());
}
void WebWorkspace::resizeEvent(QResizeEvent *event) {
    QWidget::resizeEvent(event);
    updateBounds();
}
void WebWorkspace::moveEvent(QMoveEvent *event) {
    QWidget::moveEvent(event);
    updateBounds();
}
void WebWorkspace::showEvent(QShowEvent *event) {
    QWidget::showEvent(event);
    if (state && state->controller)
        state->controller->put_IsVisible(TRUE);
    updateBounds();
}
void WebWorkspace::hideEvent(QHideEvent *event) {
    if (state && state->controller)
        state->controller->put_IsVisible(FALSE);
    QWidget::hideEvent(event);
}
void WebWorkspace::focusInEvent(QFocusEvent *event) {
    QWidget::focusInEvent(event);
    if (state && state->controller)
        state->controller->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
}
} // namespace hexagon
