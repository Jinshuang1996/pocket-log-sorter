import SwiftUI
import AVFoundation
import AVKit
import UniformTypeIdentifiers
import AppKit
import ImageIO

enum ColorProfile: String, CaseIterable, Identifiable {
    case dlog2 = "D-Log 2"
    case dlog = "D-Log"
    case dlogM = "D-Log M"
    case hlg = "HLG"
    case hdr = "HDR / PQ"
    case normal = "Rec.709"
    case jpeg = "JPG"
    case raw = "RAW"
    case unknown = "待确认"

    var id: String { rawValue }
    var folderName: String {
        switch self {
        case .dlog2: return "01_D-Log_2"
        case .dlog: return "02_D-Log"
        case .dlogM: return "03_D-Log_M"
        case .hlg: return "04_HLG"
        case .hdr: return "05_HDR"
        case .normal: return "06_Normal_Rec709"
        case .jpeg: return "07_JPG"
        case .raw: return "08_RAW"
        case .unknown: return "99_待确认"
        }
    }
    var symbol: String {
        switch self {
        case .dlog2, .dlog, .dlogM: return "camera.filters"
        case .hlg: return "sun.max.trianglebadge.exclamationmark"
        case .hdr: return "sparkles.tv"
        case .normal: return "rectangle.fill.on.rectangle.fill"
        case .jpeg: return "photo"
        case .raw: return "camera.aperture"
        case .unknown: return "questionmark.circle"
        }
    }
    var color: Color {
        switch self {
        case .dlog2: return Color(red: 0.20, green: 0.72, blue: 1.00)
        case .dlog: return Color(red: 0.69, green: 0.34, blue: 1.00)
        case .dlogM: return Color(red: 0.98, green: 0.31, blue: 0.69)
        case .hlg: return Color(red: 1.00, green: 0.65, blue: 0.18)
        case .hdr: return Color(red: 0.26, green: 0.87, blue: 0.58)
        case .normal: return Color(red: 0.25, green: 0.78, blue: 0.88)
        case .jpeg: return Color(red: 0.96, green: 0.78, blue: 0.26)
        case .raw: return Color(red: 0.93, green: 0.43, blue: 0.24)
        case .unknown: return Color(red: 0.57, green: 0.62, blue: 0.68)
        }
    }
}

struct DetectionResult {
    let profile: ColorProfile
    let reason: String
    let metadata: String
}

struct MediaItem: Identifiable {
    let id = UUID()
    let url: URL
    var result: DetectionResult?
    var thumbnail: NSImage?
    var lrfURL: URL?
    var duration: TimeInterval?
    var error: String?
    var isWorking = true

    var isStillImage: Bool {
        Detector.imageExtensions.contains(url.pathExtension.lowercased())
    }
}

enum Detector {
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    static let jpegExtensions: Set<String> = ["jpg", "jpeg"]
    static let rawExtensions: Set<String> = [
        "3fr", "arw", "cr2", "cr3", "dng", "erf", "iiq", "kdc", "mef",
        "mos", "nef", "nrw", "orf", "pef", "raf", "raw", "rw2", "rwl",
        "srw", "x3f"
    ]
    static let imageExtensions = jpegExtensions.union(rawExtensions)
    static let supportedExtensions = videoExtensions.union(imageExtensions)

