import SwiftUI

struct StatusSummaryView: View {
    let status: PrinterStatus
    let coverImageState: CoverImageState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                CoverImageView(state: coverImageState, size: CGSize(width: 108, height: 108))

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(status.activity.title)
                                .font(.title3.bold())
                            Text(status.jobName?.isEmpty == false ? status.jobName! : "No active job")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 8)
                        progressBadge
                    }

                    ProgressView(value: Double(status.progress ?? 0), total: 100)
                }
                .padding(.top, 2)
            }

            HStack(spacing: 10) {
                nozzleMetric
                MetricView(title: "Bed", value: temperature(status.bedTemperature))
                MetricView(title: "Remaining", value: remainingTime)
            }

            if !status.amsUnits.isEmpty {
                AMSUnitsView(units: status.amsUnits)
            }
        }
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

    @ViewBuilder
    private var nozzleMetric: some View {
        if status.leftNozzleTemperature != nil || status.rightNozzleTemperature != nil {
            DualNozzleMetricView(
                leftTemperature: temperature(status.leftNozzleTemperature),
                rightTemperature: temperature(status.rightNozzleTemperature)
            )
        } else {
            MetricView(title: "Nozzle", value: temperature(status.nozzleTemperature))
        }
    }

    private func temperature(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return "\(Int(value.rounded())) C"
    }
}

private struct AMSUnitsView: View {
    let units: [AMSUnitStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(units) { unit in
                HStack(spacing: 8) {
                    Text(unit.name)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 44, alignment: .leading)

                    HStack(spacing: 6) {
                        ForEach(unit.slots) { slot in
                            AMSSlotView(slot: slot)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
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
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
    }

    private var slotColor: Color {
        guard let colorHex = slot.colorHex,
              let color = Color(hexRGB: colorHex) else {
            return .clear
        }
        return color
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
            .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct VideoPlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "video.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Video preview is not enabled in this version.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 116)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
