Q群：1102815471
<p align="center">
  <img src="assets/app_icon.png" width="96" alt="六角代理图标">
</p>

<h1 align="center">六角代理</h1>

<p align="center">
  一只会守护网络的像素美西螈<br>
  面向 Windows 的轻量 Mihomo 图形客户端
</p>

<p align="center">
  <img alt="Windows" src="https://img.shields.io/badge/Windows-10%20%2F%2011-3478b8">
  <img alt="Godot" src="https://img.shields.io/badge/Godot-4.7-478cbf">
  <img alt="Mihomo" src="https://img.shields.io/badge/Core-Mihomo-16866f">
  <img alt="License" src="https://img.shields.io/badge/License-Source--Available-c84d68">
</p>

六角代理把订阅、节点、系统代理和桌面宠物放进同一个浅色水晶界面。应用负责本地管理与交互，网络协议由独立运行的 [Mihomo](https://github.com/MetaCubeX/mihomo) 内核处理。

## 下载

在仓库的 **Releases** 页面选择一种版本：

| 文件 | 适合场景 |
| --- | --- |
| `HexagonProxy.exe` | 便携版，下载后直接运行，不写入安装目录 |
| `HexagonProxySetup.exe` | 安装版，自动创建桌面、开始菜单及卸载快捷方式 |

两种版本均不需要管理员权限。首次运行如果遇到 Windows SmartScreen，请核对下载来源后选择“更多信息 → 仍要运行”；当前个人发布版本尚未购买代码签名证书。

## 主要功能

- HTTP / Clash / Mihomo 订阅、本地 YAML 和 V2 分享链接导入
- 多个 HTTP、V2、本地配置同时保存，自由切换、刷新和删除
- 支持 VLESS Reality、VMess、Hysteria2、Trojan、SS、SSR、TUIC
- 节点选择、单节点测速和批量测速
- 规则、全局、直连三种代理模式
- 实时速度、累计流量与活动连接统计
- 托盘驻留、开机自启和可拖动的透明桌面宠物
- 内核版本检查与应用内更新
- 订阅和运行配置仅保存在本机用户目录

## 使用

1. 打开“订阅”，添加订阅地址、V2 分享链接或本地 YAML。
2. 切换到想使用的订阅，在“节点”中选择线路并测速。
3. 返回“总览”，打开“一键连接”。

关闭主窗口后应用默认驻留系统托盘。需要完全退出时，请使用托盘菜单中的“退出六角代理”。

## 隐私与安全

- 订阅内容仅存放在本机 Godot 用户数据目录，不会上传到六角代理服务器。
- Mihomo 控制接口仅监听 `127.0.0.1`，并为每份运行配置生成访问密钥。
- 正常退出时会关闭本应用启用的 Windows 系统代理并停止本应用启动的内核进程。
- 当前使用 Windows 系统 HTTP/SOCKS 混合代理；暂未提供 TUN 模式。

<details>
<summary><strong>从源码运行与构建</strong></summary>

### 环境

- Windows 10/11 x64
- Godot 4.7 stable
- 官方 Windows x64 `mihomo.exe`，放置于 `bin/mihomo.exe`

使用 Godot 打开项目目录即可运行。生成两种发布产物时执行：

```powershell
powershell -ExecutionPolicy Bypass -File tools/build_windows_release.ps1
```

产物保存在 `dist/`。脚本会先运行自动化测试，再导出便携版并调用 Windows IExpress 制作安装包。开发环境的运行数据位于 Godot 的 `user://runtime` 与 `user://profiles`，不会写入源码目录。

</details>

## 许可与第三方组件

本项目以 **源码公开（Source-Available）** 方式提供，并非 OSI 开源许可证。未经 FanzhouStudio 书面许可，禁止商业使用、倒卖、捆绑销售、二次封装、换皮以及分发修改版或编译成品。完整条款见 [LICENSE](LICENSE)。

Mihomo 是独立运行的第三方组件，继续适用 GNU GPL v3；其他第三方项目也保留各自的许可权利。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
