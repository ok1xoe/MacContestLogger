import MCLCore
import SwiftUI

/// The rotator's compass (`RotatorWindow.kt:59-69`): a ring, a thin ray to the call's azimuth and the needle of the
/// rotator's azimuth, 0° up, clockwise.
struct RotatorCompass: View {
    let azimuth: Double?
    let target: Int?
    /// The spoken value (the rotator's azimuth and the target), the picture itself has no text.
    var value: String = ""
    var label: String = ""

    var body: some View {
        Canvas { context, size in
            let radius: CGFloat = min(size.width, size.height) / 2 - 4
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let ring = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                              width: radius * 2, height: radius * 2))
            context.stroke(ring, with: .color(Color(nsColor: .separatorColor)), lineWidth: 2)
            if let target {
                context.stroke(Self.ray(Double(target), centre: centre, radius: radius),
                               with: .color(Color(domain: DomainColors.tertiary)), lineWidth: 2)
            }
            if let azimuth {
                context.stroke(Self.ray(azimuth, centre: centre, radius: radius),
                               with: .color(AccentToken.color(.primary, in: context.environment)), lineWidth: 4)
            }
        }
        .frame(width: 180, height: 180)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(verbatim: value))
        .accessibilityAddTraits(.isImage)
    }

    /// Kotlin `ray(deg)`: from the centre to `(c.x + r·sin, c.y − r·cos)`.
    private static func ray(_ degrees: Double, centre: CGPoint, radius: CGFloat) -> Path {
        let radians: Double = degrees * Double.pi / 180
        let dx: CGFloat = radius * CGFloat(sin(radians))
        let dy: CGFloat = radius * CGFloat(cos(radians))
        var path = Path()
        path.move(to: centre)
        path.addLine(to: CGPoint(x: centre.x + dx, y: centre.y - dy))
        return path
    }
}
