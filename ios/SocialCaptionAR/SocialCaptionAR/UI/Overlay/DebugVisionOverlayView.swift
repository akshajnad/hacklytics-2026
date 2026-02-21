//
//  DebugVisionOverlayView.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//


import SwiftUI
import AVFoundation

struct DebugVisionOverlayView: View {
    let faces: [TrackedFace]
    let activeFaceId: UUID?
    let previewLayer: AVCaptureVideoPreviewLayer

    var body: some View {
        Canvas { context, size in
            for face in faces {
                let rect = previewLayer.layerRectConverted(fromMetadataOutputRect: face.visionBoundingBox)

                // Face box
                var boxPath = Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height))
                context.stroke(boxPath, with: .color(.green), lineWidth: 3)

                // Mouth landmarks
                if !face.mouthPoints.isEmpty {
                    for p in face.mouthPoints {
                        // Convert Vision bottom-left to capture-device top-left
                        let devicePoint = CGPoint(x: p.x, y: 1.0 - p.y)
                        let lp = previewLayer.layerPointConverted(fromCaptureDevicePoint: devicePoint)

                        let dotRect = CGRect(x: lp.x - 2.5, y: lp.y - 2.5, width: 5, height: 5)
                        context.fill(Path(ellipseIn: dotRect), with: .color(.yellow))
                    }
                }

                // “Talking” label placeholder (only show for active for now)
                if face.id == activeFaceId {
                    let label = Text("Talking")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)

                    context.draw(label, at: CGPoint(x: rect.maxX + 40, y: rect.minY + 10), anchor: .top)
                }
            }
        }
        .allowsHitTesting(false)
    }
}