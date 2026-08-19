# 透明宠物动画云端压缩

这套流程把体积很大的透明 MOV 母版转换成透明动画 WebP。旧的 HEVC with Alpha 方案已经移除，因为 GitHub 托管的 macOS 运行器没有提供该编码器，继续重试也不会成功。

## 操作步骤

1. 在仓库的 **Releases** 中创建临时 Release，并上传唯一一个透明 MOV。
2. 打开 **Actions → Convert transparent animation for iPhone → Run workflow**。
3. 填写：
   - `release_tag`：例如 `alpha-source-20260819`
   - `output_name`：例如 `zhangsan-idle-alpha.webp`
   - `target_edge`：先选 `512`
   - `target_fps`：先选 `10`
4. 成功后，在运行详情底部下载 `transparent-animation-webp`。

流程会检查输出同时具有动画和透明通道，并拒绝空文件或超过 20 MB 的异常结果。

## 推荐参数

`512 × 512 / 10 fps / quality 80` 已使用当前 200 MB、1440 × 1440、约 5 秒的透明母版实际转换成功，结果约 1.47 MB。需要更清晰时再尝试 `768` 或更高帧率。

确认下载并备份成品后，可以删除临时 Release。Actions 产物只保留 7 天。
