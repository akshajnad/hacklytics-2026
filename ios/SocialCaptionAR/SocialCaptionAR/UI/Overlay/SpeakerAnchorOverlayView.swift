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

    var body: some View {
        if let id = activeFaceId,
           let face = faces.first(where: { $0.id == id }) {

            let rect = previewLayer.layerRectConverted(fromMetadataOutputRect: face.visionBoundingBox)

            VStack(spacing: 10) {
                // Empty placeholders for now
                CaptionBubbleView(
                    text: "",
                    tone: Tone(label: "", confidence: 0.0, hex: "#9CA3AF"),
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