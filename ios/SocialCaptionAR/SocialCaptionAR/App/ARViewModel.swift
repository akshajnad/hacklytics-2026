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

    let camera = CameraManager()

    private let faceTracker = VisionFaceTracker()
    private let poseTracker = VisionPoseTracker()
    private let idAssigner = FaceIDAssigner()
    private let speakerDetector = MotionSpeakerDetector()
    private let wsClient = WebSocketClient()

    private var speakerHistory = RingBuffer<SpeakerSample>(capacity: 90)
    private let anchorLatencySeconds: TimeInterval = 0.40
    @Published var wsURLString: String = "ws://127.0.0.1:8000/ws"

    // cache latest pose output
    private var latestPoseOutput: VisionPoseTracker.Output = .init(bodyPoints: [], handPoints: [])

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

    private func handleFrame(pixelBuffer: CVPixelBuffer) {
        // update pose cache
        poseTracker.processFrame(pixelBuffer: pixelBuffer) { [weak self] poseOut in
            guard let self else { return }
            self.latestPoseOutput = poseOut
        }

        // update faces + choose active
        faceTracker.processFrame(pixelBuffer: pixelBuffer) { [weak self] detected in
            guard let self else { return }

            Task { @MainActor in
                let now = Date().timeIntervalSince1970

                let tracked = self.idAssigner.assignIDs(to: detected, now: now)
                self.faces = tracked

                let pose = self.latestPoseOutput
                let out = self.speakerDetector.update(
                    faces: tracked,
                    poseBodyPoints: pose.bodyPoints,
                    poseHandPoints: pose.handPoints,
                    now: now
                )

                // Ensure always under a face if any exist
                if let id = out.activeFaceId {
                    self.activeFaceId = id
                } else if let biggest = tracked.max(by: { $0.visionBoundingBox.width * $0.visionBoundingBox.height <
                                                      $1.visionBoundingBox.width * $1.visionBoundingBox.height })?.id {
                    self.activeFaceId = biggest
                }

                self.speakerHistory.push(SpeakerSample(time: now, faceId: self.activeFaceId))
            }
        }
    }

    private func handleCaptionEvent(_ ev: CaptionEvent) {
        let now = Date().timeIntervalSince1970
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
}
