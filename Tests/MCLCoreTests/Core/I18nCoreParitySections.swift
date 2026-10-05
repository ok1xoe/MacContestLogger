import Foundation
import Testing
@testable import MCLCore

/// Swift side of the sections `i18n.*` of the Java parity suite (maintainer-only probe): `LanguageCatalog.load`
/// over the fuzzer files (string items only), `Translator.translate` and `Translator.format` under `en_US` (`.`)
/// and `cs_CZ` (`,`); a Java format exception = `nil`.
enum I18nCoreParitySections {

    typealias Ctx = JavaCoreParityFixture.Ctx
    typealias Rows = JavaCoreParityFixture.Rows
    typealias X = JavaCoreParityFixture
    typealias F = JavaIoParityFixture

    static let names: [String] = ["i18n.LOAD", "i18n.FMT"]

    static func compute(_ name: String, _ path: String, _ f: [String], _ ctx: Ctx) throws -> Rows {
        switch name {
        case "i18n.LOAD": return [(path, try load(f, ctx))]
        case "i18n.FMT": return [(path, try format(f))]
        default: throw X.Malformed(text: "unknown item \(name)")
        }
    }

    static func load(_ f: [String], _ ctx: Ctx) throws -> [String] {
        let file: String = try ctx.temporaryDirectory() + "/lang_fuzz.json"
        try X.write(try X.bytes(hex: f[0]), to: file)
        defer { try? FileManager.default.removeItem(atPath: file) }
        let translations: LanguageCatalog.Translations = LanguageCatalog.load(file)
        let queries: [String] = try X.list(f, from: 1).items
        var out: [String] = [String(translations.count)]
        for entry in translations.sortedEntries {
            out.append(F.tx(entry.key))
            out.append(F.tx(entry.value))
        }
        let translator = Translator(language: "xx", translations: translations)
        for query in queries {
            out.append(F.tx(translator.translate(query)))
        }
        return out
    }

    static func arg(_ field: String) throws -> Translator.Arg {
        let value = String(field.dropFirst(2))
        switch field.prefix(2) {
        case "i:", "l:": return .int(try X.int(value))
        case "d:": return .double(try X.double(bits: value))
        case "s:": return .string(X.text(value))
        case "n:": return .string(nil)
        default: throw X.Malformed(text: field)
        }
    }

    static func format(_ f: [String]) throws -> [String] {
        let pattern: String = X.text(f[0]) ?? ""
        let args: [Translator.Arg] = try f.dropFirst().map(arg)
        var out: [String] = []
        for separator in [".", ","] {
            out.append(Translator.format(pattern, args, decimalSeparator: separator).map { F.tx($0) } ?? "THROW")
        }
        return out
    }
}
