# 代码与架构说明

本文面向希望理解识别原理、审查安全性或扩展新 DJI 机型的开发者。

## 1. 总体流程

```mermaid
flowchart LR
    A["拖拽或文件选择器"] --> B["展开目录并过滤视频/照片"]
    B --> C["读取 DJI djmd 第一包"]
    B --> T["匹配同名 LRF 并生成缩略图"]
    B --> P["按扩展名识别 JPG / RAW"]
    C --> D{"ColorGammaSxS / record_mode"}
    D -->|"22"| E["D-Log 2"]
    D -->|"2"| F["D-Log"]
    D -->|"nil + mode 8"| G["普通 Rec.709"]
    D -->|"未知或无 djmd"| H["AVFoundation 标准元数据回退"]
    H --> I["D-Log M / HLG / HDR / 待确认"]
    E --> J["复制或移动到分类目录"]
    F --> J
    G --> J
    I --> J
    P --> J
    T --> K["播放器与分组缩略图"]
    P --> K
```

应用不会用画面内容猜测视频色彩格式。视频识别依赖相机写入的拍摄元数据；JPG 与 RAW 则按受支持扩展名归类。缩略图只承担预览功能，不参与分类判断。

## 2. 源码文件

| 文件 | 职责 |
|---|---|
| `PocketColorSorter.swift` | SwiftUI 界面、文件选择/拖拽、任务状态、标准色彩元数据回退和文件整理 |
| `DjiMetadataReader.swift` | ISO BMFF box 解析、定位 `djmd` sample、未知 schema protobuf 解析 |
| `DjiMetadataReaderTests.swift` | 用最小合成 MP4 验证 D-Log 2、D-Log、普通模式字段路径 |
| `Info.plist` | Bundle ID、版本、最低系统、应用图标配置 |
| `build.sh` | 生成双架构 Universal Binary、`.icns`、签名后的 `.app` |
| `build_dmg.sh` | 生成带“应用程序”快捷方式和安装说明的压缩 DMG |
| `test.sh` | 编译并运行元数据读取测试 |

Finder 拖入通过 `public.file-url` 的 `NSItemProvider` 显式加载，不依赖 SwiftUI 对 `URL: Transferable` 的推断。`FileDropLoader` 异步汇总多个 provider，转换 `URL`、`NSURL`、二进制 URL data 或字符串路径，随后统一交给 `SorterModel.add(urls:)` 去重和递归展开。根视图与左侧导入区共用 `SorterModel.acceptDrop`，因此整个窗口都能接收文件。素材卡片使用原文件 URL 创建 `NSItemProvider`，支持向 Finder 和外部应用拖出。

## 3. `djmd` 读取器

### 3.1 ISO BMFF box 遍历

`DjiMetadataReader` 只实现定位第一条 DJI 元数据 sample 所需的 MP4/MOV 子集。它从顶层查找 `moov`，随后遍历每个：

```text
moov/trak/mdia/minf/stbl
```

读取的 sample table box：

- `stsd`：判断 sample entry type 是否包含 `djmd`。
- `stsz` / `stz2`：取得第一条 sample 的大小。
- `stsc`：取得第一条 chunk 与每 chunk sample 数。
- `stco` / `co64`：取得第一条 chunk 的文件偏移。

box size 同时支持 32 位 size、64 位 large size 和延伸到父 box 末尾的 size 0。每次读取都会检查边界，避免损坏文件导致越界。

发现顶层 `moof` 时，读取器返回不支持 fragmented MP4 的错误。上层把错误降级为标准元数据回退或“待确认”，不会中断其他文件。

### 3.2 无 schema protobuf 解析

DJI `djmd` sample 使用嵌套 protobuf。项目没有依赖 `.proto` 文件，而是保留字段号、wire type 和值的轻量递归解析器。

支持的 wire type：

- `0`：varint
- `1`：64 位数据
- `2`：length-delimited 嵌套消息
- `5`：32 位数据

最大递归深度为 8。遇到非法 varint、越界长度或未知 group wire type 时保守停止解析。

### 3.3 当前字段路径

```text
ColorGammaSxS: top.field(2)[0].field(2)[0].field(3)[0].field(1)
record_mode:   top.field(2)[0].field(3)[0].field(5)
```

映射：

```swift
ColorGammaSxS == 22  // D-Log 2
ColorGammaSxS == 2   // D-Log
ColorGammaSxS == nil && record_mode == 8 // 普通 Rec.709
```

该字段路径参考 MIT 许可项目 `dlog_color_classifier`；许可文本保留在 `THIRD_PARTY_NOTICES.txt`。

## 4. 标准元数据回退

`Detector.inspect` 优先调用 `DjiMetadataReader`。无法获得已知映射时，使用 AVFoundation 枚举：

- Asset metadata formats、identifier、key space、key、value。
- 视频 track 的 `CMFormatDescription` extensions。

归一化成小写文本后按优先级判断：

1. D-Log 2
2. D-Log M
3. D-Log
4. Rec.2100 HLG / ARIB STD-B67
5. SMPTE ST 2084 / Dolby Vision / PQ
6. BT.2020
7. DJI 明确标记 Rec.709
8. 待确认

仅有 BT.709 时不归入普通模式，这是有意的安全策略。

### 4.1 JPG 与 RAW 分支

