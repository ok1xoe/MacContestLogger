import Foundation
import Testing
@testable import MCLCore

/// The printable error protocol of `IO/`: Java class and `getMessage()` of every error that reaches a
/// status text. Values from the maintainer-only probe (`io-probe.tsv`).
@Suite struct JavaThrowableTests {

    private struct Row: Sendable, CustomStringConvertible {
        let error: any Error & Sendable
        let javaClass: String
        let message: String?
        var description: String { javaClass }
    }

    private static let rows: [Row] = [
        // ADIF.readFile
        Row(error: UncheckedIOError(message: "Nelze načíst ADIF: /x/missing.adi", cause: JavaIOError("/x/missing.adi")),
            javaClass: "java.io.UncheckedIOException", message: "Nelze načíst ADIF: /x/missing.adi"),
        // CAB.read, CAB.readFile
        Row(error: CabrilloReaderError.numberFormat(message: "For input string: \"99999999999\""),
            javaClass: "java.lang.NumberFormatException", message: "For input string: \"99999999999\""),
        Row(error: CabrilloReaderError.unreadable(message: "Nelze načíst Cabrillo: /x/a.log",
                                                  causeClass: "java.nio.file.NoSuchFileException"),
            javaClass: "java.io.UncheckedIOException", message: "Nelze načíst Cabrillo: /x/a.log"),
        Row(error: CabrilloExportError.illegalArgument(message: "no cabrillo"),
            javaClass: "java.lang.IllegalArgumentException", message: "no cabrillo"),
        // ADIF.read
        Row(error: JavaIndexOutOfBoundsError(message: "Range [9, 8) out of bounds for length 13"),
            javaClass: "java.lang.StringIndexOutOfBoundsException", message: "Range [9, 8) out of bounds for length 13"),
        Row(error: LogExportsError.nullPointer(message: "temporal"),
            javaClass: "java.lang.NullPointerException", message: "temporal"),
        // MAL
        Row(error: Utf8Text.MalformedInput(length: 3),
            javaClass: "java.nio.charset.MalformedInputException", message: "Input length = 3"),
        Row(error: JavaIOError(nil, javaClass: "java.net.ConnectException"),
            javaClass: "java.net.ConnectException", message: nil),
        // DB.notADatabase
        Row(error: LogbookError("Nelze otevřít deník: jdbc:sqlite:/x/text.sqlite"),
            javaClass: "cz.ok1xoe.maccontestlogger.logbook.LogbookException",
            message: "Nelze otevřít deník: jdbc:sqlite:/x/text.sqlite"),
    ]

    @Test(arguments: rows)
    private func describesItself(_ row: Row) {
        let described = JavaThrowables.describe(row.error)
        #expect(described.javaClass == row.javaClass)
        #expect(described.message == row.message)
        #expect(JavaThrowables.message(row.error) == IoTexts.template(row.message))
    }

    /// `WsjtxImportMapper` reads `ArrayList.get(0)` (`WsjtxImportMapper.java:28`) — the other index class.
    @Test func wsjtxEmptyListIsIndexOutOfBounds() {
        let error = WsjtxImportMapper.emptyQsoList
        #expect(JavaThrowables.describe(error).javaClass == "java.lang.IndexOutOfBoundsException")
        #expect(JavaThrowables.describe(error).message == "Index 0 out of bounds for length 0")
    }

    @Test func templatePrintsNullForMissingMessage() {
        #expect(IoTexts.template(nil) == "null")
        #expect(IoTexts.template("") == "")
        #expect(JavaThrowables.message(JavaIOError(nil)) == "null")
    }

    /// Foundation file errors get the `java.nio.file` class with only the path (rows `FS.missing`, `FS.denied`).
    @Test func foundationFileErrorsMapToJavaClasses() throws {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/a.adi")
        let error = #expect(throws: (any Error).self) { _ = try Data(contentsOf: missing) }
        let described = JavaThrowables.describe(try #require(error))
        #expect(described.javaClass == "java.nio.file.NoSuchFileException")
        #expect(described.message == missing.path)

        let denied = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadNoPermission.rawValue,
                             userInfo: [NSFilePathErrorKey: "/x/locked.adi"])
        #expect(JavaThrowables.describe(denied).javaClass == "java.nio.file.AccessDeniedException")
        #expect(JavaThrowables.describe(denied).message == "/x/locked.adi")

        // `UnixException.translateToIOException`: EPERM is a `FileSystemException` with the reason.
        let eperm = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM), userInfo: [NSFilePathErrorKey: "/x/a.adi"])
        #expect(JavaThrowables.describe(eperm).javaClass == "java.nio.file.FileSystemException")
        #expect(JavaThrowables.describe(eperm).message == "/x/a.adi: Operation not permitted")

        let other = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteOutOfSpace.rawValue)
        #expect(JavaThrowables.describe(other).javaClass == "java.io.IOException")
        #expect(JavaThrowables.describe(other).message == other.localizedDescription)
    }

    @Test func swiftErrorsDescribeThemselves() {
        struct Odd: Error {}
        #expect(JavaThrowables.describe(Odd()).javaClass == "Swift.Odd")
    }

    /// `Files.readString` lengths (rows `MAL`) — not the `CharsetDecoder` lengths of `readAllLines`.
    @Test(arguments: [
        ("FF", 1), ("41FF42", 1), ("C3", 1), ("41C3", 1), ("C328", 1), ("C0AF", 1), ("E282", 1), ("E28241", 3),
        ("E0809F", 3), ("EDA080", 3), ("EDA041", 3), ("F0", 1), ("F09F", 1), ("F09F98", 1), ("F09F9841", 4),
        ("F09F41", 1), ("F49080", 1), ("F4908080", 4), ("F8888080", 1), ("80", 1), ("EFBBBF41FF", 1),
        ("E241", 2), ("E080", 2), ("E09F", 2), ("C3A9E241", 2), ("EDA0", 1), ("ED9F", 1), ("F041", 1), ("F08F", 1),
        ("F590", 1), ("F490", 1),
    ])
    func readStringMalformedLengthMatchesJava(_ hex: String, _ length: Int) {
        #expect(Utf8Text.readStringMalformedLength(Self.bytes(hex)) == length)
    }

    @Test func validUtf8HasNoMalformedLength() {
        #expect(Utf8Text.readStringMalformedLength(Self.bytes("EFBBBF41C3A1E282ACF09F9880")) == nil)
        #expect(Utf8Text.readStringMalformedLength([]) == nil)
    }

    /// `readFileKeepingBom` carries the length (`ED A0 80` = 3).
    @Test func readFileKeepingBomCarriesTheLength() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bad = dir.appendingPathComponent("bad")
        try Data([0x41, 0xED, 0xA0, 0x80]).write(to: bad)
        let error = #expect(throws: Utf8Text.MalformedInput.self) { try Utf8Text.readFileKeepingBom(bad) }
        #expect(error?.javaMessage == "Input length = 3")
    }

    static func bytes(_ hex: String) -> [UInt8] {
        var out: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            out.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        return out
    }
}
