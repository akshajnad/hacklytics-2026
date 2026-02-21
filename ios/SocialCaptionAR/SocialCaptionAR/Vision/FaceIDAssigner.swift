//
//  FaceIDAssigner.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//


import Foundation
import CoreGraphics

final class FaceIDAssigner {
    private struct Track {
        var id: UUID
        var bbox: CGRect
        var lastSeen: TimeInterval
    }

    private var tracks: [Track] = []
    private let maxDist: CGFloat = 0.18
    private let ttl: TimeInterval = 0.8

    func assignIDs(to detected: [DetectedFace], now: TimeInterval) -> [TrackedFace] {
        tracks.removeAll { now - $0.lastSeen > ttl }

        var used = Set<UUID>()
        var out: [TrackedFace] = []

        for f in detected {
            let c = center(f.visionBoundingBox)

            var bestIdx: Int?
            var bestD: CGFloat = .greatestFiniteMagnitude

            for (i, t) in tracks.enumerated() where !used.contains(t.id) {
                let d = hypot(center(t.bbox).x - c.x, center(t.bbox).y - c.y)
                if d < bestD { bestD = d; bestIdx = i }
            }

            if let idx = bestIdx, bestD < maxDist {
                let id = tracks[idx].id
                used.insert(id)
                tracks[idx].bbox = f.visionBoundingBox
                tracks[idx].lastSeen = now

                out.append(TrackedFace(id: id,
                                      visionBoundingBox: f.visionBoundingBox,
                                      mouthPoints: f.mouthPoints))
            } else {
                let id = UUID()
                tracks.append(Track(id: id, bbox: f.visionBoundingBox, lastSeen: now))
                used.insert(id)

                out.append(TrackedFace(id: id,
                                      visionBoundingBox: f.visionBoundingBox,
                                      mouthPoints: f.mouthPoints))
            }
        }

        return out
    }

    private func center(_ r: CGRect) -> CGPoint {
        CGPoint(x: r.midX, y: r.midY)
    }
}
