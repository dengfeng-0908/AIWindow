# AI 视窗 for iOS

AI 视窗是 iOS 17+ 的 SwiftUI App，提供 AI HOT 公开资讯、LINUX DO 站内搜索和本地收藏能力。它是非官方独立客户端；Chatbot 和 App 后端尚未加入。

## 当前功能

- AI HOT 精选、热点、最新日报、分类、搜索、刷新和分页
- AI HOT 署名、canonical 入口、第三方原文入口和系统分享
- Bing / Google 的 LINUX DO 站内搜索入口
- 搜索引擎临时会话与 LINUX DO 主站持久登录会话
- 网页内自行登录、跨重启保持登录，以及设置页清除此 App 的会话
- LINUX DO 帖子浏览历史、收藏、标签、备注和检索
- JSON 导入、导出、格式校验和去重合并
- 无自建账号、无后端、无广告、无分析 SDK、无 API Key

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

LINUX DO 页面只由用户主动打开。Bing 和 Google 结果页使用临时 WebKit 数据存储；`linux.do` 顶层页面使用 App 沙盒中的持久数据存储，方便网页登录跨重启保持。搜索结果进入主站时会自动切换会话，其他 HTTP/HTTPS 链接交给 iOS 默认浏览器。

App 不读取、记录或导出 Cookie、密码与验证码，也不判断具体账号身份。设置页的“清除此 App 的登录状态”会清空 App 的持久 WebKit 数据，不撤销其他设备的会话，也不影响 Safari。项目不自动登录、签到、发帖、点赞、读取通知，也不对论坛执行爬取、后台监控或批量内容提取。

服务条款和第三方权利边界见仓库根目录的 `NOTICE.md`。
