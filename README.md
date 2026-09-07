<p align="center">
  <img src="assets/app_icon.png" width="104" alt="HexagonProxy 图标">
</p>

<h1 align="center">HexagonProxy</h1>

<p align="center">
  一只会守护网络的像素美西螈<br>
  面向 Windows 的轻量 Mihomo 图形客户端
</p>

<p align="center">
  <img alt="Latest Release" src="https://img.shields.io/github/v/release/FanzhouStudio/HexagonProxy?label=Release">
  <img alt="Windows" src="https://img.shields.io/badge/Windows-10%20%2F%2011-3478b8">
  <img alt="Godot" src="https://img.shields.io/badge/Godot-4.7-478cbf">
  <img alt="Mihomo" src="https://img.shields.io/badge/Core-Mihomo-16866f">
  <img alt="License" src="https://img.shields.io/badge/License-AGPL--3.0--only-663399">
</p>

<p align="center">
  <a href="https://github.com/FanzhouStudio/HexagonProxy/releases">下载最新版</a> ·
  <a href="https://github.com/FanzhouStudio/HexagonProxy/issues">反馈问题</a> ·
  QQ 群：1102815471
</p>

HexagonProxy 将订阅、节点、系统代理、应用分流、故障切换、内置终端与桌面宠物整合在同一个像素水晶界面中。网络协议由独立运行的 [Mihomo](https://github.com/MetaCubeX/mihomo) 内核处理，客户端负责本地配置、交互与 Windows 集成。

## 下载与首次使用

当前官方 Windows Release 默认提供单文件便携版：

| 文件 | 说明 |
| --- | --- |
| `HexagonProxy.exe` | Windows x64 便携版，下载后直接运行 |
| `SHA256SUMS.txt` | 发布文件 SHA256 校验值 |

正式发布版不再内置 Mihomo，以降低主程序体积。首次使用请进入：

**设置 → Mihomo 内核 → 检查并下载最新内核**

正常使用通常不需要管理员权限。当前个人发布版本尚未购买代码签名证书，因此 Windows SmartScreen 或部分安全软件可能显示未知发布者/启发式提示；建议从官方 Releases 下载并核对 SHA256。

### 快速开始

1. 打开“订阅”，添加 Clash/Mihomo 订阅、V2 分享链接或本地 YAML。
2. 切换到需要使用的配置，在“节点”页选择线路并测速。
3. 返回“总览”，打开“一键连接”。
4. 关闭主窗口可继续在系统托盘守护；需要彻底退出时使用右上角“退出”、ESC 退出确认或托盘菜单。

## 主要功能

### 订阅与协议

- 支持 HTTP / Clash / Mihomo 订阅、本地 YAML 与 V2 分享链接导入。
- 支持多个 HTTP、V2、本地配置同时保存、切换、刷新和删除。
- 支持 VLESS Reality、VMess、Trojan、SS、SSR、Hysteria2、TUIC 等常见节点格式。
- 分享链接可本地解析，无需依赖第三方在线转换服务。

### 节点与稳定性

- 节点选择、单节点测速、批量测速。
- 节点页采用增量刷新；延迟、选中状态与备选状态不会反复重建整个列表。
- 大型订阅分批渲染，已针对数百节点场景做稳定性测试。
- 可手动指定故障切换备选节点。
- 当前节点连续探测失败后，自动选择健康备选中延迟最低者。
- 内置冷却、失败周期与熔断机制，避免全部掉线时循环切换。

### 代理与分流

- 规则、全局、直连三种代理模式。
- 应用分流：按 Windows `.exe` / 进程名设置直连或走代理。
- 应用规则优先于普通域名/IP 规则。
- 当前基于 Windows 系统代理工作，暂未提供 TUN 模式。

### 本地网络保护

HexagonProxy 会同时在 Windows 系统代理层和 Mihomo 规则层保护本机/局域网访问，避免常见本地服务被错误送入远程代理。

默认直连/绕过包括：

- `localhost`、`127.0.0.0/8`、IPv6 `::1`
- `10.0.0.0/8`
- `172.16.0.0/12`
- `192.168.0.0/16`
- `169.254.0.0/16`
- `100.64.0.0/10`
- IPv6 ULA / Link-local
- `.local`、`.lan`、`.home.arpa` 等常见本地域名

启用系统代理时会合并用户原有的 `ProxyOverride`，关闭时恢复原值，不会简单覆盖已有公司内网或自定义例外规则。

### 端口管理

- 混合代理端口与控制接口端口可编辑、随机生成并持久化。
- 保存前进行范围、重复和占用检查。
- 端口被占用时可查看占用进程名称与 PID。
- 用户确认后可结束占用进程并等待端口真正释放。
- Windows 关键系统进程、HexagonProxy 自身以及当前受管理的 Mihomo 受到保护，避免误杀。

### 内置终端

- 内置 PowerShell / CMD，可直接在 HexagonProxy 中执行常用网络与开发命令。
- 支持工作目录选择、常用命令预设、停止进程树、清空输入与输出。
- 输出采用增量读取与批量 UI 刷新，长日志不会反复扫描整份文件。
- 针对 PowerShell、CMD、Node.js / npx 等原生程序做 UTF-8 中文输出兼容。
- 超长输出会自动清理较早内容，避免终端长时间运行后持续变卡。
- PowerShell 采用透明的临时 `.ps1` + `RemoteSigned` 启动方式，不使用 `EncodedCommand` / `ExecutionPolicy Bypass`。

> 内置终端会执行用户主动输入的命令，请只运行自己理解并信任的命令。

### Codex 账号切换

- 新建账号配置后切换，在 Codex 桌面端完成官方登录；也可导入完整的 `auth.json`。
- “保存为独立账号”按登录身份匹配已有账号；新身份保存为新账号，不再覆盖默认栏。空账号栏可点击“将当前登录保存到此账号”，把当前登录绑定到指定栏位。
- 状态刷新不会替换已保存账号身份；切换前若发现外部更换了登录，会先独立保存新账号，保护旧备份。
- 切换先关闭 Codex，再保存它最新的登录状态，仅切换 `auth.json` 与 `config.toml`，随后重新启动。聊天历史、SQLite 数据库和插件文件不被复制或覆盖。
- 每个账号保存自己的配置；导入或新建账号会继承当前配置中的其他设置，并选择 OpenAI provider 和文件凭据存储。
- 认证、配置或账号索引写入失败，以及桌面启动失败，都会尝试恢复切换前的状态。异常中断后显示“恢复中断切换”入口。
- 账号卡片直接显示 5 小时、每周剩余额度进度条，以及本地恢复时间和倒计时。保存登录后自动查询一次，仍可点击“查额度”更新。失败时保留上次结果；未知值显示“未知”。API Key 账号不提供 ChatGPT 订阅额度。
- 登录文件只保存在本机。额度查询仅请求 OpenAI 官方地址，令牌不进入界面、账号索引或错误输出。令牌过期后需在 Codex 中重新登录或导入新文件，不主动轮换 refresh token。
- 支持 `CODEX_HOME`，兼容旧版独立账号目录；迁移只复制认证与配置，保留原始目录。移除账号只删除列表入口。
- 当前切换使用文件凭据。若当前登录使用 `keyring` / `auto` 或 `auth.json` 不完整，会在修改前提示先设置 `cli_auth_credentials_store = "file"` 并重新登录，确保原账号能够恢复。

账号索引位于 Godot 用户数据目录的 `codex_profiles.json`，备份默认位于 `%USERPROFILE%\.codex-profiles\HexagonProxy\accounts`。切换会中断 Codex 中正在运行的本地任务，界面会在执行前提示。

功能设计参考 [codex-tools](https://github.com/170-carry/codex-tools)，以本项目的 Godot / PowerShell 架构实现。认证格式及文件存储规则参见 [OpenAI 官方认证说明](https://learn.chatgpt.com/docs/auth)。额度服务接口可能发生变化；查询失败会显示原因，不会更改当前登录或伪造额度。

### Windows 集成

- 系统托盘驻留与窗口恢复。
- 可选开机自启。
- 右上角提供最小化、关闭到托盘与安全退出入口。
- ESC 可快速打开/取消退出确认。
- 正常退出时恢复系统代理并停止由 HexagonProxy 启动的 Mihomo。
- 可拖动透明桌面宠物显示当前节点与延迟状态。

### 界面与性能

- 海蓝治愈 / 夜海黑两套主题，可实时切换并持久化。
- UI 使用数据驱动的纹理主题与统一 `UiFactory`。
- 节点结构变化采用双缓冲网格：新列表构建完成后再一次性交换，避免刷新空白帧。
- 水族背景拆分为静态背景层与独立气泡动画层，减少全屏重绘压力。

## 隐私与安全

- 订阅、节点与运行配置默认仅保存在本机用户数据目录，不会上传到 HexagonProxy 服务器。
- Mihomo 控制接口仅监听 `127.0.0.1`，运行配置会生成控制访问密钥。
- 本地网络与回环地址默认绕过远程代理，降低本地开发服务、NAS、路由器后台等访问异常的概率。
- 下载 Mihomo 后由应用负责本地管理；正式版主程序不内置 Mihomo 二进制。
- 当前版本未提供 TUN，因此部分游戏、驱动级网络程序或完全忽略 Windows 系统代理的软件可能不受应用分流控制。
- 当前官方个人发布版本尚未使用 Authenticode 代码签名，安全软件可能基于启发式/ML 产生误报；建议核对 GitHub Release 来源与 SHA256。

## 架构

HexagonProxy 按 UI、协调层与服务/模块层拆分，避免界面直接调用系统能力：

```text
UI Panels
    ↓ user intent / view state
Coordinators
    ↓
Services / Modules
    ├─ Proxy / Mihomo
    ├─ Subscription
    ├─ Routing / Failover
    ├─ System Proxy / Ports
    ├─ Terminal
    └─ Theme / Runtime Profile Pipeline
```

应用分流、动态端口等运行时配置通过 `RuntimeProfilePipeline` 组合，便于后续扩展而不把逻辑重新堆回主控制器。

<details>
<summary><strong>从源码运行与构建</strong></summary>

### 环境

- Windows 10/11 x64
- Godot 4.7 stable
- Git（用于源码管理）

使用 Godot 打开仓库目录即可运行。开发时如果本机已经有 `bin/mihomo.exe` 可以直接使用；没有时也可以通过应用设置页按需下载运行内核。

### 构建 Windows 便携版

在仓库根目录的 PowerShell 中执行：

```powershell
.\tools\build_windows_release.ps1
```

脚本会先运行发布门禁测试，再导出：

```text
dist/HexagonProxy.exe
dist/SHA256SUMS.txt
```

构建统一输出 `dist/HexagonProxy.exe` 和 `SHA256SUMS.txt`，不再生成带版本后缀的 EXE 或安装包。测试和导出成功后覆盖旧包，并清理 build/dist 内历史 HexagonProxy 应用包；若旧程序正在运行导致文件占用，请退出后重新构建。Mihomo 内核不打入 EXE。

开发环境运行数据位于 Godot 用户目录下的 `user://runtime`、`user://profiles` 等位置，不写入源码目录。

</details>

## 开源许可与商业授权

HexagonProxy 的原创客户端代码及随附材料以 **GNU Affero General Public License v3.0 only（AGPL-3.0-only）** 开源。你可以免费使用、研究、修改、分发和商业使用，但必须遵守 AGPL-3.0 的源码公开、相同许可证和通知保留等要求。

- 许可范围：[LICENSING.md](LICENSING.md)
- 完整许可证：[LICENSE](LICENSE)
- 对应源码说明：[SOURCE.md](SOURCE.md)
- 第三方许可：[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

如果企业需要闭源集成、OEM / 品牌定制、私有发行，或希望获得不受 AGPL-3.0 约束的其他权利，可以申请单独的商业授权。详情见 [COMMERCIAL-LICENSE.md](COMMERCIAL-LICENSE.md)，联系邮箱：**494919080@qq.com**。

“HexagonProxy”“FanzhouStudio”以及项目名称、Logo 和官方版本标识不因代码开源而自动授权。第三方版本不得冒充官方版本，详见 [TRADEMARK.md](TRADEMARK.md)。

Mihomo 是独立运行的第三方组件，继续适用其自身的 GNU GPL v3 许可，不属于 FanzhouStudio 可另行商业授权的代码。

## 参与贡献

欢迎提交 Issue 和 Pull Request。提交代码前请阅读：

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [CLA.md](CLA.md)

贡献者保留自己贡献的著作权；CLA 允许 FanzhouStudio 在保持社区版本开源的同时，对有权另行许可的原创内容继续提供商业授权。
