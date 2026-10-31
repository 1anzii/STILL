# 发布 STILL 更新

项目仓库为 [1anzii/STILL](https://github.com/1anzii/STILL)。首次发布已完成；后续版本沿用现有仓库及提交历史。以下以 **1.10.0** 为例。

## 准备源码与安装包

先同步版本、文档并冻结代码，从同一份代码构建、验证和打包。构建及测试说明见 [开发文档](docs/DEVELOPMENT.md)。如实记录测试范围和失败项，不把编译或单项测试通过写成全部通过。

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/test-dial.sh
./scripts/test-switch.sh
./scripts/package.sh
./scripts/export-source.sh
```

导出会生成 `dist/open-source-1.10.0/STILL/` 和 `dist/STILL-1.10.0-source.zip`。它只复制白名单内的源码、测试、脚本、许可及资源，包括开发文档和 README 介绍图；不包含个人日志、运行截图、缓存或旧安装包。发布前检查文件列表及 README 图片的相对链接。

导出脚本不会覆盖已有文件。发布前需要重新导出同版本时，先将旧源码目录和源码 ZIP 移至独立备份目录，再运行脚本；已发布版本的更新应使用新版本号。

安装包与源码包都完成后，在 `dist/` 内生成并核验统一校验清单：

```sh
shasum -a 256 STILL-1.10.0-universal.zip STILL-1.10.0-universal.dmg STILL-1.10.0-source.zip > STILL-1.10.0-universal-SHA256.txt
shasum -a 256 -c STILL-1.10.0-universal-SHA256.txt
```

## 更新仓库并发布 Release

1. 将干净导出目录中的文件同步到现有仓库工作副本，保留 `.git` 与既有历史。审查差异，确认源码、介绍图、开发文档和许可齐全；不要直接提交开发目录或整个 `dist/`。
2. 提交并推送本次更新。新建标签 `v1.10.0`，指向包含对应源码的提交。
3. 创建标题为 `STILL 1.10.0` 的 Release，上传四个文件：
   - `STILL-1.10.0-universal.dmg`
   - `STILL-1.10.0-universal.zip`
   - `STILL-1.10.0-source.zip`
   - `STILL-1.10.0-universal-SHA256.txt`
4. 发布说明写清变更、macOS 13+、Apple Silicon / Intel、安装与升级方式、实际测试范围，以及 **ad-hoc 本地签名、未经过 Apple 公证**。确认标签、附件和校验值后发布。
5. 从 Release 下载附件并复核 SHA256，确认仓库 README 的介绍图和文档链接能打开。

当前版本的变更说明应包括合盖调暗内置屏幕：默认开启，开盖恢复原亮度；兼容性受 macOS 和机型影响，降低背光不等于温控保证。电源服务仍为 1.1.1，已有该服务的用户无需重新授权。

## 许可与后续维护

每个安装包都应同时提供可构建该版本的对应源码和脚本。保留 GPL-3.0-only 版权、许可及第三方声明，Michroma 字体继续使用 SIL OFL 1.1。完整条款见 [LICENSE](LICENSE) 和 [第三方声明](THIRD_PARTY_NOTICES.md)。

GitHub 发布不等于 Apple 公证。签名、公证及技术细节见 [开发文档](docs/DEVELOPMENT.md)。证书、私钥、密码、令牌和个人运行日志不得提交。后续修复应更新版本与文档，再重复上述流程。
