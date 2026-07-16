# 平平 App · 产品需求文档（PRD）

> 版本：v1（2026-07-16 整理）
> 状态：MVP 骨架已搭好，正在做首页/遛狗/完美的一天的视觉与交互打磨
> 定位：给自家狗狗「平平」做的 iOS 养宠 App，你和女朋友共同管理

---

## 1. 产品概述

### 1.1 一句话定义
一个把「养狗的日常」游戏化、有温度、有仪式感的 iOS App —— 平平不只是一条数据记录，而是一个能在首页「活着」的 3D 形象，陪你走过每一次遛狗、每一个完成的照顾任务。

### 1.2 目标用户
- **主要**：App 拥有者（你）+ 女朋友，两人共同管理同一条狗
- 现阶段是**双人私用**，不面向公开市场，不上架 App Store（走 TestFlight 内部测试分发）

### 1.3 设计基调
- 视觉：荧光黄绿（#cdec2e）+ 灰/黑，勋章徽章的能量感 × 苹果原生液态玻璃质感
- 情感：安静、高级、有生命温度 —— 「像用星尘凝结成的灵魂」
- 原生优先：能用苹果系统能力（SwiftUI / RealityKit / SF 字体 / QuickLook）就不自造

---

## 2. 目标与非目标

### 2.1 本期目标（Phase 1 / 2）
- 三个核心模块能用：**平平首页、狗朋友（含 3D）、遛狗轨迹**
- 第四个模块骨架：**完美的一天**（每日照顾任务打卡 + 积分）
- 数据结构为「双人共管」预埋字段，但先单机本地存储
- 能在真机上跑起来（免费签名本地测试 → 定稿后 TestFlight）

### 2.2 非目标（明确不做 / 暂缓）
- ❌ 不上架 App Store、不做 Android
- ❌ 不做后端服务（Tripo API 客户端直连，key 打包进 App）——除非将来给更多人用
- ⏸ 联机同步（CloudKit）先不做，只预埋字段
- ⏸ 叫声判断、衣橱/OOTD、照片去重 —— 放 Backlog

---

## 3. 技术架构决策

| 维度 | 决策 | 理由 |
|---|---|---|
| 平台 | 原生 SwiftUI，仅 iOS | 吃满 RealityKit / QuickLook / SF 字体等苹果独有能力 |
| 部署目标 | iOS 18.0+ | 首页「会走路的平平」用了 `RealityView`（iOS 18 API） |
| 持久化 | SwiftData + MVVM | 官方方案，为 CloudKit 迁移留后路 |
| 工程生成 | XcodeGen（`project.yml`） | 不手写 `.xcodeproj` 二进制，避免冲突 |
| 3D 建模 | Tripo3D API | 你已有的、效果好的现成服务 |
| 3D 展示 | 转 USDZ → QuickLook / RealityKit | 苹果原生只认 USDZ，不认 GLB/GLTF |
| 密钥管理 | `Config/Secrets.xcconfig`（gitignore） | 不进仓库；客户端直连风险已知（见 §8） |
| 代码托管 | GitHub `chaikeji/pingping-dog`（private） | — |
| 无 Mac 方案 | 云 Mac / ToDesk 连 M4 编译 | 详见 §9 |

### 3.1 目录结构
```
PingpingApp/
├── App/            PingpingApp.swift（入口）
├── Models/         SwiftData @Model 数据模型
├── Services/       网络/定位/算法等无 UI 逻辑
├── ViewModels/     MVVM 状态层
└── Views/          按模块分子目录
    ├── Profile/    平平首页 + 档案
    ├── Friends/    狗朋友
    ├── Walk/       遛狗轨迹
    └── RootTabView 底部导航
Config/             Secrets.xcconfig（本地，不提交）
docs/               本 PRD
```

---

## 4. 数据模型（架构基石）

> 所有表都预埋 `ownerID: String?` —— 现在留空，将来接 CloudKit 共享数据库时用来区分「谁的记录」，不用改表结构就能升级到双人共管。

### 4.1 DogProfile（平平本人，全局唯一）
| 字段 | 类型 | 说明 |
|---|---|---|
| id | UUID | |
| name | String | 默认「平平」 |
| breed | String | 品种（雪纳瑞） |
| birthday | Date? | 2015-10-26 |
| avatarData | Data? | 头像原图，也是生成 3D 模型的输入 |
| model3DLocalURL | URL? | 「会走路的平平」USDZ 本地缓存路径 |
| model3DRemoteJobID | String? | Tripo 任务 ID |
| modelStatus | ModelBuildStatus | notStarted/queued/processing/ready/failed |
| modelErrorMessage | String? | 失败时的人话文案 |
| ownerID | String? | 预埋同步字段 |

