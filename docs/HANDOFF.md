# 交接 / TODO

> 更新于 2026-07-21。新开对话时先读这份。

## 环境约束

- 开发机是 Windows,**没有 Mac**。本地编译不了,验证靠推 GitHub → Actions 手动跑 `ipa.yml` → 下 IPA → Sideloadly 侧载。**一轮约 15 分钟**,所以推之前尽量把能想到的编译错误都想清楚。
- `gh` CLI 没装,也没有 GITHUB_TOKEN → **Actions 只能手动在网页上点 Run workflow**,我这边触发不了。
- Tripo API 调用花真钱(一只狗 35 额度),不许静默触发。
- 有取舍的地方给推荐 + 备选,然后停下来等答复。没答复不等于同意。

## 已完成(截至 `fe49cbd`,IPA 已验证无问题)

遛狗模块的 Panora 深色玻璃风改造(Batch 1)已经全部落地并真机验过:

- `PanoraTheme.swift` — 深色 token,**只在遛狗模块用**,其它 tab 还是浅色的 `AppTheme`,后面分批迁
- `WalkHistoryView` — 遛狗 tab,顶部地图 + 玻璃总览条 + 荧光绿「开遛!」,下面里程卡/月度回顾卡左右并排等高
- `WalkTrackingView` — 全屏深色地图,顶/底黑色渐变,超大 km 数,暂停横杠→红方块+绿三角,自定义居中的「距离过短」弹窗
- `WalkSummaryView` / `MonthlyDetailView` — 深色化
- `MonthlyReviewGalleryView` — 新增的遛狗回顾月卡页,入口是点里程柱状卡
- 雪纳瑞头像替掉 emoji:`dog_pin`(地图定位标,`anchor: .bottom` 钉在尖尖上)、`dog_head`(「完美的一天」圆环里)。遛狗总结页的 🐕 是「别人的狗」的计数,**故意没动**
- 遛狗 tab 的狗头走 `requestOneShotIfAuthorized()` —— 已授权才取位置,**不为展示 tab 主动弹权限**。代价:全新用户第一次进这个 tab 看不到狗,要等他点开遛授权后才有

## 下一步:接入 Mapbox

**已就绪:**
- `MAPBOX_PUBLIC_TOKEN`(`pk.` 开头)已写进 `Config/Secrets.xcconfig`(gitignore 里,不进仓库)
- `MAPBOX_DOWNLOAD_TOKEN`(`sk.` 开头)已加进 GitHub 仓库 Secrets

**已定下的三个取舍:**
- **分两轮推。** 第一轮只动管道、视图一行不改 —— 最可能红的地方是「SPM 能不能在 CI 上解析 Mapbox 的私有二进制包」,把它单独验掉,红了错误来源唯一。
- **用 `UIViewRepresentable` 包 `MapView`,不用 Mapbox 自带的 SwiftUI `Map`。** 命令式 API(`PolylineAnnotationManager` / `PointAnnotationManager` / `setCamera`)从 v10 到 v11 基本没变,凭记忆写把握大;SwiftUI 那套的 `Viewport` / `ViewAnnotation` 在 11.x 各小版本之间改过。牺牲代码量换编译确定性。
- **三张地图全迁**,包括 `WalkSummaryView` 那张静态轨迹卡(原交接文档漏了它,只写了两处)。留一张在 MapKit 会导致底图配色不一致,而且两个 `Map` 重名要处处写全限定名。

**第一轮(管道)—— 已落地:**
1. ✅ `project.yml` 加 `packages:` → `mapbox-maps-ios` `from: 11.0.0`,target 加 `dependencies`
2. ✅ `project.yml` 的 Info.plist 加 `MBXAccessToken: $(MAPBOX_PUBLIC_TOKEN)`
3. ✅ `ipa.yml` **和 `build.yml`** 都加了 `Write ~/.netrc for Mapbox SPM` 步骤(`chmod 600`,缺 secret 直接报错退出);两个 workflow 的 `Secrets.xcconfig` 步骤也都追加了 `MAPBOX_PUBLIC_TOKEN`
   - `build.yml` 必须一起改:它 `on: push` 到 master 就跑,不加 netrc 的话每次 push 都红
4. ✅ `MapboxLinkProbe.swift` —— 一行 `typealias`,只为逼编译器 import + 链接。**第二轮删掉**

**第一轮验证要看的:** SPM 解析(会拉几百 MB,首轮慢)、链接过不过。视图没动,别的不该变。

**第一轮结果:绿了。** SPM 能解析 Mapbox 私有包、能链接、能 import。

