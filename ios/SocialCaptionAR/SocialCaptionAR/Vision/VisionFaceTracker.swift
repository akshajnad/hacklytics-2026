//
//  VisionFaceTracker.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//


import Foundation
import Vision
import CoreMedia
import QuartzCore

final class VisionFaceTracker {
    private let queue = DispatchQueue(label: "vision.queue")
    private let handler = VNSequenceRequestHandler()

    // throttle to keep FPS reasonable
    private var lastRun: CFTimeInterval = 0
    private let minInterval: CFTimeInterval = 1.0 / 15.0 // 15 fps vision

    func processFrame(pixelBuffer: CVPixelBuffer,
                      timestamp: CMTime,
                      completion: @escaping ([DetectedFace]) -> Void) {

        let now = CACurrentMediaTime()
        if now - lastRun < minInterval { return }
        lastRun = now

        queue.async {
            let req = VNDetectFaceLandmarksRequest()
            do {
                try self.handler.perform([req], on: pixelBuffer, orientation: .right) // portrait, back camera
            } catch {
                completion([])
                return
            }

            guard let results = req.results as? [VNFaceObservation] else {
                completion([])
                return
            }

            let faces: [DetectedFace] = results.map { obs in
                let rectTopLeft = Self.visionRectToTopLeft(obs.boundingBox)

                // Landmarks
                let landmarks = obs.landmarks
                let mouthLocal = Self.mouthLocalCenter(landmarks: landmarks)
                let mouthOpen = Self.mouthOpenness(landmarks: landmarks)
                let browRaise = Self.browRaise(landmarks: landmarks)

                return DetectedFace(
                    rect: rectTopLeft,
                    mouthLocalCenter: mouthLocal,
                    mouthOpen: mouthOpen,
                    browRaise: browRaise
                )
            }

            completion(faces)
        }
    }

    // Vision boundingBox is normalized with origin bottom-left.
    // Convert to normalized with origin top-left (easier in SwiftUI).
    private static func visionRectToTopLeft(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX,
               y: 1.0 - r.maxY,
               width: r.width,
               height: r.height)
    }

    // Returns mouth center in local face coords [0..1] with origin top-left
    private static func mouthLocalCenter(landmarks: VNFaceLandmarks2D?) -> CGPoint? {
        guard let pts = landmarks?.outerLips?.normalizedPoints, !pts.isEmpty else { return nil }
        // pts are in local face coords with origin bottom-left
        let avg = pts.reduce(CGPoint.zero) { partial, p in
            CGPoint(x: partial.x + CGFloat(p.x), y: partial.y + CGFloat(p.y))
        }
        let x = avg.x / CGFloat(pts.count)
        let yBottomLeft = avg.y / CGFloat(pts.count)
        let yTopLeft = 1.0 - yBottomLeft
        return CGPoint(x: x, y: yTopLeft)
    }

    // Mouth openness as fraction of face height (0..1-ish)
    private static func mouthOpenness(landmarks: VNFaceLandmarks2D?) -> CGFloat? {
        guard let pts = landmarks?.innerLips?.normalizedPoints, !pts.isEmpty else { return nil }
        let ys = pts.map { CGFloat($0.y) } // bottom-left
        guard let minY = ys.min(), let maxY = ys.max() else { return nil }
        return maxY - minY
    }

    // Brow raise proxy: distance between eyebrow and eye (0..1-ish)
    private static func browRaise(landmarks: VNFaceLandmarks2D?) -> CGFloat? {
        guard
            let brow = landmarks?.leftEyebrow?.normalizedPoints, !brow.isEmpty,
            let eye = landmarks?.leftEye?.normalizedPoints, !eye.isEmpty
        else { return nil }

        let browY = brow.map { CGFloat($0.y) }.reduce(0, +) / CGFloat(brow.count)
        let eyeY = eye.map { CGFloat($0.y) }.reduce(0, +) / CGFloat(eye.count)

        // In bottom-left coords, eyebrow should be above eye, so browY > eyeY
        return max(0, browY - eyeY)
    }
}
