//
//  TrackedFace.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//

import Foundation
import CoreGraphics

struct DetectedFace {
    /// Vision boundingBox: normalized, origin bottom-left
    let visionBoundingBox: CGRect

    /// Mouth landmark points in Vision image coords (normalized, origin bottom-left)
    let mouthPoints: [CGPoint]
}

struct TrackedFace: Identifiable {
    let id: UUID

    /// Vision boundingBox (normalized, origin bottom-left)
    let visionBoundingBox: CGRect

    /// Mouth points (normalized, origin bottom-left)
    let mouthPoints: [CGPoint]
}

struct SpeakerArrowState {
    let direction: ArrowDirection
    let showUntil: TimeInterval
}

struct ListenerBadge: Identifiable {
    let id = UUID()
    let faceId: UUID
    let label: String
    let createdAt: TimeInterval
    let ttl: TimeInterval

    func opacity(now: TimeInterval) -> Double {
        let t = now - createdAt
        if t < 0 { return 0 }
        if t > ttl { return 0 }
        if ttl - t < 0.4 { return Double((ttl - t) / 0.4) }
        return 1.0
    }
}

struct CaptionBubbleState {
    let text: String
    let tone: Tone
    let volume: Double
    let isFinal: Bool
    let anchorFaceId: UUID?
    let receivedAt: TimeInterval
}

struct SpeakerSample {
    let time: TimeInterval
    let faceId: UUID?
}
