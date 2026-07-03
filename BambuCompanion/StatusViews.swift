import SwiftUI

struct StatusSummaryView: View {
    let status: PrinterStatus
    let coverImageState: CoverImageState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CoverImageView(state: coverImageState)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.activity.title)
                        .font(.title3.bold())
                    Text(status.jobName?.isEmpty == false ? status.jobName! : "No active job")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                progressBadge
            }

            ProgressView(value: Double(status.progress ?? 0), total: 100)

            HStack(spacing: 10) {
                MetricView(title: "Nozzle", value: temperature(status.nozzleTemperature))
                MetricView(title: "Bed", value: temperature(status.bedTemperature))
                MetricView(title: "Remaining", value: remainingTime)
            }

            if let filamentSummary = status.filamentSummary {
                Text(filamentSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var progressBadge: some View {
        Text("\(status.progress ?? 0)%")
            .font(.system(.title3, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .frame(minWidth: 54, minHeight: 34)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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

    private func temperature(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return "\(Int(value.rounded())) C"
    }
}

private struct CoverImageView: View {
    let state: CoverImageState

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
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        case .loading:
            placeholder(icon: "photo", text: "Loading cover image")
        case .failed:
            placeholder(icon: "photo.badge.exclamationmark", text: "Cover image unavailable")
        case .unavailable:
            EmptyView()
        }
    }

    private func placeholder(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
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
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
