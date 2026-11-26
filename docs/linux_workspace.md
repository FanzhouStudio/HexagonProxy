# HexagonLinux 工作区

在 HexagonProxy 左侧打开 **HexagonLinux → 安装与启动**。选择安装目录，在 **磁盘与维护** 页设置 1～10 GB 系统盘上限，然后回到 **安装与启动** 点击 **安装并启动**。运行包已内置，无需 WSL、Docker 或宿主机分区操作。

启动完成会直接切到软件内的 **工作区** 标签，在应用内使用文件管理器、编辑器和持久终端。登录页、工具栏与关于页使用 HexagonLinux 品牌和小六角头像。底层工作区由 Tuxee 提供。登录用户为 `root`，使用工具栏的 **复制登录密码** 获取本机随机密码。

## 安装目录与已有数据

安装目录可输入路径或通过 **选择目录** 指定，点击 **应用目录** 保存。必须先停止工作区才能更改目录。

- 选择空目录：下次安装会在这里创建新的环境。
- 选择已有 HexagonProxy 工作区：读取原有磁盘与本机设置。
- 更改目录不会搬移、覆盖或删除原目录数据。要搬移已有环境，请先停止，再完整复制工作区目录并选择新位置。
- 目录中存在无法识别的 `linux.qcow2` 时拒绝覆盖。
- 从旧版 Godot 客户端迁移时直接引用旧工作区目录，不复制大磁盘。

`linux.qcow2` 保存系统、程序和工作文件；`native-serial.log` 记录启动错误；`native-vm.json` 保存容量及本机凭据，`webview` 保存内嵌视图会话。旧工作区可能仍含 `settings.cfg`。请勿公开凭据文件，只能在工作区完全停止后备份。

## 容量与生命周期

系统盘最小 1 GB、最大 10 GB，按实际数据增长，包含文件系统和 qcow2 元数据；只读 QEMU、启动文件及界面缓存另外占空间。创建前通过 qemu-img 校验完全分配后的磁盘大小不超过所选预算。

停止后调大容量，点击 **启动 / 应用扩容**，原文件保留；已有磁盘不能缩小。**重建系统盘**需要确认，会删除 Linux 内全部数据。

切换 HexagonProxy 页面保留已加载的工作区；停止工作区会正常关闭其中程序并保存磁盘。退出软件先正常关闭 Linux，保存未结束时取消退出，不强制断电。

默认分配 512 MB guest 内存、2 个虚拟 CPU，使用 QEMU TCG 软件模拟。总占用还包含 QEMU、内嵌视图和 Linux 其他进程，不能用 Tuxee 单进程空闲内存估计。镜像不预装额外开发工具。

内嵌视图使用 Microsoft WebView2 Runtime。Windows 11 通常自带；若缺失，页面显示具体初始化错误，可安装微软的 [Evergreen Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/)。组件分发方式见 [微软说明](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution)。
