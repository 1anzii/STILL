# 将 STILL 发布到 GitHub

本地文件已按 GPL-3.0-only 准备。本指南不会自动创建 GitHub 仓库或上传任何文件。

## 1. 使用干净的源码目录

在开发项目中运行：

```sh
./scripts/export-source.sh
```

版本 1.9.4 会生成：

- `dist/open-source-1.9.4/STILL/`：准备提交的源码目录。
- `dist/STILL-1.9.4-source.zip`：同版本对应源码压缩包。

导出只复制白名单内的源码、图标、字体、纹理、脚本、测试与文档，排除截图、个人日志、缓存和旧安装包；已有导出不会被覆盖。发布前仍应人工查看文件列表。不要直接上传开发目录或整个 `dist`。

## 2. 用 GitHub Desktop 发布源码

1. 安装 [GitHub Desktop](https://desktop.github.com/)，登录你要发布的 GitHub 账号，并配置提交显示名与邮箱。需要隐藏私人邮箱时，使用 GitHub 账号提供的 noreply 邮箱。
2. 首次使用导出目录时，在终端进入 `dist/open-source-1.9.4/STILL`，运行 `git init -b main`。若目录已有 `.git`，跳过此步。
3. GitHub Desktop 选择 **File → Add Local Repository**，选中这个 `STILL` 目录。查看 Changes，确认只有要公开的文件。填写提交说明 `Initial open-source release`，点击 **Commit to main**。
4. 点击 **Publish repository**，名称填 `STILL`，描述可填 `A mechanical macOS menu bar app for timed clamshell wake control.`。取消勾选 **Keep this code private**，确认账号后发布。
5. 打开网页仓库，确认 README、LICENSE 与 THIRD_PARTY_NOTICES.md 显示正确。仓库已经包含 GPL-3.0 许可，不要另外生成 MIT 许可。

步骤依据：[添加本地仓库](https://docs.github.com/en/desktop/adding-and-cloning-repositories/adding-a-repository-from-your-local-computer-to-github-desktop) · [发布已有项目](https://docs.github.com/en/desktop/adding-and-cloning-repositories/adding-an-existing-project-to-github-using-github-desktop)。

## 3. 发布可直接安装的 Release

从同一份源码构建并打包：

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/test-dial.sh
./scripts/test-switch.sh
./scripts/package.sh
```

1. 仓库网页选择 **Releases → Draft a new release**。
2. 新建标签 `v1.9.4`，Target 选包含本次源码的提交，标题填 `STILL 1.9.4`。
3. 上传以下四个文件，不要把安装包提交进 Git 源码历史：
   - `STILL-1.9.4-universal.dmg`
   - `STILL-1.9.4-universal.zip`
   - `STILL-1.9.4-universal-SHA256.txt`
   - `STILL-1.9.4-source.zip`
4. 写清系统要求、安装方法和当前签名状态；先存草稿检查附件，确认后点击 **Publish release**。同事从 Release 下载 DMG 即可。

可使用的发布说明：

> STILL 1.9.4 · macOS 13+ · Apple Silicon / Intel。机械旋钮定时控制合盖运行，支持电源限制和会话到期恢复。打开 DMG，将 STILL 拖入“应用程序”。首次开启运行需管理员授权。当前为 ad-hoc 签名、未经过 Apple 公证；确认来源后可按系统提示允许打开。使用前请在自己的 Mac 上短测，运行时保持通风。GPL-3.0-only；本次对应源码附在 Release 中。

如果目标硬件还未充分测试，可勾选 **This is a pre-release** 并注明测试范围。操作依据：[GitHub Release 官方说明](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。

## 后续更新与许可

- 修改代码后同步 `Resources/Info.plist`、`scripts/build.sh` 默认版本和文档；提交、构建、测试、导出对应源码，再发布新标签。每个二进制版本都应有能构建该版本的源码及脚本，并与下载包放在同一 Release 中供获取。
- GPL 允许商用；分发受 GPL 覆盖的修改版时，应保留许可和版权声明、注明修改，并按 GPL 提供对应源码。仅自己使用的修改不因此要求公开。完整条款以 [LICENSE](LICENSE) 为准；字体保持 OFL 许可。
- GitHub 开源不等于 Apple 公证。需要更顺畅的首次安装体验时，使用自己的 Developer ID 签名并公证，见 README。证书、私钥、密码和令牌不能提交到仓库。
- 用户报告问题可使用 GitHub Issues；请仅索取机型、系统版本、现象和必要错误信息，不索取密码或完整个人日志。
