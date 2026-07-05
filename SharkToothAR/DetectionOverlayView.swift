import SwiftUI

/// Draws live 2D bounding boxes over the camera feed.
struct DetectionOverlayView: View {
    let detections: [ScreenDetection]

    var body: some View {
        ZStack {
            ForEach(detections) { detection in
                Rectangle()
                    .stroke(.yellow, lineWidth: 2)
                    .frame(width: max(detection.rect.width, 1),
                           height: max(detection.rect.height, 1))
                    .overlay(alignment: .topLeading) {
                        Text("\(detection.label) \(Int(detection.confidence * 100))%")
                            .font(.caption2.bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.yellow)
                            .offset(y: -18)
                    }
                    .position(x: detection.rect.midX, y: detection.rect.midY)
            }
        }
        .allowsHitTesting(false)
    }
}
