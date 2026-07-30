# AI 视窗

<img src="apps/ios/AIWindow/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" alt="AI 视窗 App 图标">

AI 视窗（工程名 `AIWindow`）是一款面向 iPhone 的开源 AI 资讯与社区浏览工具。它把 AI HOT 的公开资讯接口、LINUX DO 站内搜索、本地收藏和用户自带模型的帖子分析放在一个 SwiftUI App 中。

> AI 视窗是独立开发的非官方客户端，与 AI HOT 和 LINUX DO 无隶属、合作或认可关系。

## 功能

- AI HOT 精选、热点和最新日报，支持时间窗口、分类、搜索、刷新和 cursor 分页
- 资讯详情中的 AI HOT 署名、canonical 入口、第三方原文入口和系统分享
- App 内原样打开 LINUX DO 官方搜索页；Bing / Google 作为临时会话备用入口
- LINUX DO 浏览历史、收藏、标签、备注和 JSON 备份恢复，数据保存在本机；异常旧标题会先显示帖子编号，并在用户重新打开该帖子时校正
- LINUX DO 登录状态在 App 沙盒中保持，并可在设置中清除此 App 的会话
- Kimi、DeepSeek、GLM、OpenAI 模型预设与自定义兼容服务，一键分析当前已加载的帖子文字
- 无自建账号、无广告、无行为统计 SDK、无项目后端；资讯和浏览功能不需要 API Key

当前模型能力是用户主动触发的单次帖子分析，不是 Chatbot；App 后端尚未开发。

## 第三方服务边界

AI HOT 明确允许个人项目和独立产品客户端使用匿名只读接口。公开展示数据时，本项目保留 AI HOT 署名与 canonical 链接；同一完整 URL 至少间隔 60 秒才会再次请求，过期缓存使用条件请求，收到 `Retry-After` 时继续退避。详见 [AI HOT 公开接入条款](https://aihot.virxact.com/terms)。

LINUX DO 的访问仅由用户通过官方搜索页、外部搜索备用入口、系统浏览器或 `WKWebView` 发起。默认搜索直接在持久 `WKWebView` 中打开 `linux.do/search`，保留站点自己的网页样式、排序和筛选；项目不调用或模拟论坛 API。用户可以在网页内自行登录，但项目不自动登录、签到、发帖、点赞或读取通知，也不爬取、后台监控、镜像或批量再分发论坛帖子和图片。只有在用户点击“分析当前帖子”后，App 才会提取当前页面已经加载的正文文字并发送到用户自己配置的模型服务；不会自动加载未浏览回复。详见 [LINUX DO 服务条款](https://linux.do/tos)。

第三方名称、商标、接口数据、帖子、图片和链接文章不属于本仓库的 MIT 授权范围。完整声明见 [NOTICE.md](NOTICE.md)。

## 环境与构建

- macOS 与 Xcode 26 或兼容版本
- iOS 17 或更高版本的 iPhone / Simulator

无需签名的模拟器构建：

```sh
cd apps/ios
xcodebuild \
  -project AIWindow.xcodeproj \
  -scheme AIWindow \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

测试前先用以下命令查看本机已安装的 Simulator，再把目标名称填入测试命令：

```sh
xcodebuild -project AIWindow.xcodeproj -scheme AIWindow -showdestinations
xcodebuild \
  -project AIWindow.xcodeproj \
  -scheme AIWindow \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=<Simulator Name>' \
  test
```

真机签名和安装见 [apps/ios/README.md](apps/ios/README.md)。项目不会提交任何开发者的 Apple Team 值。

## 隐私

SwiftData 数据库存放在 App 沙盒中。导出的 JSON 包含帖子链接、标题、时间、收藏、标签、备注和搜索记录，不包含网页正文、Cookie 或账号凭据。

LINUX DO 官方搜索和其他 `linux.do` 顶层页面使用 App 专属的持久网页存储，以便搜索时复用登录状态并在重启后保持登录。Bing 和 Google 备用搜索使用临时网页会话。Cookie 仍留在 App 沙盒，代码不会读取、记录或导出它们。设置中的“清除此 App 的登录状态”会清空该持久网页存储，不撤销其他设备的会话，也不影响 Safari。

模型服务、模型、推理强度和自定义 HTTPS 地址保存在普通本地设置中，用户提供的 API Key 只进入当前设备的 Keychain，不进入 SwiftData、JSON 备份或 Git。首次向某个模型域名分析时，App 会显示实际发送范围；请求由 iPhone 直接发往该服务，不经过 AIWindow 服务器。发送内容仅含当前已加载的帖子文字、标题、canonical URL 和用户问题，不含 Cookie、密码、验证码或其他浏览记录。分析结果只在当前界面内存中显示。

AI HOT 内容当前只保留在运行内存中；App 不发送设备标识符或 Apple 账号信息。

## 项目结构

```text
AIWindow/
├── apps/ios/                 iPhone App 与测试
├── docs/                     架构和资产来源说明
├── scripts/                  图标重建与公开发布审计
├── AGENTS.md                 贡献与验证约束
├── LICENSE                   MIT License
├── NOTICE.md                 第三方权利与非官方声明
└── SECURITY.md               安全问题报告方式
```

## 开源审计

提交前从仓库根目录运行：

```sh
./scripts/public_release_audit.sh
git diff --check
```

审计脚本会检查签名字段、本机路径、常见凭据和设备标识符、本地 Xcode 状态、未审阅媒体以及公开文件完整性。它不能替代人工代码审查或法律意见。

## License

项目自有代码和素材使用 [MIT License](LICENSE)。第三方服务与内容边界见 [NOTICE.md](NOTICE.md)。
