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
import CoreImage
import UIKit

@MainActor
final class ARViewModel: ObservableObject {

    @Published var faces: [TrackedFace] = []
    @Published var activeFaceId: UUID? = nil
    @Published var latestCaption: CaptionBubbleState? = nil
    @Published var wsStatus: String = "Disconnected"
    @Published var isMirrored: Bool = true
    @Published var isMeetingRecording: Bool = false

    // Pose data for debug overlay
    @Published var poseBodies: [VisionPoseTracker.BodyPose] = []
    @Published var poseHandPoints: [CGPoint] = []
    @Published var perFaceScores: [UUID: Double] = [:]

    // Name-mention bubble: shows above the speaker who said Om's name.
    @Published var nameMentionFaceId: UUID? = nil
    @Published var nameMentionUntil: TimeInterval = 0

    let camera = CameraManager()

    private let faceTracker = VisionFaceTracker()
    private let poseTracker = VisionPoseTracker()
    private let idAssigner = FaceIDAssigner()
    private let speakerDetector = MotionSpeakerDetector()
    private let wsClient = WebSocketClient()

    private var speakerHistory = RingBuffer<SpeakerSample>(capacity: 90)
    private let anchorLatencySeconds: TimeInterval = 0.40
    // Websocket endpoint for realtime captions + final meeting upload.
    // - Simulator on same Mac: ws://127.0.0.1:8765
    // - Physical iPhone: replace 127.0.0.1 with your Mac's LAN IP (same Wi-Fi).
    @Published var wsURLString: String = "ws://172.20.10.2:8765"
    private var meetingStartMs: Int64?
    private var meetingTranscripts: [MeetingTranscriptRecord] = []
    private var latestFrameImage: CIImage?
    private let ciContext = CIContext(options: nil)

    // cached pose (so face + pose don’t have to finish same moment)
    private var latestPose: VisionPoseTracker.Output = .init(bodies: [], handFingerCentroids: [], handPoints: [])

    private func log(_ message: String) {
        print("[ARViewModel] \(message)")
    }

    func start() async {
        log("start() called; starting camera and websocket wiring")
        await camera.start()

        // Cache latest camera frame for participant snapshots on meeting stop.
        camera.onFrame = { [weak self] pixelBuffer, _ in
            guard let self else { return }
            self.handleFrame(pixelBuffer: pixelBuffer)
        }

        wsClient.onStatus = { [weak self] status in
            Task { @MainActor in
                self?.wsStatus = status
                self?.log("WebSocket status update: \(status)")
            }
        }

        wsClient.onCaptionEvent = { [weak self] ev in
            Task { @MainActor in self?.handleCaptionEvent(ev) }
        }

        connectWebSocket()
    }

    func stop() {
        log("stop() called; stopping camera + websocket")
        camera.stop()
        wsClient.disconnect()
    }

    func startMeetingRecording() {
        // Recording session state lives in-memory for one meeting.
        meetingTranscripts.removeAll()
        meetingStartMs = currentTimestampMs()
        isMeetingRecording = true
        log("Meeting recording started at ms=\(meetingStartMs ?? 0)")
    }

    func stopMeetingRecordingAndSend() async {
        guard isMeetingRecording else { return }

        isMeetingRecording = false
        let startedAtMs = meetingStartMs ?? currentTimestampMs()
        let endedAtMs = currentTimestampMs()
        // Build one face snapshot per known participant ID at stop time.
        let participants = buildParticipantSnapshotRecords()
        let payload = MeetingPayloadEvent(
            started_at_ms: startedAtMs,
            ended_at_ms: endedAtMs,
            transcripts: meetingTranscripts,
            participants: participants
        )
        log(
            "Stopping meeting recording: transcripts=\(meetingTranscripts.count), " +
            "participants=\(participants.count)"
        )

        do {
            try await wsClient.sendMeetingPayload(payload)
            wsStatus = "Meeting payload sent"
            log("Meeting payload sent successfully")
        } catch {
            wsStatus = "Meeting payload send failed"
            log("Meeting payload send failed: \(error.localizedDescription)")
        }

        meetingStartMs = nil
        meetingTranscripts.removeAll()
        log("Meeting recording state reset")
    }

