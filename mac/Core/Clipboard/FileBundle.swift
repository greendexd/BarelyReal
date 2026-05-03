import Foundation

/// One file inside a `ClipboardFileBundle`.
public struct ClipboardFile: Equatable {
    public let name: String
    public let bytes: Data

    public init(name: String, bytes: Data) {
        self.name = name
        self.bytes = bytes
    }
}

/// A set of files transferred together over the clipboard channel.
/// Wire format (within a clipboard frame, after the `kind = 3` byte):
///
///   u32 fileCount
///   for each file:
///     u16 nameLen
///     utf8 name           (sanitized: no path separators or NUL)
///     u64 size
///     bytes[size]
public struct ClipboardFileBundle: Equatable {
    public let files: [ClipboardFile]

    public init(files: [ClipboardFile]) {
        self.files = files
    }
}

public enum ClipboardFileBundleError: Error, Equatable {
    case truncated
    case tooManyFiles(Int)
    case nameTooLong(Int)
    case fileTooLarge(UInt64)
    case totalTooLarge(UInt64)
    case invalidName
    case invalidUtf8
}

public enum ClipboardFileBundleCodec {
    public static let maxFiles: Int = 64
    public static let maxNameBytes: Int = 1024
    public static let maxFileBytes: UInt64 = 200_000_000
    public static let maxTotalBytes: UInt64 = 200_000_000

    /// Strip any path separators / NUL / dot-segments from a file name.
    /// Returns `nil` if nothing usable remains (caller should refuse the file).
    public static func sanitizeName(_ raw: String) -> String? {
        // Take only the last component if user passed a path.
        let lastComponent = (raw as NSString).lastPathComponent
        let stripped = lastComponent.replacingOccurrences(of: "\0", with: "")
        let trimmed = stripped.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "." || trimmed == ".." {
            return nil
        }
        let forbidden = CharacterSet(charactersIn: "/\\:")
        var result = ""
        for scalar in trimmed.unicodeScalars {
            if forbidden.contains(scalar) {
                result.append("_")
            } else {
                result.append(Character(scalar))
            }
        }
        let utf8Count = result.utf8.count
        if utf8Count == 0 || utf8Count > maxNameBytes {
            return nil
        }
        return result
    }

    public static func encode(_ bundle: ClipboardFileBundle) -> Data {
        var data = Data()
        data.appendLE(UInt32(bundle.files.count))
        for file in bundle.files {
            let nameBytes = Data(file.name.utf8)
            data.appendLE(UInt16(nameBytes.count))
            data.append(nameBytes)
            data.appendLE(UInt64(file.bytes.count))
            data.append(file.bytes)
        }
        return data
    }

    public static func decode(_ data: Data) throws -> ClipboardFileBundle {
        var cursor = data.startIndex
        let end = data.endIndex

        guard end - cursor >= 4 else { throw ClipboardFileBundleError.truncated }
        let fileCountRaw: UInt32 = data.readLE(at: cursor - data.startIndex)
        cursor += 4
        let fileCount = Int(fileCountRaw)
        if fileCount > maxFiles {
            throw ClipboardFileBundleError.tooManyFiles(fileCount)
        }

        var files: [ClipboardFile] = []
        files.reserveCapacity(fileCount)
        var totalBytes: UInt64 = 0

        for _ in 0..<fileCount {
            guard end - cursor >= 2 else { throw ClipboardFileBundleError.truncated }
            let nameLen: UInt16 = data.readLE(at: cursor - data.startIndex)
            cursor += 2
            let nameLenInt = Int(nameLen)
            if nameLenInt > maxNameBytes {
                throw ClipboardFileBundleError.nameTooLong(nameLenInt)
            }
            guard end - cursor >= nameLenInt else { throw ClipboardFileBundleError.truncated }
            let nameSlice = data[cursor..<(cursor + nameLenInt)]
            cursor += nameLenInt
            guard let name = String(data: nameSlice, encoding: .utf8) else {
                throw ClipboardFileBundleError.invalidUtf8
            }
            guard let safeName = sanitizeName(name) else {
                throw ClipboardFileBundleError.invalidName
            }

            guard end - cursor >= 8 else { throw ClipboardFileBundleError.truncated }
            let size: UInt64 = data.readLE(at: cursor - data.startIndex)
            cursor += 8
            if size > maxFileBytes {
                throw ClipboardFileBundleError.fileTooLarge(size)
            }
            totalBytes &+= size
            if totalBytes > maxTotalBytes {
                throw ClipboardFileBundleError.totalTooLarge(totalBytes)
            }

            let sizeInt = Int(size)
            guard end - cursor >= sizeInt else { throw ClipboardFileBundleError.truncated }
            let bytes = Data(data[cursor..<(cursor + sizeInt)])
            cursor += sizeInt

            files.append(ClipboardFile(name: safeName, bytes: bytes))
        }

        return ClipboardFileBundle(files: files)
    }
}
