import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

// MARK: - Pileup simulator

/// The controls of the simulator window (Kotlin `remember { mutableStateOf }`).
@MainActor
final class SimulatorFormState: ObservableObject {
    @Published var activity: Double = 3
    @Published var minWpm = "22"
    @Published var maxWpm = "32"
    @Published var spread = "300"
    @Published var noise: Double = 0.15
}

/// Kotlin `SimulatorWindow` (`simulator` 620×520, `SimulatorWindow.kt:35-104`): the pileup simulator. While it runs the
/// CW of the F-keys goes to the simulator instead of the key and the keying of the real rig is refused.
/// A start that is refused — an outward service is live, or the sound output does not open — says so right here, in
/// the model's own text; the window never starts anything the model refuses. Closing the window stops the session.
struct SimulatorWindowView: View {
    static let id = "simulator"

    let host: AppHost

    var body: some View {
        ToolWindowShell(host: host, id: Self.id, title: { $0.language.tr("Simulátor pileupu") },
                        size: CGSize(width: 620, height: 520), minSize: CGSize(width: 460, height: 340),
                        disappeared: { $0.simulator.windowClosed() },
                        stepperInContent: true,
                        content: { app, _ in SimulatorContent(app: app) })
    }
}

private struct SimulatorContent: View {
    let app: AppModel
    @StateObject private var form = SimulatorFormState()

