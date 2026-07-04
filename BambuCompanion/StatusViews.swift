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
                if shouldShowCoverImage {
                    CoverImageView(state: coverImageState, size: CGSize(width: 84, height: 84))
                }

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
                BedChamberMetricView(
                    bedTemperature: temperature(status.bedTemperature),
                    bedDetail: temperature(status.bedTemperature, target: status.targetBedTemperature),
                    chamberTemperature: status.chamberTemperature.map { temperature($0) },
                    chamberDetail: status.chamberTemperature.map { _ in
                        temperature(status.chamberTemperature, target: status.targetChamberTemperature)
                    }
                )
                RemainingMetricView(value: remainingTime, completionDate: estimatedCompletionDate)
                if status.fans.hasAnyValue || status.airductMode != nil {
                    FanMetricView(fans: status.fans, airductMode: status.airductMode)
                }
            }

            if !status.amsUnits.isEmpty {
                AMSUnitsView(units: status.amsUnits)
            }
        }
    }

    private var shouldShowCoverImage: Bool {
        switch coverImageState {
        case .ready, .loading:
            true
        case .failed, .unavailable:
            false
        }
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    private var statusDetail: String {
        status.jobName?.isEmpty == false ? status.jobName! : L10n.string("No active job")
    }

    private var layerText: String? {
        guard let currentLayer = status.currentLayer, currentLayer > 0 else {
            return nil
        }
        if let totalLayers = status.totalLayers, totalLayers > 0 {
            return L10n.format("Layer %d/%d", currentLayer, totalLayers)
        }
        return L10n.format("Layer %d", currentLayer)
    }

    private var progressBadge: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(status.progress ?? 0)%")
                .font(.system(.title3, design: .rounded, weight: .semibold))

            if let layerText {
                Text(layerText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .monospacedDigit()
        .frame(minWidth: 58, alignment: .trailing)
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
            lines.append(L10n.format("Temperature: %@", TemperatureText.string(temperature)))
        }
        if let humidityPercent = unit.humidityPercent {
            lines.append(L10n.format("Humidity: %d%%", humidityPercent))
        } else if let humidityIndex = unit.humidityIndex {
            lines.append(L10n.format("Humidity index: %d", humidityIndex))
        }
        if unit.isDrying {
            lines.append(L10n.format("Drying: %@ remaining", dryingRemainingText(unit.dryingRemainingMinutes)))
            if let dryingTemperature = unit.dryingTemperature {
                lines.append(L10n.format("Drying temperature: %@", TemperatureText.string(dryingTemperature)))
            }
            if let dryingFilament = unit.dryingFilament {
                lines.append(L10n.format("Drying filament: %@", dryingFilament))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                AMSUnitLabelView(unit: unit)
                    .help(helpText)

                Spacer(minLength: 8)

                AMSUnitStatusLine(unit: unit)
                    .help(helpText)
            }

            HStack(spacing: 6) {
                ForEach(unit.slots) { slot in
                    AMSSlotView(slot: slot)
                }
            }
        }
        .padding(.vertical, 3)
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

private struct AMSUnitStatusLine: View {
    let unit: AMSUnitStatus

    var body: some View {
        HStack(spacing: 8) {
            if unit.isDrying {
                HStack(spacing: 3) {
                    Image(systemName: "timer")
                    Text(dryingRemainingText(unit.dryingRemainingMinutes))
                }

                if let dryingTemperature = unit.dryingTemperature {
                    HStack(spacing: 3) {
                        Image(systemName: "sun.max")
                        Text(TemperatureText.string(dryingTemperature))
                    }
                }
            }

            if let temperature = unit.temperature {
                HStack(spacing: 3) {
                    Image(systemName: "thermometer.medium")
                    Text(TemperatureText.string(temperature))
                }
            }

            if let humidityText {
                HStack(spacing: 3) {
                    Image(systemName: "humidity")
                    Text(humidityText)
                }
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(unit.isDrying ? .orange : .secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .monospacedDigit()
    }

    private var humidityText: String? {
        if let humidityPercent = unit.humidityPercent {
            return "\(humidityPercent)%"
        }
        if let humidityIndex = unit.humidityIndex {
            return "\(humidityIndex)"
        }
        return nil
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
        .frame(maxWidth: .infinity, minHeight: 34)
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
        var lines: [String] = [L10n.format("Slot %d", slot.index + 1)]
        lines.append(L10n.format("Material: %@", slot.material ?? L10n.string("Empty")))
        append(L10n.string("Name"), slot.name, to: &lines)
        append(L10n.string("Brand"), slot.subBrands, to: &lines)
        append(L10n.string("Color"), slot.colorHex.map { "#\($0)" }, to: &lines)
        if let remainingPercent = slot.remainingPercent {
            lines.append(L10n.format("Remaining: %d%%", remainingPercent))
        }
        append(L10n.string("Spool ID"), slot.trayInfoIndex, to: &lines)
        append(L10n.string("Tag UID"), slot.tagUID, to: &lines)
        if let diameter = slot.diameter {
            lines.append(L10n.format("Diameter: %@ mm", diameter.formatted(.number.precision(.fractionLength(2)))))
        }
        if let remainingWeight = slot.remainingWeight {
            lines.append(L10n.format("Estimated remaining weight: %@ g", remainingWeight.formatted(.number.precision(.fractionLength(0)))))
        }
        if slot.nozzleTemperatureMin != nil || slot.nozzleTemperatureMax != nil {
            lines.append(L10n.format("Nozzle range: %@", temperatureRangeText))
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
            placeholder(icon: "photo", text: L10n.string("Loading cover image"))
        case .failed, .unavailable:
            EmptyView()
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
    let title: LocalizedStringKey
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

private struct DynamicMetricView: View {
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

private struct BedChamberMetricView: View {
    let bedTemperature: String
    let bedDetail: String
    let chamberTemperature: String?
    let chamberDetail: String?

    var body: some View {
        MetricView(title: chamberTemperature == nil ? "Bed" : "Bed / Chamber", value: value)
            .help(helpText)
    }

    private var value: String {
        guard let chamberTemperature else {
            return bedTemperature
        }
        return "\(bedTemperature) / \(chamberTemperature)"
    }

    private var helpText: String {
        var lines = [L10n.format("Bed: %@", bedDetail)]
        if let chamberDetail {
            lines.append(L10n.format("Chamber: %@", chamberDetail))
        }
        return lines.joined(separator: "\n")
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
            return L10n.string("Estimated completion unavailable")
        }
        return L10n.format("Estimated completion: %@", Self.completionFormatter.string(from: completionDate))
    }

    private static let completionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private enum AirductModeText {
    static func value(for rawMode: String) -> String {
        switch normalizedMode(rawMode) {
        case "0", "cooling":
            return L10n.string("Cooling")
        case "1", "heating":
            return L10n.string("Chamber hold")
        case "2", "laser":
            return L10n.string("Laser")
        default:
            return rawMode
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
    }

    private static func normalizedMode(_ rawMode: String) -> String {
        rawMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct FanMetricView: View {
    let fans: PrinterFanStatus
    let airductMode: String?

    var body: some View {
        DynamicMetricView(title: title, value: value)
            .help(helpText)
    }

    private var title: String {
        guard let airductMode else {
            return L10n.string("Fan")
        }
        return AirductModeText.value(for: airductMode)
    }

    private var value: String {
        let activePercents = fanPercents(showingZeroValues: false)
        if activePercents.isEmpty {
            return L10n.string("Off")
        }
        return activePercents.joined(separator: " / ")
    }

    private var helpText: String {
        fanLines(showingZeroValues: true).joined(separator: "\n")
    }

    private func fanLines(showingZeroValues: Bool) -> [String] {
        [
            fanLine("Part", fans.partCoolingPercent, showingZeroValues: showingZeroValues),
            fanLine("Aux", fans.auxiliaryPercent, showingZeroValues: showingZeroValues),
            fanLine("Chamber", fans.chamberPercent, showingZeroValues: showingZeroValues),
            fanLine("Heatbreak", fans.heatbreakPercent, showingZeroValues: showingZeroValues)
        ].compactMap(\.self)
    }

    private func fanPercents(showingZeroValues: Bool) -> [String] {
        [
            fanPercent(fans.partCoolingPercent, showingZeroValues: showingZeroValues),
            fanPercent(fans.auxiliaryPercent, showingZeroValues: showingZeroValues),
            fanPercent(fans.chamberPercent, showingZeroValues: showingZeroValues),
            fanPercent(fans.heatbreakPercent, showingZeroValues: showingZeroValues)
        ].compactMap(\.self)
    }

    private func fanPercent(_ percent: Int?, showingZeroValues: Bool) -> String? {
        guard let percent, showingZeroValues || percent > 0 else {
            return nil
        }
        return "\(percent)%"
    }

    private func fanLine(_ name: String, _ percent: Int?, showingZeroValues: Bool) -> String? {
        guard let percent, showingZeroValues || percent > 0 else {
            return nil
        }
        return "\(L10n.string(name)) \(percent)%"
    }
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

    var body: some View {
        NativeVideoPreviewView(url: url)
    }
}
