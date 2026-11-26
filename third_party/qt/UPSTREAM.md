# Qt 与 C++ 客户端

HexagonProxy 0.5.0 的主客户端使用 C++20 / Qt Widgets；不加载 Godot 引擎或 GDScript。

- Qt 6.10.2，官方 MSVC2022 Windows x64 组件：
  <https://download.qt.io/online/qtsdkrepository/windows_x86/desktop/qt6_6102/qt6_6102/>
- Qt 源码与许可证：<https://code.qt.io/cgit/qt/qtbase.git/tree/?h=v6.10.2>，SVG 模块 <https://code.qt.io/cgit/qt/qtsvg.git/tree/?h=v6.10.2>。
- Qt Core / GUI / Widgets / Network / Concurrent / SVG 使用动态库；随包附 LGPL-3.0 和 GPL-3.0 许可证原文。各组件的具体许可见其对应源码与 Qt SBOM。
- yaml-cpp 0.8.0（MIT）：<https://github.com/jbeder/yaml-cpp/tree/0.8.0>，完整 MIT 许可保留为 `YAML-CPP-LICENSE.txt`。
- Windows CRT 使用 Visual Studio 的正式 Redistributable 目录中的 x64 CRT，继续适用 Microsoft 对这些可再分发文件的许可。
- WebView2 SDK 1.0.4370.26 使用 Microsoft 官方 NuGet 包，静态链接加载器，不捆绑浏览器主程序。随包保留 `WEBVIEW2-LICENSE.txt`；工作区使用系统的 Evergreen Runtime 在客户端 HWND 内显示，未调用外部浏览器。

唯一交付包仍为 `HexagonProxy.exe`。它首先用独立 C++ 启动器将 Qt DLL、插件、C++ 客户端及第三方资源展开到当前用户的 `%LOCALAPPDATA%/FanzhouStudio/HexagonProxy/runtime/<payload hash>/`，然后启动同名客户端。运行时不需要安装 Qt SDK。

如需检查或替换动态库，可执行 `HexagonProxy.exe --extract-only` 获取展开目录。展开后的 C++ 客户端、DLL 和插件可直接运行；启动器不会因 DLL 内容改变而重新覆盖，只检查文件是否完整存在。开发者可使用本仓库的 CMake 工程及 `tools/build_native.ps1` 重新构建、调试和打包客户端。

Qt 组件版权归 Qt Company 与相应贡献者所有。HexagonProxy 的原创 C++ 源码继续采用根目录的 AGPL-3.0-only；第三方动态库不因本项目的商业授权而改变许可。
