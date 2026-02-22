//
//  MotionSpeakerDetector.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//

import Foundation
import CoreGraphics


final class MotionSpeakerDetector {

    struct Output {
        let activeFaceId: UUID?
        let didChange: Bool
        let perFaceScores: [UUID: Double]
    }

    // MARK: - Per-face state

    private struct PerFaceState {
        // Arm motion (tracked per-wrist from associated body)
        var lastLeftWrist: CGPoint?
        var lastRightWrist: CGPoint?
        var lastLeftElbow: CGPoint?
        var lastRightElbow: CGPoint?
        var armEnergyEMA: Double = 0

        // Hand visibility (smoothed to survive brief detection drops)
        var handsVisibleEMA: Double = 0

        // Mouth motion (tie-breaker)
        var lastMouthCentroid: CGPoint?
        var mouthEnergyEMA: Double = 0

        var lastUpdate: TimeInterval = 0
        var lastScore: Double = 0
    }

    private var states: [UUID: PerFaceState] = [:]
    private var activeFaceId: UUID? = nil

    // Challenger tracking for hysteresis
    private var challengerId: UUID? = nil
    private var challengerSince: TimeInterval = 0
    private var lockUntil: TimeInterval = 0

    // MARK: - Tunables (demo-friendly)

    private let ttl: TimeInterval = 1.5
    private let motionAlpha: Double = 0.20        // EMA for motion energy
    private let handAlpha: Double = 0.12          // EMA for hand visibility (slower → resists flicker)

    // Scoring weights — hand visibility is THE decision
    private let wHands: Double = 1.0              // hand visible EMA (0..1) IS the score
    private let wArms: Double = 0.001             // negligible tie-breaker
    private let wMouth: Double = 0.0005           // negligible tie-breaker

    // Hysteresis
    private let switchHoldDuration: TimeInterval = 0.45
    private let lockDuration: TimeInterval = 0.90
    private let winRatio: Double = 1.25
    private let winMargin: Double = 0.003

    // Body/hand → face association thresholds (normalized coords)
    private let bodyAssignMaxHorizDist: Double = 0.25
    private let handAssignMaxHorizDist: Double = 0.30

    // MARK: - Public API

