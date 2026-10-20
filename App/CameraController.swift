import AVFoundation
import Combine
import Foundation
import Photos

/// Back-camera preview, video/audio recording, and torch share one capture session.
/// All AVFoundation session/device mutations occur on sessionQueue.
final class CameraController: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()

    @Published var torchEnabled = false
    @Published var brightnessPosition: Double = 0  // logarithmic: 0.1% -> 100% requested level
    @Published private(set) var isRecording = false
    @Published private(set) var isReady = false
    @Published private(set) var status = "カメラの起動を待っています"

    private let sessionQueue = DispatchQueue(label: "app.ultradim.camera.session")
    private let movieOutput = AVCaptureMovieFileOutput()
    private var cameraDevice: AVCaptureDevice?
    private var configured = false
    private var requestedTorchEnabled = false
    private var requestedTorchLevel: Float = 0.001
    private var stopAfterRecording = false

    var requestedLevel: Float {
        // Values below the phone's hardware floor may produce the same brightness.
        Float(pow(10.0, -3.0 + 3.0 * brightnessPosition))
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            checkMicrophoneAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.checkMicrophoneAndStart()
                    } else {
                        self?.status = "設定からカメラへのアクセスを許可してください"
                    }
                }
            }
        default:
            status = "設定からカメラへのアクセスを許可してください"
        }
    }

    private func checkMicrophoneAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginSession(includeAudio: true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.beginSession(includeAudio: granted)
                }
            }
        default:
            // Silent video is still useful if the user denies microphone access.
            beginSession(includeAudio: false)
        }
    }

    private func beginSession(includeAudio: Bool) {
        let enabled = torchEnabled
        let level = requestedLevel
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.requestedTorchEnabled = enabled
            self.requestedTorchLevel = level

            if !self.configured {
                guard self.configureSession(includeAudio: includeAudio) else { return }
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            self.applyTorchOnQueue()
            DispatchQueue.main.async {
                self.isReady = true
                self.status = "撮影できます"
            }
        }
    }

    /// Called after either light switch or slider changes.
    func applyTorchSetting() {
        let enabled = torchEnabled
        let level = requestedLevel
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.requestedTorchEnabled = enabled
            self.requestedTorchLevel = level
            self.applyTorchOnQueue()
        }
    }

    private func configureSession(includeAudio: Bool) -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video, position: .back) else {
            report("背面カメラがありません")
            return false
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                report("カメラ入力を追加できません")
                return false
            }
            session.addInput(input)
            cameraDevice = device
        } catch {
            report("カメラを開けません: \(error.localizedDescription)")
            return false
        }

        if includeAudio, let microphone = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: microphone),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
        guard session.canAddOutput(movieOutput) else {
            report("動画出力に対応していません")
            return false
        }
        session.addOutput(movieOutput)
        configured = true
        return true
    }

    private func applyTorchOnQueue() {
        guard let device = cameraDevice, session.isRunning else { return }
        guard device.hasTorch, device.isTorchAvailable else {
            if requestedTorchEnabled { report("このカメラではライトが利用できません") }
            return
        }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if requestedTorchEnabled {
                // The accepted API level is not a measured brightness percentage.
                try device.setTorchModeOn(level: max(0.001, min(requestedTorchLevel, 1.0)))
            } else {
                device.torchMode = .off
            }
        } catch {
            report("ライトの調光に失敗: \(error.localizedDescription)")
        }
    }

    func toggleRecording() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            } else {
                let file = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")
                self.movieOutput.startRecording(to: file, recordingDelegate: self)
                DispatchQueue.main.async {
                    self.isRecording = true
                    self.status = "録画中"
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.movieOutput.isRecording {
                self.stopAfterRecording = true
                self.movieOutput.stopRecording()
            } else {
                self.stopSessionOnQueue()
            }
        }
        DispatchQueue.main.async { self.isReady = false }
    }

    private func stopSessionOnQueue() {
        requestedTorchEnabled = false
        applyTorchOnQueue()
        if session.isRunning { session.stopRunning() }
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { self.status = message }
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.stopAfterRecording {
                self.stopAfterRecording = false
                self.stopSessionOnQueue()
            }
        }
        DispatchQueue.main.async { self.isRecording = false }

        if let error = error {
            report("録画失敗: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] authorization in
            guard authorization == .authorized || authorization == .limited else {
                self?.report("写真への追加を許可してください。動画は保存されません")
                try? FileManager.default.removeItem(at: outputFileURL)
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
            }) { [weak self] success, saveError in
                if success {
                    self?.report("写真アプリに動画を保存しました")
                } else {
                    self?.report("保存に失敗: \(saveError?.localizedDescription ?? "不明なエラー")")
                }
                try? FileManager.default.removeItem(at: outputFileURL)
            }
        }
    }
}
