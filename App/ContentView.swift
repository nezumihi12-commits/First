import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = CameraController()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("微光カメラ")
                        .font(.largeTitle.bold())
                    Text("最小のライトで、動画を撮る")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack(alignment: .topLeading) {
                    CameraPreview(session: camera.session)
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    if camera.isRecording {
                        Label("REC", systemImage: "record.circle.fill")
                            .font(.headline)
                            .padding(10)
                            .background(.red, in: RoundedRectangle(cornerRadius: 10))
                            .padding(12)
                    }
                }

                VStack(spacing: 14) {
                    Toggle(isOn: $camera.torchEnabled) {
                        Label("ライト", systemImage: "flashlight.on.fill")
                    }
                    .onChange(of: camera.torchEnabled) { _ in camera.applyTorchSetting() }

                    HStack {
                        Text("指定光量")
                        Spacer()
                        Text(String(format: "%.2f%%", Double(camera.requestedLevel) * 100))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    Slider(value: $camera.brightnessPosition, in: 0...1) { _ in
                        camera.applyTorchSetting()
                    }
                    .onChange(of: camera.brightnessPosition) { _ in
                        camera.applyTorchSetting()
                    }
                    HStack {
                        Text("0.1%")
                        Spacer()
                        Text("100%")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Button {
                        camera.brightnessPosition = 0
                        camera.applyTorchSetting()
                    } label: {
                        Label("最小指定値に戻す", systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                Button(action: camera.toggleRecording) {
                    Label(camera.isRecording ? "録画を停止" : "動画を録画",
                          systemImage: camera.isRecording ? "stop.fill" : "record.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(camera.isRecording ? .red : .accentColor)
                .disabled(!camera.isReady)

                Text(camera.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("※ 指定光量はAPIへの入力値。LEDの実際の明るさではありません。端末の最小光量より弱くはできません。画面を離れると消灯し、録画も停止します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .background(Color(UIColor.systemBackground))
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
}
