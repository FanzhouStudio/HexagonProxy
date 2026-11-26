# 内置 Linux 工作区

运行包由 `node tools/build_linux_runtime.mjs` 生成，输出 `runtime.zip`，不把构建产物提交到 Git。正式 Windows 导出会将它嵌入唯一的 `HexagonProxy.exe`。首次使用在当前 Windows 用户的 Godot 应用数据目录中校验并展开；运行过程不需要 WSL、Docker、Node 或联网下载系统组件。

## 组成与来源

- QEMU Windows x64：Stefan Weil 的 2026-08-11 构建，`11.1.0 (v11.1.0-12130-ge470268ff4)`。
  - 下载：<https://qemu.weilnetz.de/w64/2026/qemu-w64-setup-20260811.exe>
  - 上游校验：同目录 `qemu-w64-setup-20260811.sha512`，构建时强制验证。
  - 源码：<https://repo.or.cz/qemu/win32.git>，构建版本见上面的 Git 标识；上游镜像 <https://github.com/stefanweil/qemu>。
  - 保留 `COPYING` / `COPYING.LIB`；仅打包 x86-64 system emulator、qemu-img、PE 导入表递归解析到的 DLL 和实际使用的 BIOS/ROM。各组件继续适用各自许可证，QEMU 主程序为 GPL-2.0。
- Linux 启动环境：Alpine 3.22 x86-64 官方软件仓库中的 `linux-virt`、BusyBox、kmod、e2fsprogs 及其运行依赖。Alpine/musl 仅用于启动和磁盘初始化，实际 Tuxee 用户空间来自下述 Debian 镜像。
  - 二进制仓库：<https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/>
  - 对应源码与构建配方：<https://gitlab.alpinelinux.org/alpine/aports/-/tree/3.22-stable/main>，按 `SOURCES.json` 记录的软件包版本获取对应历史配方及其 source 字段。
  - Linux 内核为 GPL-2.0-only，BusyBox 为 GPL-2.0，其他软件按 APK 的 license 字段。
- Tuxee 1.5.0：<https://github.com/agent0ai/tuxee/tree/v1.5.0>，MIT；官方 `agent0ai/tuxee:1.5.0` 的 linux/amd64 OCI 镜像。
  - 每个 OCI 层按 registry 返回的 SHA-256 校验，合并白化标记后保留全部运行文件和 `/usr/share/doc` 下 Debian 软件包版权声明。
  - Debian 组件各自的源码可通过镜像内 apt 软件源及 Debian snapshot 获取；保留 `/var/lib/dpkg` 的版本记录。

`runtime.zip` 内的 `SOURCES.json` 记录每份下载的 URL 和 SHA-256，`manifest.json` 记录每个运行文件的 SHA-256 和长度。Windows 使用的 7-Zip 仅为构建工具，不随运行包分发。

## 原创改动

`scripts/linux/init.sh` 和 `guest-init.sh` 是 HexagonProxy 的启动/初始化脚本，采用本项目 AGPL-3.0-only；没有修改上游 ELF、Windows 可执行文件、DLL 或内核字节。Windows 端通过命令行、串口及仅绑定 127.0.0.1 的 HTTP 端口与独立 QEMU 进程通信。

## 磁盘与数据

容量按 GiB（界面标作 GB）设置为 1～10。qcow2 按实际写入增长，预留 16 MiB 元数据空间，并在创建/扩容前用 `qemu-img measure` 验证完全分配时的镜像文件大小不超过所选容量。容量包含整个 guest 系统盘，不包含只读启动资源和 Windows 程序本身。停止后只允许扩容，不执行危险的在线缩盘。

首次安装只格式化新建空盘。已有文件系统没有安装完成标记时拒绝覆盖，用户可通过确认弹窗明确重建。正常关闭通过带随机令牌的第二串口通知 PID 1，同步文件并卸载后关机；未成功关机时取消退出，避免强制终止写盘。

Linux 登录为独立的 root 账户，随机密码和串口令牌保存在当前 Windows 用户的数据目录中，不出现在日志、进程参数和 Git 中。Web 端口仅绑定本机，未自动挂载任何 Windows 目录。修改 guest 密码后，软件保存的初始密码不会自动更新。