**第二轮(视图)—— 已落地,待真机验:**
5. ✅ 新增 `PanoraMapView`(`UIViewRepresentable` 包 `MapView`)—— 三张地图共用一个组件。参数:`route` / `pin` / `center` / `zoom` / `recenterToken` / `interactive` / `fitsRoute` / `pinWidth`
6. ✅ 新增 `CoordinateTransform` —— GCJ-02 → WGS-84。**这才是那个「差 300m」的真凶**:国内 `CLLocation` 给的是 GCJ-02,Mapbox 瓦片是 WGS-84。MapKit 看着对是因为苹果中国底图也是 GCJ-02,两边偏一样多抵消了。上一轮加的精度闸门只挡粗定位,挡不掉这个
7. ✅ 三张地图全迁:`WalkTrackingView` 全屏、`WalkHistoryView` 顶部、`WalkSummaryView` 静态卡
8. ✅ 删掉 `MapboxLinkProbe.swift`;全 app 已无 `import MapKit`

**这一轮的实现取舍(踩坑前先看这里):**
- **不观察 `onStyleLoaded`**,`makeUIView` 里直接建 annotation manager。v11 的事件是 Signal,签名比命令式那套新;少碰一个 API 少一个编译风险。**如果真机上轨迹线/狗头不显示,第一个要试的就是补上样式加载后再建 manager**
- **不用 `mapboxMap.camera(for:...)` 做「装下整条轨迹」**,自己算包围盒 + `log2(360/span)` 出 zoom。那个方法的参数列表在 11.x 里改过
- **狗头先把 UIImage 缩到 `pinWidth` 再交给 Mapbox**,不调 `iconSize`(它是相对原图分辨率的倍数,不好预测)。缩好的图缓存在 Coordinator 里
- `WalkHistoryView` 顶部那张设了 `interactive: false` —— 它是展示性质、上面还压着「开遛!」,关手势免得跟外层 List 抢滚动。想能拖改成 `true` 就行
- Mapbox 的 logo / attribution **按使用条款必须保留**,别去关

**样式还是自带的 `dark-v11`。** 想要纯 Panora 配色,去 Mapbox Studio 调一个,然后改 `PanoraMapView` 里 `MapInitOptions(styleURI:)` 那一行。

## 待办 / 悬而未决

- [x] ~~`MAPBOX_PUBLIC_TOKEN` 加进 GitHub Secrets~~ —— 已加
- [x] ~~临时红点诊断~~ —— **结论:不该做坐标转换。** 真机上「未转换」的红点落在真实位置,「转换后」的狗头偏了。说明 Mapbox 给这台设备的底图跟 GCJ-02 是对齐的,跟全球版 Mapbox 用 WGS-84 的公开说法不一致。`PanoraMapView` 已改成直接用 CLLocation 原值;`CoordinateTransform.swift` **留着但没人调**,换区域/换 endpoint 可能又要用
- [ ] **Mapbox 的 logo / attribution 藏不掉,别再尝试。** 它俩的 `.visibility` 被标了 `@_spi`,编译直接报 `inaccessible due to '@_spi' protection level`(`scaleBar` / `compass` 的同名属性是公开的,唯独这两个不是)。Mapbox 用编译期强制执行署名条款。**唯一合规的缓解是调 `position` / `margins` 挪位置**,还没试过;绕过 SPI 去 hack subview 属于明知故犯,不做
- [ ] **`sk.` 下载 token 要 revoke 重建。** 它在聊天记录里贴过,算泄露了。等 Mapbox CI 跑通、确认能编译,就去 mapbox.com 撤销旧的、建新的,再更新 GitHub Secret。`pk.` 那个不用管,本来就是公开的
- [ ] 遛狗 tab 顶部地图:全新用户看不到狗头(见上)。如果希望一进来就有,得接受多弹一次权限
- [ ] 月卡页底部的悬浮玻璃 Tab(原型里有)没做 —— 要改全局 `RootTabView`,留给后面的 Batch
- [ ] 其它 tab(首页/狗朋友/完美的一天)还是浅色 `AppTheme`,等 Batch 2/3 逐块迁

## 别碰

- `AppTheme`(浅色主题)—— 还有三个 tab 在用
- 狗朋友 tab —— 明确说过不改
- 「完美的一天」的圆环刻度 —— 270° 弧 + 底部 90° 缺口是定过的,`TickRing` 里那些啰嗦的显式类型标注是为了绕开 Swift 类型检查器超时,**别合并简化**
