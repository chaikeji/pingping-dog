# 平平 App

给平平做的 iOS App（SwiftUI，iOS 17+）。当前是 MVP 骨架，包含三个模块：平平档案、狗朋友（含3D建模占位接口）、遛狗轨迹（GPS + 新旧路线判断）。

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

## 没有自己的 Mac？

推荐组合，不用自己买 Mac：

1. **GitHub 仓库**托管这份代码
2. **Apple Developer Program**账号（$99/年，TestFlight 必需）
3. **Xcode Cloud**（App Store Connect 里配置，付费开发者账号自带每月 25 小时免费额度）：push 到 GitHub 后自动跑 `xcodegen generate` + 编译 + 发布到 TestFlight，你直接在自己的 iPhone 17 / 17 Air / 17 Pro 上装 TestFlight App 测试，不用碰 Mac
4. 偶尔需要断点调试、Instruments 性能分析这类必须要交互式 Xcode 的场景，按小时租云端 Mac（MacinCloud 按需付费、或 AWS/Scaleway 的 Mac 实例）

## 待办 / 需要你补充的信息

- **3D 建模 API**：`PingpingApp/Services/ThreeDModelService.swift` 里 `PlaceholderThreeDModelService` 是占位实现，等你确认 API 的 endpoint / 鉴权方式 / 输入格式（照片还是视频）/ 同步还是异步任务后替换成真实网络请求
- **后台定位权限文案**：`project.yml` 里 `NSLocationAlwaysAndWhenInUseUsageDescription` 等文案是我先写的，提交 App Store 审核前建议再打磨一下措辞
- 叫声判断、衣橱/OOTD、照片去重三个模块目前是 backlog，还没排进代码里

## 已知需要在真机上验证的点

- `LocationManager` 里 `allowsBackgroundLocationUpdates` 需要用户先同意"始终允许"定位授权才会真正在后台生效，模拟器上不好完整测试后台/锁屏轨迹，建议真机测试
- 路线相似度判断（`RouteMatchingService`）目前是简单的"走廊重合比例"算法（采样点是否落在已知路线 30 米范围内），线上数据量大了以后可能要换更精确的算法（比如 Fréchet 距离）
