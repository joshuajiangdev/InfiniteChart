#if os(macOS)
import AppKit
import AVFoundation

/// Records only this example's content view; no screen-recording permission is needed.
@MainActor
final class BTCExampleVideoRecorder: NSObject {
    private let view: NSView
    private let outputURL: URL
    private let duration: TimeInterval
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let completion: (Result<URL, Error>) -> Void
    private var timer: Timer?
    private var startedAt: TimeInterval = 0
    private var isFinishing = false
    private var recordedFrames = 0

    private static let width = 1100
    private static let height = 760
    private static let framesPerSecond = 20

    init(view: NSView, outputURL: URL, duration: TimeInterval,
         completion: @escaping (Result<URL, Error>) -> Void) throws {
        guard duration.isFinite, duration > 0 else {
            throw CaptureError("Recording duration must be a positive number of seconds.")
        }
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CaptureError("The recording destination already exists: \(outputURL.path)")
        }
        self.view = view
        self.outputURL = outputURL
        self.duration = duration
        self.completion = completion
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Self.width,
            AVVideoHeightKey: Self.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 4_000_000,
                AVVideoExpectedSourceFrameRateKey: Self.framesPerSecond,
                AVVideoMaxKeyFrameIntervalKey: Self.framesPerSecond * 2
            ]
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.width,
            kCVPixelBufferHeightKey as String: Self.height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        super.init()
        guard writer.canAdd(input) else {
            throw CaptureError("The H.264 video writer could not accept its input.")
        }
        writer.add(input)
    }

    func start() throws {
        guard writer.startWriting() else {
            throw writer.error ?? CaptureError("Could not start the video writer.")
        }
        writer.startSession(atSourceTime: .zero)
        startedAt = ProcessInfo.processInfo.systemUptime
        captureFrame()
        guard !isFinishing else { return }
        let timer = Timer(timeInterval: 1 / Double(Self.framesPerSecond), target: self,
                          selector: #selector(captureFrame), userInfo: nil, repeats: true)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        print("Recording example view to \(outputURL.path) for \(duration) seconds…")
    }

    @objc private func captureFrame() {
        guard !isFinishing else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        if elapsed >= duration {
            finish()
            return
        }
        guard writer.status == .writing else {
            fail(writer.error ?? CaptureError("The video writer stopped unexpectedly."))
            return
        }
        // Skip a busy encoder frame while retaining elapsed-time timestamps.
        guard input.isReadyForMoreMediaData else { return }
        do {
            let frame = try makeFrame()
            let timestamp = recordedFrames == 0 ? CMTime.zero : CMTime(seconds: elapsed, preferredTimescale: 600)
            guard adaptor.append(frame, withPresentationTime: timestamp) else {
                throw writer.error ?? CaptureError("Could not append a video frame.")
            }
            recordedFrames += 1
        } catch {
            fail(error)
        }
    }

    private func makeFrame() throws -> CVPixelBuffer {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CaptureError("Could not create a bitmap for the example view.")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let image = bitmap.cgImage, let pool = adaptor.pixelBufferPool else {
            throw CaptureError("Could not prepare the example's video frame.")
        }
        var optionalBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &optionalBuffer) == kCVReturnSuccess,
              let buffer = optionalBuffer else {
            throw CaptureError("Could not allocate a video frame.")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Self.width, height: Self.height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            throw CaptureError("Could not draw into a video frame.")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: Self.width, height: Self.height))
        return buffer
    }

    private func finish() {
        isFinishing = true
        timer?.invalidate()
        timer = nil
        guard recordedFrames > 0 else {
            writer.cancelWriting()
            completion(.failure(CaptureError("The recording did not contain any frames.")))
            return
        }
        writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: 600))
        input.markAsFinished()
        writer.finishWriting { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.writer.status == .completed {
                    print("Recorded \(self.recordedFrames) frames: \(self.outputURL.path)")
                    self.completion(.success(self.outputURL))
                } else {
                    self.completion(.failure(self.writer.error ?? CaptureError("Could not finish the video file.")))
                }
            }
        }
    }

    private func fail(_ error: Error) {
        isFinishing = true
        timer?.invalidate()
        timer = nil
        writer.cancelWriting()
        completion(.failure(error))
    }
}

private struct CaptureError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
#endif
