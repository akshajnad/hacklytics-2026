//
//  CameraPreviewView.swift
//  SocialCaptionAR
//
//  Created by Akshaj Nadimpalli on 2/21/26.
//

import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var onPreviewLayer: ((AVCaptureVideoPreviewLayer) -> Void)? = nil

    // Must match CameraManager
    private let desiredOrientation: AVCaptureVideoOrientation = .landscapeRight

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.videoPreviewLayer.session = session

        // Keep aspectFill so overlays stay aligned with your current math
        v.videoPreviewLayer.videoGravity = .resizeAspectFill

        if let conn = v.videoPreviewLayer.connection, conn.isVideoOrientationSupported {
            conn.videoOrientation = desiredOrientation
            if conn.isVideoMirroringSupported { conn.isVideoMirrored = false }
        }

        // Give SwiftUI access to the layer once
        DispatchQueue.main.async {
            onPreviewLayer?(v.videoPreviewLayer)
        }

        return v
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.videoPreviewLayer.session = session

        if let conn = uiView.videoPreviewLayer.connection, conn.isVideoOrientationSupported {
            conn.videoOrientation = desiredOrientation
            if conn.isVideoMirroringSupported { conn.isVideoMirrored = false }
        }

        DispatchQueue.main.async {
            onPreviewLayer?(uiView.videoPreviewLayer)
        }
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
