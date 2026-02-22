//
//  SpeakerAnchorOverlayView.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//

import SwiftUI
import AVFoundation

struct SpeakerAnchorOverlayView: View {
    let faces: [TrackedFace]
    let activeFaceId: UUID?
    let latestCaption: CaptionBubbleState?
    let previewLayer: AVCaptureVideoPreviewLayer
    let nameMentionFaceId: UUID?
    let nameMentionUntil: TimeInterval

    // Placeholder tone for when you want the UI to always render
    private let defaultTone = Tone(label: "neutral", confidence: 0.0, hex: "#9CA3AF")

    var body: some View {
        ZStack {
            // Prefer the face anchor from the latest caption event; fallback to active speaker.
            if let id = latestCaption?.anchorFaceId ?? activeFaceId,
               let face = faces.first(where: { $0.id == id }) {

                // IMPORTANT: Vision bbox is bottom-left origin.
                // Convert to metadataOutputRect (top-left origin) before converting to layer rect.
                let metaRect = CGRect(
                    x: face.visionBoundingBox.minX,
                    y: 1.0 - face.visionBoundingBox.maxY,
                    width: face.visionBoundingBox.width,
                    height: face.visionBoundingBox.height
                )

                let rect = previewLayer.layerRectConverted(fromMetadataOutputRect: metaRect)
                // Caption text is the full latest websocket chunk (not incremental append).
                let captionText = latestCaption?.text ?? ""
                let captionTone = latestCaption?.tone ?? defaultTone
                let captionVolume = latestCaption?.volume ?? 0.0

                VStack(spacing: 10) {
                    CaptionBubbleView(
                        text: captionText,
                        tone: captionTone,
                        volume: captionVolume
                    )
                    .opacity(0.85)
                }
                .frame(maxWidth: 360)
                .position(
                    x: rect.midX,
                    y: min(rect.maxY + 90, UIScreen.main.bounds.height - 90)
                )
                .allowsHitTesting(false)
            }

            // Name-mention bubble above the speaker who said Om's name.
            if Date().timeIntervalSince1970 < nameMentionUntil,
               let mentionId = nameMentionFaceId,
               let mentionFace = faces.first(where: { $0.id == mentionId }) {

                let metaRect = CGRect(
                    x: mentionFace.visionBoundingBox.minX,
                    y: 1.0 - mentionFace.visionBoundingBox.maxY,
                    width: mentionFace.visionBoundingBox.width,
                    height: mentionFace.visionBoundingBox.height
                )
                let rect = previewLayer.layerRectConverted(fromMetadataOutputRect: metaRect)

                Text("Your name was said!")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green)
                    .clipShape(Capsule())
                    .position(x: rect.midX, y: max(rect.minY - 18, 30))
                    .allowsHitTesting(false)
            }
        }
    }
}
