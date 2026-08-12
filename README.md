# 六角代理

一款以“六角恐龙”粉色美西螈为主角、采用浅色通透水晶界面的 Windows 代理客户端。六角代理本身负责界面、订阅管理、配置和系统代理，网络协议由成熟的 [Mihomo](https://github.com/MetaCubeX/mihomo) 内核处理。

## 已实现

- 一键启动/停止内核，并联动 Windows 系统代理
- Clash / Mihomo 订阅地址和本地 YAML 配置导入
- V2RayN 分享链接与 Base64 订阅正文导入，支持 VLESS Reality、VMess、Hysteria2、Trojan、SS、SSR、TUIC
- HTTP、V2 与本地配置可同时保存，在订阅库中自由切换、刷新和删除
- 策略组、节点选择和独立/批量延迟测试
- 规则、全局、直连三种模式
- 实时上下行速度、累计流量和活动连接数
- Windows 托盘驻留：主窗口关闭后代理和桌宠继续运行，可从托盘连接、断开或退出
- 开机自启：写入当前用户的 Windows 启动项，登录后自动缩到托盘并连接
- 置顶透明桌面宠物：可拖动、右键隐藏、双击打开主界面，头顶显示当前节点与实测延迟
- 在应用内从 GitHub 下载/更新 Windows x64 Mihomo 内核
- 订阅地址仅保存在本机用户目录；控制 API 仅监听 `127.0.0.1` 并带密钥
- 退出时关闭本应用开启的系统代理并停止内核

## 运行

1. 使用 Godot 4.7 打开本目录并运行项目。
2. 发布版已附带经过测试的 Mihomo 内核；也可在“设置”中检查并下载新版内核。
3. 在“订阅”中添加 HTTP 订阅、粘贴一条或多条 V2 分享链接，或导入本地 `.yaml/.yml`。
4. 返回“总览”，点击“一键连接”。
5. 在“设置 → 后台与启动”中控制托盘驻留、桌面宠物和开机自启。

开发期也可将官方 `mihomo.exe` 放到 `bin/mihomo.exe`，客户端会优先使用它。运行时文件位于 Godot 的 `user://runtime` 和 `user://profiles`，不会写入游戏工程。

## 构建

朋友不需要安装 Godot。开发者首次构建时运行模板下载脚本，它通过 HTTP Range 只获取 Windows x64 模板，然后导出单文件 EXE：

```powershell
node tools/fetch_godot_windows_templates.mjs "build_tooling/appdata/Roaming/Godot/export_templates/4.7.stable"
$env:APPDATA="$PWD/build_tooling/appdata/Roaming"
$env:LOCALAPPDATA="$PWD/build_tooling/appdata/Local"
Godot_v4.7-stable_win64.exe --headless --path "$PWD" --export-release "Windows Desktop" "$PWD/build/六角代理.exe"
```

发布时同时提供 `THIRD_PARTY_NOTICES.md` 与 `third_party/Mihomo-LICENSE.txt`。

`dist/六角代理.exe` 是无需安装的单文件便携版；`dist/六角代理安装包.exe` 会安装到当前用户目录，并创建桌面、开始菜单和卸载快捷方式，全程无需管理员权限。

## 范围说明

当前版本使用 Windows 系统 HTTP/SOCKS 混合代理（端口 `7890`）。托盘驻留与当前用户级开机自启不需要管理员权限；TUN 虚拟网卡和代码签名尚未加入。

## 许可与使用限制

本仓库以源码公开（Source-Available）的方式提供，并非 OSI 定义的开源软件。除非事先取得 FanzhouStudio 的书面许可：

- 仅允许个人、非商业的学习、评估、安全审查以及向官方项目贡献代码；
- 禁止商业使用、收费、倒卖、捆绑销售或借此提供付费服务；
- 禁止分发二次封装、修改版、换皮版、安装包、编译成品或镜像；
- 禁止移除版权、品牌和第三方许可声明。

完整条款请阅读 [LICENSE](LICENSE)。需要商业授权、集成或再分发许可时，请联系 FanzhouStudio。

Mihomo 是独立下载、独立运行的第三方组件，仍按 GNU GPL v3 授权；其他第三方项目也不受本仓库自定义许可重新授权。详情见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。粉色美西螈“六角恐龙”素材来自作者自有游戏《8-bit掌上宠物》。
