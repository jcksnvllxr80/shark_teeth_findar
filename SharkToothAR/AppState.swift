import SwiftUI

/// A detection converted to screen coordinates, ready to draw as an overlay.
struct ScreenDetection: Identifiable {
    let id = UUID()
    let rect: CGRect
    let label: String
    let confidence: Float
}

/// Shared state between the AR session and the SwiftUI overlay.
/// All access happens on the main thread.
final class AppState: ObservableObject {
    @Published var detections: [ScreenDetection] = []
    @Published var usingCustomModel = false
    @Published var lockedCount = 0

    /// Set by the AR coordinator so the UI's Clear button can remove locked markers.
    var clearAction: (() -> Void)?
}
