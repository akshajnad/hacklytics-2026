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
    let previewLayer: AVCaptureVideoPreviewLayer

    // Placeholder tone for when you want the UI to always render
    private let defaultTone = Tone(label: "neutral", confidence: 0.0, hex: "#9CA3AF")

    var body: some View {
        if let id = activeFaceId,
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

            VStack(spacing: 10) {
                // If you want “always visible”, keep this placeholder.
                // Once WS events are flowing, you’ll replace these with vm.latestCaption values.
                CaptionBubbleView(
                    text: "",
                    tone: defaultTone,
                    volume: 0.0
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
    }
}
