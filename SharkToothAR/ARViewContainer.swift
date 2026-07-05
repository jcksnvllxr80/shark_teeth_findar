import SwiftUI
import ARKit
import RealityKit

/// Hosts the RealityKit ARView and feeds camera frames through the detector.
struct ARViewContainer: UIViewRepresentable {
    let appState: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        arView.session.run(configuration)

        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    final class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView?
        private let appState: AppState
        private let detector = ToothDetector()
        private let visionQueue = DispatchQueue(label: "tooth-detection")
        private var isProcessing = false
        private var lastRunTime: TimeInterval = 0

        /// A detection track: the same spot seen across consecutive passes.
        /// Once a track survives `streakToLock` passes, a marker is anchored there.
        private struct Candidate {
            var center: CGPoint
            var streak: Int
            var lastSeen: TimeInterval
        }
        private var candidates: [Candidate] = []
        private var lockedAnchors: [AnchorEntity] = []
        private let streakToLock = 4

        init(appState: AppState) {
            self.appState = appState
            super.init()
            appState.usingCustomModel = detector.usesCustomModel
            appState.clearAction = { [weak self] in self?.clearLockedMarkers() }
        }

        // MARK: - Frame processing

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Throttle to ~6 detection passes per second, one in flight at a time.
            guard !isProcessing, frame.timestamp - lastRunTime > 0.15 else { return }
            guard let arView, arView.bounds.width > 0 else { return }

            isProcessing = true
            lastRunTime = frame.timestamp
            // Keep only the pixel buffer, not the ARFrame, so the camera pipeline isn't stalled.
            let pixelBuffer = frame.capturedImage
            let viewSize = arView.bounds.size
            let timestamp = frame.timestamp

            visionQueue.async { [weak self] in
                guard let self else { return }
                let detections = self.detector.detect(in: pixelBuffer)
                let orientedImageSize = CGSize(width: CVPixelBufferGetHeight(pixelBuffer),
                                               height: CVPixelBufferGetWidth(pixelBuffer))
                DispatchQueue.main.async {
                    self.handle(detections: detections,
                                orientedImageSize: orientedImageSize,
                                viewSize: viewSize,
                                timestamp: timestamp)
                    self.isProcessing = false
                }
            }
        }

        private func handle(detections: [Detection],
                            orientedImageSize: CGSize,
                            viewSize: CGSize,
                            timestamp: TimeInterval) {
            let screenDetections = detections.map { detection in
                ScreenDetection(rect: screenRect(for: detection.boundingBox,
                                                 orientedImageSize: orientedImageSize,
                                                 viewSize: viewSize),
                                label: detection.label,
                                confidence: detection.confidence)
            }
            appState.detections = screenDetections
            updateCandidates(with: screenDetections.map(\.rect), timestamp: timestamp)
        }

        /// Maps a Vision bounding box (normalized, bottom-left origin, portrait image)
        /// to view coordinates. The ARView shows the camera image aspect-filled and
        /// centered, so the image is scaled up and cropped equally on two sides.
        private func screenRect(for box: CGRect,
                                orientedImageSize: CGSize,
                                viewSize: CGSize) -> CGRect {
            let scale = max(viewSize.width / orientedImageSize.width,
                            viewSize.height / orientedImageSize.height)
            let scaled = CGSize(width: orientedImageSize.width * scale,
                                height: orientedImageSize.height * scale)
            let xOffset = (scaled.width - viewSize.width) / 2
            let yOffset = (scaled.height - viewSize.height) / 2
            return CGRect(x: box.minX * scaled.width - xOffset,
                          y: (1 - box.maxY) * scaled.height - yOffset,
                          width: box.width * scaled.width,
                          height: box.height * scaled.height)
        }

        // MARK: - Locking markers in world space

        private func updateCandidates(with rects: [CGRect], timestamp: TimeInterval) {
            for rect in rects {
                let center = CGPoint(x: rect.midX, y: rect.midY)
                if let index = candidates.firstIndex(where: {
                    hypot($0.center.x - center.x, $0.center.y - center.y) < 60
                }) {
                    candidates[index].center = center
                    candidates[index].streak += 1
                    candidates[index].lastSeen = timestamp
                    if candidates[index].streak == streakToLock {
                        lockMarker(at: center)
                    }
                } else {
                    candidates.append(Candidate(center: center, streak: 1, lastSeen: timestamp))
                }
            }
            candidates.removeAll { timestamp - $0.lastSeen > 1.0 }
        }

        /// Raycasts from the detection's screen position into the world and pins
        /// a marker on whatever surface is hit. Skips spots that already have one.
        private func lockMarker(at point: CGPoint) {
            guard let arView,
                  let result = arView.raycast(from: point,
                                              allowing: .estimatedPlane,
                                              alignment: .any).first else { return }

            let position = SIMD3<Float>(result.worldTransform.columns.3.x,
                                        result.worldTransform.columns.3.y,
                                        result.worldTransform.columns.3.z)
            for anchor in lockedAnchors
            where simd_distance(anchor.position(relativeTo: nil), position) < 0.08 {
                return
            }

            let anchor = AnchorEntity(world: result.worldTransform)
            anchor.addChild(Self.makeMarker())
            arView.scene.addAnchor(anchor)
            lockedAnchors.append(anchor)
            appState.lockedCount = lockedAnchors.count
        }

        private func clearLockedMarkers() {
            guard let arView else { return }
            for anchor in lockedAnchors {
                arView.scene.removeAnchor(anchor)
            }
            lockedAnchors.removeAll()
            candidates.removeAll()
            appState.lockedCount = 0
        }

        /// A 6 cm open yellow square that lies flat on the surface it was pinned to.
        private static func makeMarker() -> Entity {
            let side: Float = 0.06
            let thickness: Float = 0.004
            let material = UnlitMaterial(color: .systemYellow)
            let root = Entity()
            let half = side / 2
            let bars: [(position: SIMD3<Float>, size: SIMD3<Float>)] = [
                (SIMD3(0, 0, -half), SIMD3(side + thickness, thickness, thickness)),
                (SIMD3(0, 0, half), SIMD3(side + thickness, thickness, thickness)),
                (SIMD3(-half, 0, 0), SIMD3(thickness, thickness, side + thickness)),
                (SIMD3(half, 0, 0), SIMD3(thickness, thickness, side + thickness)),
            ]
            for bar in bars {
                let box = ModelEntity(mesh: .generateBox(width: bar.size.x,
                                                         height: bar.size.y,
                                                         depth: bar.size.z),
                                      materials: [material])
                box.position = bar.position + SIMD3(0, thickness, 0)
                root.addChild(box)
            }
            return root
        }
    }
}