    static func classifyText(_ raw: String) -> DetectionResult {
        let s = raw.lowercased()
        let explicitDJI = s.contains("colorgammasxs") || s.contains("color gamma sx s")

        if s.contains("d-log2") || s.contains("d-log 2") || s.contains("dlog2") || s.contains("dlog 2") {
            return DetectionResult(profile: .dlog2, reason: "DJI 元数据标记为 D-Log 2", metadata: raw)
        }
        if s.contains("d-log m") || s.contains("dlog-m") || s.contains("dlog m") {
            return DetectionResult(profile: .dlogM, reason: "DJI 元数据标记为 D-Log M", metadata: raw)
        }
        if s.contains("d-log") || s.contains("dlog") {
            return DetectionResult(profile: .dlog, reason: "DJI 元数据标记为 D-Log", metadata: raw)
        }
        if s.contains("rec.2100 hlg") || s.contains("rec 2100 hlg") || s.contains("arib-std-b67") || s.contains("itu_r_2100_hlg") || s.contains("hlg") {
            return DetectionResult(profile: .hlg, reason: explicitDJI ? "DJI 元数据标记为 Rec.2100 HLG" : "色彩传递函数为 HLG", metadata: raw)
        }
        if s.contains("smpte2084") || s.contains("smpte 2084") || s.contains("pq") || s.contains("dolby vision") || s.contains("dovi") {
            return DetectionResult(profile: .hdr, reason: "检测到 PQ / Dolby Vision HDR 标记", metadata: raw)
        }
        if s.contains("bt.2020") || s.contains("bt2020") || s.contains("itur_2020") {
            return DetectionResult(profile: .hdr, reason: "检测到 BT.2020，但未找到 HLG 标记", metadata: raw)
        }
        if explicitDJI && (s.contains("rec.709") || s.contains("rec 709") || s.contains("bt.709") || s.contains("bt709")) {
            return DetectionResult(profile: .normal, reason: "DJI 元数据标记为普通 Rec.709", metadata: raw)
        }
        if s.contains("bt.709") || s.contains("bt709") || s.contains("itur_709") {
            return DetectionResult(profile: .unknown, reason: "仅检测到 BT.709；DJI Log 也可能写成 BT.709，无法安全判断", metadata: raw)
        }
        return DetectionResult(profile: .unknown, reason: "文件未提供可识别的色彩模式标记", metadata: raw)
    }

    static func inspect(url: URL) async -> DetectionResult {
        let ext = url.pathExtension.lowercased()
        if jpegExtensions.contains(ext) {
            return DetectionResult(profile: .jpeg, reason: "JPEG 相机照片", metadata: "文件扩展名：.\(ext)")
        }
        if rawExtensions.contains(ext) {
            return DetectionResult(profile: .raw, reason: "相机 RAW 原始照片", metadata: "文件扩展名：.\(ext)")
        }

        var djiEvidence = ""
        if let evidence = try? DjiMetadataReader.inspect(url: url) {
            djiEvidence = "djmd: ColorGammaSxS=\(evidence.colorGammaSxS.map(String.init) ?? "nil"), record_mode=\(evidence.recordMode.map(String.init) ?? "nil")"
            if evidence.colorGammaSxS == 22 {
                return DetectionResult(profile: .dlog2, reason: "DJI 私有元数据确认：D-Log 2", metadata: djiEvidence)
            }
            if evidence.colorGammaSxS == 2 {
                return DetectionResult(profile: .dlog, reason: "DJI 私有元数据确认：D-Log", metadata: djiEvidence)
            }
            if evidence.colorGammaSxS == nil && evidence.recordMode == 8 {
                return DetectionResult(profile: .normal, reason: "DJI 私有元数据确认：普通 Rec.709", metadata: djiEvidence)
            }
        }

        let asset = AVURLAsset(url: url)
        var lines: [String] = []

        for format in asset.availableMetadataFormats {
            for item in asset.metadata(forFormat: format) {
                let identifier = item.identifier?.rawValue ?? ""
                let keySpace = item.keySpace?.rawValue ?? ""
                let key = item.key.map { String(describing: $0) } ?? ""
                let value: String
                if let string = item.stringValue { value = string }
                else if let number = item.numberValue { value = number.stringValue }
                else if let data = item.dataValue, let string = String(data: data, encoding: .utf8) { value = string }
                else { value = "" }
                lines.append("\(format.rawValue) | \(identifier) | \(keySpace) | \(key) | \(value)")
            }
        }

        if let track = asset.tracks(withMediaType: .video).first {
            for description in track.formatDescriptions {
                let formatDescription = description as! CMFormatDescription
                if let extensions = CMFormatDescriptionGetExtensions(formatDescription) {
                    lines.append("formatDescription | \(extensions)")
                }
            }
        }

        let standardMetadata = lines.joined(separator: "\n")
        let result = classifyText(standardMetadata)
        if result.profile == .unknown && !djiEvidence.isEmpty {
            return DetectionResult(profile: .unknown, reason: "检测到 DJI 元数据，但其数值尚未收录", metadata: djiEvidence + "\n" + standardMetadata)
        }
        return result
    }
}

