import Foundation

/// 直接读取 Mach-O 头，判断应用包含 arm64 / x86_64 中的哪些架构。
enum MachOReader {
    static func architectures(of url: URL) -> [String] {
        guard FileManager.default.isReadableFile(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: 8192),
              data.count >= 8 else {
            return []
        }
        try? handle.close()
        return architectures(from: data)
    }

    static func architectures(from data: Data) -> [String] {
        guard data.count >= 8 else { return [] }
        let bytes = [UInt8](data.prefix(8))
        let magic = Array(bytes.prefix(4))

        switch magic {
        case [0xCF, 0xFA, 0xED, 0xFE]:
            return cpuName(readUInt32(data, at: 4, bigEndian: false))
        case [0xFE, 0xED, 0xFA, 0xCF]:
            return cpuName(readUInt32(data, at: 4, bigEndian: true))
        case [0xCE, 0xFA, 0xED, 0xFE]:
            return cpuName(readUInt32(data, at: 4, bigEndian: false))
        case [0xFE, 0xED, 0xFA, 0xCE]:
            return cpuName(readUInt32(data, at: 4, bigEndian: true))
        case [0xCA, 0xFE, 0xBA, 0xBE], [0xCA, 0xFE, 0xBA, 0xBF]:
            return fatArchitectures(data, bigEndian: true, is64: magic[3] == 0xBF)
        case [0xBE, 0xBA, 0xFE, 0xCA], [0xBF, 0xBA, 0xFE, 0xCA]:
            return fatArchitectures(data, bigEndian: false, is64: magic[3] == 0xBF)
        default:
            return []
        }
    }

    private static func fatArchitectures(_ data: Data, bigEndian: Bool, is64: Bool) -> [String] {
        guard let count = readUInt32(data, at: 4, bigEndian: bigEndian) else { return [] }
        let stride = is64 ? 32 : 20
        var result: [String] = []

        for index in 0..<min(Int(count), 32) {
            let offset = 8 + index * stride
            guard let cpuType = readUInt32(data, at: offset, bigEndian: bigEndian) else { break }
            for arch in cpuName(cpuType) where !result.contains(arch) {
                result.append(arch)
            }
        }
        return result
    }

    private static func readUInt32(_ data: Data, at offset: Int, bigEndian: Bool) -> UInt32? {
        guard offset >= 0, data.count >= offset + 4 else { return nil }
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])

        if bigEndian {
            return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        }
        return (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
    }

    private static func cpuName(_ cpuType: UInt32?) -> [String] {
        guard let cpuType else { return [] }
        switch Int32(bitPattern: cpuType) {
        case CPU_TYPE_ARM64:
            return ["arm64"]
        case CPU_TYPE_ARM64_32:
            return ["arm64_32"]
        case CPU_TYPE_X86_64:
            return ["x86_64"]
        case CPU_TYPE_ARM:
            return ["arm"]
        case CPU_TYPE_I386:
            return ["i386"]
        default:
            return []
        }
    }

    private static let CPU_TYPE_ARM64: Int32 = 0x0100_000C
    private static let CPU_TYPE_ARM64_32: Int32 = 0x0200_000C
    private static let CPU_TYPE_X86_64: Int32 = 0x0100_0007
    private static let CPU_TYPE_ARM: Int32 = 12
    private static let CPU_TYPE_I386: Int32 = 7
}
