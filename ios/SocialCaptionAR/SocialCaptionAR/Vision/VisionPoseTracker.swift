import Foundation
import Vision
import QuartzCore
import CoreGraphics
import ImageIO

/// Runs Vision Body + Hand pose on-device.
/// Returns normalized points (0..1) in the SAME coordinate space as Vision face bounding boxes
/// (origin bottom-left), so we can fuse directly with face bbox values.
final class VisionPoseTracker {
    private let queue = DispatchQueue(label: "vision.pose.queue")
    private let handler = VNSequenceRequestHandler()

    private var lastRun: CFTimeInterval = 0
    private let minInterval: CFTimeInterval = 1.0 / 15.0

    // Keep the same orientation you use in VisionFaceTracker
    private let orientation: CGImagePropertyOrientation = .up

    struct Output {
        let bodyPoints: [CGPoint]   // wrists/elbows/shoulders (normalized, bottom-left)
        let handPoints: [CGPoint]   // wrist + MCPs (normalized, bottom-left)
    }

    func processFrame(pixelBuffer: CVPixelBuffer,
                      completion: @escaping (Output) -> Void) {
        let now = CACurrentMediaTime()
        if now - lastRun < minInterval { return }
        lastRun = now

        queue.async {
            var bodyPts: [CGPoint] = []
            var handPts: [CGPoint] = []

            // --- Body pose request ---
            let bodyReq = VNDetectHumanBodyPoseRequest()
            // NOTE: Some iOS/Vision versions do NOT have maximumHumanCount here.
            // We'll just cap points used downstream.

            // --- Hand pose request ---
            let handReq = VNDetectHumanHandPoseRequest()
            handReq.maximumHandCount = 4

            do {
                try self.handler.perform([bodyReq, handReq], on: pixelBuffer, orientation: self.orientation)
            } catch {
                completion(Output(bodyPoints: [], handPoints: []))
                return
            }

            // Body points
            if let bodies = bodyReq.results as? [VNHumanBodyPoseObservation] {
                // cap bodies used (demo-friendly)
                for b in bodies.prefix(6) {
                    let joints: [VNHumanBodyPoseObservation.JointName] = [
                        .leftWrist, .rightWrist,
                        .leftElbow, .rightElbow,
                        .leftShoulder, .rightShoulder
                    ]

                    for j in joints {
                        if let p = try? b.recognizedPoint(j), p.confidence >= 0.3 {
                            bodyPts.append(CGPoint(x: p.location.x, y: p.location.y))
                        }
                    }
                }
            }

            // Hand points
            if let hands = handReq.results as? [VNHumanHandPoseObservation] {
                for h in hands.prefix(4) {
                    let joints: [VNHumanHandPoseObservation.JointName] = [
                        .wrist,
                        .thumbMP, .indexMCP, .middleMCP, .ringMCP, .littleMCP
                    ]

                    for j in joints {
                        if let p = try? h.recognizedPoint(j), p.confidence >= 0.3 {
                            handPts.append(CGPoint(x: p.location.x, y: p.location.y))
                        }
                    }
                }
            }

            completion(Output(bodyPoints: bodyPts, handPoints: handPts))
        }
    }
}