struct ThumbnailPayload {
    let image: NSImage?
    let lrfURL: URL?
    let duration: TimeInterval?
}

enum ThumbnailLoader {
    static func load(for videoURL: URL, preferredLRF: URL? = nil) -> ThumbnailPayload {
        if Detector.imageExtensions.contains(videoURL.pathExtension.lowercased()) {
            return ThumbnailPayload(image: renderImage(url: videoURL), lrfURL: nil, duration: nil)
        }
        let lrf = preferredLRF ?? companionLRF(for: videoURL)
        if let lrf, let preview = render(url: lrf) {
            return ThumbnailPayload(image: preview.image, lrfURL: lrf, duration: preview.duration)
        }
        let preview = render(url: videoURL)
        return ThumbnailPayload(image: preview?.image, lrfURL: lrf, duration: preview?.duration)
    }

    static func companionLRF(for videoURL: URL) -> URL? {
        let folder = videoURL.deletingLastPathComponent()
        let stem = videoURL.deletingPathExtension().lastPathComponent.lowercased()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return files.first { candidate in
            candidate.pathExtension.lowercased() == "lrf" &&
            candidate.deletingPathExtension().lastPathComponent.lowercased() == stem
        }
    }

    private static func render(url: URL) -> (image: NSImage, duration: TimeInterval?)? {
        let asset = AVURLAsset(url: url)
        let seconds = asset.duration.seconds
        let duration = seconds.isFinite && seconds > 0 ? seconds : nil
        let time = CMTime(seconds: min(1, max(0, (duration ?? 0) * 0.08)), preferredTimescale: 600)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 405)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return (NSImage(cgImage: cgImage, size: .zero), duration)
    }

    private static func renderImage(url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 960
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }
        return NSImage(cgImage: image, size: .zero)
    }
}

@MainActor
final class SorterModel: ObservableObject {
    @Published var items: [MediaItem] = []
    @Published var outputURL: URL?
    @Published var copyFiles = false
    @Published var includeLRF = true
    @Published var selectedForExport: Set<UUID> = []
    @Published var status = "拖入视频、照片或点击导入"
    private var importedLRFs: [URL] = []

    var readyCount: Int { items.filter { !$0.isWorking }.count }
    var canSort: Bool { !selectedForExport.isEmpty && items.allSatisfy { !$0.isWorking } && outputURL != nil }
    var selectedCount: Int { selectedForExport.count }
    var lrfCount: Int { items.filter { $0.lrfURL != nil }.count }
    var videoCount: Int { items.filter { !$0.isStillImage }.count }
    var photoCount: Int { items.filter { $0.isStillImage }.count }
    var detectedGroupCount: Int { Set(items.compactMap { $0.result?.profile }).count }

