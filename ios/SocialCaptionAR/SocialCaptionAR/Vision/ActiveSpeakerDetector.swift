//
//  ActiveSpeakerDetector.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//


import Foundation
import CoreGraphics

final class ActiveSpeakerDetector {
    private struct MouthState {
        var last: CGPoint?
        var score: Double
        var lastUpdate: TimeInterval
    }

    private var perFace: [UUID: MouthState] = [:]

    private(set) var activeFaceId: UUID? = nil

    private var candidateId: UUID? = nil
    private var candidateSince: TimeInterval = 0
    private var lockUntil: TimeInterval = 0

    // tunables
    private let emaAlpha = 0.35               // smoothing
    private let challengeMargin: Double = 1.4 // challenger must be 1.4x current
    private let switchHold: TimeInterval = 0.30
    private let lockDuration: TimeInterval = 0.80

    func update(faces: [TrackedFace], now: TimeInterval) -> (activeFaceId: UUID?, didChange: Bool, arrowDirection: ArrowDirection?) {
        // update mouth motion scores
        for f in faces {
            guard let mouth = f.mouthLocalCenter else { continue }

            var st = perFace[f.id] ?? MouthState(last: nil, score: 0, lastUpdate: now)

            if let last = st.last {
                let d = Double(hypot(mouth.x - last.x, mouth.y - last.y))
                st.score = (1 - emaAlpha) * st.score + emaAlpha * d
            }
            st.last = mouth
            st.lastUpdate = now
            perFace[f.id] = st
        }

        // prune stale face states
        perFace = perFace.filter { now - $0.value.lastUpdate < 1.2 }

        // pick best candidate by score
        let scored: [(UUID, Double, CGRect)] = faces.map { f in
            let s = perFace[f.id]?.score ?? 0
            return (f.id, s, f.rect)
        }.sorted { $0.1 > $1.1 }

        guard let top = scored.first else {
            return (activeFaceId, false, nil)
        }

        let topId = top.0
        let topScore = top.1
        let topRect = top.2

        // If no active speaker yet, pick top immediately
        if activeFaceId == nil {
            activeFaceId = topId
            return (activeFaceId, true, direction(for: topRect))
        }

        // Respect lock
        if now < lockUntil {
            return (activeFaceId, false, nil)
        }

        // Compare against current
        let currentId = activeFaceId!
        let currentScore = perFace[currentId]?.score ?? 0.00001

        // If top is already current, reset candidate
        if topId == currentId {
            candidateId = nil
            return (activeFaceId, false, nil)
        }

        // Decide if challenger is strong enough
        if topScore > currentScore * challengeMargin {
            if candidateId != topId {
                candidateId = topId
                candidateSince = now
            } else {
                if now - candidateSince >= switchHold {
                    // switch
                    activeFaceId = topId
                    lockUntil = now + lockDuration
                    candidateId = nil
                    return (activeFaceId, true, direction(for: topRect))
                }
            }
        } else {
            candidateId = nil
        }

        return (activeFaceId, false, nil)
    }

    private func direction(for rect: CGRect) -> ArrowDirection {
        let x = rect.midX
        if x < 0.33 { return .left }
        if x > 0.66 { return .right }
        return .center
    }
}
