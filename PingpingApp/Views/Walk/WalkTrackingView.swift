import SwiftUI
import SwiftData
import MapKit

struct WalkTrackingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = WalkSessionViewModel()

    var body: some View {
        VStack(spacing: 16) {
            Map {
                MapPolyline(coordinates: session.locationManager.currentPoints.map(\.coordinate))
                    .stroke(.orange, lineWidth: 4)
            }
            .frame(height: 320)

            HStack(spacing: 32) {
                VStack {
                    Text(formattedElapsed).font(.title.monospacedDigit())
                    Text("时长").font(.caption).foregroundStyle(.secondary)
                }
                VStack {
                    Text(String(format: "%.0f 米", session.distanceMeters))
                        .font(.title.monospacedDigit())
                    Text("距离").font(.caption).foregroundStyle(.secondary)
                }
            }

            Button(session.locationManager.isTracking ? "结束遛狗" : "开始遛狗") {
                if session.locationManager.isTracking {
                    session.finish(context: context)
                    dismiss()
                } else {
                    session.start()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(session.locationManager.isTracking ? .red : .orange)
        }
        .padding()
        .navigationTitle("遛平平")
    }

    private var formattedElapsed: String {
        let minutes = session.elapsedSeconds / 60
        let seconds = session.elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
