import SwiftUI
import FestivalCore
import FestivalDesign

/// Native public CHOpt image/text viewer with generation-safe request switching.
struct SongPathsSheet: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("fst.settings.pathUnavailableWarningDismissed")
    private var warningDismissed = false
    @State private var instrument: Instrument
    @State private var difficulty = PathDifficulty.expert
    @State private var display: PathDisplayMode
    /// The image, table or error on screen; nil while the spinner shows (issue #70).
    @State private var shown: LoadState?
    /// The loading spinner is on screen (it fades in and out between charts).
    @State private var spinnerVisible = true
    /// A chart has been requested before, so later loads are switches VoiceOver announces.
    @State private var hasRequested = false
    @State private var retryRevision = 0
    @State private var zoom: CGFloat = 1
    @State private var pinchOrigin: CGFloat = 1
    @State private var warningPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let song: Song
    let session: FestivalSession
    let instruments: [Instrument]
    let warnAboutKaraoke: Bool

    private enum LoadState {
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
        // Web-like layout: one compact title bar (the shared modal's, with the image
        // zoom controls and the system Close), the path image/table filling the sheet,
        // and a compact selector row at the bottom (operator audit 2026-09-28).
        FestivalModal("Paths", closeIdentifier: "fst.paths.close") {
            VStack(spacing: 10) {
                pathContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                selectorRow
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar { zoomControls }
        }
        // Full-bleed page sizing at every width: the zoomable image/table benefits from
        // the extra room on Duo unfolded/iPad rather than a centered form card.
        .festivalSheet(.large, sizing: .page)
        .task(id: requestKey) { await loadPath() }
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

    /// Image zoom controls on the leading side of the title bar (image mode only); the
    /// shared modal supplies the title and the system Close.
    @ToolbarContentBuilder private var zoomControls: some ToolbarContent {
        if showsZoom {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    setZoom(zoom / 1.5)
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .disabled(zoom <= 1)
                .accessibilityIdentifier("fst.paths.zoom-out")
                Text("\(Int(zoom * 100))%")
                    .font(.subheadline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(FestivalText.primary)
                    .accessibilityLabel("Zoom \(Int(zoom * 100)) percent")
                Button {
                    setZoom(zoom * 1.5)
                } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                .disabled(zoom >= 3)
                .accessibilityIdentifier("fst.paths.zoom-in")
            }
        }
    }

    /// The image (not the text table) is showing, so zoom applies.
    private var showsZoom: Bool {
        if case .image = shown { return true }
        return false
    }

    /// One compact bottom row of native pop-up menus: instrument, difficulty and view
    /// (issue #88: the instrument is a native menu like the other two, not the web's
    /// mobile accordion; pop-up-buttons › "a flat list of mutually exclusive options").
    private var selectorRow: some View {
        selectorLayout {
            selectorMenu("Instrument", selection: $instrument, value: instrument.label) {
                ForEach(instruments) { choice in
                    Label {
                        Text(choice.label)
                    } icon: {
                        InstrumentIcon.menuImage(for: choice, keyboard: usesKeyboardIcon(choice))
                    }
                    .tag(choice)
                }
            } current: {
                // Every option has an icon (menus › "icons for all or none"). The name
                // always stays (it must keep scaling with Dynamic Type) and long names
                // such as "Pro Drums + Cymbals" wrap to a second line.
                HStack(spacing: 6) {
                    InstrumentIcon(
                        instrument, keyboard: usesKeyboardIcon(instrument), size: InstrumentIcon.menuIconSide
                    )
                    Text(instrument.label)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .accessibilityIdentifier("fst.paths.instrument")
            selectorMenu("Difficulty", selection: $difficulty, value: difficulty.label) {
                ForEach(PathDifficulty.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            } current: {
                Text(difficulty.label)
            }
            .accessibilityIdentifier("fst.paths.difficulty")
            selectorMenu("View", selection: $display, value: display.label) {
                ForEach(PathDisplayMode.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            } current: {
                Text(display.label)
            }
            .accessibilityIdentifier("fst.paths.display")
        }
        .frame(maxWidth: .infinity)
    }

    /// Whether this chart shows the keys artwork (Lead/Pro Lead on a keyboard song).
    ///
    /// - Parameter choice: Path instrument.
    /// - Returns: True for Lead or Pro Lead when the song uses the keyboard icon.
    private func usesKeyboardIcon(_ choice: Instrument) -> Bool {
        song.usesKeyboardIcon && (choice == .lead || choice == .proLead)
    }

    /// A native pop-up menu of mutually exclusive options on a compact glass capsule.
    ///
    /// iOS/iPadOS: a `Menu` holding an inline `Picker` (the system menu with a checkmark
    /// on the current option) whose label shows the current value; the 44 pt frame sits
    /// inside the label because a frame outside a `Menu` doesn't grow its tap area
    /// (accessibility › iOS, iPadOS 44×44 pt). macOS: the system pop-up button.
    ///
    /// - Parameters:
    ///   - title: Control name VoiceOver reads before the value.
    ///   - selection: The chosen option.
    ///   - value: Current option's name, read as the accessibility value.
    ///   - options: Tagged option rows.
    ///   - current: The collapsed control's view of the current option (iOS/iPadOS).
    /// - Returns: The menu control.
    @ViewBuilder
    private func selectorMenu<Value: Hashable, Options: View, Current: View>(
        _ title: String, selection: Binding<Value>, value: String,
        @ViewBuilder options: () -> Options, @ViewBuilder current: () -> Current
    ) -> some View {
        #if os(macOS)
        Picker(title, selection: selection, content: options)
            .pickerStyle(.menu)
            .tint(FestivalText.primary)
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 44)
            .festivalGlassCapsule(.control, interactive: true)
        #else
        Menu {
            Picker(title, selection: selection, content: options)
                .pickerStyle(.inline)
                .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                current()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.body)
            .lineLimit(1)
            .foregroundStyle(FestivalText.primary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Capsule())
            .festivalGlassCapsule(.control, interactive: true)
        }
        // Keep options in source order when the menu opens upward from the bottom row.
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        #endif
    }

    /// The spinner and the current image, table or error, each fading in and out on its
    /// own (web `PathImage` phases, issue #70).
    private var pathContent: some View {
        ZStack {
            if let shown {
                loadedContent(shown)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
            if spinnerVisible {
                FestivalLoadingView(accessibilityLabel: "Loading \(display.label.lowercased()) path")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
    }

    /// Render the independent image/text state with honest freshness and errors.
    ///
    /// - Parameter state: The loaded image, table or failure.
    /// - Returns: The content for that state.
    @ViewBuilder
    private func loadedContent(_ state: LoadState) -> some View {
        switch state {
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
                    // Web mobile `PathDataTable`: one card per activation, no path text
                    // or max score above them (operator batch 6.27).
                    VStack(alignment: .leading, spacing: 8) {
                        let rows = payload.rows
                        if rows.isEmpty {
                            Text("Path data not available for this chart.")
                                .foregroundStyle(FestivalText.primary)
                                .frame(maxWidth: .infinity)
                        }
                        ForEach(rows, id: \.number) { row in
                            activationCard(row)
                        }
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Names the chart and difficulty shown (journeys wait on it).
                .accessibilityIdentifier("fst.paths.text.\(instrument.rawValue).\(difficulty.rawValue)")
            }
        }
    }

    /// Keep a large path scrollable at fit width while allowing pinch/button zoom.
    ///
    /// The image fits the full viewport width and sits in a viewport-sized frame,
    /// centered horizontally and pinned to the top, so equal margins never depend on
    /// how a two-axis `ScrollView` places narrower content (issue #87). Indicators are
    /// hidden like the app's other scrollers; the cut-off bottom edge keeps the tall
    /// path visibly scrollable, and macOS still shows scroll bars when the user's
    /// system setting asks for them.
    ///
    /// - Parameter image: Validated, bounded image decoded away from the UI actor.
    /// - Returns: Scrollable native image viewport.
    private func imageScroll(_ image: CGImage) -> some View {
        GeometryReader { geometry in
            let fit = min(1, max(1, geometry.size.width) / CGFloat(image.width))
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
                .frame(
                    minWidth: geometry.size.width, minHeight: geometry.size.height,
                    alignment: .top
                )
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("fst.paths.image-viewport")
        }
    }

    /// One activation as the web's mobile row card: a Note label over five fret pills;
    /// Beat, Time and Score side by side; an Overdrive label over the amber OD bar.
    ///
    /// - Parameter row: Resolved beat, time, frets, OD and score for one activation.
    /// - Returns: Accessible activation card.
    private func activationCard(_ row: PathActivationRow) -> some View {
        let values: AnyLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                caption("Note")
                HStack(spacing: 4) {
                    ForEach(["green", "red", "yellow", "blue", "orange"], id: \.self) { fret in
                        let active = row.frets.contains(fret)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(active ? Self.fretColor(fret) : BrandTokens.surfaceMuted)
                            .overlay {
                                if !active {
                                    RoundedRectangle(cornerRadius: 4).stroke(Self.borderSubtle, lineWidth: 2)
                                }
                            }
                            .frame(width: 22, height: 22)
                    }
                }
                .accessibilityHidden(true)
            }
            values {
                valueColumn("Beat", row.beat.formatted(.number.precision(.fractionLength(2))))
                valueColumn("Time", Self.time(row.seconds))
                valueColumn("Score", row.scoreBeforeActivation?.formatted())
            }
            VStack(alignment: .leading, spacing: 8) {
                caption("Overdrive")
                if let amount = row.odPercent {
                    OverdriveBar(percent: amount)
                } else {
                    Text("\u{2014}").foregroundStyle(FestivalText.primary)
                }
            }
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(FestivalText.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .festivalGlass(.card, cornerRadius: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activation \(row.number)")
        .accessibilityValue(spokenValue(row))
        .accessibilityIdentifier("fst.paths.activation.\(row.number)")
    }

    /// Web mobile column caption (uppercase, semibold, small).
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(FestivalText.primary)
    }

    /// One labelled value; a missing value is an em dash (web `missingValue`).
    private func valueColumn(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            caption(label)
            Text(value ?? "\u{2014}")
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Everything the card shows, for VoiceOver.
    private func spokenValue(_ row: PathActivationRow) -> String {
        var parts = [row.frets.isEmpty ? "No anchor note" : "Frets \(row.frets.joined(separator: ", "))"]
        parts.append("beat \(row.beat.formatted(.number.precision(.fractionLength(2))))")
        parts.append("time \(Self.time(row.seconds))")
        if let score = row.scoreBeforeActivation { parts.append("score \(score.formatted())") }
        if let od = row.odPercent { parts.append("overdrive \(Int(od.rounded())) percent") }
        return parts.joined(separator: ", ")
    }

    /// Web `Colors.borderSubtle` (#1E2A3A), the inactive fret pill border.
    private static let borderSubtle = Color(.sRGB, red: 30 / 255, green: 42 / 255, blue: 58 / 255)

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

    // MARK: - Switching

    /// Swap to the selected chart: fade the old content out, show the spinner while the
    /// path loads (at least 400 ms for an image, 500 ms for text), then fade the new
    /// content in. A newer selection, retry or publication change cancels this task, so
    /// a late response never paints (issue #70).
    private func loadPath() async {
        let requested = requestKey
        let announces = hasRequested
        hasRequested = true
        let timing = PathSwitchTransition.timing(for: requested.display, reduceMotion: reduceMotion)
        let session = session
        let song = song
        do {
            try await PathSwitchTransition.run(
                timing: timing, contentShown: shown != nil, clock: ContinuousClock(),
                load: { try await Self.fetch(requested, song: song, session: session) },
                apply: { step in apply(step, for: requested, timing: timing, announces: announces) }
            )
        } catch {
            // Cancelled by a newer selection, which now owns the sheet.
        }
    }

    /// Perform one visible step of a switch.
    ///
    /// - Parameters:
    ///   - step: The fade to perform.
    ///   - requested: The selection being loaded.
    ///   - timing: Fade duration (zero swaps instantly for Reduce Motion).
    ///   - announces: Whether VoiceOver hears the loading and loaded announcements.
    private func apply(
        _ step: PathSwitchTransition.Step<LoadState>, for requested: RequestKey,
        timing: PathSwitchTransition.Timing, announces: Bool
    ) {
        let fade: Animation? = timing.fadeSeconds > 0 ? .easeInOut(duration: timing.fadeSeconds) : nil
        switch step {
        case .hideContent:
            withAnimation(fade) { shown = nil }
        case .showSpinner:
            resetZoom()
            withAnimation(fade) { spinnerVisible = true }
            if announces {
                AccessibilityNotification.Announcement(
                    "Loading \(Self.chartName(requested)) \(requested.display.label.lowercased()) path"
                ).post()
            }
        case .hideSpinner:
            withAnimation(fade) { spinnerVisible = false }
        case let .showContent(content):
            guard requestKey == requested else { return }
            withAnimation(fade) { shown = content }
            if announces, let spoken = Self.loadedAnnouncement(content, for: requested) {
                AccessibilityNotification.Announcement(spoken).post()
            }
        }
    }

    /// Fetch the requested image or text; a service failure becomes the error state.
    ///
    /// - Parameters:
    ///   - requested: The selection to load.
    ///   - song: Catalogue item with optional artifact generation ID.
    ///   - session: Process-scoped, publication-aware public client.
    /// - Returns: The image, table or failure to show.
    /// - Throws: `CancellationError` when a newer selection cancels the request.
    @MainActor
    private static func fetch(
        _ requested: RequestKey, song: Song, session: FestivalSession
    ) async throws -> LoadState {
        do {
            switch requested.display {
            case .image:
                return .image(try await session.pathImage(
                    song: song, instrument: requested.instrument, difficulty: requested.difficulty
                ))
            case .text:
                return .text(try await session.pathData(
                    song: song, instrument: requested.instrument, difficulty: requested.difficulty
                ))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return .failed(ServiceIssue(error))
        }
    }

    /// "Lead Expert" for announcements.
    private static func chartName(_ requested: RequestKey) -> String {
        "\(requested.instrument.label) \(requested.difficulty.label)"
    }

    /// What VoiceOver hears once the new content fades in; failures announce themselves.
    ///
    /// - Parameters:
    ///   - content: The content now shown.
    ///   - requested: The selection it belongs to.
    /// - Returns: The announcement, or nil for an error state.
    private static func loadedAnnouncement(_ content: LoadState, for requested: RequestKey) -> String? {
        switch content {
        case .image:
            "\(chartName(requested)) path image"
        case let .text(payload):
            "\(chartName(requested)) path, \(payload.rows.count) \(payload.rows.count == 1 ? "activation" : "activations")"
        case .failed:
            nil
        }
    }
}

// MARK: - Overdrive bar

/// The web's `OdBar`: an amber (`statusAmber` #F5A623) bar filled to the clamped
/// percent, with a bold "NN%" label (a tinted system progress bar, for contrast).
struct OverdriveBar: View {
    let percent: Double

    private var clamped: Int { Int(min(max(percent, 0), 100).rounded()) }

    var body: some View {
        HStack(spacing: 12) {
            // A native linear progress bar tinted amber: a custom drawn track failed the
            // XCUITest contrast audit (twice), the system bar passes it.
            ProgressView(value: Double(clamped), total: 100)
                .tint(Color(.sRGB, red: 245 / 255, green: 166 / 255, blue: 35 / 255))
                .scaleEffect(x: 1, y: 2, anchor: .center)
                .frame(minWidth: 80)
            Text("\(clamped)%")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 40, alignment: .trailing)
        }
        .accessibilityHidden(true)
    }
}
