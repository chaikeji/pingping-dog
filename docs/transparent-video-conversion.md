# 透明宠物视频云端压缩

这套流程使用 GitHub 的 macOS 运行器，把体积很大的透明 MOV 母版转换为 iPhone 可直接播放的 HEVC with Alpha。输入视频只作为临时 Release 附件存在，不进入 Git 历史。

## 1. 上传临时母版

在 GitHub 仓库页面打开 **Releases → Draft a new release**：

1. 新建 tag，例如 `alpha-source-20260819`。
2. 标题填写“临时透明视频母版”。
3. 上传从抠图工具下载的透明 MOV。
4. 勾选 **Set as a pre-release**。
5. 发布这个临时 Release。

GitHub 单个 Release 附件允许大于 Git 仓库的 100 MB 文件限制，因此不要把母版拖进代码目录或提交到 Git。

## 2. 运行转换

打开 **Actions → Convert transparent video for iPhone → Run workflow**，填写：

- `release_tag`：刚才创建的 tag，例如 `alpha-source-20260819`。
- `asset_name`：附件的完整文件名，用于核对。即使GitHub调整了中文文件名，只要临时Release中只有一个MOV，工作流也会自动找到它。
- `output_name`：建议使用用途明确的英文文件名，例如 `zhangsan-idle-alpha.mov`。
- `target_edge`：首页宠物默认选择 `768`。

任务完成后，在运行详情页面底部下载 `transparent-video-hevc-alpha`。

工作流会自动验证：

- 输入视频确实包含 Alpha 通道；
- macOS 支持苹果的透明 HEVC 预设；
- 输出仍然包含 Alpha 通道；
- 输出尺寸和文件大小正常。

任何一项失败，任务都会停止，不会把没有透明度的错误视频当成成品。

## 3. 清理临时文件

确认下载并备份转换后的文件后，删除临时 Release。Actions 生成的下载产物只保留 7 天。

透明 MOV 母版建议在本地单独归档；App 只使用转换后的 HEVC with Alpha 文件。
