import CryptoKit
import Foundation
import Testing
@testable import MCLCore

/// Test `JavaRandom` (`java.util.Random`) against JDK 21.0.2 (maintainer-only probe,
/// rows `R.*`). The port of `CwDecoderTest` needs it (`new Random(1)`, `nextGaussian` as noise).
/// `nextGaussian` stands on `StrictMath.log` (fdlibm) — `JavaRandom` carries its port, so the match is
/// **bitwise**, no tolerance (a fingerprint of 200,000 values per seed).
@Suite struct JavaRandomTests {

    /// Row = `kind seed [bound] values…`; double values as `Long.toHexString(doubleToRawLongBits)`.
    static let measured = """
nextInt 0 -1155484576 -723955400 1033096058 -1690734402 -1557280266 1327362106 -1930858313 502539523
nextIntBound 0 1 0 0 0 0 0 0
nextIntBound 0 2 1 1 0 1 1 0
nextIntBound 0 3 0 1 1 2 2 2
nextIntBound 0 7 5 2 4 2 4 0
nextIntBound 0 10 0 8 9 7 5 3
nextIntBound 0 100 60 48 29 47 15 53
nextIntBound 0 1073741824 784870680 892752974 258274014 651058223 684421757 331840526
nextIntBound 0 1073741825 516548029 663681053 251269761 715581077 542832677 827187473
nextIntBound 0 2147483647 1569741360 1785505948 516548029 1302116447 1368843515 663681053
nextDouble 0 3fe764168ea6ca89 3fcec9e5b3672e14 3fe465b93a78ef81 3fe19d2e10efa128 3fe31f174640953b 3fd55373440b5f04
nextGaussian 0 3fe9ae59d1d6f861 bfecd9772eb2e0c8 4000a5b9cca3a4b8 3fe870cf65026a96 3fef81a273668e4a bffaef41b15175aa
mixed 0 3fe9ae59d1d6f861 -1557280266 bfecd9772eb2e0c8 3
gaussianRun 0 200000 f13a81bdf8a1dfb0f3f30aab7e25b88abffd1e9a9fbc105d4de23dc803c15f06
nextInt 1 -1155869325 431529176 1761283695 1749940626 892128508 155629808 1429008869 -1465154083
nextIntBound 1 1 0 0 0 0 0 0
nextIntBound 1 2 1 0 0 0 0 0
nextIntBound 1 3 0 1 1 0 2 1
nextIntBound 1 7 4 4 1 0 6 6
nextIntBound 1 10 5 8 7 3 4 4
nextIntBound 1 100 85 88 47 13 54 4
nextIntBound 1 1073741824 784774492 107882294 440320923 437485156 223032127 38907452
nextIntBound 1 1073741825 215764588 880641847 874970313 446064254 77814904 714504434
nextIntBound 1 2147483647 1569548985 215764588 880641847 874970313 446064254 77814904
nextDouble 1 3fe7635aa8cdc4e6 3fda3ec39684df98 3fca96666128d71c 3fd54b3c7a8ab85c 3feef7db3daf9843 3f790e549c66e000
nextGaussian 1 3ff8fc3c669aa4c1 bfe3763b5ee2e541 bff175ab5e5bb186 bfe3fc3b989cfc86 bff1e47cef7b6c24 bffa887c6af9fb4d
mixed 1 3ff8fc3c669aa4c1 892128508 bfe3763b5ee2e541 4
gaussianRun 1 200000 c61a47007c731c31e8e88bf51546ccf88f515c1dfa0eac1a5c8444b219824873
nextInt 42 -1170105035 234785527 -1360544799 205897768 1325939940 -248792245 1190043011 -1255373459
nextIntBound 42 1 0 0 0 0 0 0
nextIntBound 42 2 1 0 1 0 0 1
nextIntBound 42 3 2 0 0 2 0 1
nextIntBound 42 7 1 5 6 3 5 4
nextIntBound 42 10 0 3 8 4 0 5
nextIntBound 42 100 30 63 48 84 70 25
nextIntBound 42 1073741824 781215565 58696381 733605624 51474442 331484985 1011543762
nextIntBound 42 1073741825 117392763 102948884 662969970 595021505 196118093 969067502
nextIntBound 42 2147483647 1562431130 117392763 1467211248 102948884 662969970 2023087525
nextDouble 42 3fe74833a06ff457 3fe5dcf778622e01 3fd3c20f3f12bbb4 3fd1bba76b52c856 3fe54c2d50bb0864 3fece86cf39c2cbe
nextGaussian 42 3ff2453e82115d86 3fed6bca38120847 bfee654eb7a040c2 bff1b63b72513280 3fd1fb89a19b83af 3fe5e86e10aad3bc
mixed 42 3ff2453e82115d86 1325939940 3fed6bca38120847 5
gaussianRun 42 200000 2f90eb3d215b972c05f214e3cedcfcf1ee96a908452661072f30a21532377c91
nextInt 44319 759471996 -1354321717 -367396970 145417997 805798770 1574464502 -2100387561 1879275878
nextIntBound 44319 1 0 0 0 0 0 0
nextIntBound 44319 2 0 1 1 0 0 0
nextIntBound 44319 3 0 1 1 2 0 1
nextIntBound 44319 7 5 5 4 5 0 1
nextIntBound 44319 10 8 9 3 8 5 1
nextIntBound 44319 100 98 89 63 98 85 51
nextIntBound 44319 1073741824 189867999 735161394 981892581 36354499 201449692 393616125
nextIntBound 44319 1073741825 379735998 72708998 402899385 787232251 939637939 358371756
nextIntBound 44319 2147483647 379735998 1470322789 1963785163 72708998 402899385 787232251
nextDouble 44319 3fc6a24fb5e8d618 3fed433ef0455738 3fc803c1abbb0d7c 3fe059d423801bcb 3fe6875cbfeb4329 3fe2f62e7155c51a
nextGaussian 44319 bff5eb3b3dde780e 3fa89eee1fd5a6df 3ffa1c633b8cb23c 3fe7b07cfa8fd0b0 3fc75b538cd9d133 3f955eba730ce21e
mixed 44319 bff5eb3b3dde780e -1271208477 3fa89eee1fd5a6df 4
gaussianRun 44319 200000 4c21bfea9f9f624bd70c1ce2e6fe6096183931ce4b1a6b92f7629daadedbc6ce
nextInt -1 1155099827 1887904451 52699159 -1941176418 -1451336087 -1714570420 1788588954 1714930956
nextIntBound -1 1 0 0 0 0 0 0
nextIntBound -1 2 0 0 0 1 1 1
nextIntBound -1 3 2 2 0 2 2 0
nextIntBound -1 7 3 6 4 6 6 4
nextIntBound -1 10 3 5 9 9 4 8
nextIntBound -1 100 13 25 79 39 4 38
nextIntBound -1 1073741824 288774956 471976112 13174789 588447719 710907802 645099219
nextIntBound -1 1073741825 577549913 943952225 26349579 894294477 857465478 121412731
nextIntBound -1 2147483647 577549913 943952225 26349579 1176895439 1421815604 1290198438
nextDouble -1 3fd1365b2708722c 3f8921011897ff00 3fe52fcbccce6dda 3fdaa6ece6637c50 3fea6ff37873c9c7 3fe9cb0ea27a675a
nextGaussian -1 3ffc90b7b3790a3a bfed740e27d7f93c 3fdf2a0338e45a13 3fdd3daa8a1780ed 3ffb32df66dd7991 3fdcf0e9905364be
mixed -1 3ffc90b7b3790a3a -746611766 bfed740e27d7f93c 1
gaussianRun -1 200000 8bfbe4bc61c3f5c9e7f8dd72c7c8b9254aab864eb24651cc25f2a6a19f61d22c
nextInt -9223372036854775808 -1155484576 -723955400 1033096058 -1690734402 -1557280266 1327362106 -1930858313 502539523
nextIntBound -9223372036854775808 1 0 0 0 0 0 0
nextIntBound -9223372036854775808 2 1 1 0 1 1 0
nextIntBound -9223372036854775808 3 0 1 1 2 2 2
nextIntBound -9223372036854775808 7 5 2 4 2 4 0
nextIntBound -9223372036854775808 10 0 8 9 7 5 3
nextIntBound -9223372036854775808 100 60 48 29 47 15 53
nextIntBound -9223372036854775808 1073741824 784870680 892752974 258274014 651058223 684421757 331840526
nextIntBound -9223372036854775808 1073741825 516548029 663681053 251269761 715581077 542832677 827187473
nextIntBound -9223372036854775808 2147483647 1569741360 1785505948 516548029 1302116447 1368843515 663681053
nextDouble -9223372036854775808 3fe764168ea6ca89 3fcec9e5b3672e14 3fe465b93a78ef81 3fe19d2e10efa128 3fe31f174640953b 3fd55373440b5f04
nextGaussian -9223372036854775808 3fe9ae59d1d6f861 bfecd9772eb2e0c8 4000a5b9cca3a4b8 3fe870cf65026a96 3fef81a273668e4a bffaef41b15175aa
mixed -9223372036854775808 3fe9ae59d1d6f861 -1557280266 bfecd9772eb2e0c8 3
gaussianRun -9223372036854775808 200000 f13a81bdf8a1dfb0f3f30aab7e25b88abffd1e9a9fbc105d4de23dc803c15f06
"""

