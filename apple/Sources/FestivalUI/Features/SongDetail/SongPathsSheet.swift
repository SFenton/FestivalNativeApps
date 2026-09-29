import SwiftUI
import FestivalCore
import FestivalDesign

/// Native public CHOpt image/text viewer with generation-safe request switching.
struct SongPathsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("fst.settings.pathUnavailableWarningDismissed")
    private var warningDismissed = false
    @AppStorage("fst.settings.pathColumnOrder")
    private var pathColumnOrderRaw = SettingsOrder.encode(PathColumnKey.allCases)
    @State private var instrument: Instrument
    @State private var difficulty = PathDifficulty.expert
    @State private var display: PathDisplayMode
    @State private var state = LoadState.loading
    @State private var retryRevision = 0
    @State private var zoom: CGFloat = 1
    @State private var pinchOrigin: CGFloat = 1
    @State private var warningPresented = false

    let song: Song
    let session: FestivalSession
    let instruments: [Instrument]
    let warnAboutKaraoke: Bool

    private enum LoadState {
        case loading
        case image(SongPathImagePayload)
        case text(SongPathDataPayload)
        case failed(ServiceIssue)
    }

    private struct RequestKey: Equatable {
        let instrument: Instrument
        let difficulty: PathDifficulty
        let display: PathDisplayMode
        let publicationRevision: Int
        let retryRevision: Int
    }

    private var requestKey: RequestKey {
        RequestKey(
            instrument: instrument, difficulty: difficulty, display: display,
            publicationRevision: session.publicationRevision, retryRevision: retryRevision
        )
    }

    private var selectorLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    /// Reset controls for each opening without changing the Settings default.
    ///
    /// - Parameters:
    ///   - song: Catalogue item with optional artifact generation ID.
    ///   - session: Process-scoped, publication-aware public client.
    ///   - instruments: Enabled path-capable instruments in source order.
    ///   - firstInstrument: First validated entry in `instruments`.
    ///   - defaultDisplay: Image or text preference from app Settings.
    ///   - warnAboutKaraoke: Whether an enabled chart lacks CHOpt paths.
    init(
        song: Song, session: FestivalSession, instruments: [Instrument],
        firstInstrument: Instrument, defaultDisplay: PathDisplayMode,
        warnAboutKaraoke: Bool
    ) {
        self.song = song
        self.session = session
        self.instruments = instruments
        self.warnAboutKaraoke = warnAboutKaraoke
        _instrument = State(initialValue: firstInstrument)
        _display = State(initialValue: defaultDisplay)
    }

    var body: some View {
        // Web-like layout: one compact title row, the path image/table filling the
        // sheet, and a compact selector row at the bottom (operator audit 2026-09-28).
        VStack(spacing: 10) {
            topBar
            pathContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            selectorRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Full-bleed page sizing at every width: the zoomable image/table benefits from
        // the extra room on Duo unfolded/iPad rather than a centered form card.
        .festivalSheet(.large, sizing: .page)
        .task(id: requestKey) { await loadPath() }
        .onChange(of: instrument) { _, _ in resetZoom() }
        .onChange(of: difficulty) { _, _ in resetZoom() }
        .onChange(of: display) { _, _ in resetZoom() }
        .onAppear { warningPresented = warnAboutKaraoke && !warningDismissed }
        .alert("Some Instruments Unavailable", isPresented: $warningPresented) {
            Button("OK") {}
            Button("Don't show again") { warningDismissed = true }
                .accessibilityIdentifier("fst.paths.warning.dismiss")
        } message: {
            Text("Karaoke is not available for path visualization yet.")
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Compact chrome

    /// One row: title, image zoom controls (image mode only) and an icon Close.
    private var topBar: some View {
        HStack(spacing: 8) {
            Text("Paths")
                .font(.headline)
                .foregroundStyle(FestivalText.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if case .image = state {
                zoomButton(
                    "Zoom out", symbol: "minus.magnifyingglass", enabled: zoom > 1
                ) {
                    setZoom(zoom / 1.5)
                }
                .accessibilityIdentifier("fst.paths.zoom-out")
                Text("\(Int(zoom * 100))%")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(FestivalText.primary)
                zoomButton(
                    "Zoom in", symbol: "plus.magnifyingglass", enabled: zoom < 3
                ) {
                    setZoom(zoom * 1.5)
                }
                .accessibilityIdentifier("fst.paths.zoom-in")
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(FestivalText.primary)
                    .frame(width: 44, height: 44)
                    .background(BrandTokens.cardBackground, in: Circle())
            }
            .buttonStyle(HighContrastPagerStyle())
            .accessibilityLabel("Close")
            .accessibilityIdentifier("fst.paths.close")
        }
    }

    /// Instrument, difficulty and view menus in one compact bottom row (web's
    /// bottom pickers).
    private var selectorRow: some View {
        selectorLayout {
            selectorMenu {
                Picker("Instrument", selection: $instrument) {
                    ForEach(instruments) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
            }
            .accessibilityIdentifier("fst.paths.instrument")
            selectorMenu {
                Picker("Difficulty", selection: $difficulty) {
                    ForEach(PathDifficulty.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
            }
            .accessibilityIdentifier("fst.paths.difficulty")
            selectorMenu {
                Picker("View", selection: $display) {
                    ForEach(PathDisplayMode.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
            }
            .accessibilityIdentifier("fst.paths.display")
        }
        .frame(maxWidth: .infinity)
    }

    /// Menu-style picker on a compact glass capsule.
    ///
    /// - Parameter picker: The picker to present as a menu.
    /// - Returns: Capsule-backed menu picker at least 44pt tall.
    private func selectorMenu<P: View>(@ViewBuilder _ picker: () -> P) -> some View {
        picker()
            .pickerStyle(.menu)
            .tint(FestivalText.primary)
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 44)
            .festivalGlassCapsule(.control, interactive: true)
    }

    /// Render the independent image/text state with honest freshness and errors.
    @ViewBuilder
    private var pathContent: some View {
        switch state {
        case .loading:
            FestivalLoadingView(accessibilityLabel: "Loading \(display.label.lowercased()) path")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(issue):
            ServiceStatusView(issue, title: "Path unavailable") {
                retryRevision += 1
            }
            .accessibilityIdentifier("fst.paths.error")
        case let .image(payload):
            VStack(spacing: 8) {
                freshness(publicationId: payload.publicationId)
                imageScroll(payload.image)
            }
        case let .text(payload):
            VStack(spacing: 8) {
                freshness(publicationId: payload.publicationId)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(payload.path.pathSummary.isEmpty
                            ? "No path summary provided" : payload.path.pathSummary)
                            .font(.headline)
                            .foregroundStyle(FestivalText.primary)
                            .accessibilityIdentifier("fst.paths.text-summary")
                        Text("Max score: \(payload.path.totalScore.formatted())")
                            .foregroundStyle(FestivalText.primary)
                        let rows = payload.rows
                        if rows.isEmpty {
                            Text("No path activations for this chart")
                                .foregroundStyle(FestivalText.primary)
                        }
                        ForEach(rows, id: \.number) { row in
                            activationCard(row)
                        }
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Retain visible contrast for either enabled or disabled zoom actions.
    ///
    /// - Parameters:
    ///   - title: Spoken and visible zoom action.
    ///   - symbol: Decorative magnification icon.
    ///   - enabled: Whether another zoom step is within the supported range.
    ///   - action: New zoom scale to apply when activated.
    /// - Returns: Native button with a stable opaque plate and disabled trait.
    private func zoomButton(
        _ title: String, symbol: String, enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(
                    enabled ? FestivalText.primary : FestivalText.disabled
                )
                .frame(width: 44, height: 44)
                .background(BrandTokens.cardBackground, in: Circle())
        }
        .buttonStyle(HighContrastPagerStyle())
        .accessibilityLabel(title)
        .disabled(!enabled)
    }

    /// Keep a large path scrollable at fit width while allowing pinch/button zoom.
    ///
    /// - Parameter image: Validated, bounded image decoded away from the UI actor.
    /// - Returns: Scrollable native image viewport.
    private func imageScroll(_ image: CGImage) -> some View {
        GeometryReader { geometry in
            let fit = min(1, max(1, geometry.size.width - 16) / CGFloat(image.width))
            ScrollView([.vertical, .horizontal]) {
                Image(image, scale: 1, label: Text(
                    "\(instrument.label) \(difficulty.label) CHOpt path"
                ))
                .resizable()
                .interpolation(.high)
                .frame(
                    width: CGFloat(image.width) * fit * zoom,
                    height: CGFloat(image.height) * fit * zoom
                )
                .accessibilityIdentifier("fst.paths.image")
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            zoom = min(3, max(1, pinchOrigin * value.magnification))
                        }
                        .onEnded { value in
                            setZoom(pinchOrigin * value.magnification)
                        }
                )
            }
        }
    }

    /// Make the source's activation table readable at native Dynamic Type sizes.
    ///
    /// - Parameter row: Resolved beat, time, frets, OD and score for one activation.
    /// - Returns: Accessible native activation card.
    private func activationCard(_ row: PathActivationRow) -> some View {
        let metrics: AnyLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return VStack(alignment: .leading, spacing: 12) {
            Text("Activation \(row.number)")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let instruction = row.instruction, !instruction.isEmpty {
                Text(instruction)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            metrics {
                ForEach(SettingsOrder.decode(pathColumnOrderRaw) as [PathColumnKey]) { key in
                    column(key, row: row)
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(FestivalText.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            BrandTokens.cardBackground,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fst.paths.activation.\(row.number)")
    }

    /// One activation-table column, in Settings' saved `pathColumnOrder` position.
    ///
    /// - Parameters:
    ///   - key: Which column to render.
    ///   - row: Resolved beat, time, frets, OD and score for this activation.
    /// - Returns: A labeled column matching the other four's compact style.
    @ViewBuilder
    private func column(_ key: PathColumnKey, row: PathActivationRow) -> some View {
        switch key {
        case .note:
            VStack(alignment: .leading, spacing: 4) {
                Text(key.label)
                    .font(.caption)
                    .foregroundStyle(FestivalText.primary)
                HStack(spacing: 4) {
                    ForEach(["green", "red", "yellow", "blue", "orange"], id: \.self) { fret in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(row.frets.contains(fret)
                                ? Self.fretColor(fret) : BrandTokens.appBackground)
                            .frame(width: 20, height: 20)
                            .overlay {
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(BrandTokens.glassBorder, lineWidth: 1)
                            }
                            .accessibilityHidden(true)
                    }
                    if row.frets.contains("open") {
                        Text("Open")
                            .font(.caption2.bold())
                            .padding(4)
                            .background(BrandTokens.appBackground, in: Capsule())
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Activation frets")
            .accessibilityValue(row.frets.isEmpty ? "No anchor" : row.frets.joined(separator: ", "))
        case .beat:
            VStack(alignment: .leading, spacing: 4) {
                Text(key.label)
                    .font(.caption)
                    .foregroundStyle(FestivalText.primary)
                Text(row.beat.formatted(.number.precision(.fractionLength(2))))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .time:
            VStack(alignment: .leading, spacing: 4) {
                Text(key.label)
                    .font(.caption)
                    .foregroundStyle(FestivalText.primary)
                Text(Self.time(row.seconds))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .od:
            VStack(alignment: .leading, spacing: 4) {
                Text("Overdrive %")
                    .font(.caption)
                    .foregroundStyle(FestivalText.primary)
                if let amount = row.odPercent {
                    HStack(spacing: 6) {
                        ProgressView(value: amount, total: 100)
                            .tint(BrandTokens.gold)
                            .accessibilityLabel("Overdrive")
                            .accessibilityValue("\(Int(amount.rounded())) percent")
                        Text("\(Int(amount.rounded()))%")
                            .monospacedDigit()
                    }
                } else {
                    Text("Unavailable")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .score:
            VStack(alignment: .leading, spacing: 4) {
                Text(key.label)
                    .font(.caption)
                    .foregroundStyle(FestivalText.primary)
                Text(row.scoreBeforeActivation.map { $0.formatted() } ?? "Unavailable")
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Match the source's five visible fret colors using original SwiftUI shapes.
    ///
    /// - Parameter name: One of the five validated CHOpt fret keys.
    /// - Returns: The corresponding sRGB accent.
    private static func fretColor(_ name: String) -> Color {
        switch name {
        case "green": Color(red: 46.0 / 255, green: 204.0 / 255, blue: 113.0 / 255)
        case "red": Color(red: 231.0 / 255, green: 76.0 / 255, blue: 60.0 / 255)
        case "yellow": Color(red: 241.0 / 255, green: 196.0 / 255, blue: 15.0 / 255)
        case "blue": Color(red: 52.0 / 255, green: 152.0 / 255, blue: 219.0 / 255)
        case "orange": Color(red: 230.0 / 255, green: 126.0 / 255, blue: 34.0 / 255)
        default: BrandTokens.appBackground
        }
    }

    /// Format seconds as the source's minute/second/millisecond time.
    ///
    /// - Parameter seconds: Nonnegative, validated time from CHOpt data.
    /// - Returns: `mm:ss:SSS` with normalized millisecond rollover.
    private static func time(_ seconds: Double) -> String {
        let millis = Int((seconds * 1000).rounded())
        return String(
            format: "%02d:%02d:%03d", millis / 60_000,
            millis / 1_000 % 60, millis % 1_000
        )
    }

    /// Disclose whether this path is response-verified.
    ///
    /// - Parameter publicationId: Response-proven generation, if supplied.
    /// - Returns: Optional provenance banner.
    @ViewBuilder
    private func freshness(publicationId: Int?) -> some View {
        if publicationId == nil {
            FreshnessDisclosure(
                message: "Showing live path without publication verification",
                symbol: "info.circle"
            )
        }
    }

    /// Clamp the image scale and let the next pinch start from that new scale.
    ///
    /// - Parameter proposed: Zoom requested by a button or gesture.
    private func setZoom(_ proposed: CGFloat) {
        zoom = min(3, max(1, proposed))
        pinchOrigin = zoom
    }

    /// Restore fit width when switching the image's chart or difficulty.
    private func resetZoom() {
        zoom = 1
        pinchOrigin = 1
    }

    /// Ignore late responses after any selector, retry or publication change.
    private func loadPath() async {
        let requested = requestKey
        state = .loading
        do {
            switch requested.display {
            case .image:
                let result = try await session.pathImage(
                    song: song, instrument: requested.instrument,
                    difficulty: requested.difficulty
                )
                try Task.checkCancellation()
                guard requestKey == requested else { return }
                state = .image(result)
            case .text:
                let result = try await session.pathData(
                    song: song, instrument: requested.instrument,
                    difficulty: requested.difficulty
                )
                try Task.checkCancellation()
                guard requestKey == requested else { return }
                state = .text(result)
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled, requestKey == requested else { return }
            state = .failed(ServiceIssue(error))
        }
    }
}
