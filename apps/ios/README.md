# AI 视窗 for iOS

AI 视窗是 iOS 17+ 的 SwiftUI App，提供 AI HOT 公开资讯、LINUX DO 站内搜索、本地收藏和用户自带模型的帖子分析。它是非官方独立客户端；Chatbot 和 App 后端尚未加入。

## 当前功能

- AI HOT 精选、热点、最新日报、分类、搜索、刷新和分页
- AI HOT 署名、canonical 入口、第三方原文入口和系统分享
- 保留网页原样的 LINUX DO 官方搜索页，以及 Bing / Google 临时备用入口
- LINUX DO 官方搜索与主站共享持久登录会话；外部搜索使用临时会话
- 网页内自行登录、跨重启保持登录，以及设置页清除此 App 的会话
- LINUX DO 帖子浏览历史、收藏、标签、备注和检索
- 一键整理当前已加载帖子文字并发送到用户配置的 Chat Completions API
- JSON 导入、导出、格式校验和去重合并
- 无自建账号、无后端、无广告、无行为统计 SDK；核心浏览功能无需 API Key

## 环境

- macOS 与 Xcode 26 或兼容版本
- iOS 17 或更高版本的 iPhone / Simulator
- 真机安装需要一个已添加到 Xcode 的 Apple Account

## 在自己的 iPhone 上安装

1. 用 Xcode 打开 `AIWindow.xcodeproj`。
2. 连接并选择自己的 iPhone。
3. 打开 `AIWindow` target 的 **Signing & Capabilities**。
4. 保持 **Automatically manage signing** 开启，并在本机选择自己的 Team。
5. 若 `com.local.AIWindow` 冲突，在本机改成自己控制的 Bundle Identifier。
6. 点击 Run；设备若要求开发者模式或信任开发者，只按 iOS 系统提示处理。

仓库有意不保存 `DEVELOPMENT_TEAM`。选择 Team 后，Xcode 可能修改 `project.pbxproj`；不要把个人 Team 值、签名证书、描述文件或设备标识符提交到 Git。提交前运行根目录的 `scripts/public_release_audit.sh`。

个人团队签名可能存在有效期限制，具体以当前 Xcode 和 Apple Account 提示为准。

## 配置帖子分析

在 App 的“设置 → AI 分析”中填写完整的 OpenAI-compatible Chat Completions HTTPS 地址、模型名称和自己的 API Key。项目不预置模型服务或共享密钥；API Key 只存入当前设备的 Keychain，可在同一页面一次清除全部模型设置。

打开一个 LINUX DO 主题后，点击底部的星光按钮即可自动整理当前已经加载的主帖和附近回复。第一次向某个模型域名发送时会显示目标域名和实际范围；之后不要求手动选择帖子文字。该功能不会自动滚动、加载整帖或分析私信和账号页面。

## 命令行验证

无需签名的 Debug 构建：

```sh
xcodebuild \
  -project AIWindow.xcodeproj \
  -scheme AIWindow \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Release 构建把 `-configuration Debug` 改为 `Release`。运行测试前先查看可用目标：

```sh
xcodebuild -project AIWindow.xcodeproj -scheme AIWindow -showdestinations
xcodebuild \
  -project AIWindow.xcodeproj \
  -scheme AIWindow \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=<Simulator Name>' \
  test
```

## 数据、网络与隐私

SwiftData 数据库存放在 App 沙盒中。导出的 JSON 包含帖子链接、标题、时间、收藏、标签、备注和搜索记录，不包含网页正文、Cookie 或账号凭据。导入默认合并现有数据，不覆盖已有非空备注。

AI HOT 通过 `https://aihot.virxact.com/api/v1` 匿名读取，不发送账号、Cookie、设备标识符或 API Key。响应只缓存在运行内存中；相同完整 URL 在 60 秒内不会重复请求，过期后使用条件请求，并遵守服务端 `Retry-After`。

LINUX DO 页面只由用户主动打开。默认搜索直接进入 `linux.do/search` 官方网页，保留站点自己的结果样式、排序和筛选，并与其他 `linux.do` 顶层页面共用 App 沙盒中的持久 WebKit 数据存储。App 不抓取、解析或重分发搜索结果，也不调用或模拟论坛 API。Bing 和 Google 仅作为备用入口，其结果页使用临时数据存储；从备用结果进入主站时会自动切换到持久会话。第三方 HTTPS 链接在独立的临时 App 内网页中打开，不接触 LINUX DO 的登录会话。

App 不读取、记录或导出 Cookie、密码与验证码，也不判断具体账号身份。设置页的“清除此 App 的登录状态”会清空 App 的持久 WebKit 数据，不撤销其他设备的会话，也不影响 Safari。项目不自动登录、签到、发帖、点赞、读取通知，也不对论坛执行爬取、后台监控或批量内容提取。

模型分析只在用户点击后读取当前页面已渲染的帖子正文，并与用户问题一起从 iPhone 直接发送到所配置的模型服务。请求不包含 Cookie、密码、验证码、其他浏览记录或未加载回复，也不经过 AIWindow 后端。模型端点和模型名保存在普通本地设置中；API Key 在 Keychain 中；提示、帖子正文和结果都不进入 SwiftData 或 JSON 备份。

服务条款和第三方权利边界见仓库根目录的 `NOTICE.md`。
