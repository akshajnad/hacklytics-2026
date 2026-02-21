//
//  ARViewModel.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//

import Foundation
import SwiftUI
import AVFoundation
import Combine

@MainActor
final class ARViewModel: ObservableObject {

    // MARK: - Published UI state
    @Published var faces: [TrackedFace] = []
    @Published var activeFaceId: UUID? = nil

    @Published var latestCaption: CaptionBubbleState? = nil

    @Published var wsStatus: String = "Disconnected"
    @Published var isMirrored: Bool = true // set true if you later switch to front camera

    // MARK: - Core components
    let camera = CameraManager()

    private let faceTracker = VisionFaceTracker()
    private let idAssigner = FaceIDAssigner()
    private let wsClient = WebSocketClient()

    // Buffer of active-speaker decisions to handle caption latency
    private var speakerHistory = RingBuffer<SpeakerSample>(capacity: 90) // ~3s at 30fps

    // Tunables
    private let anchorLatencySeconds: TimeInterval = 0.40 // anchor captions to who was active ~400ms ago

    // Default WS URL (change to your Mac IP)
    // Example: ws://192.168.1.23:8000/ws
    @Published var wsURLString: String = "ws://127.0.0.1:8000/ws"

    // MARK: - Lifecycle

    func start() async {
        await camera.start()

        camera.onFrame = { [weak self] pixelBuffer, _ in
            guard let self else { return }
            self.handleFrame(pixelBuffer: pixelBuffer)
        }

        wsClient.onStatus = { [weak self] status in
            Task { @MainActor in self?.wsStatus = status }
        }

        wsClient.onCaptionEvent = { [weak self] ev in
            Task { @MainActor in self?.handleCaptionEvent(ev) }
        }

        connectWebSocket()
    }

    func stop() {
        camera.stop()
        wsClient.disconnect()
    }

    func connectWebSocket() {
        guard let url = URL(string: wsURLString) else {
            wsStatus = "Bad URL"
            return
        }
        wsClient.connect(url: url)
    }

    // MARK: - Frame processing (Vision → faces + temporary active-face)

    private func handleFrame(pixelBuffer: CVPixelBuffer) {
        faceTracker.processFrame(pixelBuffer: pixelBuffer) { [weak self] detected in
            guard let self else { return }

            Task { @MainActor in
                let now = Date().timeIntervalSince1970

                // Stable face IDs
                let tracked = self.idAssigner.assignIDs(to: detected, now: now)
                self.faces = tracked

                // TEMP: choose active face as the largest face box (good enough to wire UI)
                self.activeFaceId = tracked
                    .max(by: { $0.visionBoundingBox.width < $1.visionBoundingBox.width })?
                    .id

                // Keep history for caption anchoring
                self.speakerHistory.push(SpeakerSample(time: now, faceId: self.activeFaceId))
            }
        }
    }

    // MARK: - WS captions → anchor under face

    private func handleCaptionEvent(_ ev: CaptionEvent) {
        let now = Date().timeIntervalSince1970
        let anchorTime = now - anchorLatencySeconds

        // Face to anchor caption under: from ~400ms ago
        let anchorFaceId = speakerHistory.closest(to: anchorTime)?.faceId ?? self.activeFaceId

        self.latestCaption = CaptionBubbleState(
            text: ev.text,
            tone: ev.toneValue,
            volume: ev.volumeValue,
            isFinal: ev.isFinal,
            anchorFaceId: anchorFaceId,
            receivedAt: now
        )
    }
}
