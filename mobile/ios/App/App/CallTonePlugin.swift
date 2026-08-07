import AVFoundation
import Capacitor
import Foundation

/// Native outgoing ringback used only while the Capacitor WebView is backgrounded.
/// The shared web layer stops its HTMLAudio tone before invoking this bridge, so the sounds never overlap.
@objc(CallTonePlugin)
public final class CallTonePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CallTonePlugin"
    public let jsName = "CallTone"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "startOutgoing", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise),
    ]

    private var player: AVAudioPlayer?

    @objc public func startOutgoing(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return call.reject("CALL_TONE_START_FAILED") }
            do {
                if self.player?.isPlaying == true {
                    call.resolve(["playing": true])
                    return
                }
                guard let url = Bundle.main.url(
                    forResource: "call-outgoing",
                    withExtension: "mp3",
                    subdirectory: "public/assets"
                ) else {
                    throw NSError(domain: "app.greenchat.calltone", code: 1, userInfo: [NSLocalizedDescriptionKey: "ringback asset missing"])
                }
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
                try session.setActive(true)
                let next = try AVAudioPlayer(contentsOf: url)
                next.numberOfLoops = -1
                next.volume = 1
                next.prepareToPlay()
                guard next.play() else {
                    throw NSError(domain: "app.greenchat.calltone", code: 2, userInfo: [NSLocalizedDescriptionKey: "ringback playback refused"])
                }
                self.player = next
                call.resolve(["playing": true])
            } catch {
                self.stopPlayer()
                call.reject("CALL_TONE_START_FAILED", nil, error)
            }
        }
    }

    @objc public func stop(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            self?.stopPlayer()
            call.resolve(["playing": false])
        }
    }

    private func stopPlayer() {
        player?.stop()
        player = nil
        // Do not deactivate AVAudioSession here: WebRTC may already own the same playAndRecord session.
    }

    deinit {
        stopPlayer()
    }
}
