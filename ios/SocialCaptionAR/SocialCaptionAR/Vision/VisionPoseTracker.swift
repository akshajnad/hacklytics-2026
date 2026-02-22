//
//  VisionPoseTracker.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//


import Foundation
import Vision
import QuartzCore
import CoreGraphics
import ImageIO

/// Tracks body pose (arms) + hand pose (optional).
/// All points returned are normalized in Vision coords (0..1) with origin bottom-left.
final class VisionPoseTracker {
    private let queue = DispatchQueue(label: "vision.pose.queue")
    private let handler = VNSequenceRequestHandler()

    private var lastRun: CFTimeInterval = 0
    private let minInterval: CFTimeInterval = 1.0 / 15.0

    // MUST match your VisionFaceTracker orientation
    private let orientation: CGImagePropertyOrientation = .up

    struct BodyPose: Identifiable {
        let id: Int

        let leftShoulder: CGPoint?
        let leftElbow: CGPoint?
        let leftWrist: CGPoint?

        let rightShoulder: CGPoint?
        let rightElbow: CGPoint?
        let rightWrist: CGPoint?
    }

    struct Output {
        let bodies: [BodyPose]
        /// Centroid of detected finger joints per hand — only emitted when
        /// at least 2 finger MCP/MP joints are visible (i.e. actual hand
        /// open in frame, not just a wrist). Used for face association.
        let handFingerCentroids: [CGPoint]
        let handPoints: [CGPoint]   // all hand joint points (for debug overlay)
    }

    func processFrame(pixelBuffer: CVPixelBuffer,
                      completion: @escaping (Output) -> Void) {
        let now = CACurrentMediaTime()
        if now - lastRun < minInterval { return }
        lastRun = now

        queue.async {
            let bodyReq = VNDetectHumanBodyPoseRequest()
            let handReq = VNDetectHumanHandPoseRequest()
            handReq.maximumHandCount = 4

            do {
                try self.handler.perform([bodyReq, handReq], on: pixelBuffer, orientation: self.orientation)
            } catch {
                completion(Output(bodies: [], handFingerCentroids: [], handPoints: []))
                return
            }

            var bodiesOut: [BodyPose] = []
            if let bodies = bodyReq.results as? [VNHumanBodyPoseObservation] {
                for (idx, b) in bodies.prefix(6).enumerated() {
                    let ls = Self.point(b, .leftShoulder)
                    let le = Self.point(b, .leftElbow)
                    let lw = Self.point(b, .leftWrist)

                    let rs = Self.point(b, .rightShoulder)
                    let re = Self.point(b, .rightElbow)
                    let rw = Self.point(b, .rightWrist)

                    bodiesOut.append(
                        BodyPose(
                            id: idx,
                            leftShoulder: ls, leftElbow: le, leftWrist: lw,
                            rightShoulder: rs, rightElbow: re, rightWrist: rw
                        )
                    )
                }
            }

            var handFingerCentroids: [CGPoint] = []
            var handPts: [CGPoint] = []
            let minFingersRequired = 2  // need at least 2 finger joints visible

            if let hands = handReq.results as? [VNHumanHandPoseObservation] {
                for h in hands.prefix(4) {
                    // Collect wrist for debug
                    if let w = try? h.recognizedPoint(.wrist), w.confidence >= 0.3 {
                        handPts.append(CGPoint(x: w.location.x, y: w.location.y))
                    }

                    // Collect finger MCP/MP joints
                    let fingerJoints: [VNHumanHandPoseObservation.JointName] = [
                        .thumbMP, .indexMCP, .middleMCP, .ringMCP, .littleMCP
                    ]
                    var fingerPts: [CGPoint] = []
                    for j in fingerJoints {
                        if let p = try? h.recognizedPoint(j), p.confidence >= 0.3 {
                            let pt = CGPoint(x: p.location.x, y: p.location.y)
                            fingerPts.append(pt)
                            handPts.append(pt)
                        }
                    }

                    // Only count this hand as "visible" if enough finger joints detected
                    if fingerPts.count >= minFingersRequired {
                        var sx: Double = 0, sy: Double = 0
                        for p in fingerPts { sx += Double(p.x); sy += Double(p.y) }
                        let centroid = CGPoint(x: sx / Double(fingerPts.count),
                                               y: sy / Double(fingerPts.count))
                        handFingerCentroids.append(centroid)
                    }
                }
            }

            completion(Output(bodies: bodiesOut, handFingerCentroids: handFingerCentroids, handPoints: handPts))
        }
    }

    private static func point(_ obs: VNHumanBodyPoseObservation,
                              _ joint: VNHumanBodyPoseObservation.JointName,
                              minConfidence: Float = 0.3) -> CGPoint? {
        guard let p = try? obs.recognizedPoint(joint), p.confidence >= minConfidence else { return nil }
        return CGPoint(x: p.location.x, y: p.location.y)
    }
}