    func add(urls: [URL]) {
        let expanded = expand(urls: urls)
        register(lrfs: expanded.lrfs)

        var newlyAttached = 0
        for index in items.indices {
            guard !items[index].isStillImage else { continue }
            guard let lrf = preferredLRF(for: items[index].url),
                  items[index].lrfURL?.standardizedFileURL != lrf.standardizedFileURL else { continue }
            let itemID = items[index].id
            let videoURL = items[index].url
            items[index].lrfURL = lrf
            newlyAttached += 1
            refreshPreview(itemID: itemID, videoURL: videoURL, lrfURL: lrf)
        }

        let existing = Set(items.map { $0.url.standardizedFileURL.path })
        let fresh = expanded.media.filter { !existing.contains($0.standardizedFileURL.path) }
        guard !fresh.isEmpty else {
            if !expanded.lrfs.isEmpty {
                status = "已导入 \(expanded.lrfs.count) 个 LRF，匹配 \(newlyAttached) 个视频；LRF 不会显示在下方"
            } else {
                status = expanded.media.isEmpty ? "没有找到支持的视频、照片或 LRF 文件" : "这些素材已在项目中"
            }
            return
        }
        let newItems = fresh.map { MediaItem(url: $0) }
        items.append(contentsOf: newItems)
        selectedForExport.formUnion(newItems.map(\.id))
        status = "正在分析 \(fresh.count) 个素材…"

        for item in newItems {
            let preferredLRF = item.isStillImage ? nil : preferredLRF(for: item.url)
            Task {
                let payload = await Task.detached(priority: .userInitiated) {
                    let result = await Detector.inspect(url: item.url)
                    let thumbnail = ThumbnailLoader.load(for: item.url, preferredLRF: preferredLRF)
                    return (result, thumbnail)
                }.value
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].result = payload.0
                    items[index].thumbnail = payload.1.image
                    items[index].lrfURL = payload.1.lrfURL
                    items[index].duration = payload.1.duration
                    items[index].isWorking = false
                }
                status = items.allSatisfy { !$0.isWorking }
                    ? "分析完成：\(items.count) 个素材，匹配 \(lrfCount) 个 LRF"
                    : "正在分析… \(readyCount)/\(items.count)"
            }
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        var types: [UTType] = [.movie, .mpeg4Movie, .quickTimeMovie, .image, .jpeg, .folder]
        if let rawType = UTType("public.camera-raw-image") { types.append(rawType) }
        for ext in Detector.rawExtensions.sorted() {
            if let type = UTType(filenameExtension: ext), !types.contains(type) { types.append(type) }
        }
        if let lrfType = UTType("com.pocketlogsorter.dji-lrf") { types.append(lrfType) }
        panel.allowedContentTypes = types
        panel.prompt = "导入素材"
        panel.message = "选择视频、JPG、相机 RAW、LRF 或整个素材文件夹；LRF 不会单独显示"
        if panel.runModal() == .OK { add(urls: panel.urls) }
    }

    private func expand(urls: [URL]) -> (media: [URL], lrfs: [URL]) {
        var media: [URL] = []
        var lrfs: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    for case let child as URL in enumerator {
                        let ext = child.pathExtension.lowercased()
                        if Detector.supportedExtensions.contains(ext) { media.append(child) }
                        else if ext == "lrf" { lrfs.append(child) }
                    }
                }
            } else if Detector.supportedExtensions.contains(url.pathExtension.lowercased()) {
                media.append(url)
            } else if url.pathExtension.lowercased() == "lrf" {
                lrfs.append(url)
            }
        }
        return (
            media.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending },
            lrfs.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        )
    }

    private func register(lrfs: [URL]) {
        var known = Set(importedLRFs.map { $0.standardizedFileURL.path })
        for lrf in lrfs where known.insert(lrf.standardizedFileURL.path).inserted {
            importedLRFs.append(lrf)
        }
    }

    private func preferredLRF(for videoURL: URL) -> URL? {
        let exactKey = pairKey(for: videoURL)
        if let exact = importedLRFs.first(where: { pairKey(for: $0) == exactKey }) { return exact }

        let stem = videoURL.deletingPathExtension().lastPathComponent.lowercased()
        let sameStem = importedLRFs.filter {
            $0.deletingPathExtension().lastPathComponent.lowercased() == stem
        }
        if sameStem.count == 1 { return sameStem[0] }
        return ThumbnailLoader.companionLRF(for: videoURL)
    }

    private func pairKey(for url: URL) -> String {
        let folder = url.deletingLastPathComponent().standardizedFileURL.path.lowercased()
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        return folder + "/" + stem
    }

    private func refreshPreview(itemID: UUID, videoURL: URL, lrfURL: URL) {
        Task {
            let preview = await Task.detached(priority: .userInitiated) {
                ThumbnailLoader.load(for: videoURL, preferredLRF: lrfURL)
            }.value
            guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
            items[index].thumbnail = preview.image
            items[index].lrfURL = preview.lrfURL
            items[index].duration = preview.duration
        }
    }

    func chooseOutput() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择输出位置"
        panel.message = "应用会在这里创建 D-Log、HLG、HDR、Rec.709、JPG、RAW 等分类文件夹"
        if panel.runModal() == .OK { outputURL = panel.url }
    }

    func sort() {
        guard let root = outputURL else { return }
        let fm = FileManager.default
        var successes = 0
        var failures = 0
        var lrfFailures = 0
        status = copyFiles ? "正在复制并分类…" : "正在移动并分类…"

        for index in items.indices {
            guard selectedForExport.contains(items[index].id) else { continue }
            guard let profile = items[index].result?.profile else { continue }
            let folder = root.appendingPathComponent(profile.folderName, isDirectory: true)
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = uniqueDestination(for: items[index].url, in: folder)
                if copyFiles { try fm.copyItem(at: items[index].url, to: destination) }
                else { try fm.moveItem(at: items[index].url, to: destination) }
                successes += 1

                if includeLRF, let lrf = items[index].lrfURL, fm.fileExists(atPath: lrf.path) {
                    let sidecarName = destination.deletingPathExtension().lastPathComponent + "." + lrf.pathExtension
                    let sidecarDestination = uniqueDestination(for: lrf, in: folder, preferredName: sidecarName)
                    do {
                        if copyFiles { try fm.copyItem(at: lrf, to: sidecarDestination) }
                        else { try fm.moveItem(at: lrf, to: sidecarDestination) }
                    } catch {
                        lrfFailures += 1
                    }
                }
            } catch {
                items[index].error = error.localizedDescription
                failures += 1
            }
        }
        if failures == 0 && lrfFailures == 0 {
            status = "完成：已分类 \(successes) 个素材"
        } else {
            status = "完成 \(successes) 个；素材失败 \(failures) 个，LRF 失败 \(lrfFailures) 个"
        }
    }

    func clear() {
        items.removeAll()
        selectedForExport.removeAll()
        importedLRFs.removeAll()
        status = "拖入视频、照片或点击导入"
    }

    func selectAll() {
        selectedForExport = Set(items.map(\.id))
    }

    func deselectAll() {
        selectedForExport.removeAll()
    }

    func toggleExportSelection(_ id: UUID) {
        if selectedForExport.contains(id) { selectedForExport.remove(id) }
        else { selectedForExport.insert(id) }
    }

    private func uniqueDestination(for source: URL, in folder: URL, preferredName: String? = nil) -> URL {
        let fm = FileManager.default
        let initialName = preferredName ?? source.lastPathComponent
        var candidate = folder.appendingPathComponent(initialName)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            let initial = URL(fileURLWithPath: initialName)
            let base = initial.deletingPathExtension().lastPathComponent
            let ext = initial.pathExtension
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base)_\(n)" : "\(base)_\(n).\(ext)")
            n += 1
        }
        return candidate
    }
}

