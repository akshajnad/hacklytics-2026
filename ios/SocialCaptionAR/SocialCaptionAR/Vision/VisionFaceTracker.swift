//
//  VisionFaceTracker.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//


import Foundation
import Vision
import QuartzCore

final class VisionFaceTracker {
    private let queue = DispatchQueue(label: "vision.queue")
    private let handler = VNSequenceRequestHandler()

    private var lastRun: CFTimeInterval = 0
    private let minInterval: CFTimeInterval = 1.0 / 15.0

    func processFrame(pixelBuffer: CVPixelBuffer,
                      completion: @escaping ([DetectedFace]) -> Void) {

        let now = CACurrentMediaTime()
        if now - lastRun < minInterval { return }
        lastRun = now

        queue.async {
            let req = VNDetectFaceLandmarksRequest()
            do {
                // For landscape-right camera feed, this is typically correct.
                // If boxes are rotated 90°, swap to .right/.left and test once.
                try self.handler.perform([req], on: pixelBuffer, orientation: .up)
            } catch {
                completion([])
                return
            }

            guard let results = req.results as? [VNFaceObservation] else {
                completion([])
                return
            }

            let detected = results.map { obs -> DetectedFace in
                let bbox = obs.boundingBox // normalized, origin bottom-left

                // Mouth points (outer lips)
                var mouthPts: [CGPoint] = []
                if let pts = obs.landmarks?.outerLips?.normalizedPoints {
                    mouthPts = pts.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) } // still bottom-left
                }

                return DetectedFace(visionBoundingBox: bbox, mouthPoints: mouthPts)
            }

            completion(detected)
        }
    }
}
