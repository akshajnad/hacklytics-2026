//
//  TrackedFace.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//

import Foundation
import CoreGraphics

struct DetectedFace {
    // Normalized rect in view coords (origin top-left)
    let rect: CGRect
    // Local face coords (0..1, origin top-left)
    let mouthLocalCenter: CGPoint?
    let mouthOpen: CGFloat?
    let browRaise: CGFloat?
}

struct TrackedFace: Identifiable {
    let id: UUID
    let rect: CGRect // normalized, origin top-left
    let mouthLocalCenter: CGPoint?
    let mouthOpen: CGFloat?
    let browRaise: CGFloat?

    func rectInView(in size: CGSize) -> CGRect {
        CGRect(
            x: rect.minX * size.width,
            y: rect.minY * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
    }
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
        // simple fade out in last 0.4s
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
