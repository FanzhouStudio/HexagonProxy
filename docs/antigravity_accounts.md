# Antigravity 独立账号与额度

在 Antigravity 页中选择程序，点击“添加账号并登录”（备注可选），立即打开独立的官方登录窗口。完成官方登录后会自动检测登录与额度，并保存账号身份；每行账号都有“切换”和“刷新登录与额度”。无需先创建目录再从下拉框选择。默认账号行使用原有数据目录，之前创建的配置保留在列表中。

各账号单独保存登录，共享原有项目与对话。账号的 `home/.gemini/antigravity` 和 `home/.gemini/config` 使用目录联接指向 Windows 用户原来的 `.gemini` 数据目录，账号的 `.gemini/jetski-standalone-oauth-token` 保持独立。项目文件本身不移动。只复制项目选择和对话布局等明确的界面状态字段，不复制其他账号的登录身份字段。

旧版创建的私有项目和历史会在首次切换时迁移：先请求正常关闭目标账号窗口，等待后台退出；如有未保存提示或无法关闭则取消，不强行终止。将原目录保留为 `.before-sharing-时间戳` 备份后合并新增项目、对话文件和 SQLite 对话索引；已有同名文件或对话行不会覆盖，冲突内容保留在备份。对话全文搜索索引由 Antigravity 自己维护，程序只合并对话列表和父子关系。失败会恢复旧账号目录，重试不会重复覆盖数据。完成迁移后，所有账号看到同一批项目和对话，无需重新创建工作区。

点击任意账号行的“刷新登录与额度”读取该配置运行中的本地语言服务。显示接口返回的模型剩余百分比、重置时间和查询时间，账号行显示缓存摘要。添加或切换后自动轮询登录（最长约两分钟）；未登录、未运行、权限不足或接口版本不兼容时显示未知及原因。缺失额度不会显示为 0。账号操作信息显示在账号栏，与网络代理状态独立。登录由官方窗口完成，不自动填写 Google 凭据。

Windows 启动器使用独立子进程环境和不继承标准输出的进程创建，账号窗口不会依赖助手的输出管道。语言服务按程序路径和编辑器进程归属匹配，支持用户目录路径的正反斜杠差异。原生调用、登录识别、额度读取和重启后的元数据恢复可用隔离配置执行 `tests/test_antigravity_live_flow.gd` 检查；该测试需要设置独立的 `HEXAGON_ANTIGRAVITY_TEST_ROOT`，不会操作正常账号列表。

实现参考（未引入这些项目的依赖或可执行文件）：

- [OrbitSwitch](https://github.com/shengyy/orbitswitch)：账号列表与额度呈现。
- [MultiGravity](https://github.com/rodolford1112/MultiGravity-Multi-Profile-Manager-for-Antigravity)：Windows 独立数据目录及子进程环境隔离。后端采用远程会话兼容环境以使用独立目录内的凭据文件，这可能影响依赖会话类型的第三方扩展。
- [OpenUsage Windows 的 Antigravity 接口说明](https://github.com/mesomya/openusage-windows/blob/main/docs/providers/antigravity.md)：本地语言服务发现、GetUserStatus 和 quotaInfo 字段。请求仅发往匹配进程的本机端口，CSRF 不写入日志和账号列表；自签名证书兼容只用于该本机请求，不改变外网 TLS 验证。