`Detector.inspect` 在视频元数据解析前检查扩展名。`jpg/jpeg` 直接映射到 `07_JPG`；常见相机 RAW 扩展名映射到 `08_RAW`。RAW 列表包含 DNG、ARW、CR2/CR3、NEF/NRW、RAF、ORF、RW2、PEF、SRW、X3F 等格式。

照片缩略图使用 ImageIO 的 `CGImageSourceCreateThumbnailAtIndex` 解码，最长边限制为 960 像素并应用 EXIF 方向。ImageIO 无法解码时回退到 `NSImage`；仍然失败只影响预览，不影响扩展名分类和导出。

## 5. LRF 匹配与缩略图

`ThumbnailLoader.companionLRF` 枚举视频所在目录，并按以下规则查找代理文件：

1. 扩展名忽略大小写后为 `lrf`。
2. 去掉扩展名后的文件名与视频完全相同，比较时忽略大小写。

找到 LRF 后，`AVAssetImageGenerator` 在大约 8% 时长、最多第 1 秒处抽取一帧，输出尺寸限制为 720×405。LRF 解码失败时重新对原视频执行同一流程。此过程不改变 `Detector.inspect` 的输入；色彩模式始终从原视频读取。

文件选择器通过应用声明的 `com.pocketlogsorter.dji-lrf` UTI 接受 `.lrf` 扩展名，同时接受 `public.image` 与 `public.camera-raw-image`。目录展开收集视频、照片和 LRF；视频与照片创建 `MediaItem`，LRF 只进入匹配缓存。显式导入的代理保存在 `importedLRFs` 中：优先按“目录 + 主体文件名”匹配；只有一个同名候选时允许跨目录匹配，避免同名 DJI 文件错误关联。照片明确跳过 LRF 匹配。

`VideoPreviewView` 对视频默认创建 LRF 对应的 `AVPlayerItem`，并异步加载 `AVAsset.isPlayable`。代理不可播放或收到播放失败通知时，`playOriginal` 自动切换为 `true`。选择照片时播放器会被清空并切换到静态图片预览。

## 6. 并发与 UI 状态

`SorterModel` 标记为 `@MainActor`，所有 SwiftUI 状态更新都发生在主 actor。每个素材的磁盘、元数据或缩略图读取通过 `Task.detached` 执行，避免大型批次冻结界面。

每个 `MediaItem` 独立保存：

- 源 URL
- 分析状态
- `DetectionResult`
- 缩略图和时长
- 匹配的 LRF URL
- 文件操作错误

`selectedForExport` 使用 `Set<UUID>` 保存多选状态。活动预览素材和导出选择互相独立：点击卡片只改变 `activeID`，点击卡片勾选框才改变导出集合。`sort()` 在处理每个条目前先检查该集合，因此未选择的素材不会发生文件操作。

根视图使用 `GeometryReader` 按实时窗口尺寸计算上半区高度、侧栏宽度和检查器宽度。窗口低于紧凑阈值时，导入区会收紧间距，非必要的标题辅助文字会隐藏；侧栏与检查器各自处理纵向溢出，因此控件不会互相覆盖。窗口仅设置 `960 × 680` 的安全最小尺寸，不再锁定到固定内容尺寸，并通过 AppKit 启用原生全屏。

上半区中的 `VideoPlayer`、环形占比图和导出控件不会跟随素材列表移动。照片由 `ZoomableImagePreview` 显示，缩放范围为 25%–600%；放大后的内容尺寸参与双向 `ScrollView` 布局，因此可以平移查看细节。下半区的外层 `ScrollView(.horizontal)` 只负责格式切换，每个 `ProfileGroupView` 内部拥有独立的 `ScrollView(.vertical)`。`GeometryReader` 将所有格式列约束到同一可视高度，因此最大分组不会撑高其他列；所有 `ColorProfile` 始终显示。

`DonutChartView` 根据每个 `ColorProfile` 的实际数量计算累计区间，用多个旋转后的 `Circle.trim` 绘制环形分段，不依赖第三方图表库。

## 7. 文件整理安全策略

应用支持复制和移动：

- 使用 `FileManager.createDirectory` 按需创建目标目录。
- `uniqueDestination` 在冲突时追加 `_2`、`_3`，不会覆盖。
- 单个文件失败只记录到该行，不阻止后续文件。
- 未知模式使用独立目录，避免错误 LUT 污染工作流。
- 启用“同时导出匹配的 LRF”时，代理文件与视频进入同一目录；LRF 失败不会回滚已成功导出的视频。

## 8. 测试设计

测试不包含真实用户视频。`DjiMetadataReaderTests.swift` 在运行时构造最小 MP4：

```text
ftyp + mdat(djmd protobuf) + moov/trak/mdia/minf/stbl
```

测试矩阵：

| 输入 | 期望 |
|---|---|
| `ColorGammaSxS = 22` | D-Log 2 |
| `ColorGammaSxS = 2` | D-Log |
| `record_mode = 8`，无 gamma | 普通 Rec.709 |

增加新映射时应先添加失败测试，再扩展分类规则。

## 9. 扩展建议

### 添加新的枚举值

1. 确认它来自未转码的原始素材。
2. 用至少两台设备或多个样本交叉验证。
3. 添加匿名化合成 fixture。
4. 更新 `Detector.inspect`、README 分类表和 Changelog。

### 支持 fragmented MP4

需要解析 `moof/traf/tfhd/trun` 以计算 fragment sample offset。实现时必须覆盖 base-data-offset、default sample size 和多 fragment 情况，不应仅扫描字节字符串。
