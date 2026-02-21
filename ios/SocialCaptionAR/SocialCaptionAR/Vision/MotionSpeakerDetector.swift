//
//  MotionSpeakerDetector.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//


import Foundation
import CoreGraphics

/// Speaker selection driven primarily by hand + arm/body motion.
/// Keeps captions under SOME face always (fallback to largest face).
final class MotionSpeakerDetector {

    struct Output {
        let activeFaceId: UUID?
        let didChange: Bool
    }

    private struct PerFaceState {
        var lastAssignedHandCentroid: CGPoint?
        var lastAssignedBodyCentroid: CGPoint?
        var lastMouthCentroid: CGPoint?

        var handEnergyEMA: Double = 0
        var bodyEnergyEMA: Double = 0
        var mouthEnergyEMA: Double = 0

        var lastUpdate: TimeInterval = 0
    }

    private var states: [UUID: PerFaceState] = [:]
    private var activeFaceId: UUID? = nil

    private var challengerId: UUID? = nil
    private var challengerSince: TimeInterval = 0
    private var lockUntil: TimeInterval = 0

    // --- Tunables (demo-friendly) ---
    private let ttl: TimeInterval = 1.2
    private let alpha: Double = 0.25

    // weights: hand dominates
    private let wHand: Double = 1.0
    private let wBody: Double = 0.55
    private let wMouth: Double = 0.20

    // switching behavior
    private let switchHold: TimeInterval = 0.45
    private let lockDuration: TimeInterval = 0.85
    private let winRatio: Double = 1.35
    private let winMargin: Double = 0.006

    // gating
    private let assignMaxDist: Double = 0.28

    func update(faces: [TrackedFace],
                poseBodyPoints: [CGPoint],
                poseHandPoints: [CGPoint],
                now: TimeInterval) -> Output {

        states = states.filter { now - $0.value.lastUpdate < ttl }

        guard !faces.isEmpty else {
            return Output(activeFaceId: nil, didChange: false)
        }

        let faceInfo: [(id: UUID, center: CGPoint, area: Double, bbox: CGRect, mouth: [CGPoint])] = faces.map { f in
            let bb = f.visionBoundingBox
            let center = CGPoint(x: bb.midX, y: bb.midY)
            let area = Double(bb.width * bb.height)
            return (f.id, center, area, bb, f.mouthPoints)
        }

        let handCentroid = centroid(of: poseHandPoints)
        let bodyCentroid = centroid(of: poseBodyPoints)

        for finfo in faceInfo {
            var st = states[finfo.id] ?? PerFaceState()

            // Hand motion energy
            if let hc = handCentroid {
                let d = hypot(Double(hc.x - finfo.center.x), Double(hc.y - finfo.center.y))
                if d <= assignMaxDist {
                    if let last = st.lastAssignedHandCentroid {
                        let dm = hypot(Double(hc.x - last.x), Double(hc.y - last.y))
                        st.handEnergyEMA = (1 - alpha) * st.handEnergyEMA + alpha * dm
                    }
                    st.lastAssignedHandCentroid = hc
                } else {
                    st.lastAssignedHandCentroid = nil
                    st.handEnergyEMA = (1 - alpha) * st.handEnergyEMA
                }
            } else {
                st.lastAssignedHandCentroid = nil
                st.handEnergyEMA = (1 - alpha) * st.handEnergyEMA
            }

            // Body motion energy
            if let bc = bodyCentroid {
                let d = hypot(Double(bc.x - finfo.center.x), Double(bc.y - finfo.center.y))
                if d <= assignMaxDist {
                    if let last = st.lastAssignedBodyCentroid {
                        let dm = hypot(Double(bc.x - last.x), Double(bc.y - last.y))
                        st.bodyEnergyEMA = (1 - alpha) * st.bodyEnergyEMA + alpha * dm
                    }
                    st.lastAssignedBodyCentroid = bc
                } else {
                    st.lastAssignedBodyCentroid = nil
                    st.bodyEnergyEMA = (1 - alpha) * st.bodyEnergyEMA
                }
            } else {
                st.lastAssignedBodyCentroid = nil
                st.bodyEnergyEMA = (1 - alpha) * st.bodyEnergyEMA
            }

            // Mouth energy (fallback)
            if let mc = centroid(of: finfo.mouth) {
                if let last = st.lastMouthCentroid {
                    let dm = hypot(Double(mc.x - last.x), Double(mc.y - last.y))
                    st.mouthEnergyEMA = (1 - alpha) * st.mouthEnergyEMA + alpha * dm
                }
                st.lastMouthCentroid = mc
            } else {
                st.lastMouthCentroid = nil
                st.mouthEnergyEMA = (1 - alpha) * st.mouthEnergyEMA
            }

            st.lastUpdate = now
            states[finfo.id] = st
        }

        var scored: [(id: UUID, score: Double, area: Double)] = []
        scored.reserveCapacity(faceInfo.count)

        for finfo in faceInfo {
            guard let st = states[finfo.id] else { continue }
            let score = wHand * st.handEnergyEMA + wBody * st.bodyEnergyEMA + wMouth * st.mouthEnergyEMA
            scored.append((finfo.id, score, finfo.area))
        }

        scored.sort {
            if abs($0.score - $1.score) > 1e-9 { return $0.score > $1.score }
            return $0.area > $1.area
        }

        let top = scored[0]

        if activeFaceId == nil {
            activeFaceId = biggestFaceId(faceInfo)
        }

        if now < lockUntil {
            return Output(activeFaceId: activeFaceId, didChange: false)
        }

        let currentId = activeFaceId ?? top.id
        let currentScore = scored.first(where: { $0.id == currentId })?.score ?? 0.00001

        if top.id == currentId {
            challengerId = nil
            return Output(activeFaceId: activeFaceId, didChange: false)
        }

        let isClearWinner = (top.score >= currentScore * winRatio) && ((top.score - currentScore) >= winMargin)

        if isClearWinner {
            if challengerId != top.id {
                challengerId = top.id
                challengerSince = now
            } else {
                if now - challengerSince >= switchHold {
                    activeFaceId = top.id
                    challengerId = nil
                    lockUntil = now + lockDuration
                    return Output(activeFaceId: activeFaceId, didChange: true)
                }
            }
        } else {
            challengerId = nil
        }

        if !faceInfo.contains(where: { $0.id == currentId }) {
            activeFaceId = biggestFaceId(faceInfo)
            return Output(activeFaceId: activeFaceId, didChange: true)
        }

        return Output(activeFaceId: activeFaceId, didChange: false)
    }

    private func centroid(of pts: [CGPoint]) -> CGPoint? {
        guard !pts.isEmpty else { return nil }
        var sx: Double = 0
        var sy: Double = 0
        for p in pts {
            sx += Double(p.x)
            sy += Double(p.y)
        }
        return CGPoint(x: sx / Double(pts.count), y: sy / Double(pts.count))
    }

    private func biggestFaceId(_ faces: [(id: UUID, center: CGPoint, area: Double, bbox: CGRect, mouth: [CGPoint])]) -> UUID? {
        faces.max(by: { $0.area < $1.area })?.id
    }
}