private let appBackground = Color(red: 0.035, green: 0.047, blue: 0.055)
private let panelBackground = Color(red: 0.060, green: 0.075, blue: 0.084)
private let cardBackground = Color(red: 0.080, green: 0.096, blue: 0.106)
private let borderColor = Color.white.opacity(0.09)

struct Panel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(panelBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(borderColor, lineWidth: 1))
    }
}

struct ImportDropZone: View {
    let action: ([URL]) -> Void
    let browseAction: () -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(targeted ? Color.cyan : Color.white.opacity(0.44))
            VStack(spacing: 4) {
                Text("拖放视频、JPG、RAW 或素材文件夹")
                    .font(.system(size: 13, weight: .semibold))
                Text("照片独立分组 · 自动匹配同名 LRF")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("点击导入", action: browseAction)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.04, green: 0.52, blue: 0.92))
        }
        .frame(maxWidth: .infinity, minHeight: 155)
        .background(targeted ? Color.cyan.opacity(0.10) : Color.black.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(targeted ? Color.cyan : Color.white.opacity(0.20), style: StrokeStyle(lineWidth: 1, dash: [6]))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: browseAction)
        .dropDestination(for: URL.self) { urls, _ in
            action(urls)
            return true
        } isTargeted: { targeted = $0 }
    }
}

