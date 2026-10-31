# 开发与技术说明

STILL 1.10.0（build 24）· 电源服务 1.1.1

[返回项目首页](../README.md) · [使用指南](../Resources/安装说明.txt)

## 本版验证范围

- macOS 13+ 的 arm64 与 x86_64 构建和严格签名验证通过。
- 在 Apple 芯片、macOS 26.4.1 上实测：合盖后亮度从约 93.75% 降至 1.5625%，开盖恢复原值；闭盖期间持续运行，系统报告显示器未进入睡眠。Intel 与其他系统版本仍需实机验证。
- 客户端 17 项、亮度恢复 81 项、后台 72 项检查分别通过。亮度检查使用模拟显示器，不操作真实硬件。
- 本机整套构建加测试流程曾在启动亮度测试时被 SIGKILL 中断；单独执行同一产物通过。原因未定位，未将其记为完整流水线通过。

## 工作原理与边界

STILL 通过管理员授权的后台服务，在有限会话期间设置 `pmset -a disablesleep`。这是系统级休眠设置，会同时影响合盖、闲置及主动休眠。SLEEP 恢复 macOS 的正常规则，不是立即让电脑睡着；外屏、外设或其他应用仍可能保持唤醒。

该参数见 [Apple 电源管理实现](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m)，未列入当前 `pmset` 手册，系统升级后应重新验证。普通 `caffeinate` 防闲置休眠断言不能可靠替代合盖控制。

后台独立处理会话到期、应用退出、心跳失联、仅接电模式下拔电、无法读取电池状态及系统报告严重温度异常时的恢复。状态在更改前持久化，恢复后读回核对；不会接管其他工具已经禁用休眠的状态。请避免同时使用多个防休眠工具。

内屏亮度控制使用 macOS 的 DisplayServices 私有接口，兼容性因系统版本和机型而异；系统升级后应重新验证。调暗仅降低背光，不保证温度下降，也不能替代通风或温度保护。

这些保护依赖 macOS、硬件和系统策略，不保证所有机型都能合盖运行，也不能阻止没电、关机或硬件保护。应用无需联网，不含遥测或自动更新。

## 从源码构建

需要 macOS、Xcode Command Line Tools 和 macOS 13+ SDK。使用系统框架，无需第三方包管理器或 Xcode 工程。

```sh
xcode-select --install  # 已安装时跳过
./scripts/build.sh
./scripts/test.sh
./scripts/test-dial.sh
./scripts/test-switch.sh
./scripts/package.sh
```

默认输出双架构 App、DMG、ZIP 与 SHA-256 校验文件至 `dist/`。图标在构建时自动生成；应用与后台服务均执行严格签名验证。

```sh
ARCHS=arm64 ./scripts/build.sh                     # 仅构建 Apple Silicon
APP_VERSION=1.10.1 APP_BUILD=25 ./scripts/build.sh  # 自定义版本
./scripts/export-source.sh                       # 导出干净源码与源码 ZIP
```

测试覆盖客户端编码与解析、后台会话及文件安全逻辑、模拟内屏调暗与恢复、旋钮拖动几何、拨杆状态和文案。自动化测试不安装服务、不修改真实亮度或系统休眠设置，也不能代替真实硬件验证。

### 在目标 Mac 上验证

在通风的桌面环境保存工作、关闭其他防休眠工具，依次检查：

1. 开启短会话，确认绿色状态和 `pmset -g` 中的 `SleepDisabled 1`。
2. 合盖约一分钟后打开，核对一个持续记录时间的本机任务是否在期间继续运行。
3. 关闭会话，确认 `SleepDisabled 0`，再次合盖确认正常休眠与唤醒。外屏可能触发系统自身的合盖运行模式。
4. 检查到期、退出应用和仅接电模式下拔电的恢复行为。
5. 在非零亮度下核对合盖调暗与开盖恢复，并检查关闭选项、手动改亮度及外接屏幕不受影响。合盖时内屏可能暂时不可用，此时应显示提示并保留待恢复记录。

公开发行前应在目标系统与芯片上实测，并如实记录范围；双架构编译通过不等于所有 Mac 已验证。

## 卸载与应急恢复

先拨回 SLEEP 并确认恢复，再关闭「登录时启动」。在「使用说明与关于 → 故障恢复与卸载」卸载电源服务，最后退出并删除 App。服务由本机已授权用户共用。

需要手动恢复时，在终端执行：

```sh
sudo pmset -a disablesleep 0
pmset -g
```

确认 `SleepDisabled` 为 `0`。此命令也会影响其他防休眠工具的设置；仍异常时请保持通风，重启后检查或联系 IT。

## Developer ID 签名与公证

GitHub 开源不等于 Apple 公证。正式发行可使用自己的 Developer ID Application 证书：

```sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./scripts/build.sh
xcrun notarytool store-credentials LidKeeper-notary
NOTARY_PROFILE=LidKeeper-notary ./scripts/notarize.sh
```

请通过 Apple 的交互提示将凭据存入钥匙串，不写入仓库或命令历史。公证脚本会上传 App 到 Apple，只有返回 `Accepted` 才附加票据并重新打包。需要 Apple Developer Program 资格及有效证书。[Apple 公证流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

## 项目结构

```text
Sources/LidKeeper/     菜单栏界面、设置、状态与心跳
Sources/PowerHelper/   管理员服务、会话与电源控制
Resources/            图标、字体、纹理、安装说明
scripts/              构建、测试、打包、公证与源码导出
Tests/                可复现的自动化检查
```

发布流程见 [PUBLISHING.md](../PUBLISHING.md)。为兼容已有安装，内部标识继续使用 `com.yeonza.LidKeeper`；界面与分发名称为 STILL。

## 许可与免责声明

Copyright (C) 2026 1anzii

项目原创部分按 **GPL-3.0-only** 开源，允许依许可使用、修改与分发。分发受 GPL 覆盖的修改版本时，应保留版权和许可、注明修改，并按 GPL 提供对应源码。完整条款见 [LICENSE](../LICENSE)；字体采用独立的 SIL OFL 1.1，详见 [第三方声明](../THIRD_PARTY_NOTICES.md)。

STILL 按现状提供，不作担保，不保证无故障或适合特定用途。请自行评估使用风险；在适用法律允许的范围内，保证与责任限制以 GPL 第 15–17 条为准。
