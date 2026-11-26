<p align="center"><img src="assets/app_icon.png" width="96" alt="HexagonProxy"></p>
<h1 align="center">HexagonProxy</h1>
<p align="center">六角恐龙，守护每一次连接 · Windows C++ / Qt Widgets 客户端</p>

HexagonProxy 集成 Mihomo 代理、订阅、节点、应用分流、备用节点切换、PowerShell / CMD 终端、Codex / Antigravity 账号管理，以及可选的内置 Linux 工作区。

**0.5.4 使用 C++20 / Qt Widgets。** 窗口按钮直接调用原生窗口接口，各页面保持控件实例，后台进程和网络请求异步执行。旧版 Godot 源码保留在仓库中。

## 使用

唯一交付包为 `HexagonProxy.exe`，另附 `SHA256SUMS.txt`。启动器展开客户端、Qt 动态库和离线资源后运行，不需要安装 Qt SDK。Mihomo 仍按需下载：**设置 → 检查并下载最新内核**。已有旧版内核会复用到新目录。

1. 在订阅页导入 Mihomo YAML、订阅 URL 或分享链接。
2. 停止代理时选择活动配置，连接后在节点页选择线路、测速、标记备用节点。
3. 在设置中启用系统代理或 TUN；TUN 需要管理员权限。
4. Codex 和 Antigravity 页提供添加、切换、刷新登录与额度等操作。登录与切换继续使用本机事务助手；模型额度逐行显示。
5. HexagonLinux 在软件内提供文件管理和持久终端，安装目录可以自选，系统盘支持 1～10 GB。详见 [工作区说明](docs/linux_workspace.md)。

原生分享链接解析支持 SS、VMess、VLESS、Trojan、Hysteria2；其他协议和复杂传输配置请使用完整 Mihomo YAML，避免转换丢失字段。代理协议由独立的 Mihomo 内核实现。

主要页面采用分页：总览分为连接与流量、运行记录；设置分为界面、内核、连接、窗口；Antigravity 分为账号、模型额度、网络连接。列表提供上一页/下一页，窗口按屏幕工作区尺寸启动，避免遮挡任务栏。

内核下载同时支持官方 Windows ZIP / GZIP，GitHub API 查询失败时转到官方发布页，继续校验 SHA256；系统代理请求失败时尝试直连。

## 数据兼容

新版设置和账号索引默认保存在 `%APPDATA%/FanzhouStudio/HexagonProxy`。首次启动从 `%APPDATA%/Godot/app_userdata/HexagonProxy` 导入设置、订阅、分流、命令预设和账号索引，原文件保留。

旧账号快照、Antigravity 共享项目与登录目录、Linux 磁盘继续引用原位置，不通过复制整个账号目录切号。不要删除旧目录中仍被引用的数据。移除账号只移除列表入口，不删除项目和登录备份。

运行新旧客户端时，代理端口和同一虚拟机磁盘不能同时占用；新版会显示具体冲突原因。Linux 目录必须在停止后更改，原磁盘不会因选择新路径而被移动或覆盖。

## 界面

提供暖灰、浅色渐变和深色渐变主题，六角恐龙始终使用固定粉色。字号滑条范围 100%～200%，首次默认 150%。窗口无系统标题栏，支持顶部拖动、双击最大化、边缘缩放和托盘驻留。鼠标悬浮只重绘按钮，不重建页面。

## 从源码构建

需要 Windows 10/11 x64、Visual Studio C++ 构建工具（含 Windows SDK、CMake、Ninja）、Node.js 24 和 PowerShell 7。Qt 6.10.2、yaml-cpp 0.8.0 和 WebView2 SDK 由脚本下载校验。Linux 资源构建无需 WSL 或 Docker。

```powershell
node tools/build_linux_runtime.mjs
node tools/setup_native_toolchain.mjs
./tools/build_native.ps1
```

开发运行时设置 `HEXAGON_RESOURCE_DIR` 为仓库绝对路径，然后运行 `build/native/HexagonProxy.exe`。可以通过 `HEXAGON_DATA_DIR` 和 `HEXAGON_LEGACY_DIR` 指定隔离测试目录。

构建唯一便携包：

```powershell
./tools/build_windows_release.ps1
```

输出 `dist/HexagonProxy.exe` 和 `dist/SHA256SUMS.txt`。旧包若正在运行，构建脚本将它保留为 build 内的 `.running` 文件后放入新包，不结束用户进程。历史 Godot 构建脚本保留为 `tools/build_legacy_godot.ps1`。

## 验证

默认构建运行 QtTest：配置解析、数据迁移、磁盘边界、安装目录保护、账号入口删除与按钮悬浮持久性。真实集成测试可设置 `HEXAGON_LIVE_CORE=1` / `HEXAGON_TEST_CORE`、`HEXAGON_LIVE_LINUX=1`、`HEXAGON_LIVE_WEB=1`，通过 Windows 平台运行 `hexagon_native_tests.exe`。这些测试使用临时目录，不切换真实用户账号。

## 许可

原创源码采用 [AGPL-3.0-only](LICENSE)，商业授权见 [COMMERCIAL-LICENSE.md](COMMERCIAL-LICENSE.md)。Qt 动态库、yaml-cpp、WebView2、QEMU、Linux、Tuxee、Mihomo 和其他第三方组件各自保留上游许可，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 与 [Qt 构建说明](third_party/qt/UPSTREAM.md)。

[源码仓库与下载](https://github.com/FanzhouStudio/HexagonProxy) · [反馈问题](https://github.com/FanzhouStudio/HexagonProxy/issues) · QQ 群：1102815471
