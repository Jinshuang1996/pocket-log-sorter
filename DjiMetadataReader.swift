import Foundation

// The DJI djmd container/protobuf field mapping is adapted from Ray Lei's
// dlog_color_classifier (MIT License). See THIRD_PARTY_NOTICES.txt.

struct DjiMetadataEvidence {
    let colorGammaSxS: UInt64?
    let recordMode: UInt64?
}

enum DjiMetadataReader {
    enum ReaderError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            if case .invalid(let message) = self { return message }
            return "无法读取 DJI 元数据"
        }
    }

    private struct Box {
        let type: String
        let start: UInt64
        let size: UInt64
        let headerSize: UInt64
        let children: [Box]
        var payloadStart: UInt64 { start + headerSize }
        var end: UInt64 { start + size }
    }

    private struct SampleTable {
        let entryTypes: [String]
        let sampleSizes: [UInt64]
        let chunkOffsets: [UInt64]
        let firstChunk: UInt64
        let samplesPerChunk: UInt64
    }

    private static let containers: Set<String> = ["moov", "trak", "mdia", "minf", "stbl", "edts", "dinf"]

    static func inspect(url: URL) throws -> DjiMetadataEvidence {
        let packet = try readFirstPacket(url: url)
        let fields = parseProto(packet)
        let gamma = value(at: [(2, 0), (2, 0), (3, 0)], field: 1, in: fields)
        let recordMode = value(at: [(2, 0), (3, 0)], field: 5, in: fields)
        return DjiMetadataEvidence(colorGammaSxS: gamma, recordMode: recordMode)
    }

    private static func readFirstPacket(url: URL) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = (attributes[.size] as? NSNumber)?.uint64Value else {
            throw ReaderError.invalid("无法读取文件大小")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let top = try parseChildren(handle, start: 0, end: fileSize)
        if find(top, path: ["moof"]) != nil { throw ReaderError.invalid("暂不支持 fragmented MP4") }
        guard let moov = find(top, path: ["moov"]) else { throw ReaderError.invalid("未找到 MP4 moov 数据") }

        for track in moov.children where track.type == "trak" {
            guard let table = try sampleTable(handle, track: track), table.entryTypes.contains("djmd") else { continue }
            guard let size = table.sampleSizes.first,
                  table.firstChunk > 0,
                  table.firstChunk <= UInt64(table.chunkOffsets.count),
                  table.samplesPerChunk > 0 else {
                throw ReaderError.invalid("DJI sample table 无效")
            }
            let offset = table.chunkOffsets[Int(table.firstChunk - 1)]
            guard size > 0, offset + size <= fileSize else { throw ReaderError.invalid("DJI 数据偏移无效") }
            return try read(handle, offset: offset, count: Int(size))
        }
        throw ReaderError.invalid("未找到 DJI djmd 数据轨")
    }

    private static func parseChildren(_ handle: FileHandle, start: UInt64, end: UInt64) throws -> [Box] {
        var boxes: [Box] = []
        var offset = start
        while offset + 8 <= end {
            let header = try read(handle, offset: offset, count: 8)
            let size32 = try u32(header, 0)
            let type = fourCC(header, 4)
            var size = UInt64(size32)
            var headerSize: UInt64 = 8
            if size32 == 1 {
                size = try u64(read(handle, offset: offset + 8, count: 8), 0)
                headerSize = 16
            } else if size32 == 0 {
                size = end - offset
            }
            guard size >= headerSize, offset + size <= end else { throw ReaderError.invalid("MP4 box \(type) 损坏") }
            let children = containers.contains(type) ? try parseChildren(handle, start: offset + headerSize, end: offset + size) : []
            boxes.append(Box(type: type, start: offset, size: size, headerSize: headerSize, children: children))
            guard size > 0 else { break }
            offset += size
        }
        return boxes
    }

    private static func sampleTable(_ handle: FileHandle, track: Box) throws -> SampleTable? {
        guard let stbl = find([track], path: ["trak", "mdia", "minf", "stbl"]),
              let stsd = child(stbl, "stsd"),
              let stsc = child(stbl, "stsc"),
              let sizeBox = child(stbl, "stsz") ?? child(stbl, "stz2"),
              let offsetBox = child(stbl, "stco") ?? child(stbl, "co64") else { return nil }
        let types = try readStsd(handle, stsd)
        let sizes = sizeBox.type == "stsz" ? try readStsz(handle, sizeBox) : try readStz2(handle, sizeBox)
        let (firstChunk, samplesPerChunk) = try readStsc(handle, stsc)
        let offsets = offsetBox.type == "stco" ? try readStco(handle, offsetBox) : try readCo64(handle, offsetBox)
        return SampleTable(entryTypes: types, sampleSizes: sizes, chunkOffsets: offsets, firstChunk: firstChunk, samplesPerChunk: samplesPerChunk)
    }

    private static func payload(_ handle: FileHandle, _ box: Box) throws -> Data {
        try read(handle, offset: box.payloadStart, count: Int(box.size - box.headerSize))
    }

    private static func readStsd(_ handle: FileHandle, _ box: Box) throws -> [String] {
        let data = try payload(handle, box)
        guard data.count >= 8 else { throw ReaderError.invalid("stsd 数据过短") }
        let count = Int(try u32(data, 4))
        var offset = 8
        var types: [String] = []
        for _ in 0..<count {
            guard offset + 8 <= data.count else { throw ReaderError.invalid("stsd entry 不完整") }
            let size = Int(try u32(data, offset))
            guard size >= 8, offset + size <= data.count else { throw ReaderError.invalid("stsd entry 无效") }
            types.append(fourCC(data, offset + 4))
            offset += size
        }
        return types
    }

    private static func readStsz(_ handle: FileHandle, _ box: Box) throws -> [UInt64] {
        let data = try payload(handle, box)
        guard data.count >= 12 else { throw ReaderError.invalid("stsz 数据过短") }
        let fixed = UInt64(try u32(data, 4))
        let count = Int(try u32(data, 8))
        guard count > 0 else { throw ReaderError.invalid("stsz 无 sample") }
        if fixed > 0 { return Array(repeating: fixed, count: count) }
        guard 12 + count * 4 <= data.count else { throw ReaderError.invalid("stsz 表不完整") }
        return try (0..<count).map { UInt64(try u32(data, 12 + $0 * 4)) }
    }

    private static func readStz2(_ handle: FileHandle, _ box: Box) throws -> [UInt64] {
        let data = try payload(handle, box)
        guard data.count >= 12 else { throw ReaderError.invalid("stz2 数据过短") }
        let bits = data[7]
        let count = Int(try u32(data, 8))
        var result: [UInt64] = []
        switch bits {
        case 4:
            for byte in data.dropFirst(12) {
                result.append(UInt64(byte >> 4)); if result.count == count { break }
                result.append(UInt64(byte & 0x0f)); if result.count == count { break }
            }
        case 8:
            result = data.dropFirst(12).prefix(count).map(UInt64.init)
        case 16:
            guard 12 + count * 2 <= data.count else { throw ReaderError.invalid("stz2 表不完整") }
            result = try (0..<count).map { UInt64(try u16(data, 12 + $0 * 2)) }
        default: throw ReaderError.invalid("不支持的 stz2 位宽")
        }
        guard result.count == count else { throw ReaderError.invalid("stz2 表不完整") }
        return result
    }

    private static func readStsc(_ handle: FileHandle, _ box: Box) throws -> (UInt64, UInt64) {
        let data = try payload(handle, box)
        guard data.count >= 20, try u32(data, 4) > 0 else { throw ReaderError.invalid("stsc 数据无效") }
        return (UInt64(try u32(data, 8)), UInt64(try u32(data, 12)))
    }

    private static func readStco(_ handle: FileHandle, _ box: Box) throws -> [UInt64] {
        let data = try payload(handle, box)
        guard data.count >= 8 else { throw ReaderError.invalid("stco 数据过短") }
        let count = Int(try u32(data, 4))
        guard 8 + count * 4 <= data.count else { throw ReaderError.invalid("stco 表不完整") }
        return try (0..<count).map { UInt64(try u32(data, 8 + $0 * 4)) }
    }

    private static func readCo64(_ handle: FileHandle, _ box: Box) throws -> [UInt64] {
        let data = try payload(handle, box)
        guard data.count >= 8 else { throw ReaderError.invalid("co64 数据过短") }
        let count = Int(try u32(data, 4))
        guard 8 + count * 8 <= data.count else { throw ReaderError.invalid("co64 表不完整") }
        return try (0..<count).map { try u64(data, 8 + $0 * 8) }
    }

    private indirect enum ProtoValue { case integer(UInt64), message([ProtoField]), bytes(Data) }
    private struct ProtoField { let number: UInt64; let wire: UInt64; let value: ProtoValue }

    private static func parseProto(_ data: Data, depth: Int = 0) -> [ProtoField] {
        var fields: [ProtoField] = []
        var offset = 0
        while offset < data.count {
            guard let (key, next) = readVarint(data, offset) else { break }
            offset = next
            let number = key >> 3, wire = key & 7
            guard number > 0 else { break }
            switch wire {
            case 0:
                guard let (value, end) = readVarint(data, offset) else { return fields }
                fields.append(ProtoField(number: number, wire: wire, value: .integer(value))); offset = end
            case 1:
                guard offset + 8 <= data.count else { return fields }
                fields.append(ProtoField(number: number, wire: wire, value: .bytes(data.subdata(in: offset..<(offset + 8))))); offset += 8
            case 2:
                guard let (length, nextOffset) = readVarint(data, offset) else { return fields }
                offset = nextOffset
                guard length <= UInt64(Int.max), offset + Int(length) <= data.count else { return fields }
                let bytes = data.subdata(in: offset..<(offset + Int(length))); offset += Int(length)
                let value: ProtoValue = depth < 8 && !bytes.isEmpty ? .message(parseProto(bytes, depth: depth + 1)) : .bytes(bytes)
                fields.append(ProtoField(number: number, wire: wire, value: value))
            case 5:
                guard offset + 4 <= data.count else { return fields }
                fields.append(ProtoField(number: number, wire: wire, value: .bytes(data.subdata(in: offset..<(offset + 4))))); offset += 4
            default: return fields
            }
        }
        return fields
    }

    private static func readVarint(_ data: Data, _ start: Int) -> (UInt64, Int)? {
        var value: UInt64 = 0, shift: UInt64 = 0
        var offset = start
        while offset < data.count, shift <= 63 {
            let byte = data[offset]; offset += 1
            value |= UInt64(byte & 0x7f) << shift
            if byte < 0x80 { return (value, offset) }
            shift += 7
        }
        return nil
    }

    private static func value(at path: [(UInt64, Int)], field: UInt64, in fields: [ProtoField]) -> UInt64? {
        var current = fields
        for (number, index) in path {
            let messages = current.compactMap { item -> [ProtoField]? in
                guard item.number == number, item.wire == 2, case .message(let nested) = item.value else { return nil }
                return nested
            }
            guard messages.indices.contains(index) else { return nil }
            current = messages[index]
        }
        for item in current where item.number == field && item.wire == 0 {
            if case .integer(let integer) = item.value { return integer }
        }
        return nil
    }

    private static func read(_ handle: FileHandle, offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        guard let data = try handle.read(upToCount: count), data.count == count else { throw ReaderError.invalid("文件读取不完整") }
        return data
    }

    private static func child(_ box: Box, _ type: String) -> Box? { box.children.first { $0.type == type } }
    private static func find(_ boxes: [Box], path: [String]) -> Box? {
        guard let head = path.first else { return nil }
        for box in boxes where box.type == head {
            return path.count == 1 ? box : find(box.children, path: Array(path.dropFirst()))
        }
        return nil
    }

    private static func fourCC(_ data: Data, _ offset: Int) -> String {
        String(bytes: data[offset..<(offset + 4)], encoding: .isoLatin1) ?? "????"
    }
    private static func u16(_ data: Data, _ offset: Int) throws -> UInt16 {
        guard offset + 2 <= data.count else { throw ReaderError.invalid("整数越界") }
        return data[offset..<(offset + 2)].reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
    }
    private static func u32(_ data: Data, _ offset: Int) throws -> UInt32 {
        guard offset + 4 <= data.count else { throw ReaderError.invalid("整数越界") }
        return data[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
    private static func u64(_ data: Data, _ offset: Int) throws -> UInt64 {
        guard offset + 8 <= data.count else { throw ReaderError.invalid("整数越界") }
        return data[offset..<(offset + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}