struct SidebarView: View {
    @ObservedObject var model: SorterModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("POCKET").foregroundStyle(Color(red: 0.12, green: 0.70, blue: 1.00))
                    Text("LOG SORTER").foregroundStyle(.white.opacity(0.72))
                }
                .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("DJI Color Profile Workspace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    Label("导入素材", systemImage: "tray.and.arrow.down").font(.headline)
                    ImportDropZone(action: model.add, browseAction: model.chooseFiles)
                }
                .padding(12)
            }

            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("项目概览").font(.headline)
                        Spacer()
                        Text("\(model.readyCount)/\(model.items.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    metricRow("视频", value: "\(model.videoCount)", icon: "film")
                    metricRow("照片", value: "\(model.photoCount)", icon: "photo")
                    metricRow("LRF 匹配", value: "\(model.lrfCount)", icon: "photo.on.rectangle")
                    metricRow("格式分组", value: "\(model.detectedGroupCount)", icon: "square.grid.2x2")
                }
                .padding(13)
            }

            Spacer(minLength: 0)
            if !model.items.isEmpty {
                Button(role: .destructive, action: model.clear) {
                    Label("清空当前项目", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(width: 250)
    }

    private func metricRow(_ title: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
            Text(title).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.bold().monospacedDigit())
        }
    }
}

struct VideoPreviewView: View {
    let item: MediaItem?
    @State private var player = AVPlayer()
    @State private var playOriginal = false

    private var playbackURL: URL? {
        guard let item else { return nil }
        return playOriginal ? item.url : (item.lrfURL ?? item.url)
    }

