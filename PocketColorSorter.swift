import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import AppKit

enum ColorProfile: String, CaseIterable, Identifiable {
    case dlog2 = "D-Log 2"
    case dlog = "D-Log"
    case dlogM = "D-Log M"
    case hlg = "HLG"
    case hdr = "HDR / PQ"
    case normal = "Rec.709"
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
        case .unknown: return "99_待确认"
        }
    }
    var symbol: String {
        switch self {
        case .dlog2, .dlog, .dlogM: return "camera.filters"
        case .hlg: return "sun.max.trianglebadge.exclamationmark"
        case .hdr: return "sparkles.tv"
        case .normal: return "rectangle.fill.on.rectangle.fill"
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
}

enum Detector {
    static let supportedExtensions: Set<String> = ["mp4", "mov", "m4v"]

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
    static func load(for videoURL: URL) -> ThumbnailPayload {
        let lrf = companionLRF(for: videoURL)
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
}

@MainActor
final class SorterModel: ObservableObject {
    @Published var items: [MediaItem] = []
    @Published var outputURL: URL?
    @Published var copyFiles = true
    @Published var includeLRF = true
    @Published var status = "拖入视频或点击导入"

    var readyCount: Int { items.filter { !$0.isWorking }.count }
    var canSort: Bool { !items.isEmpty && items.allSatisfy { !$0.isWorking } && outputURL != nil }
    var lrfCount: Int { items.filter { $0.lrfURL != nil }.count }
    var detectedGroupCount: Int { Set(items.compactMap { $0.result?.profile }).count }

    func add(urls: [URL]) {
        let expanded = expand(urls: urls)
        let existing = Set(items.map { $0.url.standardizedFileURL.path })
        let fresh = expanded.filter { !existing.contains($0.standardizedFileURL.path) }
        guard !fresh.isEmpty else {
            status = expanded.isEmpty ? "没有找到支持的 MP4、MOV 或 M4V 文件" : "这些视频已在项目中"
            return
        }
        let newItems = fresh.map { MediaItem(url: $0) }
        items.append(contentsOf: newItems)
        status = "正在分析 \(fresh.count) 个视频…"

        for item in newItems {
            Task {
                let payload = await Task.detached(priority: .userInitiated) {
                    let result = await Detector.inspect(url: item.url)
                    let thumbnail = ThumbnailLoader.load(for: item.url)
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
                    ? "分析完成：\(items.count) 个视频，匹配 \(lrfCount) 个 LRF"
                    : "正在分析… \(readyCount)/\(items.count)"
            }
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .folder]
        panel.prompt = "导入素材"
        panel.message = "选择视频或整个 DJI 素材文件夹；同名 LRF 会自动用于缩略图"
        if panel.runModal() == .OK { add(urls: panel.urls) }
    }

    private func expand(urls: [URL]) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    for case let child as URL in enumerator where Detector.supportedExtensions.contains(child.pathExtension.lowercased()) {
                        result.append(child)
                    }
                }
            } else if Detector.supportedExtensions.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }
        return result.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func chooseOutput() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择输出位置"
        panel.message = "应用会在这里创建 D-Log、HLG、HDR、Rec.709 等分类文件夹"
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
            status = "完成：已分类 \(successes) 个视频"
        } else {
            status = "完成 \(successes) 个；视频失败 \(failures) 个，LRF 失败 \(lrfFailures) 个"
        }
    }

    func clear() {
        items.removeAll()
        status = "拖入视频或点击导入"
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
                Text("拖放视频或素材文件夹")
                    .font(.system(size: 13, weight: .semibold))
                Text("自动匹配同名 LRF 缩略文件")
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
                    metricRow("视频", value: "\(model.items.count)", icon: "film")
                    metricRow("LRF 匹配", value: "\(model.lrfCount)", icon: "photo.on.rectangle")
                    metricRow("色彩分组", value: "\(model.detectedGroupCount)", icon: "square.grid.2x2")
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

struct PreviewView: View {
    let item: MediaItem?

    var body: some View {
        Panel {
            ZStack(alignment: .bottom) {
                Rectangle().fill(Color.black.opacity(0.45))
                if let image = item?.thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: item == nil ? "film.stack" : "waveform.path.ecg")
                            .font(.system(size: 46, weight: .thin))
                            .foregroundStyle(.white.opacity(0.20))
                        Text(item == nil ? "导入素材后在这里预览" : "正在生成视频缩略图…")
                            .foregroundStyle(.secondary)
                    }
                }

                if let item {
                    HStack(spacing: 12) {
                        Image(systemName: item.result?.profile.symbol ?? "hourglass")
                            .foregroundStyle(item.result?.profile.color ?? .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.url.lastPathComponent)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(item.lrfURL == nil ? "原视频预览" : "LRF 低分辨率预览")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.result?.profile.rawValue ?? "分析中")
                            .font(.caption.bold())
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background((item.result?.profile.color ?? .gray).opacity(0.18), in: Capsule())
                            .foregroundStyle(item.result?.profile.color ?? .secondary)
                    }
                    .padding(12)
                    .background(.black.opacity(0.72))
                }
            }
        }
        .frame(minHeight: 310)
    }
}

