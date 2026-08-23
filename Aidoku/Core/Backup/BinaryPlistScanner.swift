//
//  BinaryPlistScanner.swift
//  Aidoku
//
//  Created by Amqx on 8/14/26.
//

import Foundation

/// A minimal random-access reader for binary property lists.
struct BinaryPlistScanner {
    enum Value {
        case bool(Bool)
        case int(Int)
        case double(Double)
        case date(Date)
        case string(String)
        /// An array, set or dictionary, of which only element count is read.
        case container(count: Int)
        /// A value of a type this scanner doesn't decode (data, uid, null).
        case other
    }

    private static let header = Data("bplist00".utf8)
    private static let trailerSize = 32

    private let data: Data
    private let offsetSize: Int
    private let refSize: Int
    private let objectCount: Int
    private let offsetTableOffset: Int

    /// The reference of the top-level object.
    let rootRef: Int

    init?(data: Data) {
        guard
            data.count > Self.header.count + Self.trailerSize,
            data.prefix(Self.header.count) == Self.header
        else {
            return nil
        }

        self.data = data

        let trailer = data.count - Self.trailerSize
        guard
            let offsetSize = Self.readUInt(in: data, at: trailer + 6, size: 1).flatMap({ Int(exactly: $0) }),
            let refSize = Self.readUInt(in: data, at: trailer + 7, size: 1).flatMap({ Int(exactly: $0) }),
            let objectCount = Self.readUInt(in: data, at: trailer + 8, size: 8).flatMap({ Int(exactly: $0) }),
            let rootRef = Self.readUInt(in: data, at: trailer + 16, size: 8).flatMap({ Int(exactly: $0) }),
            let offsetTableOffset = Self.readUInt(in: data, at: trailer + 24, size: 8).flatMap({ Int(exactly: $0) }),
            offsetSize > 0, offsetSize <= 8,
            refSize > 0, refSize <= 8,
            objectCount > 0, rootRef < objectCount,
            offsetTableOffset >= Self.header.count, offsetTableOffset <= trailer,
            // the offset table has to fit between the objects and the trailer. checked by division so that a
            // corrupt file can't overflow the multiplication
            objectCount <= (trailer - offsetTableOffset) / offsetSize
        else {
            return nil
        }

        self.offsetSize = offsetSize
        self.refSize = refSize
        self.objectCount = objectCount
        self.rootRef = rootRef
        self.offsetTableOffset = offsetTableOffset
    }

    /// Decodes a single object.
    func value(for ref: Int) -> Value? {
        guard let offset = objectOffset(for: ref) else { return nil }
        let marker = data[data.startIndex + offset]

        switch marker & 0xf0 {
            case 0x00:
                switch marker {
                    case 0x08: return .bool(false)
                    case 0x09: return .bool(true)
                    default: return .other
                }

            case 0x10: // integer, stored big-endian in 2^(low nibble) bytes
                let size = 1 << Int(marker & 0x0f)
                guard let raw = Self.readUInt(in: data, at: offset + 1, size: size) else { return nil }
                // sizes below eight bytes are unsigned, eight bytes is two's complement
                return .int(size == 8 ? Int(bitPattern: UInt(raw)) : Int(raw))

            case 0x20: // real
                let size = 1 << Int(marker & 0x0f)
                guard let raw = Self.readUInt(in: data, at: offset + 1, size: size) else { return nil }
                switch size {
                    case 4: return .double(Double(Float(bitPattern: UInt32(truncatingIfNeeded: raw))))
                    case 8: return .double(Double(bitPattern: raw))
                    default: return nil
                }

            case 0x30: // date, seconds since the reference date as a big-endian double
                guard let raw = Self.readUInt(in: data, at: offset + 1, size: 8) else { return nil }
                return .date(Date(timeIntervalSinceReferenceDate: Double(bitPattern: raw)))

            case 0x50: // ascii string
                guard
                    let (count, start) = readCount(at: offset, marker: marker),
                    count <= offsetTableOffset - start
                else {
                    return nil
                }
                let bytes = data[(data.startIndex + start)..<(data.startIndex + start + count)]
                return String(data: bytes, encoding: .ascii).map { .string($0) }

            case 0x60: // utf-16be string, count is in characters rather than bytes
                guard
                    let (count, start) = readCount(at: offset, marker: marker),
                    count <= (offsetTableOffset - start) / 2
                else {
                    return nil
                }
                let bytes = data[(data.startIndex + start)..<(data.startIndex + start + count * 2)]
                return String(data: bytes, encoding: .utf16BigEndian).map { .string($0) }

            case 0xa0, 0xc0, 0xd0: // array, set, dictionary
                guard
                    let (count, start) = readCount(at: offset, marker: marker),
                    // the references have to fit in the object table, so that a corrupt file can't report a
                    // count larger than the file could possibly hold
                    count <= (offsetTableOffset - start) / (refSize * (marker & 0xf0 == 0xd0 ? 2 : 1))
                else {
                    return nil
                }
                return .container(count: count)

            default:
                return .other
        }
    }