    var body: some View {
        Panel {
            VStack(spacing: 0) {
                ZStack {
                    Color.black
                    if item == nil {
                        VStack(spacing: 12) {
                            Image(systemName: "play.rectangle")
                                .font(.system(size: 48, weight: .thin))
                                .foregroundStyle(.white.opacity(0.22))
                            Text("导入素材后可在这里播放或预览")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if let item, item.isStillImage {
                        if let image = item.thumbnail {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding(8)
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 48, weight: .thin))
                                .foregroundStyle(.white.opacity(0.22))
                        }
                    } else {
                        VideoPlayer(player: player)
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: item?.result?.profile.symbol ?? "film")
                        .foregroundStyle(item?.result?.profile.color ?? .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item?.url.lastPathComponent ?? "未选择素材")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(item == nil ? "点击下方缩略图选择素材" : playbackSourceText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if item?.isStillImage == false && item?.lrfURL != nil {
                        Button(playOriginal ? "播放 LRF" : "播放原片") {
                            playOriginal.toggle()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Text(item?.result?.profile.rawValue ?? "—")
                        .font(.caption.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background((item?.result?.profile.color ?? .gray).opacity(0.18), in: Capsule())
                        .foregroundStyle(item?.result?.profile.color ?? .secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 54)
                .background(Color.black.opacity(0.56))
            }
        }
        .onAppear(perform: loadPlayer)
        .onChange(of: item?.id) { _ in
            playOriginal = false
            loadPlayer()
        }
        .onChange(of: playOriginal) { _ in loadPlayer() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { _ in
            if !playOriginal && item?.lrfURL != nil { playOriginal = true }
        }
        .onDisappear { player.pause() }
    }

    private var playbackSourceText: String {
        if let item, item.isStillImage {
            return item.result?.profile == .raw ? "正在预览 RAW 原始照片" : "正在预览 JPG 照片"
        }
        if playOriginal || item?.lrfURL == nil { return "正在播放原视频" }
        return "正在播放 LRF 代理文件"
    }

    private func loadPlayer() {
        player.pause()
        if item?.isStillImage == true {
            player.replaceCurrentItem(with: nil)
            return
        }
        guard let playbackURL else {
            player.replaceCurrentItem(with: nil)
            return
        }
        player.replaceCurrentItem(with: AVPlayerItem(url: playbackURL))
        if !playOriginal && item?.lrfURL != nil {
            let candidate = playbackURL
            Task {
                let asset = AVURLAsset(url: candidate)
                let playable = (try? await asset.load(.isPlayable)) ?? false
                if !playable && self.playbackURL == candidate { playOriginal = true }
            }
        }
    }
}

struct DonutChartView: View {
    let items: [MediaItem]

    private var slices: [(profile: ColorProfile, count: Int)] {
        ColorProfile.allCases.compactMap { profile in
            let count = items.filter { $0.result?.profile == profile }.count
            return count > 0 ? (profile, count) : nil
        }
    }

    private var total: Int {
        slices.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 13)
                ForEach(slices.indices, id: \.self) { index in
                    Circle()
                        .trim(from: start(at: index), to: end(at: index))
                        .stroke(
                            slices[index].profile.color,
                            style: StrokeStyle(lineWidth: 13, lineCap: .butt)
                        )
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 0) {
                    Text("\(total)")
                        .font(.title3.bold().monospacedDigit())
                    Text("素材")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 94, height: 94)

            VStack(alignment: .leading, spacing: 4) {
                if slices.isEmpty {
                    Text("等待分析")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(slices.indices, id: \.self) { index in
                        let slice = slices[index]
                        HStack(spacing: 5) {
                            Circle().fill(slice.profile.color).frame(width: 7, height: 7)
                            Text(slice.profile.rawValue)
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Spacer(minLength: 3)
                            Text("\(slice.count) · \(percent(slice.count))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(10)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }

    private func start(at index: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        let previous = slices.prefix(index).reduce(0) { $0 + $1.count }
        return CGFloat(previous) / CGFloat(total)
    }

    private func end(at index: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(slices.prefix(index + 1).reduce(0) { $0 + $1.count }) / CGFloat(total)
    }

    private func percent(_ count: Int) -> String {
        guard total > 0 else { return "0%" }
        return String(format: "%.0f%%", Double(count) / Double(total) * 100)
    }
}

struct InspectorView: View {
    @ObservedObject var model: SorterModel
    let selectedItem: MediaItem?

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("分析与导出").font(.headline)
                    Spacer()
                    if model.readyCount < model.items.count { ProgressView().controlSize(.small) }
                }

                DonutChartView(items: model.items)

                if let selectedItem {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("当前素材判定")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Text(selectedItem.error ?? selectedItem.result?.reason ?? "正在读取元数据…")
                            .font(.caption)
                            .lineLimit(2)
                            .truncationMode(.tail)
                        if selectedItem.lrfURL != nil {
                            Label("已匹配 LRF", systemImage: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.green)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: model.chooseOutput) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("选择输出文件夹").lineLimit(1)
                            Text(model.outputURL?.path(percentEncoded: false) ?? "尚未选择")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.bordered)

                Picker("", selection: $model.copyFiles) {
                    Text("复制原片").tag(true)
                    Text("移动原片").tag(false)
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Toggle("同时导出匹配的 LRF", isOn: $model.includeLRF)
                    .font(.caption)
                    .lineLimit(1)

                HStack(spacing: 7) {
                    Button("全选") { model.selectAll() }
                    Button("取消全选") { model.deselectAll() }
                    Spacer()
                    Text("\(model.selectedCount)/\(model.items.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .controlSize(.small)

                Spacer(minLength: 0)

                Button(action: model.sort) {
                    Label("导出已选 \(model.selectedCount) 个", systemImage: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.02, green: 0.52, blue: 0.92))
                .disabled(!model.canSort)
            }
            .padding(13)
        }
        .frame(width: 282)
    }
}

struct ClipCard: View {
    let item: MediaItem
    let active: Bool
    let markedForExport: Bool
    let activate: () -> Void
    let toggleExport: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.42)

                if let image = item.thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    Image(systemName: item.isWorking ? "hourglass" : (item.isStillImage ? "photo" : "film"))
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.25))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.88)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(spacing: 4) {
                    Image(systemName: item.isStillImage ? "photo" : (item.lrfURL == nil ? "film" : "photo.on.rectangle"))
                        .font(.caption2)
                    Text(item.url.deletingPathExtension().lastPathComponent)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 2)
                    Text(item.isStillImage ? item.url.pathExtension.uppercased() : durationText(item.duration))
                        .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(.white)
                .padding(6)

                VStack {
                    HStack {
                        Spacer()
                        Button(action: toggleExport) {
                            Image(systemName: markedForExport ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(markedForExport ? Color.cyan : Color.white.opacity(0.75))
                                .shadow(color: .black, radius: 2)
                        }
                        .buttonStyle(.plain)
                        .help(markedForExport ? "从导出选择中移除" : "加入导出选择")
                    }
                    Spacer()
                }
                .padding(6)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .onTapGesture(perform: activate)
        }
        .frame(height: 94)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(active ? (item.result?.profile.color ?? .cyan) : borderColor, lineWidth: active ? 2 : 1)
        )
        .opacity(markedForExport ? 1 : 0.58)
        .help(item.result?.metadata ?? "正在分析")
    }

    private func durationText(_ duration: TimeInterval?) -> String {
        guard let duration, duration.isFinite else { return "--:--" }
        let value = max(0, Int(duration.rounded()))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

struct ProfileGroupView: View {
    let profile: ColorProfile
    let items: [MediaItem]
    @Binding var activeID: UUID?
    @ObservedObject var model: SorterModel

    private let columns = [
        GridItem(.fixed(122), spacing: 8),
        GridItem(.fixed(122), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Circle().fill(profile.color).frame(width: 9, height: 9)
                Text(profile.rawValue)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text("\(items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: profile.symbol)
                        .foregroundStyle(profile.color.opacity(0.48))
                    Text("暂无素材")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 252, height: 94)
                .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(items) { item in
                            ClipCard(
                                item: item,
                                active: activeID == item.id,
                                markedForExport: model.selectedForExport.contains(item.id),
                                activate: { activeID = item.id },
                                toggleExport: { model.toggleExportSelection(item.id) }
                            )
                        }
                    }
                    .padding(.trailing, 2)
                    .padding(.bottom, 2)
                }
                .scrollIndicators(.visible)
            }
        }
        .padding(10)
        .frame(width: 272)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 9))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 9).fill(profile.color).frame(height: 3)
        }
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(borderColor, lineWidth: 1))
    }
}