struct InspectorView: View {
    @ObservedObject var model: SorterModel
    let selectedItem: MediaItem?

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("分析与导出").font(.headline)
                    Spacer()
                    if model.readyCount < model.items.count { ProgressView().controlSize(.small) }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ColorProfile.allCases.filter { profile in
                        model.items.contains { $0.result?.profile == profile }
                    }) { profile in
                        HStack {
                            Circle().fill(profile.color).frame(width: 8, height: 8)
                            Text(profile.rawValue).font(.caption)
                            Spacer()
                            Text("\(model.items.filter { $0.result?.profile == profile }.count)")
                                .font(.caption.bold().monospacedDigit())
                        }
                    }
                    if model.items.isEmpty {
                        Text("尚无分析结果").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))

                if let selectedItem {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("判定依据").font(.caption.bold()).foregroundStyle(.secondary)
                        Text(selectedItem.error ?? selectedItem.result?.reason ?? "正在读取元数据…")
                            .font(.caption)
                            .lineLimit(3)
                        if selectedItem.lrfURL != nil {
                            Label("已匹配 LRF", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.green)
                        }
                    }
                }

                Divider().overlay(borderColor)

                Button(action: model.chooseOutput) {
                    HStack {
                        Image(systemName: "folder")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("选择输出文件夹")
                            Text(model.outputURL?.path(percentEncoded: false) ?? "尚未选择")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                Picker("操作方式", selection: $model.copyFiles) {
                    Text("复制原片").tag(true)
                    Text("移动原片").tag(false)
                }
                .pickerStyle(.segmented)

                Toggle("同时导出匹配的 LRF", isOn: $model.includeLRF).font(.caption)
                Spacer(minLength: 0)

                Button(action: model.sort) {
                    Label("分类导出", systemImage: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.02, green: 0.52, blue: 0.92))
                .disabled(!model.canSort)
            }
            .padding(14)
        }
        .frame(width: 260)
    }
}

struct ClipCard: View {
    let item: MediaItem
    let selected: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.42))
            if let image = item.thumbnail {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: item.isWorking ? "hourglass" : "film")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.25))
            }
            LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
            HStack(spacing: 5) {
                Image(systemName: item.lrfURL == nil ? "film" : "photo.on.rectangle").font(.caption2)
                Text(item.url.deletingPathExtension().lastPathComponent)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(durationText(item.duration)).font(.caption2.monospacedDigit())
            }
            .foregroundStyle(.white.opacity(0.90))
            .padding(7)
        }
        .frame(height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(selected ? (item.result?.profile.color ?? .cyan) : borderColor, lineWidth: selected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
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
    @Binding var selectedID: UUID?
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(profile.color).frame(width: 10, height: 10)
                Text(profile.rawValue).font(.subheadline.bold())
                Spacer()
                Text("\(items.count) 个").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }

            if items.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: profile.symbol).foregroundStyle(profile.color.opacity(0.45))
                    Text("暂无素材").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 88)
                .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(items) { item in
                        ClipCard(item: item, selected: selectedID == item.id)
                            .onTapGesture { selectedID = item.id }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 286, alignment: .top)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 9))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 9).fill(profile.color).frame(height: 3)
        }
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(borderColor, lineWidth: 1))
    }
}

struct ContentView: View {
    @StateObject private var model = SorterModel()
    @State private var selectedID: UUID?

    private var selectedItem: MediaItem? {
        model.items.first { $0.id == selectedID } ?? model.items.first
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("POCKET LOG SORTER")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(model.status.hasPrefix("完成") ? Color.green : Color.secondary)
                Spacer()
                Text("DJI COLOR WORKSPACE")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)

            HStack(alignment: .top, spacing: 10) {
                SidebarView(model: model)
                PreviewView(item: selectedItem).frame(maxWidth: .infinity)
                InspectorView(model: model, selectedItem: selectedItem)
            }
            .frame(height: 400)

            HStack {
                Text("按色彩格式分组").font(.headline)
                Text("点击缩略图可查看判定依据").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.items.count) CLIPS").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(ColorProfile.allCases) { profile in
                        ProfileGroupView(
                            profile: profile,
                            items: model.items.filter { ($0.result?.profile ?? .unknown) == profile },
                            selectedID: $selectedID
                        )
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.visible)
        }
        .padding(10)
        .frame(width: 1320, height: 780)
        .background(appBackground)
        .preferredColorScheme(.dark)
        .onChange(of: model.items.count) { _ in
            if selectedID == nil { selectedID = model.items.first?.id }
        }
    }
}

@main
struct PocketColorSorterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup { ContentView() }
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 1320, height: 780)
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
