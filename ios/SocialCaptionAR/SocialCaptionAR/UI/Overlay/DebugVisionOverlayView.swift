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
    let bodies: [VisionPoseTracker.BodyPose]
    let handPoints: [CGPoint]
    let previewLayer: AVCaptureVideoPreviewLayer

    var body: some View {
        Canvas { ctx, size in
            // --- Faces + mouths ---
            for f in faces {
                let rect = layerRect(forVisionBBox: f.visionBoundingBox)
                let isActive = (f.id == activeFaceId)

                // Face bbox
                ctx.stroke(
                    Path(rect),
                    with: .color(isActive ? .green : .yellow),
                    lineWidth: isActive ? 3 : 2
                )

                // Mouth landmarks (map from face-local normalized -> image normalized -> layer)
                // NOTE: your mouthPoints are currently face-local (0..1) in Vision face coords.
                // For debug purposes, we'll just scatter them inside the face box.
                if !f.mouthPoints.isEmpty {
                    for p in f.mouthPoints {
                        // mouth points are in face local coords bottom-left; place them into bbox:
                        let xN = f.visionBoundingBox.minX + p.x * f.visionBoundingBox.width
                        let yN = f.visionBoundingBox.minY + p.y * f.visionBoundingBox.height
                        let pt = layerPoint(fromVisionPoint: CGPoint(x: xN, y: yN))

                        let dot = CGRect(x: pt.x - 2.5, y: pt.y - 2.5, width: 5, height: 5)
                        ctx.fill(Path(ellipseIn: dot), with: .color(.orange))
                    }
                }
            }

            // --- Body arm skeletons + arm bounding boxes ---
            for b in bodies {
                // Left arm
                drawArm(
                    ctx: &ctx,
                    shoulder: b.leftShoulder,
                    elbow: b.leftElbow,
                    wrist: b.leftWrist,
                    color: .cyan
                )

                // Right arm
                drawArm(
                    ctx: &ctx,
                    shoulder: b.rightShoulder,
                    elbow: b.rightElbow,
                    wrist: b.rightWrist,
                    color: .cyan
                )
            }

            // --- Hand points (optional) ---
            for hp in handPoints {
                let pt = layerPoint(fromVisionPoint: hp)
                let dot = CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)
                ctx.fill(Path(ellipseIn: dot), with: .color(.pink))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Arm drawing helpers

    private func drawArm(ctx: inout GraphicsContext,
                         shoulder: CGPoint?,
                         elbow: CGPoint?,
                         wrist: CGPoint?,
                         color: Color) {
        let pts = [shoulder, elbow, wrist].compactMap { $0 }
        guard !pts.isEmpty else { return }

        // Skeleton lines
        if let s = shoulder, let e = elbow {
            strokeLine(ctx: &ctx, a: layerPoint(fromVisionPoint: s), b: layerPoint(fromVisionPoint: e), color: color, width: 3)
        }
        if let e = elbow, let w = wrist {
            strokeLine(ctx: &ctx, a: layerPoint(fromVisionPoint: e), b: layerPoint(fromVisionPoint: w), color: color, width: 3)
        }

        // Joint dots
        for p in pts {
            let lp = layerPoint(fromVisionPoint: p)
            let dot = CGRect(x: lp.x - 4, y: lp.y - 4, width: 8, height: 8)
            ctx.fill(Path(ellipseIn: dot), with: .color(color))
        }

        // Arm bounding box around available joints
        let layerPts = pts.map { layerPoint(fromVisionPoint: $0) }
        if let bb = boundingRect(of: layerPts) {
            ctx.stroke(Path(bb), with: .color(color.opacity(0.9)), lineWidth: 2)
        }
    }

    private func strokeLine(ctx: inout GraphicsContext, a: CGPoint, b: CGPoint, color: Color, width: CGFloat) {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        ctx.stroke(p, with: .color(color), lineWidth: width)
    }

    private func boundingRect(of pts: [CGPoint]) -> CGRect? {
        guard let minX = pts.map(\.x).min(),
              let maxX = pts.map(\.x).max(),
              let minY = pts.map(\.y).min(),
              let maxY = pts.map(\.y).max()
        else { return nil }
        // small padding so it looks like a box
        let pad: CGFloat = 8
        return CGRect(x: minX - pad, y: minY - pad, width: (maxX - minX) + 2*pad, height: (maxY - minY) + 2*pad)
    }

    // MARK: - Coordinate conversion

    /// Vision points are normalized (0..1) with origin bottom-left.
    /// AVCaptureVideoPreviewLayer uses captureDevicePoint normalized with origin top-left.
    private func layerPoint(fromVisionPoint p: CGPoint) -> CGPoint {
        let capture = CGPoint(x: p.x, y: 1.0 - p.y)
        return previewLayer.layerPointConverted(fromCaptureDevicePoint: capture)
    }

    /// Vision face bbox: normalized (0..1), origin bottom-left.
    /// Convert to a rect in preview layer coords.
    private func layerRect(forVisionBBox bb: CGRect) -> CGRect {
        // Convert to captureDeviceRect (origin top-left)
        let capture = CGRect(
            x: bb.minX,
            y: 1.0 - bb.maxY,
            width: bb.width,
            height: bb.height
        )
        return previewLayer.layerRectConverted(fromMetadataOutputRect: capture)
    }
}
