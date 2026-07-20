# 平平 App

给雪纳瑞「平平」做的 iOS 养宠 App，双人私用不上架。
SwiftUI + SwiftData，iOS 18+，四个 Tab：平平首页 / 狗朋友 / 遛狗 / 完美的一天。

**产品定义、功能细节、已知风险、路线图一律看 [`docs/PRD.md`](docs/PRD.md)。**
这份 README 只讲「怎么把仓库跑起来」，不重复 PRD 的内容 —— 两边都写迟早会不一致。

## 在 Windows 上

代码能写能改能 review，**不能编译** —— iOS 构建必须 Xcode，只跑在 macOS 上。
所以流程是「本地改 → push → GitHub Actions 云端编译」，一轮约 15 分钟。

## 生成 Xcode 工程

仓库里没有手写的 `.xcodeproj`，用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成，
免得手改二进制工程文件出错。在 Mac 上：

```bash
brew install xcodegen
xcodegen generate
open PingpingApp.xcodeproj
```

**改过 `project.yml` 之后（加文件、换权限、改 target 之类）要重跑一次 `xcodegen generate`。**

## 配置密钥（首次 clone 必做）

`Config/Secrets.xcconfig` 在 `.gitignore` 里，不进仓库，得自己建：

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
# 编辑它，把 TRIPO_API_KEY 换成真实 key
```

漏了这步，`xcodegen generate` 会报「找不到 Config/Secrets.xcconfig」。

## 出包装机（没有 Mac 时）

GitHub Actions 里两个 workflow：

| workflow | 用途 |
|---|---|
| `build.yml` | push 后自动编译，验证改动没把工程搞坏 |
| `ipa.yml` | 手动触发，打一个**未签名** ipa |

装机：下载 `ipa.yml` 的产物，用 [Sideloadly](https://sideloadly.io/) 侧载到 iPhone。
免费账号签的包 **7 天过期**，到期重签一次。