    func connectWebSocket() {
        guard let url = URL(string: wsURLString) else {
            wsStatus = "Bad URL"
            log("connectWebSocket() failed: invalid URL string '\(wsURLString)'")
            return
        }
        log("Connecting websocket to \(url.absoluteString)")
        wsClient.connect(url: url)
    }

    private func handleFrame(pixelBuffer: CVPixelBuffer) {
        latestFrameImage = CIImage(cvPixelBuffer: pixelBuffer)

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
        let anchorTime = now - anchorLatencySeconds
        let anchorFaceId = speakerHistory.closest(to: anchorTime)?.faceId ?? self.activeFaceId
        let timestampMs = Int64(ev.t_ms ?? Int(now * 1000))
        let tone = ev.toneValue
        let volume = ev.volumeValue

        self.latestCaption = CaptionBubbleState(
            text: ev.text,
            tone: tone,
            volume: volume,
            isFinal: ev.isFinal,
            anchorFaceId: anchorFaceId,
            receivedAt: now
        )
        // Detect "Om" or "Ohm" mention (word-boundary, case-insensitive).
        // Show bubble above the speaker who said it.
        if let _ = ev.text.range(of: #"\b(om|ohm)\b"#, options: [.regularExpression, .caseInsensitive]) {
            self.nameMentionFaceId = anchorFaceId
            self.nameMentionUntil = now + 5.0
        }

        log(
            "Caption received: is_final=\(ev.isFinal), text_len=\(ev.text.count), " +
            "tone=\(tone.label), volume=\(String(format: "%.3f", volume)), " +
            "anchorFaceId=\(anchorFaceId?.uuidString ?? "nil")"
        )

        // Only committed/final chunks are persisted to the meeting transcript list.
        if isMeetingRecording && ev.isFinal {
            meetingTranscripts.append(
                MeetingTranscriptRecord(
                    speaker_id: anchorFaceId?.uuidString,
                    text: ev.text,
                    tone: tone.label,
                    volume: volume,
                    timestamp_ms: timestampMs
                )
            )
            log("Committed transcript appended. running_count=\(meetingTranscripts.count)")
        }
    }

    private func currentTimestampMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func buildParticipantSnapshotRecords() -> [MeetingParticipantRecord] {
        // IDs come from committed transcript speakers, plus currently tracked faces
        // so we do not miss participants that spoke near stop time.
        var speakerIds = Set<String>()
        for transcript in meetingTranscripts {
            if let speakerId = transcript.speaker_id {
                speakerIds.insert(speakerId)
            }
        }
        for face in faces {
            speakerIds.insert(face.id.uuidString)
        }

        let facesById = Dictionary(uniqueKeysWithValues: faces.map { ($0.id.uuidString, $0) })
        return speakerIds.sorted().map { speakerId in
            let imageBase64: String?
            if let face = facesById[speakerId] {
                imageBase64 = cropFaceToBase64JPEG(visionBoundingBox: face.visionBoundingBox)
            } else {
                imageBase64 = nil
            }
            if imageBase64 == nil {
                log("Participant snapshot missing for speaker_id=\(speakerId)")
            }
            return MeetingParticipantRecord(
                speaker_id: speakerId,
                image_base64_jpeg: imageBase64
            )
        }
    }

    private func cropFaceToBase64JPEG(visionBoundingBox: CGRect) -> String? {
        // Vision face boxes are normalized and bottom-left origin.
        // CIImage crop coordinates are pixel-based in image space.
        guard let frameImage = latestFrameImage else { return nil }
        let frameExtent = frameImage.extent
        if frameExtent.isEmpty { return nil }

        let cropRect = CGRect(
            x: frameExtent.minX + (visionBoundingBox.minX * frameExtent.width),
            y: frameExtent.minY + (visionBoundingBox.minY * frameExtent.height),
            width: visionBoundingBox.width * frameExtent.width,
            height: visionBoundingBox.height * frameExtent.height
        ).intersection(frameExtent).integral

        if cropRect.width < 2 || cropRect.height < 2 {
            return nil
        }

        let croppedImage = frameImage.cropped(to: cropRect)
        guard let cgImage = ciContext.createCGImage(croppedImage, from: croppedImage.extent) else {
            return nil
        }
        guard let jpegData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.75) else {
            return nil
        }
        return jpegData.base64EncodedString()
    }
}
