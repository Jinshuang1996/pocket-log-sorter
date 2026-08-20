# 开发、构建与发布

## 开发环境

- macOS 13+
- Xcode Command Line Tools
- Swift、SwiftUI、AppKit、AVFoundation、UniformTypeIdentifiers
- `iconutil`、`sips`、`codesign`、`hdiutil`（均由 macOS 提供）

安装命令行工具：

```bash
xcode-select --install
```

## 仓库结构

```text
.
├── PocketColorSorter.swift
├── DjiMetadataReader.swift
├── DjiMetadataReaderTests.swift
├── Info.plist
├── assets/
│   └── AppIcon-master.png
├── docs/
│   ├── CODE_GUIDE.md
│   ├── DEVELOPMENT.md
│   └── USAGE.md
├── build.sh
├── build_dmg.sh
├── test.sh
├── 安装说明.txt
├── THIRD_PARTY_NOTICES.txt
├── CHANGELOG.md
├── LICENSE
└── README.md
```

## 运行测试

```bash
chmod +x test.sh build.sh build_dmg.sh
zsh ./test.sh
```

`test.sh` 将测试程序编译到系统临时目录，退出时自动删除，不污染仓库。

## 构建应用

```bash
zsh ./build.sh
```

构建过程：

1. 分别以 `arm64-apple-macos13.0` 与 `x86_64-apple-macos13.0` 编译。
2. 用 `lipo` 合并为 Universal Binary。
3. 从 1024px 主图生成 16–1024px 的 iconset。
4. 用 `iconutil` 生成 `AppIcon.icns`。
5. 复制 Info.plist 和第三方声明。
6. 使用 ad-hoc 签名，验证 bundle 完整性。
7. 输出到 `dist/Pocket色彩分拣器.app`。

可临时覆盖输出目录：

```bash
POCKET_SORTER_OUTPUT_DIR=/absolute/output/path zsh ./build.sh
```

## 构建 DMG

```bash
zsh ./build_dmg.sh
```

脚本会重新构建应用，然后创建：

```text
dist/Pocket色彩分拣器-通用版.dmg
```

DMG 包含应用、“应用程序”符号链接和中文安装说明。

## 手动验证

```bash
zsh ./test.sh
codesign --verify --deep --strict --verbose=2 "dist/Pocket色彩分拣器.app"
file "dist/Pocket色彩分拣器.app/Contents/MacOS/PocketColorSorter"
hdiutil verify "dist/Pocket色彩分拣器-通用版.dmg"
```

`file` 应同时列出 `x86_64` 和 `arm64`。

## 正式签名与公证

仓库脚本默认使用 ad-hoc 签名，适合本地构建和开源开发。面向公众提供无 Gatekeeper 警告的下载，需要：

1. Apple Developer Program 的 Developer ID Application 证书。
2. 使用 `codesign --sign "Developer ID Application: ..." --options runtime` 签名。
3. 用 `notarytool submit` 上传 DMG 并等待通过。
4. 用 `stapler staple` 将公证票据附加到 DMG。

不要把证书、Apple ID、app-specific password 或 notary profile 提交到仓库。CI 应使用加密 Secrets。

## 发布检查清单

1. 更新 `CFBundleShortVersionString` 与 `CFBundleVersion`。
2. 更新 `CHANGELOG.md`。
3. 运行 `zsh ./test.sh`。
4. 构建并验证 `.app` 与 DMG。
5. 在真实 Apple Silicon Mac 上测试文件选择、拖拽、复制和移动。
6. 如果声称支持 Intel，至少在 Intel runner 或真机启动验证。
7. 创建 Git tag 和 GitHub Release，上传经过公证的 DMG及 SHA-256。
