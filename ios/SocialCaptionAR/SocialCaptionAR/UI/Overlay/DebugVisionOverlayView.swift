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

            // --- Body arm skeletons + arm bounding boxes ---
            for b in bodies {
                drawArm(
                    ctx: &ctx,
                    shoulder: b.leftShoulder,
                    elbow: b.leftElbow,
                    wrist: b.leftWrist,
                    color: .cyan
                )
                drawArm(
                    ctx: &ctx,
                    shoulder: b.rightShoulder,
                    elbow: b.rightElbow,
                    wrist: b.rightWrist,
                    color: .cyan
                )
            }

            // --- Hand points ---
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
        let pad: CGFloat = 8
        return CGRect(x: minX - pad, y: minY - pad, width: (maxX - minX) + 2*pad, height: (maxY - minY) + 2*pad)
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