### 4.2 DogFriend（其他狗朋友，多条）
结构同 DogProfile 的 3D 部分，另加 `ownerName`（主人称呼）、`createdAt`。每条狗朋友独立走一遍拍照 → Tripo 建模流程。

### 4.3 遛狗轨迹三件套
- **RoutePoint**（值类型，Codable）：`latitude / longitude / timestamp`，序列化成 Data 存
- **WalkRoute**：一次遛狗记录。`startDate / endDate / pointsData / distanceMeters / isKnownRoute / matchedKnownRouteID`
- **KnownRoute**：常走路线库。`name / referencePointsData / matchCount / confirmed`

### 4.4 待建模型（Phase 2+，本期只列不实现）
- **CareTask / DailyLog**：完美的一天的任务定义 + 每日打卡记录 + 当日得分
- **Badge / Achievement**：勋章库 + 解锁记录（打卡规则、连续天数触发）

---

## 5. 功能模块详述

### 5.1 平平首页 `[P0]`
**用户故事**：打开 App 第一眼看到「活着的平平」，能感知它今天的状态、快速发起遛狗。

- 中间是平平的形象（当前用抠图占位，将来是可拖动 360° 查看的 3D 模型，**不自动播放动画**）
- 顶部液态玻璃「活动提醒」卡片：动态提示（如「48 小时没遛狗了」「该剪指甲了」）—— 规则待定义
- 狗下方：年龄 + 陪伴天数（「10岁 · XX天」，按生日实时算），左上角平平专属徽章 logo
- 整体灰色背景（拍照棚灰），从上到下一整块无接缝
- **彩蛋**：双击形象弹出全屏磨砂遮罩 + 平平特效。两个候选版本：①水晶版（透明立绘）②星尘粒子云版（灰色粒子从四面八方螺旋汇聚成雪纳瑞轮廓，含脉冲光晕）
- 「会走路的平平」：档案里用头像**生成一次** USDZ（rig+retarget 原地走），之后读本地缓存循环播放，不重复调 API

### 5.2 狗朋友 `[P0]`
**用户故事**：遇到别的狗，拍张照就能收藏成一个可旋转的 3D 小模型。

- 新增流程：拍照/选图 → 填名字/品种/主人 → 后台自动跑 Tripo 全链路
- Tripo 链路：上传换 token → image-to-model → 轮询 → 转 USDZ → 下载缓存（每段轮询 3s、最多 3min）
- 详情页 `.quickLookPreview` 弹原生 3D 查看
- **不满意可换照片重新生成**（Tripo 无「微调」API，重生成是唯一路径），成功/失败都有重生成入口
- 列表项状态角标：生成中转圈 / 成功立方体 / 失败三角

### 5.3 遛狗轨迹 `[P0]`
**用户故事**：像 Keep 一样记录每次遛狗路线，App 能认出「这是常走的老路线」。

- CoreLocation 实时记录 GPS → MapKit 画轨迹 → 距离/时长/配速
- **后台持续记录**（需「始终允许」定位 + 后台模式），锁屏/切后台不断轨
- **路线识别算法**（`RouteMatchingService`）：
  - 走廊重合比例法：采样点落在已知路线 30m 走廊内的占比
  - 重合度 ≥ **90%** 且命中 **3 次** → 判定为常走路线，收进 `KnownRoute`
  - MVP 用简单算法，数据量大后可换 Fréchet/DTW
- 统计页（参考跑步 App）：去掉头像，总里程/总时长用液态玻璃圆框；下方月度卡片（当月里程、遛狗次数）
- **月度回顾详情页**：点月度卡片弹出，三列主指标（总里程/平均配速/总消耗）+ 四列次指标 + 月历高亮 + 数字滚动动画

### 5.4 完美的一天 `[P1]`
**用户故事**：每天完成照顾平平的任务，攒满「完美值」，有即时正反馈。

- 顶部液态玻璃总结栏：当日得分 / 今日满分 100
- 任务清单（示例）：遛狗30分(+30)、喂饭(+20)、陪玩15分(+20)、梳毛(+15)、换水(+15)
- **打卡动效**：点任务 → 对应 emoji 粒子（🍚🚶🎾…）从按钮沿弧线飞向分数栏 → **全部到达后**分数才滚动增加 + 弹跳 + 「+N」提示；取消则扣分
- 数据落地为 CareTask/DailyLog（见 §4.4，待建）

