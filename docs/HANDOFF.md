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

**要做的:**
1. `project.yml` 加 SPM 依赖 `https://github.com/mapbox/mapbox-maps-ios`(v11)
2. `project.yml` 的 Info.plist 里加 `MBXAccessToken: $(MAPBOX_PUBLIC_TOKEN)`
3. `ipa.yml` 在拉包前写 `~/.netrc`(Mapbox SDK 不是公开下载的,SPM 解析时要这个):
   ```
   machine api.mapbox.com
   login mapbox
   password $MAPBOX_DOWNLOAD_TOKEN
   ```
   同时 `Create Secrets.xcconfig` 那步要把 `MAPBOX_PUBLIC_TOKEN` 也写进去
4. `WalkTrackingView` 的 MapKit `Map` 换成 Mapbox 的,轨迹线用 `Panora.lime`,狗头 pin 迁过去
5. `WalkHistoryView` 顶部那张地图同样换掉

**先用 Mapbox 自带的 `dark-v11` 样式起手。** 跑通之后再考虑要不要去 Mapbox Studio 调一个纯 Panora 配色的底图 —— 那只是改一行 style URI。

**风险要说在前面:** 这是大改动,Windows 上编译不了,Mapbox v11 的 SwiftUI API 只能凭记忆写。**头一两次 build 大概率红**,每轮 15 分钟,做好来回三四轮的准备。

## 待办 / 悬而未决

- [ ] **`sk.` 下载 token 要 revoke 重建。** 它在聊天记录里贴过,算泄露了。等 Mapbox CI 跑通、确认能编译,就去 mapbox.com 撤销旧的、建新的,再更新 GitHub Secret。`pk.` 那个不用管,本来就是公开的
- [ ] 遛狗 tab 顶部地图:全新用户看不到狗头(见上)。如果希望一进来就有,得接受多弹一次权限
- [ ] 月卡页底部的悬浮玻璃 Tab(原型里有)没做 —— 要改全局 `RootTabView`,留给后面的 Batch
- [ ] 其它 tab(首页/狗朋友/完美的一天)还是浅色 `AppTheme`,等 Batch 2/3 逐块迁

## 别碰

- `AppTheme`(浅色主题)—— 还有三个 tab 在用
- 狗朋友 tab —— 明确说过不改
- 「完美的一天」的圆环刻度 —— 270° 弧 + 底部 90° 缺口是定过的,`TickRing` 里那些啰嗦的显式类型标注是为了绕开 Swift 类型检查器超时,**别合并简化**