    var body: some View {
        let model: SimulatorModel = app.simulator
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: SimulatorSession.activityText(Int(form.activity), translate: language.translator))
                .windowFont(13, weight: .medium)
                .trailingFontStepper()
            Slider(value: $form.activity, in: 1...6, step: 1)
                .accessibilityLabel(Text(verbatim: SimulatorSession.activityText(Int(form.activity),
                                                                                  translate: language.translator)))
                .accessibilityIdentifier("simulator.activity")
            HStack(spacing: 8) {
                numberField("WPM od", text: filtered($form.minWpm, 2), width: 110, identifier: "simulator.minWpm")
                numberField("WPM do", text: filtered($form.maxWpm, 2), width: 110, identifier: "simulator.maxWpm")
                numberField(language.tr("Rozptyl tónů (Hz)"), text: filtered($form.spread, 4), width: 170,
                            identifier: "simulator.spread")
            }
            Text(verbatim: SimulatorSession.noiseText(Float(form.noise)))
                .windowFont(13, weight: .medium)
            Slider(value: Binding(get: { form.noise }, set: { value in
                form.noise = value
                model.setNoise(Float(value))
            }), in: 0...0.6)
                .accessibilityLabel(Text(verbatim: SimulatorSession.noiseText(Float(form.noise))))
                .accessibilityIdentifier("simulator.noise")
            HStack(spacing: 16) {
                Toggle(isOn: Binding(get: { model.qsb }, set: { model.qsb = $0 })) {
                    Text(verbatim: language.tr("QSB (únik signálu)")).windowFont(13)
                }
                .accessibilityIdentifier("simulator.qsb")
                Toggle(isOn: Binding(get: { model.qrm }, set: { model.qrm = $0 })) {
                    Text(verbatim: language.tr("QRM (rušící stanice)")).windowFont(13)
                }
                .accessibilityIdentifier("simulator.qrm")
            }
            .toggleStyle(.checkbox)
            controls(model)
            if let notice = model.startNotice {
                Text(verbatim: notice)
                    .windowFont(12, weight: .medium)
                    .foregroundStyle(model.isOn ? Color.secondary : Color(domain: DomainColors.dupe))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("simulator.notice")
            }
            ToolHint(text: SimulatorSession.hint(translate: language.translator))
            checks(model, language: language)
        }
    }

    private func controls(_ model: SimulatorModel) -> some View {
        HStack(spacing: 8) {
            if model.isOn {
                Button("Zastavit") { model.stop() }
                    .accessibilityIdentifier("simulator.stop")
            } else {
                Button("Spustit") {
                    model.start(settings: SimulatorSession.settings(activity: Int(form.activity),
                                                                   minWpm: form.minWpm, maxWpm: form.maxWpm,
                                                                   spread: form.spread),
                                noise: Float(form.noise))
                }
                .disabled(model.isStarting)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("simulator.start")
            }
            Text(verbatim: SimulatorSession.counterText(qsos: model.qsos, errors: model.errors))
                .windowFont(15, weight: .medium)
                .accessibilityIdentifier("simulator.counter")
        }
        .windowFont(13)
    }

    private func checks(_ model: SimulatorModel, language: LanguageModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.checks.enumerated()), id: \.offset) { _, check in
                    Text(verbatim: SimulatorSession.checkText(check, translate: language.translator))
                        .windowFont(12, design: .monospaced)
                        .foregroundStyle(check.ok ? AnyShapeStyle(.mclPrimary)
                                                  : AnyShapeStyle(Color(domain: DomainColors.dupe)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("simulator.checks")
    }

    private func numberField(_ label: String, text: Binding<String>, width: CGFloat,
                             identifier: String) -> some View {
        ToolField(label: label) {
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .windowFont(12)
                .accessibilityIdentifier(identifier)
        }
        .frame(width: width)
    }

    /// The digits of the field, at most `limit` (Kotlin `filter(Char::isDigit).take(n)`).
    private func filtered(_ binding: Binding<String>, _ limit: Int) -> Binding<String> {
        Binding(get: { binding.wrappedValue },
                set: { binding.wrappedValue = SimulatorSession.digits($0, limit: limit) })
    }
}

// MARK: - Band notes

@MainActor
final class BandNoteFormState: ObservableObject {
    @Published var freq = ""
    @Published var text = ""
    private var started = false

    func start(frequency: String) {
        guard !started else { return }
        started = true
        freq = frequency
    }
}

/// Kotlin `BandNotesWindow` (`bandnotes` 560×420, `BandNotesWindow.kt:30-84`): a note to a frequency (a mark in the
/// bandmap, shown in the entry window within 2 kHz) or to a whole band.
struct BandNotesWindowView: View {
    static let id = "bandnotes"

    let host: AppHost

    var body: some View {
        ToolWindowShell(host: host, id: Self.id, title: { $0.language.tr("Poznámky k pásmům") },
                        size: CGSize(width: 560, height: 420), minSize: CGSize(width: 420, height: 240),
                        stepperInContent: true,
                        content: { app, _ in BandNotesContent(app: app) })
    }
}

private struct BandNotesContent: View {
    let app: AppModel
    @StateObject private var form = BandNoteFormState()

    var body: some View {
        let model: BandNotesModel = app.bandNotes
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 6) {
                ToolField(label: language.tr("kHz nebo pásmo (20m)")) {
                    TextField("", text: $form.freq).accessibilityIdentifier("bandnotes.freq")
                }
                .frame(width: 160)
                ToolField(label: language.tr("Poznámka")) {
                    TextField("", text: $form.text).accessibilityIdentifier("bandnotes.text")
                }
                Button(language.tr("Přidat")) {
                    if model.add(freq: form.freq, text: form.text) {
                        form.text = ""
                    }
                }
                .accessibilityIdentifier("bandnotes.add")
            }
            .textFieldStyle(.roundedBorder)
            .windowFont(12)
            .trailingFontStepper()
            Divider()
            let notes: [BandNote] = model.notes
            if notes.isEmpty {
                Text(verbatim: language.tr("Žádné poznámky."))
                    .windowFont(13)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        HStack {
                            Text(verbatim: model.rowText(note))
                                .windowFont(12, design: .monospaced)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Smazat") { model.remove(note) }
                                .buttonStyle(.borderless)
                                .windowFont(12)
                        }
                    }
                }
            }
            .accessibilityIdentifier("bandnotes.list")
        }
        .onAppear { form.start(frequency: model.defaultFrequencyText) }
    }
}

// MARK: - Move multipliers