    /// Reads the key/value reference pairs of a dictionary object without decoding anything.
    func dictionary(for ref: Int) -> [(key: String, value: Int)]? {
        guard let offset = objectOffset(for: ref) else { return nil }
        let marker = data[data.startIndex + offset]
        guard
            marker & 0xf0 == 0xd0,
            let (count, start) = readCount(at: offset, marker: marker),
            count <= (offsetTableOffset - start) / (refSize * 2)
        else {
            return nil
        }

        var entries: [(key: String, value: Int)] = []
        // the count is bounded by the file size but not otherwise trusted, so don't reserve on it directly
        entries.reserveCapacity(min(count, 1024))
        for index in 0..<count {
            guard
                let keyRef = Self.readUInt(in: data, at: start + index * refSize, size: refSize).flatMap({ Int(exactly: $0) }),
                let valueRef = Self.readUInt(in: data, at: start + (count + index) * refSize, size: refSize).flatMap({ Int(exactly: $0) }),
                case let .string(key) = value(for: keyRef)
            else {
                continue
            }
            entries.append((key, valueRef))
        }
        return entries
    }

    private func objectOffset(for ref: Int) -> Int? {
        guard
            ref >= 0, ref < objectCount,
            let offset = Self.readUInt(in: data, at: offsetTableOffset + ref * offsetSize, size: offsetSize)
                .flatMap({ Int(exactly: $0) }),
            offset < offsetTableOffset
        else {
            return nil
        }
        return offset
    }

    /// Reads the element count of a variable-length object, along with the offset of the first element.
    ///
    /// The count is packed into the low nibble of the marker, unless it's too large to fit, in which case an integer
    /// object holding it follows the marker.
    private func readCount(at offset: Int, marker: UInt8) -> (count: Int, start: Int)? {
        let low = Int(marker & 0x0f)
        guard low == 0x0f else { return (low, offset + 1) }

        guard offset + 1 < offsetTableOffset else { return nil }
        let countMarker = data[data.startIndex + offset + 1]
        guard countMarker & 0xf0 == 0x10 else { return nil }

        // readUInt rejects sizes above eight bytes, so the offsets below can't overflow
        let size = 1 << Int(countMarker & 0x0f)
        guard
            let count = Self.readUInt(in: data, at: offset + 2, size: size).flatMap({ Int(exactly: $0) }),
            // swiftlint:disable:next empty_count
            count >= 0,
            offset + 2 + size <= offsetTableOffset
        else {
            return nil
        }
        return (count, offset + 2 + size)
    }

    private static func readUInt(in data: Data, at offset: Int, size: Int) -> UInt64? {
        guard size > 0, size <= 8, offset >= 0, offset + size <= data.count else { return nil }
        var value: UInt64 = 0
        for index in 0..<size {
            value = value << 8 | UInt64(data[data.startIndex + offset + index])
        }
        return value
    }
}
