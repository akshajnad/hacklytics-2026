//
//  ListenerExpressionChangeDetector.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//


import Foundation

final class ListenerExpressionChangeDetector {
    private struct Baseline {
        var mouthOpen: Double
        var browRaise: Double
        var lastUpdate: TimeInterval
        var lastAlert: TimeInterval
    }

    private var baseline: [UUID: Baseline] = [:]

    // tunables
    private let emaAlpha = 0.08
    private let alertCooldown: TimeInterval = 1.2
    private let threshold: Double = 0.09 // adjust based on testing

    func update(faces: [TrackedFace], activeFaceId: UUID?, now: TimeInterval) -> [ListenerBadge] {
        // prune old
        baseline = baseline.filter { now - $0.value.lastUpdate < 2.0 }

        var badges: [ListenerBadge] = []

        for f in faces {
            guard f.id != activeFaceId else { continue }

            let mouth = Double(f.mouthOpen ?? 0)
            let brow = Double(f.browRaise ?? 0)

            if var b = baseline[f.id] {
                // compute deviation
                let dev = abs(mouth - b.mouthOpen) + abs(brow - b.browRaise)

                // update baseline slowly
                b.mouthOpen = (1 - emaAlpha) * b.mouthOpen + emaAlpha * mouth
                b.browRaise = (1 - emaAlpha) * b.browRaise + emaAlpha * brow
                b.lastUpdate = now

                // trigger alert if big change and cooldown passed
                if dev > threshold, now - b.lastAlert > alertCooldown {
                    b.lastAlert = now
                    let label = classify(mouthOpen: mouth, browRaise: brow, dev: dev)
                    badges.append(ListenerBadge(faceId: f.id, label: label, createdAt: now, ttl: 1.6))
                }

                baseline[f.id] = b
            } else {
                baseline[f.id] = Baseline(mouthOpen: mouth, browRaise: brow, lastUpdate: now, lastAlert: 0)
            }
        }

        // Keep only active (not expired)
        return badges
    }

    private func classify(mouthOpen: Double, browRaise: Double, dev: Double) -> String {
        // Super simple heuristics; good enough for demo
        if mouthOpen > 0.20 { return "😮 surprised" }
        if browRaise > 0.10 { return "🤨 confused" }
        return "⚡ reaction"
    }
}
