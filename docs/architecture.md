# AI 视窗架构

## 产品结构

项目采用一个 iPhone App 和一个 Git 仓库。搜索、收藏、浏览历史和用户自带模型的帖子分析共享同一套界面，避免多个移动端工程长期分叉。

移动端使用 SwiftUI、SwiftData 和 `WKWebView`，最低支持 iOS 17。目前没有 App 后端，也没有 Chatbot。

## 数据链路

```text
AI HOT：   iPhone App -> AI HOT `/api/v1` 匿名只读接口
LINUX DO：iPhone App -> 临时搜索会话 -> 用户驱动的持久主站 WKWebView
模型分析：当前帖子 WKWebView -> 本机上下文整理 -> 用户配置的模型 API
本地数据：iPhone App -> SwiftData / 用户选择的 JSON 备份文件
```

### AI HOT

- 客户端显示响应中的 AI HOT 署名、站内 canonical 入口和第三方原文链接。
- 内存缓存以完整 URL 为键。相同 URL 在 60 秒内直接复用缓存，不发网络请求。
- 60 秒后使用可用的 `ETag` / `Last-Modified` 条件请求；`304 Not Modified` 继续复用缓存。
- `429` 和 `503` 响应中的 `Retry-After` 会延长下一次允许请求的时间。
- cursor 按不透明字符串处理；未知可选字段和未知分类不会破坏已有功能。
- 当前不持久化 AI HOT 响应，也不公开镜像或批量再分发数据。

这些约束实现 [AI HOT 公开接入条款](https://aihot.virxact.com/terms) 和[接入页](https://aihot.virxact.com/agent)所要求的来源、缓存与调用频率边界。

### LINUX DO

- 搜索由 Bing 或 Google 的 `site:` 查询完成，不调用或模拟 LINUX DO 搜索接口。
- Bing 和 Google 结果页使用非持久 `WKWebsiteDataStore`。用户选择 `linux.do` 结果时，App 新开一个使用默认持久数据存储的主站 `WKWebView`，因此登录状态可跨重启保留。
- 持久会话只允许 `linux.do` 作为顶层页面；搜索引擎和第三方站点不会进入该持久会话。第三方 HTTPS 链接使用独立的临时 App 内网页会话，用户仍可从菜单明确选择默认浏览器。
- 用户只能在网页内自行登录和操作。App 不读取 Cookie、密码、验证码或账号状态，不自动登录、签到、发帖、点赞或抓取通知。
- 设置页可清空 App 的全部持久 WebKit 数据并通知已打开的 LINUX DO 页面重新加载。该存储只供 LINUX DO 主站会话使用，清除不会影响 Safari。
- App 观察 `WKWebView` 地址变化以适配站内无刷新导航，只从用户正在浏览的 `linux.do/t/...` 页面记录 canonical URL、标题、时间和访问次数。
- 不使用网络爬虫、浏览器插件、后台监控、批量提取、iframe 嵌入或内容再分发。

该边界按 [LINUX DO 服务条款](https://linux.do/tos)中对自动访问和监控的限制设计。

### 用户模型分析

- 用户在设置中填写完整的 OpenAI-compatible Chat Completions HTTPS 地址、模型名和 API Key。地址与模型名进入普通本地设置，密钥只存入仅当前设备、解锁后可用的 Keychain。
- 分析必须由用户在 `linux.do/t/...` 页面点击触发。JavaScript 只读取当前 DOM 已渲染的帖子正文和标题，不读取 Cookie、local storage、隐藏脚本、账号信息或未加载回复；桥接前最多保留 100 个候选段落，每段先限制为 12,000 字符。
- 本机上下文整理始终保留已加载范围内最早的段落，再按当前视口距离选择附近回复；最终最多 20 段、24,000 字符。若主帖未加载，界面不会误称已包含主帖。
- 系统提示把论坛文本标记为不可信资料；模型结果按纯文本显示，不执行链接、命令或工具调用。
- 首次向某个模型域名发送前显示一次实际发送范围。请求使用无 Cookie、无凭据缓存的临时 `URLSession`，拒绝重定向，并限制响应体和最终文字长度。
- 请求从 iPhone 直接到用户选择的模型服务。AIWindow 不提供中转后端，不接收 API Key、帖子内容或模型结果。

## 本地数据与隐私

LINUX DO 搜索记录、帖子元数据、收藏、标签和备注存入 SwiftData。JSON 备份由用户主动导出或导入，默认合并且不覆盖已有非空备注。网页正文、模型提示与结果、Cookie、密码、验证码、Apple 凭据、签名身份、设备标识符和 API Key 不进入数据库或备份。LINUX DO Cookie 只由 WebKit 保存在 App 沙盒中的持久网页存储，并可由用户整体清除。

## 安全与签名

- 工程启用自动签名，但不提交 `DEVELOPMENT_TEAM`。开发者只在本机选择自己的 Team。
- App 不包含第三方 SDK 或包管理器依赖；当前只链接 Apple 系统框架。
- 项目不得在安装包或 Git 仓库中放置共享模型密钥。用户自己的密钥只能由当前设备 Keychain 保存；只有未来提供项目统一额度、账号或订阅时才考虑独立后端。

## 后续方向

1. 统一 AI HOT 与 LINUX DO 的收藏入口，并明确离线缓存和备份边界。
2. 增加日报历史选择和 JSON 备份完整往返回归。
3. 只有在现有资讯与本地数据能力稳定后，才单独设计 Chatbot 和 App 后端。

任何新增数据源都必须先确认其访问条款、署名要求、缓存频率和内容再分发边界。
