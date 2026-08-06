#if DEBUG
import AVFoundation
import Foundation

/// Debug-only iOS Simulator probe. It is inert unless the app is launched with
/// `--gc-simulator-media-probe`, and the whole type is removed from Release builds.
enum GCSimulatorMediaProbe {
    private static let launchArgument = "--gc-simulator-media-probe"

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return }

        AVCaptureDevice.requestAccess(for: .video) { cameraGranted in
            AVCaptureDevice.requestAccess(for: .audio) { microphoneGranted in
                DispatchQueue.main.async {
                    finish(cameraGranted: cameraGranted, microphoneGranted: microphoneGranted)
                }
            }
        }
    }

    private static func finish(cameraGranted: Bool, microphoneGranted: Bool) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .videoChat, options: [.defaultToSpeaker])
            try session.setActive(true)

            guard cameraGranted, microphoneGranted else {
                emit(
                    "GC_SIM_MEDIA_PROBE FAIL camera=\(state(cameraGranted)) " +
                    "microphone=\(state(microphoneGranted)) audioSession=active"
                )
                return
            }

            emit("GC_SIM_MEDIA_PROBE PASS camera=granted microphone=granted audioSession=active")
        } catch {
            emit(
                "GC_SIM_MEDIA_PROBE FAIL camera=\(state(cameraGranted)) " +
                "microphone=\(state(microphoneGranted)) audioSession=\(error.localizedDescription)"
            )
        }
    }

    private static func emit(_ message: String) {
        guard let data = "\(message)\n".data(using: .utf8) else { return }
        FileHandle.standardOutput.write(data)
    }

    private static func state(_ granted: Bool) -> String {
        granted ? "granted" : "denied"
    }
}
#endif
