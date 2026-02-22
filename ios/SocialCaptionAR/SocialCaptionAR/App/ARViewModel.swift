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

    @Published var faces: [TrackedFace] = []
    @Published var activeFaceId: UUID? = nil
    @Published var latestCaption: CaptionBubbleState? = nil
    @Published var wsStatus: String = "Disconnected"
    @Published var isMirrored: Bool = true
    @Published var isUsingWebSocket: Bool = false

    // Pose data for debug overlay
    @Published var poseBodies: [VisionPoseTracker.BodyPose] = []
    @Published var poseHandPoints: [CGPoint] = []
    @Published var perFaceScores: [UUID: Double] = [:]

    let camera = CameraManager()

    private let faceTracker = VisionFaceTracker()
    private let poseTracker = VisionPoseTracker()
    private let idAssigner = FaceIDAssigner()
    private let speakerDetector = MotionSpeakerDetector()
    private let wsClient = WebSocketClient()
    private let speechManager = SpeechTranscriptionManager()

    private var speakerHistory = RingBuffer<SpeakerSample>(capacity: 90)
    private let anchorLatencySeconds: TimeInterval = 0.40
    private let webSocketSilenceTimeout: TimeInterval = 3.0
    private let fallbackTone = Tone(label: "neutral", confidence: 0.5, hex: "#9CA3AF")
    private let fallbackVolume = 0.0
    @Published var wsURLString: String = "ws://127.0.0.1:8000/ws"

    private var webSocketConnected = false
    private var lastWebSocketCaptionAt: TimeInterval?
    private var webSocketWatchdogTask: Task<Void, Never>?

    // cached pose (so face + pose don’t have to finish same moment)
    private var latestPose: VisionPoseTracker.Output = .init(bodies: [], handFingerCentroids: [], handPoints: [])

    func start() async {
        await camera.start()

        camera.onFrame = { [weak self] pixelBuffer, _ in
            guard let self else { return }
            self.handleFrame(pixelBuffer: pixelBuffer)
        }

        wsClient.onStatus = { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.wsStatus = status

                if status == "Disconnected" || status.hasPrefix("WS error:") {
                    self.webSocketConnected = false
                    self.lastWebSocketCaptionAt = nil
                    self.reconcileCaptionSource()
                }
            }
        }

        wsClient.onConnectionStateChange = { [weak self] isConnected in
            Task { @MainActor in
                guard let self else { return }
                self.webSocketConnected = isConnected
                if !isConnected {
                    self.lastWebSocketCaptionAt = nil
                }
                self.reconcileCaptionSource()
            }
        }

        wsClient.onCaptionEvent = { [weak self] ev in
            Task { @MainActor in self?.handleCaptionEvent(ev) }
        }

        connectWebSocket()
        startWebSocketWatchdog()
        speechManager.onTextUpdate = { [weak self] text, isFinal in
            Task { @MainActor in
                guard let self else { return }
                guard !self.isUsingWebSocket else { return }

                self.latestCaption = CaptionBubbleState(
                    text: text,
                    tone: self.fallbackTone,
                    volume: self.fallbackVolume,
                    isFinal: isFinal,
                    anchorFaceId: self.activeFaceId,
                    receivedAt: Date().timeIntervalSince1970
                )
            }
        }

        speechManager.onAvailabilityChanged = { [weak self] isAvailable in
            Task { @MainActor in
                guard let self else { return }
                guard !self.isUsingWebSocket else { return }
                if !isAvailable, self.latestCaption == nil {
                    self.latestCaption = CaptionBubbleState(
                        text: "Speech unavailable",
                        tone: self.fallbackTone,
                        volume: self.fallbackVolume,
                        isFinal: false,
                        anchorFaceId: self.activeFaceId,
                        receivedAt: Date().timeIntervalSince1970
                    )
                }
            }
        }

        speechManager.onStatusUpdate = { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard !self.isUsingWebSocket else { return }

                if self.latestCaption?.text.isEmpty != false || status != "Listening…" {
                    self.latestCaption = CaptionBubbleState(
                        text: status,
                        tone: self.fallbackTone,
                        volume: self.fallbackVolume,
                        isFinal: false,
                        anchorFaceId: self.activeFaceId,
                        receivedAt: Date().timeIntervalSince1970
                    )
                }
            }
        }

        reconcileCaptionSource()
    }

    func stop() {
        camera.stop()
        wsClient.disconnect()
        webSocketWatchdogTask?.cancel()
        webSocketWatchdogTask = nil
        speechManager.stop()
    }

    func connectWebSocket() {
        guard let url = URL(string: wsURLString) else {
            wsStatus = "Bad URL"
            return
        }
        wsClient.connect(url: url)
    }

    private func handleFrame(pixelBuffer: CVPixelBuffer) {
        // Update pose cache (and publish for debug)
        poseTracker.processFrame(pixelBuffer: pixelBuffer) { [weak self] out in
            guard let self else { return }
            self.latestPose = out
            Task { @MainActor in
                self.poseBodies = out.bodies
                self.poseHandPoints = out.handPoints
            }
        }

        // Update faces + active speaker
        faceTracker.processFrame(pixelBuffer: pixelBuffer) { [weak self] detected in
            guard let self else { return }

            Task { @MainActor in
                let now = Date().timeIntervalSince1970
                let tracked = self.idAssigner.assignIDs(to: detected, now: now)
                self.faces = tracked

                let out = self.speakerDetector.update(
                    faces: tracked,
                    bodies: self.latestPose.bodies,
                    handFingerCentroids: self.latestPose.handFingerCentroids,
                    now: now
                )

                self.perFaceScores = out.perFaceScores

                if let id = out.activeFaceId {
                    self.activeFaceId = id
                } else if let biggest = tracked.max(by: {
                    ($0.visionBoundingBox.width * $0.visionBoundingBox.height) <
                    ($1.visionBoundingBox.width * $1.visionBoundingBox.height)
                })?.id {
                    self.activeFaceId = biggest
                }

                self.speakerHistory.push(SpeakerSample(time: now, faceId: self.activeFaceId))
            }
        }
    }

    private func handleCaptionEvent(_ ev: CaptionEvent) {
        let now = Date().timeIntervalSince1970
        lastWebSocketCaptionAt = now
        reconcileCaptionSource()
        let anchorTime = now - anchorLatencySeconds
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

    private func startWebSocketWatchdog() {
        webSocketWatchdogTask?.cancel()
        webSocketWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await self?.watchWebSocketInactivity()
            }
        }
    }

    private func watchWebSocketInactivity() {
        reconcileCaptionSource()
    }

    private func reconcileCaptionSource() {
        let now = Date().timeIntervalSince1970
        let hasRecentWebSocketCaption: Bool
        if let lastWebSocketCaptionAt {
            hasRecentWebSocketCaption = (now - lastWebSocketCaptionAt) <= webSocketSilenceTimeout
        } else {
            hasRecentWebSocketCaption = false
        }

        let shouldUseWebSocket = webSocketConnected && hasRecentWebSocketCaption
        if isUsingWebSocket == shouldUseWebSocket { return }

        isUsingWebSocket = shouldUseWebSocket
        if shouldUseWebSocket {
            speechManager.stop()
        } else {
            if latestCaption == nil {
                latestCaption = CaptionBubbleState(
                    text: "Starting speech recognition…",
                    tone: fallbackTone,
                    volume: fallbackVolume,
                    isFinal: false,
                    anchorFaceId: activeFaceId,
                    receivedAt: Date().timeIntervalSince1970
                )
            }
            speechManager.start()
        }
    }
}