### 5.5 Backlog（Phase 2+）
| 模块 | 说明 | 优先级 |
|---|---|---|
| 勋章/成就系统 | 遛狗连续打卡、里程里程碑等触发解锁；首页已有徽章条 UI 占位 | P1 |
| 叫声判断 | 录 ~10 条平平叫声样本，本地音频 embedding 最近邻匹配 → 含义标签（非训练模型） | P2 |
| 衣橱 / OOTD | 衣物录入 + 每日穿搭 + 日历 | P3 |
| 照片去重 | Vision 相似度比对 | P3 |

---

## 6. 设计系统（Design Tokens）

> 真实 SwiftUI 里字体默认就是系统字体（SF / PingFang），无需自定义。字重最重到 **700**（不用 800/Black，太重不像原生）。

| Token | 值 | 用途 |
|---|---|---|
| lime | #cdec2e | 品牌主色 / 强调 |
| ink | #14150c | 主文字 / 深色底 |
| coral | #ff6b45 | 次强调 / 扣分 |
| amber | #f4b740 | 徽章渐变 |
| ink-sub | #6b6d5e | 辅助文字 |
| green-ok | #3f9d54 | 加分 / 成功 |
| stage-gray | #d9d9d3（浅）/ #2a2b26（深） | 首页背景 |

- **液态玻璃**：`backdrop-filter: blur + saturate` + 内高光 + 柔和投影（HTML 预览近似；真机用 SwiftUI `.glassEffect()`，效果远好于网页）
- 主题：浅色/深色双套，token 级切换
- **注意**：HTML 里叠两层渐变会在交界处产生「接缝线」，用单层平滑渐变解决 —— 真机同理，避免多层半透明蒙层叠加

---

## 7. 外部依赖：Tripo3D API

Base URL：`https://openapi.tripo3d.ai/v3` ｜ 认证：`Authorization: Bearer {key}` ｜ 统一响应 `{code, data}`，code≠0 为错误（含 message/suggestion，如 2010 余额不足）

| 用途 | 端点 |
|---|---|
| 上传图片换 file_token | `POST /files`（multipart，仅 JPEG/PNG，≤20MB） |
| 图生模型 | `POST /generation/image-to-model` |
| 查任务 | `GET /tasks/{id}`（queued/running/success/failed/cancelled） |
| 转格式 | `POST /models/convert`（format 支持 USDZ ✅） |
| 绑骨检查/绑骨/动画 | `animations/rig-check` → `rig`（四足用 v2.5 模型）→ `retarget` |

> **四足动作库限制**：90+ 预设动画只对双足人形开放，四足（狗）目前仅 `preset:quadruped:walk` 一个，配 `animate_in_place` 做「原地走」。

---

## 8. 已知风险 / 待决策

1. **API Key 安全**：客户端直连，key 可被反编译提取。双人私用风险可控；扩大使用范围前需加后端代理（Tripo 官方也建议）。
2. **首页 3D 待机**：四足只有走路一个动作，不是理想的「呼吸/摇尾」。
3. **路线算法精度**：简单走廊法对掉头/绕路可能误判，后续或换 Fréchet。
4. **联机时机**：预埋字段能降低迁移成本但不能消除；真要双人共管仍需一次 CloudKit 权限/冲突设计。
5. **活动提醒规则**：首页玻璃卡片的触发逻辑（多久没遛狗 / 剪指甲周期等）尚未定义。

---

## 9. 开发与部署流程（无 Mac）

1. 代码托管 GitHub（private）
2. 云 Mac / ToDesk 连 M4 → `brew install xcodegen` → `xcodegen generate` → Xcode 编译
3. 首次 clone 后需手动建 `Config/Secrets.xcconfig`（从 `.example` 复制填 key）
4. **免费测试阶段**：GitHub Actions macOS runner 编译 + 免费 Apple ID 签名 → Sideloadly 装机（签名 7 天过期，每周重装）
5. **定稿后**：$99 Apple Developer Program → Xcode Cloud 自动构建 → TestFlight 内部测试，iPhone 直接装，全程不碰 Mac

---

## 10. 迭代路线图

| 阶段 | 内容 | 状态 |
|---|---|---|
| Phase 0 | 工程骨架、数据模型、三模块 MVP、Tripo 全链路 | ✅ 已完成 |
| Phase 1 | 首页视觉/3D/彩蛋、遛狗统计页、月度回顾、完美的一天 | 🔄 进行中（视觉打磨） |
| Phase 2 | 真机跑通、勋章系统、完美的一天数据落地、后台定位实测 | ⏳ 待办 |
| Phase 3 | CloudKit 双人共管、叫声判断 | 📋 规划 |
| Phase 4 | 衣橱/OOTD、照片去重 | 📋 Backlog |
