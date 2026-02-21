//
//  ARViewModel.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//


import Foundation
import SwiftUI
import AVFoundation

@MainActor
final class ARViewModel: ObservableObject {
    // Published UI state
    @Published var faces: [TrackedFace] = []
    @Published var activeFaceId: UUID? = nil

    @Published var speakerArrow: SpeakerArrowState? = nil
    @Published var listenerBadges: [ListenerBadge] = []

    @Published var latestCaption: CaptionBubbleState? = nil

    @Published var wsStatus: String = "Disconnected"

    // Core components
    let camera = CameraManager()

    private let faceTracker = VisionFaceTracker()
    private let idAssigner = FaceIDAssigner()
    private let speakerDetector = ActiveSpeakerDetector()
    private let listenerDetector = ListenerExpressionChangeDetector()

    private let wsClient = WebSocketClient()

    // Buffer of speaker decisions to handle STT latency
    private var speakerHistory = RingBuffer<SpeakerSample>(capacity: 90) // ~3s at 30fps

    // Tunables
    private let anchorLatencySeconds: TimeInterval = 0.40 // anchor captions to who was speaking ~400ms ago

    // Default WS URL (change to your Mac IP)
    // Example: ws://192.168.1.23:8000/ws
    @Published var wsURLString: String = "ws://127.0.0.1:8000/ws"

    func start() async {
        await camera.start()

        camera.onFrame = { [weak self] pixelBuffer, time in
            guard let self else { return }
            self.handleFrame(pixelBuffer: pixelBuffer, time: time)
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

    private func handleFrame(pixelBuffer: CVPixelBuffer, time: CMTime) {
        // Run Vision (throttled internally) on background queue
        faceTracker.processFrame(pixelBuffer: pixelBuffer, timestamp: time) { [weak self] detected in
            guard let self else { return }
            Task { @MainActor in
                self.updateFacesAndDetectors(detectedFaces: detected)
            }
        }
    }

    private func updateFacesAndDetectors(detectedFaces: [DetectedFace]) {
        let now = Date().timeIntervalSince1970

        // Assign stable face IDs
        let tracked = idAssigner.assignIDs(to: detectedFaces, now: now)

        self.faces = tracked

        // Active speaker detection
        let speakerUpdate = speakerDetector.update(faces: tracked, now: now)

        if let newActive = speakerUpdate.activeFaceId {
            if newActive != self.activeFaceId {
                self.activeFaceId = newActive
            }
        }

        // Arrow if speaker changed
        if speakerUpdate.didChange, let arrow = speakerUpdate.arrowDirection {
            self.speakerArrow = SpeakerArrowState(direction: arrow, showUntil: now + 1.0)
        }

        // Expire arrow
        if let arrowState = self.speakerArrow, now > arrowState.showUntil {
            self.speakerArrow = nil
        }

        // Listener badges
        let newBadges = listenerDetector.update(faces: tracked, activeFaceId: self.activeFaceId, now: now)
        self.listenerBadges = newBadges

        // Update history buffer for caption anchoring
        speakerHistory.push(SpeakerSample(time: now, faceId: self.activeFaceId))
    }

    private func handleCaptionEvent(_ ev: CaptionEvent) {
        let now = Date().timeIntervalSince1970
        let anchorTime = now - anchorLatencySeconds

        // Face to anchor caption under: from ~400ms ago
        let anchorFaceId = speakerHistory.closest(to: anchorTime)?.faceId ?? self.activeFaceId

        self.latestCaption = CaptionBubbleState(
            text: ev.text,
            tone: ev.tone,
            volume: ev.volume,
            isFinal: ev.isFinal,
            anchorFaceId: anchorFaceId,
            receivedAt: now
        )
    }
}