    func update(faces: [TrackedFace],
                bodies: [VisionPoseTracker.BodyPose],
                handFingerCentroids: [CGPoint],
                now: TimeInterval) -> Output {

        // Prune stale per-face state
        states = states.filter { now - $0.value.lastUpdate < ttl }

        guard !faces.isEmpty else {
            activeFaceId = nil
            return Output(activeFaceId: nil, didChange: false, perFaceScores: [:])
        }

        // --- Precompute face info ---
        let faceInfos: [(id: UUID, center: CGPoint, area: Double, bbox: CGRect, mouth: [CGPoint])] = faces.map { f in
            let bb = f.visionBoundingBox
            return (f.id,
                    CGPoint(x: bb.midX, y: bb.midY),
                    Double(bb.width * bb.height),
                    bb,
                    f.mouthPoints)
        }

        // --- Associate bodies to faces ---
        // Match each body's shoulder midpoint to the nearest face above it.
        var faceBodyMap: [UUID: VisionPoseTracker.BodyPose] = [:]

        for body in bodies {
            let shoulderPts = [body.leftShoulder, body.rightShoulder].compactMap { $0 }
            guard let shoulderMid = centroid(of: shoulderPts) else { continue }

            var bestId: UUID? = nil
            var bestDist = Double.greatestFiniteMagnitude

            for fi in faceInfos {
                let horizDist = abs(Double(shoulderMid.x - fi.center.x))
                guard horizDist < bodyAssignMaxHorizDist else { continue }

                // Shoulder should be below face (lower y in Vision bottom-left coords)
                let vertGap = Double(fi.center.y - shoulderMid.y)
                guard vertGap > -0.05 else { continue } // allow slight overlap

                let dist = horizDist + vertGap * 0.3
                if dist < bestDist {
                    bestDist = dist
                    bestId = fi.id
                }
            }

            if let id = bestId {
                faceBodyMap[id] = body
            }
        }

        // --- Associate hands (with visible fingers) to faces ---
        var faceHandCount: [UUID: Int] = [:]

        for fingerCenter in handFingerCentroids {
            var bestId: UUID? = nil
            var bestDist = Double.greatestFiniteMagnitude

            for fi in faceInfos {
                let horizDist = abs(Double(fingerCenter.x - fi.center.x))
                guard horizDist < handAssignMaxHorizDist else { continue }

                // Hand should be at or below face level
                let vertGap = Double(fi.center.y - fingerCenter.y)
                guard vertGap > -Double(fi.bbox.height) else { continue }

                if horizDist < bestDist {
                    bestDist = horizDist
                    bestId = fi.id
                }
            }

            if let id = bestId {
                faceHandCount[id, default: 0] += 1
            }
        }

        // --- Update per-face energy & scores ---
        var perFaceScores: [UUID: Double] = [:]

        for fi in faceInfos {
            var st = states[fi.id] ?? PerFaceState()

            // 1) Hand visibility (smoothed)
            let handsNow = (faceHandCount[fi.id] ?? 0) > 0
            st.handsVisibleEMA = (1 - handAlpha) * st.handsVisibleEMA + handAlpha * (handsNow ? 1.0 : 0.0)

            // 2) Arm motion from associated body (track wrist + elbow motion)
            if let body = faceBodyMap[fi.id] {
                var motionSum: Double = 0
                var motionCount: Int = 0

                if let lw = body.leftWrist {
                    if let prev = st.lastLeftWrist {
                        motionSum += hypot(Double(lw.x - prev.x), Double(lw.y - prev.y))
                        motionCount += 1
                    }
                    st.lastLeftWrist = lw
                }
                if let rw = body.rightWrist {
                    if let prev = st.lastRightWrist {
                        motionSum += hypot(Double(rw.x - prev.x), Double(rw.y - prev.y))
                        motionCount += 1
                    }
                    st.lastRightWrist = rw
                }
                if let le = body.leftElbow {
                    if let prev = st.lastLeftElbow {
                        motionSum += hypot(Double(le.x - prev.x), Double(le.y - prev.y))
                        motionCount += 1
                    }
                    st.lastLeftElbow = le
                }
                if let re = body.rightElbow {
                    if let prev = st.lastRightElbow {
                        motionSum += hypot(Double(re.x - prev.x), Double(re.y - prev.y))
                        motionCount += 1
                    }
                    st.lastRightElbow = re
                }

                let frameMotion = motionCount > 0 ? motionSum / Double(motionCount) : 0
                st.armEnergyEMA = (1 - motionAlpha) * st.armEnergyEMA + motionAlpha * frameMotion
            } else {
                // No body associated — decay
                st.armEnergyEMA *= (1 - motionAlpha)
                st.lastLeftWrist = nil
                st.lastRightWrist = nil
                st.lastLeftElbow = nil
                st.lastRightElbow = nil
            }

            // 3) Mouth motion (tie-breaker)
            let mouthImagePts = fi.mouth.map {
                CGPoint(x: fi.bbox.minX + $0.x * fi.bbox.width,
                        y: fi.bbox.minY + $0.y * fi.bbox.height)
            }
            if let mc = centroid(of: mouthImagePts) {
                if let prev = st.lastMouthCentroid {
                    let dm = hypot(Double(mc.x - prev.x), Double(mc.y - prev.y))
                    st.mouthEnergyEMA = (1 - motionAlpha) * st.mouthEnergyEMA + motionAlpha * dm
                }
                st.lastMouthCentroid = mc
            } else {
                st.mouthEnergyEMA *= (1 - motionAlpha)
            }

            // Final score
            let score = st.handsVisibleEMA * wHands
                      + st.armEnergyEMA * wArms
                      + st.mouthEnergyEMA * wMouth
            st.lastScore = score
            st.lastUpdate = now
            states[fi.id] = st
            perFaceScores[fi.id] = score
        }

        // --- Select active face with hysteresis ---
        var scored: [(id: UUID, score: Double, area: Double)] = faceInfos.map { fi in
            (fi.id, states[fi.id]?.lastScore ?? 0, fi.area)
        }

        scored.sort {
            if abs($0.score - $1.score) > 1e-9 { return $0.score > $1.score }
            return $0.area > $1.area
        }

        let top = scored[0]

        // Ensure we always have an active face
        if activeFaceId == nil || !faceInfos.contains(where: { $0.id == activeFaceId }) {
            activeFaceId = top.id
            challengerId = nil
            lockUntil = now + lockDuration
            return Output(activeFaceId: activeFaceId, didChange: true, perFaceScores: perFaceScores)
        }

        // Respect lock period
        if now < lockUntil {
            return Output(activeFaceId: activeFaceId, didChange: false, perFaceScores: perFaceScores)
        }

        let currentId = activeFaceId!
        let currentScore = scored.first(where: { $0.id == currentId })?.score ?? 0.00001

        // If current is still the top scorer, clear challenger
        if top.id == currentId {
            challengerId = nil
            return Output(activeFaceId: activeFaceId, didChange: false, perFaceScores: perFaceScores)
        }

        // Check if challenger beats current convincingly
        let isClearWinner = (top.score >= currentScore * winRatio)
                         && ((top.score - currentScore) >= winMargin)

        if isClearWinner {
            if challengerId != top.id {
                challengerId = top.id
                challengerSince = now
            } else if now - challengerSince >= switchHoldDuration {
                activeFaceId = top.id
                challengerId = nil
                lockUntil = now + lockDuration
                return Output(activeFaceId: activeFaceId, didChange: true, perFaceScores: perFaceScores)
            }
        } else {
            challengerId = nil
        }

        return Output(activeFaceId: activeFaceId, didChange: false, perFaceScores: perFaceScores)
    }

    // MARK: - Helpers

    private func centroid(of pts: [CGPoint]) -> CGPoint? {
        guard !pts.isEmpty else { return nil }
        var sx: Double = 0, sy: Double = 0
        for p in pts { sx += Double(p.x); sy += Double(p.y) }
        return CGPoint(x: sx / Double(pts.count), y: sy / Double(pts.count))
    }
}
