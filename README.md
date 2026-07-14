# 平平 App

给平平做的 iOS App（SwiftUI，iOS 17+）。当前是 MVP 骨架，包含三个模块：平平档案、狗朋友（含 Tripo3D 建模接口）、遛狗轨迹（GPS + 新旧路线判断）。

## 在这台 Windows 机器上能做的事

代码在这里写、改、review。不能在这台机器上编译或运行——iOS 开发必须用 Xcode，只能在 macOS 上跑。

## 在 Mac 上首次打开工程

这个仓库没有手写 `.xcodeproj`，用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 自动生成，避免手改二进制工程文件出错。在 Mac 上：

```bash
brew install xcodegen
cd 平平app
xcodegen generate
open PingpingApp.xcodeproj
```

之后正常在 Xcode 里选模拟器或真机跑就行。**改完 `project.yml`（比如加新的权限描述、新 target）之后要重新跑一次 `xcodegen generate`。**

**第一次 clone 下来之后**，还要手动建一份密钥配置文件（这个文件不在 git 里，需要你自己建）：

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
# 然后编辑 Config/Secrets.xcconfig，把 TRIPO_API_KEY 换成真实的 key
```

没有这一步 `xcodegen generate` 会报找不到 `Config/Secrets.xcconfig`。

## 没有自己的 Mac？

推荐组合，不用自己买 Mac：

1. **GitHub 仓库**托管这份代码
2. **Apple Developer Program**账号（$99/年，TestFlight 必需）
3. **Xcode Cloud**（App Store Connect 里配置，付费开发者账号自带每月 25 小时免费额度）：push 到 GitHub 后自动跑 `xcodegen generate` + 编译 + 发布到 TestFlight，你直接在自己的 iPhone 17 / 17 Air / 17 Pro 上装 TestFlight App 测试，不用碰 Mac
4. 偶尔需要断点调试、Instruments 性能分析这类必须要交互式 Xcode 的场景，按小时租云端 Mac（MacinCloud 按需付费、或 AWS/Scaleway 的 Mac 实例）

## 待办 / 需要你补充的信息

- **3D 建模 API（Tripo3D）**：`PingpingApp/Services/ThreeDModelService.swift` 里 `TripoThreeDModelService` 实现了完整链路——上传图片换 `file_token` (`POST /files`) → 提交生成任务 (`generation/image-to-model`) → 轮询 (`tasks/{id}`) → 转成 `USDZ` (`models/convert`，确认支持 `format: USDZ`) → 下载到本地。`AddFriendView.swift` 保存后自动跑完这整条链（每段轮询 3 秒一次、最多 3 分钟）。`FriendDetailView.swift` 用 SwiftUI 原生的 `.quickLookPreview(_:)` 做了真的 3D 查看界面，点"查看 3D 模型"直接弹 QuickLook
- **还没实测过真实调用**：目前所有这些请求逻辑都只是写好、没编译过（没有 Mac），第一次跑通大概率要现场调一些细节（字段名、错误处理、Tripo 账户余额够不够跑一次生成）
- **API Key 安全**：真实 key 放在 `Config/Secrets.xcconfig`（已加入 `.gitignore`，不会被提交），仓库里只有 `Config/Secrets.example.xcconfig` 模板。因为这是客户端直连 Tripo API（没有做后端代理），key 会打包进 App 里，理论上被反编译能提取出来——目前只给你和女朋友用风险可控，如果以后要给更多人用，建议加一层自己的后端转发，不要让 key 留在客户端
- **后台定位权限文案**：`project.yml` 里 `NSLocationAlwaysAndWhenInUseUsageDescription` 等文案是我先写的，提交 App Store 审核前建议再打磨一下措辞
- **勋章/成就系统**：根据你发的参考图，首页已经加了勋章预览条的 UI 占位（`ProfileView` 那块），但打卡规则、勋章库这些还没排进 data model 和实际逻辑，目前是 backlog
- 叫声判断、衣橱/OOTD、照片去重三个模块目前是 backlog，还没排进代码里

## 已知需要在真机上验证的点

- `LocationManager` 里 `allowsBackgroundLocationUpdates` 需要用户先同意"始终允许"定位授权才会真正在后台生效，模拟器上不好完整测试后台/锁屏轨迹，建议真机测试
- 路线相似度判断（`RouteMatchingService`）目前是简单的"走廊重合比例"算法（采样点是否落在已知路线 30 米范围内），线上数据量大了以后可能要换更精确的算法（比如 Fréchet 距离）
