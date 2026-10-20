import AVFoundation
import Combine
import Foundation
import Photos

/// Camera preview, silent in-app recording, and torch run in one capture session.
/// No system sounds or application sound effects are deliberately played.
final class CameraController: NSObject, ObservableObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()

    @Published var torchEnabled = false
    @Published var brightnessPosition: Double = 0
    @Published private(set) var isRecording = false
    @Published private(set) var isReady = false
    @Published private(set) var status = "カメラの起動を待っています"

    private let sessionQueue = DispatchQueue(label: "app.ultradim.session")
    private let sampleQueue = DispatchQueue(label: "app.ultradim.samples")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    private var cameraDevice: AVCaptureDevice?
    private var configured = false
    private var audioConfigured = false
    private var requestedTorchEnabled = false
    private var requestedTorchLevel: Float = 0.001

    // Only touched from sampleQueue. We intentionally avoid AVCaptureMovieFileOutput;
    // video/audio sample buffers are encoded directly without recording UI sounds.
    private var wantsRecording = false
    private var writer: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var recordingURL: URL?

    var requestedLevel: Float {
        Float(pow(10.0, -3.0 + 3.0 * brightnessPosition))
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            checkMicrophoneAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.checkMicrophoneAndStart() }
                    else { self?.status = "設定からカメラを許可してください" }
                }
            }
        default:
            status = "設定からカメラを許可してください"
        }
    }

    private func checkMicrophoneAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginSession(includeAudio: true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
                DispatchQueue.main.async {
                    self?.beginSession(includeAudio: allowed)
                }
            }
        default:
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

            if !self.configured && !self.configureSession(includeAudio: includeAudio) {
                return
            }
            if !self.session.isRunning { self.session.startRunning() }
            self.applyTorchOnQueue()
            DispatchQueue.main.async {
                self.isReady = true
                self.status = "撮影できます（操作音なし）"
            }
        }
    }

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
                report("カメラ入力に失敗")
                return false
            }
            session.addInput(input)
            cameraDevice = device
        } catch {
            report("カメラを開けません: \(error.localizedDescription)")
            return false
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        guard session.canAddOutput(videoOutput) else {
            report("映像出力が利用できません")
            return false
        }
        session.addOutput(videoOutput)
        videoOutput.setSampleBufferDelegate(self, queue: sampleQueue)
        videoOutput.connection(with: .video)?.videoOrientation = .portrait

        if includeAudio, let microphone = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: microphone),
           session.canAddInput(micInput) {
            session.addInput(micInput)
            if session.canAddOutput(audioOutput) {
                session.addOutput(audioOutput)
                audioOutput.setSampleBufferDelegate(self, queue: sampleQueue)
                audioConfigured = true
            }
        }

        configured = true
        return true
    }

    private func applyTorchOnQueue() {
        guard let device = cameraDevice, session.isRunning else { return }
        guard device.hasTorch, device.isTorchAvailable else {
            if requestedTorchEnabled { report("このカメラではライトを利用できません") }
            return
        }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if requestedTorchEnabled {
                try device.setTorchModeOn(level: max(0.001, min(requestedTorchLevel, 1.0)))
            } else {
                device.torchMode = .off
            }
        } catch {
            report("ライト設定に失敗: \(error.localizedDescription)")
        }
    }

    func toggleRecording() {
        sampleQueue.async { [weak self] in
            guard let self = self else { return }
            if self.wantsRecording {
                self.finishRecordingOnSampleQueue()
            } else {
                self.wantsRecording = true
                DispatchQueue.main.async {
                    self.isRecording = true
                    self.status = "録画中（操作音なし）"
                }
            }
        }
    }

    func stop() {
        sampleQueue.async { [weak self] in
            self?.finishRecordingOnSampleQueue()
        }
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.requestedTorchEnabled = false
            self.applyTorchOnQueue()
            if self.session.isRunning { self.session.stopRunning() }
        }
        DispatchQueue.main.async { self.isReady = false }
    }

    // MARK: - Recording through AVAssetWriter

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard wantsRecording, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        if output === videoOutput {
            if writer == nil { createWriter(withFirstVideo: sampleBuffer) }
            guard let writer = writer, writer.status == .writing,
                  let input = videoWriterInput else { return }
            if input.isReadyForMoreMediaData && !input.append(sampleBuffer) {
                report("映像書き込みエラー: \(writer.error?.localizedDescription ?? "不明")")
                finishRecordingOnSampleQueue()
            }
        } else if output === audioOutput,
                  let writer = writer, writer.status == .writing,
                  let input = audioWriterInput,
                  input.isReadyForMoreMediaData {
            if !input.append(sampleBuffer) {
                report("音声書き込みエラー: \(writer.error?.localizedDescription ?? "不明")")
                finishRecordingOnSampleQueue()
            }
        }
    }

    private func createWriter(withFirstVideo sampleBuffer: CMSampleBuffer) {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            report("映像フォーマットを取得できません")
            return
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        guard dimensions.width > 0, dimensions.height > 0 else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        do {
            let newWriter = try AVAssetWriter(outputURL: url, fileType: .mov)
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(dimensions.width),
                AVVideoHeightKey: Int(dimensions.height)
            ]
            let videoInput = AVAssetWriterInput(mediaType: .video,
                                                 outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true
            guard newWriter.canAdd(videoInput) else {
                report("動画エンコーダーを利用できません")
                return
            }
            newWriter.add(videoInput)

            var audioInput: AVAssetWriterInput?
            if audioConfigured,
               let audioSettings = audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov) {
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                input.expectsMediaDataInRealTime = true
                if newWriter.canAdd(input) {
                    newWriter.add(input)
                    audioInput = input
                }
            }

            guard newWriter.startWriting() else {
                report("録画を開始できません: \(newWriter.error?.localizedDescription ?? "不明")")
                return
            }
            newWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            writer = newWriter
            videoWriterInput = videoInput
            audioWriterInput = audioInput
            recordingURL = url
        } catch {
            report("録画を開始できません: \(error.localizedDescription)")
        }
    }

    private func finishRecordingOnSampleQueue() {
        guard wantsRecording else { return }
        wantsRecording = false
        DispatchQueue.main.async { self.isRecording = false }

        guard let activeWriter = writer, let url = recordingURL else {
            report("録画時間が短すぎます")
            return
        }
        let videoInput = videoWriterInput
        let audioInput = audioWriterInput
        writer = nil
        recordingURL = nil
        videoWriterInput = nil
        audioWriterInput = nil

        guard activeWriter.status == .writing else {
            report("録画ファイルの作成に失敗しました")
            activeWriter.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            return
        }

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        activeWriter.finishWriting { [weak self] in
            if activeWriter.status == .completed {
                self?.saveMovieToPhotos(url)
            } else {
                self?.report("録画終了に失敗: \(activeWriter.error?.localizedDescription ?? "不明")")
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func saveMovieToPhotos(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] access in
            guard access == .authorized || access == .limited else {
                self?.report("写真への追加を許可してください")
                try? FileManager.default.removeItem(at: url)
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { [weak self] success, error in
                self?.report(success ? "写真アプリに動画を保存しました" :
                    "保存失敗: \(error?.localizedDescription ?? "不明")")
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { self.status = message }
    }
}
