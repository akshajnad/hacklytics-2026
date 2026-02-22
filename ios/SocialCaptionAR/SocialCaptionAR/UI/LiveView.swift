import SwiftUI
import AVFoundation

struct LiveView: View {
    @StateObject private var vm = ARViewModel()

    @State private var previewLayer: AVCaptureVideoPreviewLayer? = nil
    @State private var showSettings = false
    @State private var debugOverlayEnabled = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CameraPreviewView(session: vm.camera.session, onPreviewLayer: { layer in
                if previewLayer == nil { previewLayer = layer }
            })
            .ignoresSafeArea()

            // Always-on anchor UI
            if let layer = previewLayer {
                SpeakerAnchorOverlayView(
                    faces: vm.faces,
                    activeFaceId: vm.activeFaceId,
                    previewLayer: layer
                )
            }

            // Debug overlays
            if debugOverlayEnabled, let layer = previewLayer {
                DebugVisionOverlayView(
                    faces: vm.faces,
                    activeFaceId: vm.activeFaceId,
                    bodies: vm.poseBodies,
                    handPoints: vm.poseHandPoints,
                    perFaceScores: vm.perFaceScores,
                    previewLayer: layer
                )
            }

            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
                    .padding(.top, 14)
                    .padding(.trailing, 14)
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationView {
                Form {
                    Section("Debug") {
                        Toggle("Debug overlays", isOn: $debugOverlayEnabled)
                    }
                }
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showSettings = false }
                    }
                }
            }
        }
        .task { await vm.start() }
        .onDisappear { vm.stop() }
    }
}
