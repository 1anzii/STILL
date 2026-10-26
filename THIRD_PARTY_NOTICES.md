# 版权、许可与资源来源

## STILL

Copyright (C) 2026 1anzii

除下列另有声明的第三方资源外，STILL 的源代码、构建脚本、文档及项目自有资源按 **GNU General Public License version 3 only（GPL-3.0-only）** 提供。完整条款见 [LICENSE](LICENSE)。

STILL is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3 of the License.

STILL is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with STILL. If not, see <https://www.gnu.org/licenses/>.

## Michroma 字体

- 文件：`Resources/Fonts/Michroma-Regular.ttf`
- Copyright 2011 The Michroma Project Authors (https://github.com/googlefonts/michroma)
- 许可：**SIL Open Font License 1.1**，保持其独立许可，不改为 GPL。
- 完整许可：[Resources/Fonts/OFL.txt](Resources/Fonts/OFL.txt)
- 下载来源与 SHA-256：[Resources/Fonts/SOURCE.txt](Resources/Fonts/SOURCE.txt)

应用保留未经修改的字体文件及其版权、许可。字标和图标使用字体渲染，不修改 TTF；OFL 不要求把使用字体生成的图片或整个应用也按 OFL 发布。

## 金属纹理与图标

`Resources/Textures/WornYellowMetal-v1.png` 是为本项目生成的材质纹理。生成方式与提示词见 [来源记录](Resources/Textures/SOURCE.md)。项目将其在可许可权利范围内按 GPL-3.0-only 提供；此声明不主张对 AI 生成内容享有排他权。

图标由 `scripts/generate-icon.swift` 绘制，结合上述纹理与 Michroma 字体字形。绘图脚本和项目自有图形部分采用项目许可；字体文件仍保留 OFL。

应用依赖系统提供的 Apple 框架；这些框架不随本项目分发，也不受本项目 GPL 许可约束。
