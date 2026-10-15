import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The built-in RTTY modem's engine pane under a receiver's text in the Digital Interface (N1MM's MMTTY engine
/// window; adapted from RYRY's spectrum and waterfall views): the line spectrum and the waterfall with the mark
/// (yellow) and space (orange) markers, MMTTY's XY scope, the level against the squelch, and the shift, speed,
/// squelch and range choices. A click puts the mark under the pointer, the right button sets a notch, the wheel moves
/// the squelch threshold.
struct BuiltinEnginePane: View {
    let engine: BuiltinEngineModel
    let language: LanguageModel
    /// The slot a profile is being saved into (the name prompt is shown), `nil` = none.
    @State private var savingSlot: Int?
    @State private var profileName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            controls
            if let error = engine.profileError {
                Text(verbatim: error)
                    .windowFont(12)
                    .foregroundStyle(Color(domain: DomainColors.dupe))
            }
            if let error = engine.audioError {
                Text(verbatim: error)
                    .windowFont(12)
                    .foregroundStyle(Color(domain: DomainColors.dupe))
            }
            HStack(alignment: .top, spacing: 4) {
                VStack(spacing: 0) {
                    spectrum
                        .frame(height: 56)
                    waterfall
                        .frame(minHeight: 70, maxHeight: 120)
                }
                .overlay(EnginePointerArea(
                    label: language.tr("Spektrum a vodopád: klik nastaví mark, pravé tlačítko zářez, kolečko squelch"),
                    onClick: { engine.click(atFraction: $0) },
                    onRightClick: { engine.notch(atFraction: $0) },
                    onWheel: { engine.adjustSquelch(steps: $0) }))
                if engine.xyEnabled {
                    xyScope
                        .frame(width: 126, height: 126)
                }
            }
        }
        .onAppear { engine.start() }
        .onDisappear { engine.stop() }
        .alert(language.tr("Uložit profil modemu"), isPresented: Binding(get: { savingSlot != nil },
                                                                       set: { if !$0 { savingSlot = nil } })) {
            TextField(language.tr("Název profilu"), text: $profileName)
            Button(language.tr("Uložit")) {
                if let slot = savingSlot {
                    engine.saveProfile(slot, name: profileName)
                }
                savingSlot = nil
            }
            Button(language.tr("Zrušit"), role: .cancel) {
                savingSlot = nil
            }
        }
    }

    /// MMTTY's profiles: load one onto this receiver, save the receiver's setup into a slot, clear a slot.
    private var profileMenu: some View {
        let slots: [BuiltinModemProfile?] = engine.profiles
        return Menu {
            Section(language.tr("Načíst")) {
                ForEach(Array(slots.enumerated()), id: \.offset) { index, profile in
                    if let profile {
                        Button(String(index + 1) + ": " + profile.name) {
                            engine.loadProfile(index)
                        }
                    }
                }
            }
            Menu(language.tr("Uložit do")) {
                ForEach(Array(slots.enumerated()), id: \.offset) { index, profile in
                    Button(String(index + 1) + ": " + (profile?.name ?? "—")) {
                        profileName = profile?.name ?? ""
                        savingSlot = index
                    }
                }
            }
            Menu(language.tr("Smazat")) {
                ForEach(Array(slots.enumerated()), id: \.offset) { index, profile in
                    if let profile {
                        Button(String(index + 1) + ": " + profile.name) {
                            engine.deleteProfile(index)
                        }
                    }
                }
            }
        } label: {
            Text(verbatim: language.tr("Profil")).windowFont(12)
        }
        .fixedSize()
        .help(language.tr("Profily modemu: posun, rychlost, demodulátor, AFC/NET, filtry (makro {PROFILEn})"))
        .accessibilityIdentifier("builtin.profiles")
    }

    private var demodulatorMenu: some View {
        Menu {
            ForEach(BuiltinRttyChannel.demodulators, id: \.self) { name in
                Button(name.uppercased() + (name == engine.demodulator ? " ✓" : "")) {
                    engine.setDemodulator(name)
                }
            }
        } label: {
            Text(verbatim: engine.demodulator.uppercased()).windowFont(12)
        }
        .fixedSize()
        .help(language.tr("Demodulátor MMTTY (IIR, FIR, PLL, FFT)"))
        .accessibilityIdentifier("builtin.demodulator")
    }

    // MARK: - controls

    private var controls: some View {
        let tuning: BuiltinRttyChannel.Tuning = engine.tuning
        return HStack(spacing: 8) {
            Text(verbatim: "M " + String(Int(tuning.markHz.rounded())) + "  S "
                 + String(Int((tuning.markHz + tuning.shiftHz).rounded())))
                .windowFont(12, design: .monospaced)
                .accessibilityIdentifier("builtin.markSpace")
            Menu {
                ForEach(BuiltinRttyChannel.shifts, id: \.self) { shift in
                    Button(String(Int(shift)) + " Hz" + (shift == tuning.shiftHz ? " ✓" : "")) {
                        engine.setShift(shift)
                    }
                }
            } label: {
                Text(verbatim: language.tr("Posun") + " " + String(Int(tuning.shiftHz.rounded()))).windowFont(12)
            }
            .fixedSize()
            .help(language.tr("Posun mezi mark a space"))
            .accessibilityIdentifier("builtin.shift")
            Menu {
                ForEach(BuiltinRttyChannel.modes, id: \.name) { mode in
                    Button(Self.baudText(mode.baud) + " Bd" + (abs(mode.baud - tuning.baud) < 0.01 ? " ✓" : "")) {
                        engine.setBaud(mode.baud)
                    }
                }
            } label: {
                Text(verbatim: Self.baudText(tuning.baud) + " Bd").windowFont(12)
            }
            .fixedSize()
            .help(language.tr("Rychlost RTTY"))
            .accessibilityIdentifier("builtin.baud")
            demodulatorMenu
            profileMenu
            Toggle(isOn: Binding(get: { engine.squelchOn }, set: { engine.setSquelch($0) })) {
                Text(verbatim: "SQ").windowFont(12)
            }
            .toggleStyle(.button)
            .help(language.tr("Squelch: text jen při signálu nad prahem (kolečko nad vodopádem mění práh)"))
            .accessibilityLabel(language.tr("Squelch"))
            Toggle(isOn: Binding(get: { engine.xyEnabled }, set: { engine.setXY($0) })) {
                Text(verbatim: "XY").windowFont(12)
            }
            .toggleStyle(.button)
            .help(language.tr("XY osciloskop: mark proti space, správně naladěný signál je kříž"))
            .accessibilityLabel(language.tr("XY osciloskop"))
            Menu {
                ForEach(Array(BuiltinEngineModel.ranges.enumerated()), id: \.offset) { _, range in
                    Button(String(Int(range.from)) + "–" + String(Int(range.to)) + " Hz") {
                        engine.setRange(from: range.from, to: range.to)
                    }
                }
            } label: {
                Text(verbatim: String(Int(engine.fromHz)) + "–" + String(Int(engine.toHz)) + " Hz").windowFont(12)
            }
            .fixedSize()
            .help(language.tr("Rozsah spektra a vodopádu"))
            .accessibilityIdentifier("builtin.range")
            levelMeter
        }
    }

    static func baudText(_ baud: Double) -> String {
        baud == baud.rounded() ? String(Int(baud)) : String(format: "%.2f", baud)
    }

    /// The demodulator's level against the squelch threshold (green when the squelch is open).
    private var levelMeter: some View {
        let fraction: Double = min(max(engine.level / 32_768 * 4, 0), 1)
        let threshold: Double = min(max(engine.squelchLevel / 32_768 * 4, 0), 1)
        return Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.15)))
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width * fraction, height: size.height)),
                         with: .color(engine.squelchOpen ? .green : .gray))
            var line = Path()
            line.move(to: CGPoint(x: size.width * threshold, y: 0))
            line.addLine(to: CGPoint(x: size.width * threshold, y: size.height))
            context.stroke(line, with: .color(.red), lineWidth: 1)
        }
        .frame(width: 70, height: 10)
        .accessibilityElement()
        .accessibilityLabel(language.tr("Úroveň signálu"))
        .accessibilityValue(Text(verbatim: String(Int(fraction * 100)) + " %"))
    }

    // MARK: - displays

    private func x(_ hz: Double, _ width: CGFloat) -> CGFloat {
        CGFloat(engine.fraction(ofHz: hz)) * width
    }

    private func markers(_ context: GraphicsContext, _ size: CGSize, dashed: Bool) {
        let tuning: BuiltinRttyChannel.Tuning = engine.tuning
        let pairs: [(Double, Color)] = [(tuning.markHz, .yellow), (tuning.markHz + tuning.shiftHz, .orange)]
        for (hz, color) in pairs {
            var path = Path()
            let position: CGFloat = x(hz, size.width)
            path.move(to: CGPoint(x: position, y: 0))
            path.addLine(to: CGPoint(x: position, y: size.height))
            context.stroke(path, with: .color(color.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 1, dash: dashed ? [4, 3] : []))
        }
    }

    private var spectrum: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.08)))
            var hz: Double = (engine.fromHz / 500).rounded(.up) * 500
            while hz < engine.toHz {
                var grid = Path()
                let position: CGFloat = x(hz, size.width)
                grid.move(to: CGPoint(x: position, y: 0))
                grid.addLine(to: CGPoint(x: position, y: size.height))
                context.stroke(grid, with: .color(.white.opacity(0.12)), lineWidth: 1)
                context.draw(Text(verbatim: String(Int(hz))).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)),
                             at: CGPoint(x: position, y: 7))
                hz += 500
            }
            let line: [Float] = engine.waterfall.spectrumLine
            if line.count > 1 {
                var path = Path()
                let step: CGFloat = size.width / CGFloat(line.count - 1)
                for (index, value) in line.enumerated() {
                    let point = CGPoint(x: CGFloat(index) * step,
                                        y: size.height - 2 - CGFloat(max(0, min(1, value))) * (size.height - 6))
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
                context.stroke(path, with: .color(.green), lineWidth: 1.2)
            }
            markers(context, size, dashed: true)
        }
        .accessibilityElement()
        .accessibilityLabel(language.tr("Spektrum"))
    }

    private var waterfall: some View {
        let frame: Int = engine.frame
        return Canvas { context, size in
            _ = frame
            if let image = Self.image(engine.waterfall) {
                context.draw(Image(decorative: image, scale: 1), in: CGRect(origin: .zero, size: size))
            } else {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            }
            markers(context, size, dashed: false)
        }
        .accessibilityElement()
        .accessibilityLabel(language.tr("Vodopád"))
    }

    private var xyScope: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.85)))
            let points = engine.xyPoints
            let scale: Float = max(0.0001, points.map { max(abs($0.x), abs($0.y)) }.max() ?? 1)
            var dots = Path()
            for point in points {
                let px: CGFloat = size.width / 2 + CGFloat(point.x / scale) * size.width * 0.45
                let py: CGFloat = size.height / 2 - CGFloat(point.y / scale) * size.height * 0.45
                dots.addEllipse(in: CGRect(x: px - 0.8, y: py - 0.8, width: 1.6, height: 1.6))
            }
            context.fill(dots, with: .color(.green))
        }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.gray.opacity(0.6)))
        .accessibilityElement()
        .accessibilityLabel(language.tr("XY osciloskop"))
    }

    /// The waterfall's pixels as an image (RGBA bytes, the newest row on top).
    static func image(_ waterfall: BuiltinWaterfall) -> CGImage? {
        let data: Data = waterfall.pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: waterfall.width, height: waterfall.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: waterfall.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                           | CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// The pointer over the engine pane (an AppKit island): the left button, the right button and the wheel as positions
/// across the width (0…1).
struct EnginePointerArea: NSViewRepresentable {
    let label: String
    let onClick: @MainActor (Double) -> Void
    let onRightClick: @MainActor (Double) -> Void
    let onWheel: @MainActor (Int) -> Void

    final class PointerView: NSView {
        var onClick: (@MainActor (Double) -> Void)?
        var onRightClick: (@MainActor (Double) -> Void)?
        var onWheel: (@MainActor (Int) -> Void)?
        private var wheelRemainder: CGFloat = 0

        private func fraction(_ event: NSEvent) -> Double {
            let point: NSPoint = convert(event.locationInWindow, from: nil)
            return bounds.width > 0 ? Double(point.x / bounds.width) : 0
        }

        override func mouseDown(with event: NSEvent) {
            onClick?(fraction(event))
        }

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?(fraction(event))
        }

        override func scrollWheel(with event: NSEvent) {
            guard event.momentumPhase.isEmpty else { return }
            if event.hasPreciseScrollingDeltas {
                wheelRemainder += event.scrollingDeltaY
                while abs(wheelRemainder) >= 12 {
                    onWheel?(wheelRemainder > 0 ? 1 : -1)
                    wheelRemainder -= wheelRemainder > 0 ? 12 : -12
                }
            } else if abs(event.scrollingDeltaY) > 0.1 {
                onWheel?(event.scrollingDeltaY > 0 ? 1 : -1)
            }
        }
    }

    func makeNSView(context: Context) -> PointerView {
        let view = PointerView()
        update(view)
        return view
    }

    func updateNSView(_ view: PointerView, context: Context) {
        update(view)
    }

    private func update(_ view: PointerView) {
        view.onClick = onClick
        view.onRightClick = onRightClick
        view.onWheel = onWheel
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel(label)
    }
}
