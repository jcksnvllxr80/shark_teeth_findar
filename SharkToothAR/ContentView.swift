import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        ZStack {
            ARViewContainer(appState: appState)
                .ignoresSafeArea()

            DetectionOverlayView(detections: appState.detections)
                .ignoresSafeArea()

            VStack {
                statusBar
                Spacer()
                if appState.lockedCount > 0 {
                    clearButton
                }
            }
        }
    }

    private var statusBar: some View {
        VStack(spacing: 2) {
            Text(appState.usingCustomModel
                 ? "Shark tooth model loaded"
                 : "Demo mode: boxing any object that stands out")
                .font(.footnote.bold())
            Text("\(appState.detections.count) in view · \(appState.lockedCount) locked")
                .font(.caption2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55), in: Capsule())
        .padding(.top, 8)
    }

    private var clearButton: some View {
        Button("Clear locked markers") {
            appState.clearAction?()
        }
        .font(.footnote.bold())
        .foregroundStyle(.black)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.yellow, in: Capsule())
        .padding(.bottom, 16)
    }
}