    private static func hex(_ value: Double) -> String {
        String(value.bitPattern, radix: 16)
    }

    @Test func sequencesMatchJava() {
        var checked = 0
        for line in Self.measured.split(separator: "\n") {
            let fields: [String] = line.split(separator: " ").map(String.init)
            guard fields.count > 2, let seed = Int64(fields[1]) else { continue }
            var random = JavaRandom(seed: seed)
            let kind: String = fields[0]
            let actual: String
            let expected: String
            switch kind {
            case "nextInt":
                expected = fields[2...].joined(separator: " ")
                actual = (0..<8).map { _ in String(random.nextInt()) }.joined(separator: " ")
            case "nextIntBound":
                let bound = Int32(fields[2])!
                expected = fields[3...].joined(separator: " ")
                actual = (0..<6).map { _ in String(random.nextInt(bound: bound)) }.joined(separator: " ")
            case "nextDouble":
                expected = fields[2...].joined(separator: " ")
                actual = (0..<6).map { _ in Self.hex(random.nextDouble()) }.joined(separator: " ")
            case "nextGaussian":
                expected = fields[2...].joined(separator: " ")
                actual = (0..<6).map { _ in Self.hex(random.nextGaussian()) }.joined(separator: " ")
            case "mixed":
                expected = fields[2...].joined(separator: " ")
                let first: String = Self.hex(random.nextGaussian())
                let second: String = String(random.nextInt())
                let third: String = Self.hex(random.nextGaussian())
                let fourth: String = String(random.nextInt(bound: 10))
                actual = [first, second, third, fourth].joined(separator: " ")
            case "gaussianRun":
                let count = Int(fields[2])!
                expected = fields[3]
                var hasher = SHA256()
                for _ in 0..<count {
                    hasher.update(data: Data((Self.hex(random.nextGaussian()) + "\n").utf8))
                }
                actual = hasher.finalize().map { byte in
                    let text = String(byte, radix: 16)
                    return byte < 16 ? "0" + text : text
                }.joined()
            default:
                Issue.record("unknown row \(line)")
                continue
            }
            #expect(actual == expected, "\(kind) seed \(seed)")
            checked += 1
        }
        #expect(checked == 84)
    }

