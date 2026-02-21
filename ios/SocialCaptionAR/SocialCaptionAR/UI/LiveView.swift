//
//  LiveView.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//


import SwiftUI
import AVFoundation

struct LiveView: View {
    @StateObject private var vm = ARViewModel()

    var body: some View {
        ZStack {
            CameraPreviewView(session: vm.camera.session)
                .ignoresSafeArea()

            GeometryReader { geo in
                // Debug face boxes (keep them; you can toggle later)
                ForEach(vm.faces) { face in
                    FaceBoxView(rect: face.rectInView(in: geo.size))
                }

                // Listener badges
                ForEach(vm.listenerBadges) { badge in
                    if let face = vm.faces.first(where: { $0.id == badge.faceId }) {
                        ReactionBadgeView(label: badge.label)
                            .position(badgePosition(for: face.rectInView(in: geo.size)))
                            .opacity(badge.opacity(now: Date().timeIntervalSince1970))
                    }
                }

                // Caption bubble anchored under speaker face
                if let cap = vm.latestCaption,
                   let anchorId = cap.anchorFaceId,
                   let face = vm.faces.first(where: { $0.id == anchorId }) {

                    CaptionBubbleView(
                        text: cap.text,
                        tone: cap.tone,
                        volume: cap.volume
                    )
                    .frame(maxWidth: geo.size.width * 0.85, alignment: .leading)
                    .position(captionPosition(for: face.rectInView(in: geo.size),
                                              screen: geo.size))
                }

                // Speaker arrow overlay (bottom)
                if let arrow = vm.speakerArrow {
                    SpeakerArrowView(direction: arrow.direction)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 28)
                }
            }

            // Small dev overlay
            VStack {
                HStack {
                    Text("WS: \(vm.wsStatus)")
                        .font(.caption)
                        .padding(8)
                        .background(.black.opacity(0.5))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Spacer()
                }
                .padding(.top, 48)
                .padding(.horizontal, 12)

                Spacer()
            }
        }
        .task { await vm.start() }
        .onDisappear { vm.stop() }
    }

    private func captionPosition(for faceRect: CGRect, screen: CGSize) -> CGPoint {
        // Preferred: below face
        let preferredY = faceRect.maxY + 14
        let x = faceRect.midX

        // Rough bubble height estimate; works fine for hackathon
        let bubbleHeight: CGFloat = 90
        let margin: CGFloat = 18

        if preferredY + bubbleHeight < screen.height - margin {
            return CGPoint(x: x, y: preferredY + bubbleHeight / 2)
        } else {
            // If near bottom, place above the face (avoids covering mouth)
            let aboveY = max(margin + bubbleHeight / 2, faceRect.minY - 14 - bubbleHeight / 2)
            return CGPoint(x: x, y: aboveY)
        }
    }

    private func badgePosition(for faceRect: CGRect) -> CGPoint {
        // Put badge near top-right of face box
        CGPoint(x: faceRect.maxX - 8, y: faceRect.minY + 10)
    }
}