import Foundation

private func be32(_ value: UInt32) -> Data {
    Data([UInt8(value >> 24), UInt8(value >> 16), UInt8(value >> 8), UInt8(value)])
}

private func mp4Box(_ type: String, _ payload: Data) -> Data {
    be32(UInt32(payload.count + 8)) + Data(type.utf8) + payload
}

private func varint(_ input: UInt64) -> Data {
    var value = input
    var bytes: [UInt8] = []
    repeat {
        var byte = UInt8(value & 0x7f)
        value >>= 7
        if value > 0 { byte |= 0x80 }
        bytes.append(byte)
    } while value > 0
    return Data(bytes)
}

private func intField(_ number: UInt64, _ value: UInt64) -> Data { varint(number << 3) + varint(value) }
private func messageField(_ number: UInt64, _ payload: Data) -> Data { varint((number << 3) | 2) + varint(UInt64(payload.count)) + payload }
private func gammaPacket(_ value: UInt64) -> Data { messageField(2, messageField(2, messageField(3, intField(1, value)))) }
private func recordPacket(_ value: UInt64) -> Data { messageField(2, messageField(3, intField(5, value))) }

private func fixture(sample: Data) -> Data {
    let ftyp = mp4Box("ftyp", Data("isom\0\0\u{2}\0isom".utf8))
    let mdat = mp4Box("mdat", sample)
    let sampleOffset = UInt32(ftyp.count + 8)
    let full = Data([0, 0, 0, 0])
    let entry = be32(8) + Data("djmd".utf8)
    let stsd = mp4Box("stsd", full + be32(1) + entry)
    let stsz = mp4Box("stsz", full + be32(0) + be32(1) + be32(UInt32(sample.count)))
    let stsc = mp4Box("stsc", full + be32(1) + be32(1) + be32(1) + be32(1))
    let stco = mp4Box("stco", full + be32(1) + be32(sampleOffset))
    let moov = mp4Box("moov", mp4Box("trak", mp4Box("mdia", mp4Box("minf", mp4Box("stbl", stsd + stsz + stsc + stco)))))
    return ftyp + mdat + moov
}

@main
struct DjiMetadataReaderTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cases: [(Data, UInt64?, UInt64?)] = [
            (gammaPacket(22), 22, nil),
            (gammaPacket(2), 2, nil),
            (recordPacket(8), nil, 8)
        ]
        for (index, test) in cases.enumerated() {
            let url = directory.appendingPathComponent("fixture-\(index).mp4")
            try fixture(sample: test.0).write(to: url)
            let result = try DjiMetadataReader.inspect(url: url)
            precondition(result.colorGammaSxS == test.1)
            precondition(result.recordMode == test.2)
        }
        print("DJI metadata tests passed: \(cases.count)")
    }
}
