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
    let perFaceScores: [UUID: Double]
    let previewLayer: AVCaptureVideoPreviewLayer

    var body: some View {
        Canvas { ctx, size in
            // --- Faces + mouths + score labels ---
            for f in faces {
                let rect = layerRect(forVisionBBox: f.visionBoundingBox)
                let isActive = (f.id == activeFaceId)

                // Face bbox
                ctx.stroke(
                    Path(rect),
                    with: .color(isActive ? .green : .yellow),
                    lineWidth: isActive ? 3 : 2
                )

                // "ACTIVE" label above face box
                if isActive {
                    let labelPt = CGPoint(x: rect.midX, y: rect.minY - 22)
                    ctx.draw(
                        Text("ACTIVE")
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundColor(.green),
                        at: labelPt,
                        anchor: .bottom
                    )
                }

                // Per-face score below face box
                let score = perFaceScores[f.id] ?? 0
                let scoreStr = String(format: "%.4f", score)
                let scorePt = CGPoint(x: rect.midX, y: rect.maxY + 4)
                ctx.draw(
                    Text(scoreStr)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(isActive ? .green : .yellow),
                    at: scorePt,
                    anchor: .top
                )

                // Mouth landmarks (face-local normalized -> image normalized -> layer)
                if !f.mouthPoints.isEmpty {
                    for p in f.mouthPoints {
                        let xN = f.visionBoundingBox.minX + p.x * f.visionBoundingBox.width
                        let yN = f.visionBoundingBox.minY + p.y * f.visionBoundingBox.height
                        let pt = layerPoint(fromVisionPoint: CGPoint(x: xN, y: yN))

                        let dot = CGRect(x: pt.x - 2.5, y: pt.y - 2.5, width: 5, height: 5)
                        ctx.fill(Path(ellipseIn: dot), with: .color(.orange))
                    }
                }
            }


        }
        .allowsHitTesting(false)
    }

    // MARK: - Coordinate conversion

    private func layerPoint(fromVisionPoint p: CGPoint) -> CGPoint {
        let capture = CGPoint(x: p.x, y: 1.0 - p.y)
        return previewLayer.layerPointConverted(fromCaptureDevicePoint: capture)
    }

    private func layerRect(forVisionBBox bb: CGRect) -> CGRect {
        let capture = CGRect(
            x: bb.minX,
            y: 1.0 - bb.maxY,
            width: bb.width,
            height: bb.height
        )
        return previewLayer.layerRectConverted(fromMetadataOutputRect: capture)
    }
}
