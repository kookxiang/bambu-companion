import SwiftUI

private enum TemperatureText {
    static func string(_ value: Double) -> String {
        formatter.string(from: Measurement<UnitTemperature>(value: value.rounded(), unit: .celsius))
    }

    private static let formatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 0
        formatter.numberFormatter.minimumFractionDigits = 0
        return formatter
    }()
}

struct StatusSummaryView: View {
    let status: PrinterStatus
    let coverImageState: CoverImageState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                CoverImageView(state: coverImageState, size: CGSize(width: 84, height: 84))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(status.activity.title)
                                .font(.title3.bold())
                            Text(statusDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 8)
                        progressBadge
                    }

                    ProgressView(value: Double(status.progress ?? 0), total: 100)
                }
            }

            if let alert = status.alert {
                AlertBannerView(alert: alert)
            }

            LazyVGrid(columns: metricColumns, spacing: 10) {
                nozzleMetric
                MetricView(title: "Bed", value: temperature(status.bedTemperature, target: status.targetBedTemperature))
                if status.chamberTemperature != nil {
                    MetricView(title: "Chamber", value: temperature(status.chamberTemperature, target: status.targetChamberTemperature))
                }
                RemainingMetricView(value: remainingTime, completionDate: estimatedCompletionDate)
            }

            if !status.amsUnits.isEmpty {
                AMSUnitsView(units: status.amsUnits)
            }
        }
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    private var statusDetail: String {
        let job = status.jobName?.isEmpty == false ? status.jobName! : "No active job"
        guard let layerText else {
            return job
        }
        return "\(job) - \(layerText)"
    }

    private var layerText: String? {
        guard let currentLayer = status.currentLayer, currentLayer > 0 else {
            return nil
        }
        if let totalLayers = status.totalLayers, totalLayers > 0 {
            return "Layer \(currentLayer)/\(totalLayers)"
        }
        return "Layer \(currentLayer)"
    }

    private var progressBadge: some View {
        Text("\(status.progress ?? 0)%")
            .font(.system(.title3, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .frame(minWidth: 48, alignment: .trailing)
    }

    private var remainingTime: String {
        guard let minutes = status.remainingMinutes else {
            return "--"
        }
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private var estimatedCompletionDate: Date? {
        guard let minutes = status.remainingMinutes else {
            return nil
        }
        return Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    @ViewBuilder
    private var nozzleMetric: some View {
        if status.leftNozzleTemperature != nil || status.rightNozzleTemperature != nil {
            DualNozzleMetricView(
                leftTemperature: temperature(status.leftNozzleTemperature, target: status.targetLeftNozzleTemperature),
                rightTemperature: temperature(status.rightNozzleTemperature, target: status.targetRightNozzleTemperature)
            )
        } else {
            MetricView(title: "Nozzle", value: temperature(status.nozzleTemperature, target: status.targetNozzleTemperature))
        }
    }

    private func temperature(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return TemperatureText.string(value)
    }

    private func temperature(_ value: Double?, target: Double?) -> String {
        guard let value else {
            return "--"
        }
        guard let target, target > 0 else {
            return temperature(value)
        }
        guard abs(value - target) > 1 else {
            return temperature(value)
        }
        return "\(TemperatureText.string(value)) / \(TemperatureText.string(target))"
    }
}

private struct AMSUnitsView: View {
    let units: [AMSUnitStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(units) { unit in
                AMSUnitRowView(unit: unit, helpText: amsHelpText(for: unit))
            }
        }
    }

    private func amsHelpText(for unit: AMSUnitStatus) -> String {
        var lines: [String] = [unit.name]
        if let temperature = unit.temperature {
            lines.append("Temperature: \(TemperatureText.string(temperature))")
        }
        if let humidityPercent = unit.humidityPercent {
            lines.append("Humidity: \(humidityPercent)%")
        } else if let humidityIndex = unit.humidityIndex {
            lines.append("Humidity index: \(humidityIndex)")
        }
        if unit.isDrying {
            lines.append("Drying: \(dryingRemainingText(unit.dryingRemainingMinutes)) remaining")
            if let dryingTemperature = unit.dryingTemperature {
                lines.append("Drying temperature: \(TemperatureText.string(dryingTemperature))")
            }
            if let dryingFilament = unit.dryingFilament {
                lines.append("Drying filament: \(dryingFilament)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func dryingRemainingText(_ minutes: Int?) -> String {
        guard let minutes else {
            return "--"
        }
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

private struct AMSUnitRowView: View {
    let unit: AMSUnitStatus
    let helpText: String
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            AMSUnitLabelView(unit: unit)
                .help(helpText)

            HStack(spacing: 6) {
                ForEach(unit.slots) { slot in
                    AMSSlotView(slot: slot)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background {
            Rectangle()
                .fill(dryingHighlight)
                .padding(.horizontal, -16)
                .padding(.vertical, -8)
        }
        .animation(.easeInOut(duration: 0.2), value: unit.isDrying)
        .onAppear {
            guard unit.isDrying else {
                return
            }
            withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onChange(of: unit.isDrying) { _, isDrying in
            if isDrying {
                withAnimation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                pulse = false
            }
        }
    }

    private var dryingHighlight: LinearGradient {
        let centerOpacity = unit.isDrying ? (pulse ? 0.18 : 0.08) : 0
        let edgeOpacity = unit.isDrying ? (pulse ? 0.04 : 0.015) : 0
        return LinearGradient(
            stops: [
                .init(color: Color.orange.opacity(edgeOpacity), location: 0),
                .init(color: Color.orange.opacity(centerOpacity), location: 0.35),
                .init(color: Color.orange.opacity(centerOpacity), location: 0.65),
                .init(color: Color.orange.opacity(edgeOpacity), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct AMSUnitLabelView: View {
    let unit: AMSUnitStatus

    var body: some View {
        HStack(spacing: 4) {
            Text(unit.name)
                .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(unit.isDrying ? .orange : .secondary)
        .frame(width: 58, alignment: .leading)
    }
}

private struct AMSSlotView: View {
    let slot: AMSSlotStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(slotColor)
                .frame(width: 10, height: 10)
                .overlay {
                    Circle()
                        .stroke(.secondary.opacity(0.45), lineWidth: 0.5)
                }

            Text(slot.material ?? "--")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(slot.material == nil ? .tertiary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .padding(.horizontal, 6)
        .background {
            AMSSlotProgressBackground(
                color: slotProgressColor,
                percent: slot.remainingPercent,
                isActive: slot.isActive
            )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(slot.isActive ? Color.accentColor : Color.clear, lineWidth: 1.5)
        }
        .help(helpText)
    }

    private var slotColor: Color {
        guard let colorHex = slot.colorHex,
              let color = Color(hexRGB: colorHex) else {
            return .clear
        }
        return color
    }

    private var slotProgressColor: Color? {
        guard let colorHex = slot.colorHex else {
            return nil
        }
        return Color(hexRGB: colorHex)
    }

    private var helpText: String {
        var lines: [String] = ["Slot \(slot.index + 1)"]
        lines.append("Material: \(slot.material ?? "Empty")")
        append("Name", slot.name, to: &lines)
        append("Brand", slot.subBrands, to: &lines)
        append("Color", slot.colorHex.map { "#\($0)" }, to: &lines)
        if let remainingPercent = slot.remainingPercent {
            lines.append("Remaining: \(remainingPercent)%")
        }
        append("Spool ID", slot.trayInfoIndex, to: &lines)
        append("Tag UID", slot.tagUID, to: &lines)
        if let diameter = slot.diameter {
            lines.append("Diameter: \(diameter.formatted(.number.precision(.fractionLength(2)))) mm")
        }
        if let weight = slot.weight {
            lines.append("Weight: \(weight.formatted(.number.precision(.fractionLength(0)))) g")
        }
        if slot.nozzleTemperatureMin != nil || slot.nozzleTemperatureMax != nil {
            lines.append("Nozzle range: \(temperatureRangeText)")
        }
        return lines.joined(separator: "\n")
    }

    private var temperatureRangeText: String {
        switch (slot.nozzleTemperatureMin, slot.nozzleTemperatureMax) {
        case let (min?, max?):
            return "\(TemperatureText.string(min)) - \(TemperatureText.string(max))"
        case let (min?, nil):
            return ">= \(TemperatureText.string(min))"
        case let (nil, max?):
            return "<= \(TemperatureText.string(max))"
        default:
            return "--"
        }
    }

    private func append(_ title: String, _ value: String?, to lines: inout [String]) {
        guard let value, !value.isEmpty else {
            return
        }
        lines.append("\(title): \(value)")
    }
}

private struct AMSSlotProgressBackground: View {
    let color: Color?
    let percent: Int?
    let isActive: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 7)
                .fill(isActive ? Color.accentColor.opacity(0.16) : Color(NSColor.quaternaryLabelColor))

            if let percent {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 7)
                        .fill(progressColor.opacity(isActive ? 0.34 : 0.24))
                        .frame(width: proxy.size.width * CGFloat(percent) / 100)
                        .frame(maxHeight: .infinity, alignment: .leading)
                }
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private var progressColor: Color {
        color ?? .accentColor
    }
}

private struct AlertBannerView: View {
    let alert: PrinterAlert

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(alert.title)
                .font(.caption.weight(.semibold))
            if let detail = alert.detail {
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension Color {
    init?(hexRGB: String) {
        guard hexRGB.count == 6,
              let value = UInt32(hexRGB, radix: 16) else {
            return nil
        }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

private struct CoverImageView: View {
    let state: CoverImageState
    var size = CGSize(width: 308, height: 150)

    var body: some View {
        switch state {
        case .ready(let url):
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ProgressView()
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        case .loading:
            placeholder(icon: "photo", text: "Loading cover image")
        case .failed:
            placeholder(icon: "photo.badge.exclamationmark", text: "Cover image unavailable")
        case .unavailable:
            placeholder(icon: "photo", text: "")
        }
    }

    private func placeholder(icon: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
            if !text.isEmpty {
                Text(text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: size.width, height: size.height)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit())
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct RemainingMetricView: View {
    let value: String
    let completionDate: Date?

    var body: some View {
        MetricView(title: "Remaining", value: value)
            .help(helpText)
    }

    private var helpText: String {
        guard let completionDate else {
            return "Estimated completion unavailable"
        }
        return "Estimated completion: \(Self.completionFormatter.string(from: completionDate))"
    }

    private static let completionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct DualNozzleMetricView: View {
    let leftTemperature: String
    let rightTemperature: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Nozzle")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(leftTemperature)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(rightTemperature)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.callout.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct VideoPreviewView: View {
    let url: URL?
    @StateObject private var frameSource = FFmpegVideoFrameSource()

    var body: some View {
        Group {
            if let image = frameSource.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let errorMessage = frameSource.errorMessage {
                placeholder(icon: "video.slash", text: errorMessage)
            } else if url != nil {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Connecting video...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                placeholder(icon: "video.slash", text: "Video preview is unavailable.")
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            frameSource.start(url: url)
        }
        .onChange(of: url) { _, newURL in
            frameSource.start(url: newURL)
        }
        .onDisappear {
            frameSource.stop()
        }
    }

    private func placeholder(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private final class FFmpegVideoFrameSource: ObservableObject {
    @Published var image: NSImage?
    @Published var errorMessage: String?

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var currentURL: URL?
    private var buffer = Data()
    private let queue = DispatchQueue(label: "BambuCompanion.FFmpegVideoFrameSource")

    func start(url: URL?) {
        guard let url else {
            stop()
            return
        }
        guard currentURL != url || process == nil else {
            return
        }

        stop()
        currentURL = url
        image = nil
        errorMessage = nil

        guard let ffmpegURL = Self.ffmpegURL else {
            errorMessage = "ffmpeg is required for RTSP video preview."
            return
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-hide_banner",
            "-loglevel", "error",
            "-rtsp_transport", "tcp",
            "-i", url.absoluteString,
            "-an",
            "-vf", "fps=8,scale=960:-2",
            "-f", "image2pipe",
            "-vcodec", "mjpeg",
            "-q:v", "3",
            "pipe:1"
        ]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            self?.append(data)
        }

        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                guard self.process === process else {
                    return
                }
                self.process = nil
                self.stdoutPipe = nil
                self.stderrPipe = nil
                if self.image == nil {
                    self.errorMessage = errorText?.isEmpty == false ? "Video preview failed." : "Video preview stopped."
                }
            }
        }

        do {
            try process.run()
        } catch {
            stop()
            errorMessage = "Unable to start ffmpeg."
        }
    }

    func stop() {
        currentURL = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        stdoutPipe = nil
        stderrPipe = nil
        queue.sync {
            buffer.removeAll(keepingCapacity: true)
        }
    }

    private func append(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            self.buffer.append(data)
            while let frame = self.nextJPEGFrame() {
                guard let image = NSImage(data: frame) else {
                    continue
                }
                DispatchQueue.main.async {
                    self.image = image
                    self.errorMessage = nil
                }
            }
        }
    }

    private func nextJPEGFrame() -> Data? {
        guard let start = buffer.firstRange(of: Data([0xFF, 0xD8]))?.lowerBound,
              let endRange = buffer[start...].firstRange(of: Data([0xFF, 0xD9])) else {
            if buffer.count > 2_000_000 {
                buffer.removeAll(keepingCapacity: true)
            }
            return nil
        }

        let end = endRange.upperBound
        let frame = buffer[start..<end]
        buffer.removeSubrange(buffer.startIndex..<end)
        return Data(frame)
    }

    deinit {
        stop()
    }

    private static var ffmpegURL: URL? {
        [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        .map(URL.init(fileURLWithPath:))
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
