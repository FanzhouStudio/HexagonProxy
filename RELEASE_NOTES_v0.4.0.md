# HexagonProxy v0.4.0

新增可选 Linux 工作区：内置 QEMU 与 Tuxee 离线运行环境，无需安装 WSL 或 Docker。

- 侧栏提供安装、启动、正常停止、打开 Tuxee、复制随机登录密码与数据目录入口。
- 系统盘通过滑条选择 1～10 GB，动态增长；创建前校验完全分配时包含元数据的最大占用。
- 停止后可扩容，保留已有文件和程序；拒绝缩盘。重建须确认，不自动覆盖已有文件系统。
- 软件退出前正常关闭工作区，避免写盘时被强制终止。准备资源和磁盘操作在后台执行，界面按状态变化更新。
- QEMU 采用 TCG 软件模拟，分配 512 MB guest 内存及 2 个虚拟 CPU。工作区网页在默认浏览器中打开。

来源及使用说明见 `docs/linux_workspace.md` 和 `third_party/linux_runtime/UPSTREAM.md`。
