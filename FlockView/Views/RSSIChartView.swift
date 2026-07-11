import Charts
import SwiftUI

struct RSSIChartView: View {
    var samples: [RSSISample]

    var body: some View {
        let now = Date()
        let start = now.addingTimeInterval(-120)
        let marks = [120, 90, 60, 30, 0].map { now.addingTimeInterval(-TimeInterval($0)) }

        VStack(alignment: .leading, spacing: 10) {
            Text("RSSI History (Last 2 Minutes)")
                .font(.headline)
                .foregroundStyle(FlockTheme.textPrimary)

            Chart(samples) { sample in
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("RSSI", sample.rssi)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(FlockTheme.signalGreen)

                if sample.id == samples.last?.id {
                    PointMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("RSSI", sample.rssi)
                    )
                    .foregroundStyle(FlockTheme.signalGreen)
                }
            }
            .chartYScale(domain: -120 ... -30)
            .chartXScale(domain: start ... now)
            .chartYAxis {
                AxisMarks(values: [-120, -90, -60, -30]) { _ in
                    AxisGridLine()
                        .foregroundStyle(FlockTheme.border)
                    AxisValueLabel()
                        .foregroundStyle(FlockTheme.textSecondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: marks) { value in
                    AxisGridLine()
                        .foregroundStyle(FlockTheme.border)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(axisLabel(for: date, now: now))
                                .foregroundStyle(FlockTheme.textSecondary)
                        }
                    }
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(Color.black.opacity(0.34))
                    .overlay {
                        Rectangle()
                            .stroke(FlockTheme.border, lineWidth: 1)
                    }
            }
            .frame(height: 154)
        }
        .padding(14)
        .flockPanel(cornerRadius: 8)
        .accessibilityLabel("RSSI history chart")
    }

    private func axisLabel(for date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date).rounded())
        return seconds == 0 ? "Now" : "-\(seconds)s"
    }
}

#Preview("RSSI Chart") {
    RSSIChartView(samples: CameraDetection.makeMockDetections().first?.rssiHistory ?? [])
        .environmentObject(AppSettings())
        .frame(width: 480)
        .padding()
        .background(FlockTheme.background)
}
