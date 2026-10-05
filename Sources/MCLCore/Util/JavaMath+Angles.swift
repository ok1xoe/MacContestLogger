import Foundation

extension JavaMath {

    /// `Math.toRadians`: multiplication by the `DEGREES_TO_RADIANS` constant (JDK 21), not `x * π / 180`
    /// (which yields different bits).
    static func toRadians(_ degrees: Double) -> Double {
        degrees * 0.017453292519943295
    }

    /// `Math.toDegrees`: multiplication by the `RADIANS_TO_DEGREES` constant (JDK 21).
    static func toDegrees(_ radians: Double) -> Double {
        radians * 57.29577951308232
    }
}
