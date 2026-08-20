import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import AppKit

enum ColorProfile: String, CaseIterable, Identifiable {
    case dlog2 = "D-Log 2"
    case dlog = "D-Log"
    case dlogM = "D-Log M"
    case hlg = "HLG"
    case hdr = "HDR (PQ/Dolby Vision)"
    case normal = "普通 Rec.709"
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
        case .dlog2: return .purple
        case .dlog: return .indigo
        case .dlogM: return .mint
        case .hlg: return .orange
        case .hdr: return .pink
        case .normal: return .blue
        case .unknown: return .secondary
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

@MainActor
final class SorterModel: ObservableObject {
    @Published var items: [MediaItem] = []
    @Published var outputURL: URL?
    @Published var copyFiles = true
    @Published var isImporting = false
    @Published var status = "把视频拖到这里"

    var readyCount: Int { items.filter { !$0.isWorking }.count }
    var canSort: Bool { !items.isEmpty && items.allSatisfy { !$0.isWorking } && outputURL != nil }

    func add(urls: [URL]) {
        let expanded = expand(urls: urls)
        let existing = Set(items.map { $0.url.standardizedFileURL.path })
        let fresh = expanded.filter { !existing.contains($0.standardizedFileURL.path) }
        guard !fresh.isEmpty else { return }
        let newItems = fresh.map { MediaItem(url: $0) }
        items.append(contentsOf: newItems)
        status = "正在分析 \(fresh.count) 个视频…"

        for item in newItems {
            Task {
                let result = await Task.detached { await Detector.inspect(url: item.url) }.value
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].result = result
                    items[index].isWorking = false
                }
                status = items.allSatisfy { !$0.isWorking } ? "分析完成，请选择输出文件夹" : "正在分析… \(readyCount)/\(items.count)"
            }
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .folder]
        panel.prompt = "添加视频"
        panel.message = "选择一个或多个视频，也可以选择整个素材文件夹"
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
        return result
    }

    func chooseOutput() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "选择用于创建分类文件夹的位置"
        if panel.runModal() == .OK { outputURL = panel.url }
    }

    func sort() {
        guard let root = outputURL else { return }
        let fm = FileManager.default
        var successes = 0
        var failures = 0
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
            } catch {
                items[index].error = error.localizedDescription
                failures += 1
            }
        }
        status = failures == 0 ? "完成：已分类 \(successes) 个文件" : "完成 \(successes) 个，失败 \(failures) 个"
    }

    private func uniqueDestination(for source: URL, in folder: URL) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(source.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            let base = source.deletingPathExtension().lastPathComponent
            candidate = folder.appendingPathComponent("\(base)_\(n).\(source.pathExtension)")
            n += 1
        }
        return candidate
    }
}

struct DropZone: View {
    let action: ([URL]) -> Void
    let browseAction: () -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 38))
                .foregroundStyle(targeted ? Color.accentColor : .secondary)
            Text("拖入视频或整个素材文件夹")
                .font(.headline)
            Text("支持 MP4、MOV、M4V")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(action: browseAction) {
                Label("点击选择文件", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 145)
        .background(targeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [7])))
        .dropDestination(for: URL.self) { urls, _ in action(urls); return true } isTargeted: { targeted = $0 }
    }
}

struct ContentView: View {
    @StateObject private var model = SorterModel()

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pocket 色彩分拣器").font(.title2.bold())
                    Text("普通 · D-Log · D-Log 2 · HLG/HDR").foregroundStyle(.secondary)
                }
                Spacer()
                if !model.items.isEmpty {
                    Button("清空") { model.items.removeAll(); model.status = "把视频拖到这里" }
                }
            }

            DropZone(action: model.add, browseAction: model.chooseFiles)

            if !model.items.isEmpty {
                List(model.items) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.result?.profile.symbol ?? "hourglass")
                            .foregroundStyle(item.result?.profile.color ?? .secondary)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.url.lastPathComponent).lineLimit(1)
                            Text(item.error ?? item.result?.reason ?? "正在读取元数据…")
                                .font(.caption).foregroundStyle(item.error == nil ? Color.secondary : Color.red).lineLimit(2)
                        }
                        Spacer()
                        if let profile = item.result?.profile {
                            Text(profile.rawValue).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 5)
                                .background(profile.color.opacity(0.13), in: Capsule()).foregroundStyle(profile.color)
                        } else { ProgressView().controlSize(.small) }
                    }
                    .padding(.vertical, 3)
                    .help(item.result?.metadata ?? "")
                }
                .listStyle(.inset)
                .frame(minHeight: 180)
            }

            VStack(spacing: 10) {
                HStack {
                    Button { model.chooseOutput() } label: { Label("选择输出文件夹", systemImage: "folder") }
                    Text(model.outputURL?.path(percentEncoded: false) ?? "尚未选择")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Picker("操作", selection: $model.copyFiles) {
                        Text("复制（推荐）").tag(true)
                        Text("移动").tag(false)
                    }.pickerStyle(.segmented).frame(width: 190)
                }
                HStack {
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.sort() } label: { Label("开始分类", systemImage: "folder.badge.gearshape") }
                        .buttonStyle(.borderedProminent).disabled(!model.canSort)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 610)
    }
}

@main
struct PocketColorSorterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup { ContentView() }
            .windowStyle(.hiddenTitleBar)
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