struct ContentView: View {
    @StateObject private var model = SorterModel()
    @State private var activeID: UUID?

    private var activeItem: MediaItem? {
        model.items.first { $0.id == activeID } ?? model.items.first
    }

    private var visibleProfiles: [ColorProfile] {
        guard !model.items.isEmpty, model.readyCount == model.items.count else {
            return ColorProfile.allCases
        }
        return ColorProfile.allCases.filter { profile in
            model.items.contains { ($0.result?.profile ?? .unknown) == profile }
        }
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                Text("POCKET LOG SORTER")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.status)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(model.status.hasPrefix("完成") ? Color.green : Color.secondary)
                Spacer()
                Text("DJI COLOR WORKSPACE")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 5)

            HStack(alignment: .top, spacing: 10) {
                SidebarView(model: model)
                VideoPreviewView(item: activeItem)
                    .frame(maxWidth: .infinity)
                InspectorView(model: model, selectedItem: activeItem)
            }
            .frame(height: 426)

            HStack(spacing: 10) {
                Text("按素材格式分组").font(.headline)
                Text("点击卡片预览 · 每个分组可独立上下滚动")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("已选 \(model.selectedCount)/\(model.items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("全选", action: model.selectAll).controlSize(.small)
                Button("取消全选", action: model.deselectAll).controlSize(.small)
            }
            .padding(.horizontal, 4)

            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(visibleProfiles) { profile in
                            ProfileGroupView(
                                profile: profile,
                                items: model.items.filter { ($0.result?.profile ?? .unknown) == profile },
                                activeID: $activeID,
                                model: model
                            )
                            .frame(height: max(160, proxy.size.height - 4))
                        }
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.visible)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
        .frame(width: 1320, height: 800)
        .background(appBackground)
        .preferredColorScheme(.dark)
        .onChange(of: model.items.count) { _ in
            if activeID == nil { activeID = model.items.first?.id }
        }
    }
}

@main
struct PocketColorSorterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup { ContentView() }
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 1320, height: 800)
            .windowResizability(.contentSize)
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