/// Kotlin `MoveMultipliersWindow` (`movemults` 640×420, `MoveMultipliersWindow.kt:33-120`): the stations of the latest
/// QSOs that would be a new multiplier on another band. „QSY?" asks the station to move (CW: `PSE QSY` through the
/// keyer, otherwise only a hint), „→" retunes the rig. Both only on a button.
struct MoveMultsWindowView: View {
    static let id = "movemults"

    let host: AppHost

    var body: some View {
        ToolWindowShell(host: host, id: Self.id, title: { $0.language.tr("Přesun násobičů") },
                        size: CGSize(width: 640, height: 420), minSize: CGSize(width: 420, height: 240),
                        stepperInContent: true,
                        content: { app, _ in MoveMultsContent(app: app) })
    }
}

private struct MoveMultsContent: View {
    let app: AppModel

    var body: some View {
        let model: MoveMultsModel = app.moveMults
        let language: LanguageModel = app.language
        if !model.isContestActive {
            Text(verbatim: language.tr("Přesun násobičů je jen v závodě."))
                .windowFont(13)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("movemults.noContest")
                .trailingFontStepper()
            Spacer(minLength: 0)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Picker(selection: Binding(get: { model.showSpots }, set: { model.setShowSpots($0) })) {
                    Text(verbatim: language.tr("Poslední QSO")).tag(false)
                    Text(verbatim: language.tr("Spotované stanice")).tag(true)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .windowFont(12)
                .accessibilityLabel(Text(verbatim: language.tr("Zobrazení přesunu násobičů")))
                .accessibilityIdentifier("movemults.view")
                .trailingFontStepper()
                if model.showSpots {
                    MoveMultsSpotsView(model: model, language: language)
                } else {
                    recentQsos(model, language: language)
                }
            }
        }
    }

