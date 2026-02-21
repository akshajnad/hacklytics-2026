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
        var rect: CGRect
        var lastSeen: TimeInterval
    }

    private var tracks: [Track] = []
    private let maxDist: CGFloat = 0.18 // normalized distance threshold
    private let ttl: TimeInterval = 0.8

    func assignIDs(to detected: [DetectedFace], now: TimeInterval) -> [TrackedFace] {
        // prune old tracks
        tracks.removeAll { now - $0.lastSeen > ttl }

        var usedTrackIDs = Set<UUID>()
        var result: [TrackedFace] = []

        for face in detected {
            let c = center(face.rect)

            // find closest unused track
            var bestIdx: Int? = nil
            var bestD: CGFloat = .greatestFiniteMagnitude

            for (i, t) in tracks.enumerated() where !usedTrackIDs.contains(t.id) {
                let d = distance(center(t.rect), c)
                if d < bestD {
                    bestD = d
                    bestIdx = i
                }
            }

            if let idx = bestIdx, bestD < maxDist {
                // reuse existing
                let id = tracks[idx].id
                usedTrackIDs.insert(id)

                tracks[idx].rect = face.rect
                tracks[idx].lastSeen = now

                result.append(TrackedFace(
                    id: id,
                    rect: face.rect,
                    mouthLocalCenter: face.mouthLocalCenter,
                    mouthOpen: face.mouthOpen,
                    browRaise: face.browRaise
                ))
            } else {
                // new track
                let id = UUID()
                tracks.append(Track(id: id, rect: face.rect, lastSeen: now))
                usedTrackIDs.insert(id)

                result.append(TrackedFace(
                    id: id,
                    rect: face.rect,
                    mouthLocalCenter: face.mouthLocalCenter,
                    mouthOpen: face.mouthOpen,
                    browRaise: face.browRaise
                ))
            }
        }

        return result
    }

    private func center(_ r: CGRect) -> CGPoint {
        CGPoint(x: r.midX, y: r.midY)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}