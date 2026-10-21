import SwiftUI

/// A single-screen, camera-style layout. The preview fills the display, and
/// essential controls float above it instead of requiring scrolling.
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = CameraController()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                // Keep small labels readable without hiding the live preview.
                LinearGradient(
                    colors: [
                        .black.opacity(0.42),
                        .clear,
                        .clear,
                        .black.opacity(0.58)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    topBar

                    Spacer(minLength: 12)

                    bottomControls(compact: geometry.size.height < 620)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 8)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                camera.start()
            } else {
                camera.stop()
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                camera.torchEnabled.toggle()
                camera.applyTorchSetting()
            } label: {
                Image(systemName: camera.torchEnabled ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(camera.torchEnabled ? .yellow : .white)
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.65), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(camera.torchEnabled ? "ライトをオフ" : "ライトをオン")

            Spacer(minLength: 4)

            Text("UltraDimCamera")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundColor(.white)

            Spacer(minLength: 4)

            Group {
                if camera.isRecording {
                    Label("REC", systemImage: "circle.fill")
                        .font(.caption.bold())
                        .foregroundColor(.red)
                } else {
                    Text("VIDEO")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .frame(width: 54)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.65), in: Capsule())
        }
    }

    private func bottomControls(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 12) {
            HStack(spacing: 8) {
                Label("ライトの強さ", systemImage: "sun.min.fill")
                    .font(.subheadline.weight(.medium))

                Spacer()

                // Requested API level, not a measured LED output percentage.
                Text(String(format: "%.2f%%", Double(camera.requestedLevel) * 100))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }

            Slider(value: $camera.brightnessPosition, in: 0...1)
                .tint(.yellow)
                .accessibilityLabel("ライトの強さ")
                .onChange(of: camera.brightnessPosition) { _ in
                    camera.applyTorchSetting()
                }

            HStack {
                Text("0.1%")
                Spacer()
                Button("最小に戻す") {
                    camera.brightnessPosition = 0
                    camera.applyTorchSetting()
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered)
                .tint(.white)
                Spacer()
                Text("100%")
            }
            .font(.caption)
            .foregroundColor(.white.opacity(0.85))

            Button(action: camera.toggleRecording) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: compact ? 65 : 74, height: compact ? 65 : 74)

                    if camera.isRecording {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.red)
                            .frame(width: 27, height: 27)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: compact ? 51 : 59, height: compact ? 51 : 59)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!camera.isReady)
            .opacity(camera.isReady ? 1 : 0.45)
            .accessibilityLabel(camera.isRecording ? "録画を停止" : "録画を開始")
            .padding(.top, compact ? 2 : 4)

            Text(camera.status)
                .font(.caption)
                .foregroundColor(.white.opacity(0.88))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: compact ? 16 : 26)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, compact ? 10 : 14)
        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 22))
    }
}
