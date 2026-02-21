//
//  CameraManager.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//

import Foundation
import AVFoundation

final class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let outputQueue = DispatchQueue(label: "camera.output.queue")

    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?

    private var isConfigured = false
    private var videoOutput: AVCaptureVideoDataOutput?

    // Choose how you want landscape to look on device:
    // .landscapeRight usually matches holding phone with volume buttons DOWN on right side.
    private let desiredOrientation: AVCaptureVideoOrientation = .landscapeRight

    func start() async {
        let granted = await requestCameraPermission()
        guard granted else { return }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                self.configure()
                self.isConfigured = true
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high

        // --- Camera: prefer ultra-wide to "zoom out" ---
        // --- Camera: pick the widest back camera available (no enum constants needed) ---
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: .back
        )

        // Prefer the device that supports the smallest minAvailableVideoZoomFactor (widest view)
        let device = discovery.devices.min(by: {
            $0.minAvailableVideoZoomFactor < $1.minAvailableVideoZoomFactor
        })

        guard let cam = device,
              let input = try? AVCaptureDeviceInput(device: cam),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        // Ensure zoom = 1.0 (just in case)
        do {
            try cam.lockForConfiguration()
            if cam.videoZoomFactor != 1.0 {
                cam.videoZoomFactor = 1.0
            }
            cam.unlockForConfiguration()
        } catch {
            // ignore
        }

        // --- Output frames for Vision ---
        let out = AVCaptureVideoDataOutput()
        out.alwaysDiscardsLateVideoFrames = true
        out.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        out.setSampleBufferDelegate(self, queue: outputQueue)

        guard session.canAddOutput(out) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(out)
        self.videoOutput = out

        // Force output orientation to landscape (this is key for rotation issues)
        if let conn = out.connection(with: .video) {
            if conn.isVideoOrientationSupported {
                conn.videoOrientation = desiredOrientation
            }
            if conn.isVideoMirroringSupported {
                conn.isVideoMirrored = false
            }
        }

        session.commitConfiguration()
    }

    private func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized: return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        // Keep the connection locked to landscape (prevents random 90° flips)
        if connection.isVideoOrientationSupported, connection.videoOrientation != desiredOrientation {
            connection.videoOrientation = desiredOrientation
        }
        if connection.isVideoMirroringSupported, connection.isVideoMirrored {
            connection.isVideoMirrored = false
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        onFrame?(pixelBuffer, ts)
    }
}
