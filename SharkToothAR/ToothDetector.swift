import Vision
import CoreML
import CoreVideo

/// One detected object, in Vision's coordinate space: normalized (0-1) with the
/// origin at the bottom-left of the upright (portrait) camera image.
struct Detection {
    let boundingBox: CGRect
    let label: String
    let confidence: Float
}

/// Runs machine vision on camera frames.
///
/// If a compiled Core ML object-detection model named `SharkToothDetector` is
/// bundled with the app, it is used. Otherwise the detector falls back to
/// Vision's built-in salient-object request, which draws boxes around whatever
/// stands out in the frame — good enough to prove the AR pipeline works before
/// a real shark-tooth model is trained.
final class ToothDetector {
    private let coreMLModel: VNCoreMLModel?

    var usesCustomModel: Bool { coreMLModel != nil }

    init() {
        if let url = Bundle.main.url(forResource: "SharkToothDetector", withExtension: "mlmodelc"),
           let model = try? MLModel(contentsOf: url) {
            coreMLModel = try? VNCoreMLModel(for: model)
        } else {
            coreMLModel = nil
        }
    }

    /// Synchronously detects objects in a camera frame. Call from a background queue.
    /// The pixel buffer arrives in landscape sensor orientation; `.right` tells
    /// Vision to treat it as portrait, so results come back in upright coordinates.
    func detect(in pixelBuffer: CVPixelBuffer) -> [Detection] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)

        if let coreMLModel {
            let request = VNCoreMLRequest(model: coreMLModel)
            request.imageCropAndScaleOption = .scaleFill
            try? handler.perform([request])
            let observations = request.results as? [VNRecognizedObjectObservation] ?? []
            return observations.compactMap { observation in
                guard observation.confidence > 0.5 else { return nil }
                let label = observation.labels.first?.identifier ?? "shark tooth"
                return Detection(boundingBox: observation.boundingBox,
                                 label: label,
                                 confidence: observation.confidence)
            }
        } else {
            let request = VNGenerateObjectnessBasedSaliencyImageRequest()
            try? handler.perform([request])
            guard let result = request.results?.first,
                  let objects = result.salientObjects else { return [] }
            return objects
                .filter { $0.confidence > 0.5 }
                .map { Detection(boundingBox: $0.boundingBox,
                                 label: "object (demo)",
                                 confidence: $0.confidence) }
        }
    }
}