    /// `StrictMath.log` (fdlibm) at the edges, bitwise (`SL.log`: input → result as `doubleToRawLongBits`):
    /// zeros, negatives, infinity, NaN (for NaN only `isNaN`, the sign of NaN depends on the processor), 1,
    /// the smallest subnormal, the neighbourhood of 1 (branch `|f| < 2^-20`) and ordinary values.
    @Test func strictLogMatchesJava() {
        let measured: [(UInt64, UInt64)] = [
            (0x0000_0000_0000_0000, 0xFFF0_0000_0000_0000),
            (0x8000_0000_0000_0000, 0xFFF0_0000_0000_0000),
            (0xBFF0_0000_0000_0000, 0x7FF8_0000_0000_0000),
            (0x7FF0_0000_0000_0000, 0x7FF0_0000_0000_0000),
            (0x7FF8_0000_0000_0000, 0x7FF8_0000_0000_0000),
            (0x3FF0_0000_0000_0000, 0x0000_0000_0000_0000),
            (0x0000_0000_0000_0001, 0xC087_4385_446D_71C3),
            (0x3CB0_0000_0000_0000, 0xC042_0596_6F2B_4F12),
            (0x3FE0_0000_0000_0000, 0xBFE6_2E42_FEFA_39EF),
            (0x01A5_6E1F_C2F8_F359, 0xC085_9634_47F8_7FB5),
            (0x3FEF_FFFF_FFFF_FFFF, 0xBCA0_0000_0000_0000),
            (0x3FF0_0000_0000_0001, 0x3CAF_FFFF_FFFF_FFFF),
            (0x3FE6_6666_6666_6666, 0xBFD6_D3C3_24E1_3F50),
            (0x4000_0000_0000_0000, 0x3FE6_2E42_FEFA_39EF),
        ]
        for (input, expected) in measured {
            let actual: Double = JavaRandom.strictLog(Double(bitPattern: input))
            let wanted = Double(bitPattern: expected)
            if wanted.isNaN {
                #expect(actual.isNaN, "log(\(String(input, radix: 16)))")
            } else {
                #expect(actual.bitPattern == expected, "log(\(String(input, radix: 16)))")
            }
        }
    }
}
