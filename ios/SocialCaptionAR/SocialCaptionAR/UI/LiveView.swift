import SwiftUI
import AVFoundation

struct LiveView: View {
    @StateObject private var vm = ARViewModel()

    @State private var previewLayer: AVCaptureVideoPreviewLayer? = nil
    @State private var showSettings = false
    @State private var debugOverlayEnabled = false
    @State private var showMeetingSavedBanner = false

    var body: some View {
        ZStack(alignment: .top) {
            CameraPreviewView(session: vm.camera.session, onPreviewLayer: { layer in
                if previewLayer == nil { previewLayer = layer }
            })
            .ignoresSafeArea()

            // Always-on anchor UI
            if let layer = previewLayer {
                SpeakerAnchorOverlayView(
                    faces: vm.faces,
                    activeFaceId: vm.activeFaceId,
                    // Full current websocket chunk (no concatenation) is rendered here.
                    latestCaption: vm.latestCaption,
                    previewLayer: layer,
                    nameMentionFaceId: vm.nameMentionFaceId,
                    nameMentionUntil: vm.nameMentionUntil
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

            VStack(spacing: 10) {
                if showMeetingSavedBanner {
                    Text("Meeting saved!")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.75))
                        .clipShape(Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                HStack {
                    Button {
                        toggleMeetingRecording()
                    } label: {
                        if vm.isMeetingRecording {
                            Image(systemName: "record.circle.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.black.opacity(0.5))
                                .clipShape(Capsule())
                        } else {
                            Text("Start meeting")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.black.opacity(0.5))
                                .clipShape(Capsule())
                        }
                    }

                    Spacer()

                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, 14)
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

    private func toggleMeetingRecording() {
        if vm.isMeetingRecording {
            Task {
                // Stop meeting capture and send final meeting_payload over websocket.
                await vm.stopMeetingRecordingAndSend()
                withAnimation {
                    showMeetingSavedBanner = true
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run {
                    withAnimation {
                        showMeetingSavedBanner = false
                    }
                }
            }
        } else {
            // Start collecting committed transcript rows for this meeting.
            vm.startMeetingRecording()
        }
    }
}
