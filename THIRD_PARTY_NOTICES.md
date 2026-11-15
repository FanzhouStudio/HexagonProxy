# 第三方软件声明

## Antigravity-Proxy（可选部署的原生组件）

- 项目与对应源码：https://github.com/yuaotian/antigravity-proxy/tree/v2.4
- 发布包：`antigravity-proxy-v2.4-ide-win-x64.zip`
- 发布包 SHA-256：`ee4aead95b677148c6ac4d8e46018b3b07e2b1e4249bb5232985628ee78d82e3`
- 随包文件：`third_party/antigravity-proxy/version.dll`、`config.template.json`。
- 保留的上游许可与作者声明：`third_party/antigravity-proxy/LICENSE.txt`、`AUTHORS.txt`（MinHook / HDE 的 BSD 条款）。
- 该 DLL 为独立上游程序，在用户点击启用后部署到 Antigravity 目录。HexagonProxy 不修改 DLL 字节，只根据本机端口生成配置；上游自动更新与镜像下载关闭。

HexagonProxy 的商业授权不替代这些上游组件的许可。组件来源、校验值与获取方式见同目录 `UPSTREAM.md`。

HexagonProxy随安装包分发下列独立程序。它们与HexagonProxy UI 进程以独立可执行文件形式运行。

## Mihomo

- 项目：https://github.com/MetaCubeX/mihomo
- 对应源码：https://github.com/MetaCubeX/mihomo
- 许可证：GNU General Public License version 3
- 许可证全文：源码仓库和发布包中的 `third_party/Mihomo-LICENSE.txt`

Mihomo 不提供任何担保。接收者可依据 GPL-3.0 获取、研究、修改和再分发其对应源码。

FanzhouStudio 针对HexagonProxy原创代码提供的 AGPL-3.0 或商业授权均不会改变 Mihomo 的许可证，也不代表 FanzhouStudio 有权对 Mihomo 提供替代商业许可。分发包含 Mihomo 的安装包时，仍须独立履行 GPL-3.0 的相应义务。

## MetaCubeX meta-rules-dat

- 项目：https://github.com/MetaCubeX/meta-rules-dat
- 文件：`third_party/meta-rules-dat/geosite-cn.mrs`、`geoip-cn.mrs`
- 许可证：GNU General Public License version 3
- 许可证全文：`third_party/meta-rules-dat/LICENSE`

HexagonProxy随包提供精简的中国大陆域名与 IP 规则集，以便规则模式在离线状态下正常启动。规则数据继续适用其上游许可证，不属于 FanzhouStudio 可另行商业授权的原创内容。
