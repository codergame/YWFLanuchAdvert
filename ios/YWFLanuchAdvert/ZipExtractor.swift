import Foundation

enum ZipExtractor {
    static func unzip(file: URL, to directory: URL) throws {
        let data = try Data(contentsOf: file)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var offset = 0
        let bytes = [UInt8](data)
        while offset + 30 <= bytes.count {
            let signature = read32(bytes, offset)
            if signature == 0x02014b50 || signature == 0x06054b50 {
                break
            }
            guard signature == 0x04034b50 else {
                throw ZipError("zip 头损坏")
            }
            let flags = read16(bytes, offset + 6)
            let method = read16(bytes, offset + 8)
            let compressedSize = Int(read32(bytes, offset + 18))
            let uncompressedSize = Int(read32(bytes, offset + 22))
            let nameLength = Int(read16(bytes, offset + 26))
            let extraLength = Int(read16(bytes, offset + 28))
            let nameStart = offset + 30
            if (flags & 0x1) != 0 || (flags & 0x8) != 0 {
                throw ZipError("不支持加密或延迟写长度的 zip")
            }
            guard nameStart + nameLength + extraLength + compressedSize <= bytes.count else {
                throw ZipError("zip 条目越界")
            }
            let nameData = Data(bytes[nameStart..<(nameStart + nameLength)])
            guard let name = String(data: nameData, encoding: .utf8),
                  !name.isEmpty,
                  !name.contains(".."),
                  !name.hasPrefix("/"),
                  !name.hasPrefix("\\") else {
                throw ZipError("zip 路径非法")
            }
            let destination = directory.appendingPathComponent(name)
            let rootPath = directory.standardizedFileURL.path
            let fullPath = destination.standardizedFileURL.path
            if fullPath != rootPath && !fullPath.hasPrefix(rootPath + "/") {
                throw ZipError("zip 路径非法")
            }
            if name.hasSuffix("/") {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            } else {
                let payloadStart = nameStart + nameLength + extraLength
                let payload = Data(bytes[payloadStart..<(payloadStart + compressedSize)])
                let raw: Data
                if method == 0 {
                    raw = payload
                } else if method == 8 {
                    raw = try inflate(payload, expected: uncompressedSize)
                } else {
                    throw ZipError("不支持的压缩方式")
                }
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try raw.write(to: destination, options: .atomic)
            }
            offset = nameStart + nameLength + extraLength + compressedSize
        }
    }

    private static func inflate(_ payload: Data, expected: Int) throws -> Data {
        let capacity = expected > 0 ? expected : max(payload.count * 2, 64)
        var output = Data(count: capacity)
        let written: Int = try output.withUnsafeMutableBytes { destination in
            try payload.withUnsafeBytes { source in
                guard let src = source.bindMemory(to: UInt8.self).baseAddress,
                      let dst = destination.bindMemory(to: UInt8.self).baseAddress else {
                    throw ZipError("zip 解压失败")
                }
                var length = 0
                let status = ywf_inflate_raw(src, source.count, dst, destination.count, &length)
                if status != 0 {
                    throw ZipError("zip 解压失败")
                }
                return length
            }
        }
        return output.prefix(written)
    }

    private static func read16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func read32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}

struct ZipError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