    @ViewBuilder private func recentQsos(_ model: MoveMultsModel, language: LanguageModel) -> some View {
            let rows: [MoveMultsModel.Row] = model.rows
            VStack(alignment: .leading, spacing: 6) {
                ToolHint(text: MoveRequest.hint(translate: language.translator))
                Divider()
                if rows.isEmpty {
                    Text(verbatim: language.tr("Nic k přesunu."))
                        .windowFont(13)
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(rows) { row in
                            rowView(row, model: model)
                        }
                    }
                }
            }
    }

    private func rowView(_ row: MoveMultsModel.Row, model: MoveMultsModel) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: row.qso.call)
                .windowFont(12, weight: .bold, design: .monospaced)
                .frame(width: 110, alignment: .leading)
            Text(verbatim: MoveRequest.bandModeText(row.qso))
                .windowFont(11)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            ForEach(Array(row.candidates.enumerated()), id: \.offset) { _, candidate in
                Button(MoveRequest.buttonLabel(candidate)) {
                    model.request(row.qso, band: candidate.band)
                }
                .windowFont(11)
                .accessibilityIdentifier("movemults.qsy.\(row.id).\(candidate.band)")
                Button("→") { model.tune(band: candidate.band) }
                    .buttonStyle(.borderless)
                    .windowFont(11)
                    .accessibilityIdentifier("movemults.tune.\(row.id).\(candidate.band)")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

/// N1MM's Move Multipliers over the spot table: the options, Refresh, and a row per spotted call and mode with a cell
/// per band (shaded where spotted). A click on a shaded cell tunes to that spot, on the call to its next spotted band;
/// with Shift the spot goes to VFO B. „Skrýt řádek" hides the row until Refresh.
private struct MoveMultsSpotsView: View {
    let model: MoveMultsModel
    let language: LanguageModel

    var body: some View {
        let bands: [Band] = model.bands
        VStack(alignment: .leading, spacing: 6) {
            options(bands)
            Divider()
            let rows: [SpotMoveMults.Row] = model.visibleSpotRows
            if rows.isEmpty {
                Text(verbatim: language.tr("Žádné spotované stanice."))
                    .windowFont(13)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    header(bands)
                    ForEach(rows) { row in
                        rowView(row, bands: bands)
                    }
                }
            }
        }
        .onAppear {
            model.refreshSpots()
        }
    }

    private func options(_ bands: [Band]) -> some View {
        HStack(spacing: 8) {
            Button(language.tr("Aktualizovat")) {
                model.refreshSpots()
            }
            .accessibilityIdentifier("movemults.refresh")
            Picker(selection: Binding(get: { model.display }, set: { model.setDisplay($0) })) {
                Text(verbatim: language.tr("Násobiče")).tag(SpotMoveMults.Display.multipliers)
                Text(verbatim: language.tr("Body QSO")).tag(SpotMoveMults.Display.points)
                Text(verbatim: language.tr("Počty QSO")).tag(SpotMoveMults.Display.counts)
            } label: {
                Text(verbatim: language.tr("Zobrazit"))
            }
            .fixedSize()
            .accessibilityIdentifier("movemults.display")
            if model.display != .multipliers {
                TextField(language.tr("Rozsah"), text: Binding(get: { model.rangeText },
                                                               set: { model.setRangeText($0) }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .help(language.tr("Rozsah počtu, např. 0-6 nebo 3"))
                    .accessibilityLabel(Text(verbatim: language.tr("Rozsah")))
            }
            Picker(selection: Binding(get: { model.modes }, set: { model.setModes($0) })) {
                Text(verbatim: language.tr("Módy závodu")).tag(SpotMoveMults.ModeFilter.contest)
                Text(verbatim: language.tr("Vše")).tag(SpotMoveMults.ModeFilter.all)
                Text(verbatim: "CW").tag(SpotMoveMults.ModeFilter.cw)
                Text(verbatim: "Phone").tag(SpotMoveMults.ModeFilter.phone)
                Text(verbatim: "Digi").tag(SpotMoveMults.ModeFilter.digi)
            } label: {
                Text(verbatim: language.tr("Módy"))
            }
            .fixedSize()
            Menu(language.tr("Pásma")) {
                ForEach(MultGridExtras.bandChoices, id: \.self) { band in
                    Toggle(isOn: Binding(get: { bands.contains(band) }, set: { model.setBand(band, shown: $0) })) {
                        Text(verbatim: band.adif)
                    }
                }
            }
            .fixedSize()
            Spacer(minLength: 0)
        }
        .windowFont(12)
    }

    private func header(_ bands: [Band]) -> some View {
        HStack(spacing: 2) {
            Text(verbatim: language.tr("Volačka"))
                .frame(width: 100, alignment: .leading)
            Text(verbatim: language.tr("Mód"))
                .frame(width: 56, alignment: .leading)
            ForEach(bands, id: \.self) { band in
                Text(verbatim: MultGridExtras.header(band))
                    .frame(width: 40)
            }
        }
        .windowFont(11, weight: .bold, design: .monospaced)
        .accessibilityHidden(true)
    }

    private func rowView(_ row: SpotMoveMults.Row, bands: [Band]) -> some View {
        HStack(spacing: 2) {
            Button {
                model.tuneNext(row, otherVfo: NSEvent.modifierFlags.contains(.shift))
            } label: {
                Text(verbatim: row.call)
                    .windowFont(12, weight: .bold, design: .monospaced)
                    .frame(width: 100, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("movemults.call.\(row.id)")
            Text(verbatim: row.mode)
                .windowFont(11)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            ForEach(bands, id: \.self) { band in
                cell(row, band: band)
            }
        }
        .contextMenu {
            Button(language.tr("Skrýt řádek")) {
                model.hide(row)
            }
        }
    }

    @ViewBuilder private func cell(_ row: SpotMoveMults.Row, band: Band) -> some View {
        let text: String = model.cellText(row, band: band)
        let spotted: Bool = row.cells[band.adif]?.spot != nil
        let mults: Int = row.cells[band.adif]?.newMults ?? 0
        let label = Text(verbatim: text)
            .windowFont(11, design: .monospaced)
            .foregroundStyle(mults > 0 && model.display == .multipliers
                ? Color(argb: mults > 1 ? MultGridLayout.spottedDblColor : MultGridLayout.spottedColor)
                : Color.primary)
            .frame(width: 40, height: 18)
            .background(spotted ? Color.accentColor.opacity(0.25) : Color.clear)
        if spotted {
            Button {
                model.tune(row, band: band, otherVfo: NSEvent.modifierFlags.contains(.shift))
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: row.call + " " + band.adif))
            .accessibilityValue(Text(verbatim: text))
        } else {
            label
                .accessibilityLabel(Text(verbatim: row.call + " " + band.adif))
                .accessibilityValue(Text(verbatim: text))
        }
    }
}

// MARK: - Propagation

/// Kotlin `PropagationWindow` (`propagation` 720×360, `PropagationWindow.kt:30-113`): the forecast of the open bands
/// for each UTC hour on the path to a callsign (green open, yellow marginal, grey closed); the SFI comes from the last
/// WWV message of the cluster and can be overwritten. Nothing is fetched.
struct PropagationWindowView: View {
    static let id = "propagation"

    let host: AppHost

    var body: some View {
        ToolWindowShell(host: host, id: Self.id, title: { $0.language.tr("Předpověď šíření") },
                        size: CGSize(width: 720, height: 360), minSize: CGSize(width: 560, height: 260),
                        appeared: { $0.propagation.open() },
                        stepperInContent: true,
                        content: { app, windowSize in PropagationContent(app: app, windowSize: windowSize) })
    }
}

private struct PropagationContent: View {
    let app: AppModel
    let windowSize: Int

    var body: some View {
        let model: PropagationWindowModel = app.propagation
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                ToolField(label: language.tr("Volačka / země")) {
                    TextField("", text: Binding(get: { model.shownTarget }, set: { model.setTarget($0) }))
                        .accessibilityIdentifier("propagation.target")
                }
                .frame(width: 160)
                ToolField(label: "SFI") {
                    TextField("", text: Binding(get: { model.sfiText }, set: { model.setSfi($0) }))
                        .accessibilityIdentifier("propagation.sfi")
                }
                .frame(width: 80)
            }
            .textFieldStyle(.roundedBorder)
            .windowFont(12)
            .trailingFontStepper()
            switch model.view {
            case .message(let text):
                Text(verbatim: text)
                    .windowFont(13)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("propagation.message")
                Spacer(minLength: 0)
            case .table(let table):
                Text(verbatim: table.title)
                    .windowFont(12, weight: .medium)
                    .accessibilityIdentifier("propagation.title")
                grid(table)
                ToolHint(text: model.footnote)
                Spacer(minLength: 0)
            }
        }
    }

    private func grid(_ table: PropagationRows.Table) -> some View {
        let cell: CGFloat = CGFloat(windowSize * 2)
        let label: CGFloat = CGFloat(windowSize * 4)
        let primary = AnyShapeStyle(.mclPrimary)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Spacer().frame(width: label)
                ForEach(Array(table.hourLabels.enumerated()), id: \.offset) { hour, text in
                    Text(verbatim: text)
                        .windowFont(10, design: .monospaced)
                        .foregroundStyle(hour == table.nowHour ? primary : AnyShapeStyle(Color.secondary))
                        .frame(width: cell, alignment: .leading)
                }
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    Text(verbatim: row.band.adif)
                        .windowFont(12, design: .monospaced)
                        .frame(width: label, alignment: .leading)
                    ForEach(Array(row.levels.enumerated()), id: \.offset) { hour, level in
                        ZStack {
                            Color(argb: PropagationRows.color(level))
                            if hour == table.nowHour {
                                Color.black.opacity(0.13)
                            }
                        }
                        .padding(1)
                        .frame(width: cell, height: CGFloat(windowSize + 6))
                    }
                }
            }
        }
        .accessibilityIdentifier("propagation.grid")
    }
}
