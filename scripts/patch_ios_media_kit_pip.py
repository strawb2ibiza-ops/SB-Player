#!/usr/bin/env python3
from __future__ import annotations

import glob
import os
from pathlib import Path

roots = [Path(p) for p in glob.glob(os.path.expanduser("~/.pub-cache/hosted/pub.dev/media_kit_video-*"))]
if not roots:
    raise SystemExit("media_kit_video package not found in pub cache")
root = sorted(roots)[-1]


def find_swift(name: str, marker: str) -> Path:
    for path in root.rglob(name):
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue
        if marker in text:
            return path.resolve()
    raise SystemExit(f"Could not find {name} containing {marker!r}")


plugin = find_swift("MediaKitVideoPlugin.swift", "VideoOutputManager.Create")
manager = find_swift("VideoOutputManager.swift", "class VideoOutputManager")
output = find_swift("VideoOutput.swift", "class VideoOutput")

bridge_path = root / "ios/media_kit_video/Sources/media_kit_video/plugin/SBMediaKitPiP.swift"
bridge_path.parent.mkdir(parents=True, exist_ok=True)
bridge_path.write_text(r'''#if os(iOS)
import AVFoundation
import AVKit
import CoreMedia
import CoreVideo
import UIKit

@available(iOS 15.0, *)
final class SBMediaKitPiPBridge: NSObject,
    AVPictureInPictureControllerDelegate,
    AVPictureInPictureSampleBufferPlaybackDelegate {

    private let displayLayer = AVSampleBufferDisplayLayer()
    private var hostView: UIView?
    private var controller: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var wantsStart = false
    private var paused = false
    private let onEvent: (String, Any?) -> Void

    init(onEvent: @escaping (String, Any?) -> Void) {
        self.onEvent = onEvent
        super.init()

        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .moviePlayback,
                options: []
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            emit("failed", error.localizedDescription)
        }

        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        attachLayer()

        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        self.controller = controller

        possibleObservation = controller.observe(
            \.isPictureInPicturePossible,
            options: [.initial, .new]
        ) { [weak self] controller, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.tryStart(controller)
            }
        }
    }

    deinit {
        dispose()
    }

    func start() {
        wantsStart = true
        if let controller = controller {
            tryStart(controller)
        }
    }

    func stop() {
        wantsStart = false
        if controller?.isPictureInPictureActive == true {
            controller?.stopPictureInPicture()
        }
    }

    func dispose() {
        wantsStart = false
        possibleObservation?.invalidate()
        possibleObservation = nil
        controller?.delegate = nil
        if controller?.isPictureInPictureActive == true {
            controller?.stopPictureInPicture()
        }
        controller = nil
        displayLayer.flushAndRemoveImage()
        displayLayer.removeFromSuperlayer()
        hostView?.removeFromSuperview()
        hostView = nil
    }

    func enqueue(pixelBuffer: CVPixelBuffer) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if self.displayLayer.status == .failed {
                self.displayLayer.flush()
            }
            guard self.displayLayer.isReadyForMoreMediaData else {
                return
            }

            var formatDescription: CMVideoFormatDescription?
            let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &formatDescription
            )
            guard formatStatus == noErr, let formatDescription else {
                return
            }

            var timing = CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: .invalid,
                decodeTimeStamp: .invalid
            )
            var sampleBuffer: CMSampleBuffer?
            let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescription: formatDescription,
                sampleTiming: &timing,
                sampleBufferOut: &sampleBuffer
            )
            guard sampleStatus == noErr, let sampleBuffer else {
                return
            }

            CMSetAttachment(
                sampleBuffer,
                key: kCMSampleAttachmentKey_DisplayImmediately,
                value: kCFBooleanTrue,
                attachmentMode: kCMAttachmentMode_ShouldPropagate
            )
            self.displayLayer.enqueue(sampleBuffer)

            if let controller = self.controller {
                self.tryStart(controller)
            }
        }
    }

    private func attachLayer() {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first

        guard let window else { return }

        let host = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 9))
        host.isUserInteractionEnabled = false
        host.alpha = 0.01
        displayLayer.frame = host.bounds
        host.layer.addSublayer(displayLayer)
        window.insertSubview(host, at: 0)
        hostView = host
    }

    private func tryStart(_ controller: AVPictureInPictureController) {
        guard wantsStart,
              controller.isPictureInPicturePossible,
              !controller.isPictureInPictureActive else {
            return
        }
        controller.startPictureInPicture()
    }

    private func emit(_ event: String, _ value: Any? = nil) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent(event, value)
        }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        paused = !playing
        emit("setPlaying", playing)
    }

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        paused
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        let seconds = CMTimeGetSeconds(skipInterval)
        if seconds.isFinite {
            emit("skip", seconds)
        }
        completionHandler()
    }

    func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {}

    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        emit("didStart")
    }

    func pictureInPictureControllerWillStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {}

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        wantsStart = false
        emit("didStop")
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler
            completionHandler: @escaping (Bool) -> Void
    ) {
        emit("restore")
        completionHandler(true)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        wantsStart = false
        emit("failed", error.localizedDescription)
    }
}
#endif
''', encoding="utf-8")


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"{label}: expected source block not found in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


# Patch plugin registration and method dispatch.
replace_once(
    plugin,
    '''    let channel = FlutterMethodChannel(
      name: CHANNEL_NAME,
      binaryMessenger: binaryMessenger
    )
    let instance = MediaKitVideoPlugin(
      registry: registry,
      channel: channel,
      utils: utils
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
''',
    '''    let channel = FlutterMethodChannel(
      name: CHANNEL_NAME,
      binaryMessenger: binaryMessenger
    )
    let pipChannel = FlutterMethodChannel(
      name: "sb_player/media_kit_pip",
      binaryMessenger: binaryMessenger
    )
    let instance = MediaKitVideoPlugin(
      registry: registry,
      channel: channel,
      pipChannel: pipChannel,
      utils: utils
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addMethodCallDelegate(instance, channel: pipChannel)
''',
    "plugin register",
)
replace_once(
    plugin,
    '''  private let channel: FlutterMethodChannel
  private let videoOutputManager: VideoOutputManager
''',
    '''  private let channel: FlutterMethodChannel
  private let pipChannel: FlutterMethodChannel
  private let videoOutputManager: VideoOutputManager
''',
    "plugin fields",
)
replace_once(
    plugin,
    '''    registry: FlutterTextureRegistry,
    channel: FlutterMethodChannel,
    utils: UtilsProtocol?
  ) {
    self.channel = channel
''',
    '''    registry: FlutterTextureRegistry,
    channel: FlutterMethodChannel,
    pipChannel: FlutterMethodChannel,
    utils: UtilsProtocol?
  ) {
    self.channel = channel
    self.pipChannel = pipChannel
''',
    "plugin init",
)
replace_once(
    plugin,
    '''    case "VideoOutputManager.Dispose":
      handleDisposeMethodCall(call.arguments, result)
    case "Utils.EnterNativeFullscreen":
''',
    '''    case "VideoOutputManager.Dispose":
      handleDisposeMethodCall(call.arguments, result)
    case "SBPlayerPiP.IsSupported":
      handlePiPSupported(result)
    case "SBPlayerPiP.Start":
      handlePiPStart(call.arguments, result)
    case "SBPlayerPiP.Stop":
      handlePiPStop(result)
    case "Utils.EnterNativeFullscreen":
''',
    "plugin switch",
)
replace_once(
    plugin,
    '''  private func handleEnterNativeFullscreenMethodCall(
''',
    '''  private func handlePiPSupported(_ result: FlutterResult) {
    #if os(iOS)
      if #available(iOS 15.0, *) {
        result(videoOutputManager.isPictureInPictureSupported())
      } else {
        result(false)
      }
    #else
      result(false)
    #endif
  }

  private func handlePiPStart(
    _ arguments: Any?,
    _ result: FlutterResult
  ) {
    #if os(iOS)
      if #available(iOS 15.0, *) {
        let args = arguments as? [String: Any]
        let handleStr = args?["handle"] as? String
        guard let handleStr, let handle = Int64(handleStr) else {
          result(false)
          return
        }

        let accepted = videoOutputManager.startPictureInPicture(
          handle: handle,
          eventCallback: { [weak self] event, value in
            guard let self = self else { return }
            var payload: [String: Any] = [
              "handle": handleStr,
              "event": event,
            ]
            if let value = value {
              payload["value"] = value
            }
            self.pipChannel.invokeMethod(
              "SBPlayerPiP.Event",
              arguments: payload
            )
          }
        )
        result(accepted)
      } else {
        result(false)
      }
    #else
      result(false)
    #endif
  }

  private func handlePiPStop(_ result: FlutterResult) {
    #if os(iOS)
      if #available(iOS 15.0, *) {
        videoOutputManager.stopPictureInPicture()
      }
    #endif
    result(nil)
  }

  private func handleEnterNativeFullscreenMethodCall(
''',
    "plugin PiP methods",
)

# Patch VideoOutputManager.
replace_once(
    manager,
    '''  public func destroy(
''',
    '''  #if os(iOS)
  @available(iOS 15.0, *)
  public func isPictureInPictureSupported() -> Bool {
    return AVPictureInPictureController.isPictureInPictureSupported()
  }

  @available(iOS 15.0, *)
  public func startPictureInPicture(
    handle: Int64,
    eventCallback: @escaping (String, Any?) -> Void
  ) -> Bool {
    guard let output = videoOutputs[handle] else {
      return false
    }
    output.pipEventCallback = eventCallback
    output.startPictureInPicture()
    return true
  }

  @available(iOS 15.0, *)
  public func stopPictureInPicture() {
    for output in videoOutputs.values {
      output.stopPictureInPicture()
    }
  }
  #endif

  public func destroy(
''',
    "manager PiP methods",
)
manager_text = manager.read_text(encoding="utf-8")
if "#if os(iOS)
import AVKit
#endif" not in manager_text:
    manager.write_text(
        "#if os(iOS)\nimport AVKit\n#endif\n" + manager_text,
        encoding="utf-8",
    )

# Patch VideoOutput with PiP bridge + frame forwarding.
replace_once(
    output,
    '''  private var disposed: Bool = false
''',
    '''  private var disposed: Bool = false

  #if os(iOS)
  public var pipEventCallback: ((String, Any?) -> Void)?
  @available(iOS 15.0, *)
  private var sbPipBridge: SBMediaKitPiPBridge?
  #endif
''',
    "output fields",
)
replace_once(
    output,
    '''  deinit {
    worker.cancel()

    disposed = true
''',
    '''  deinit {
    worker.cancel()

    #if os(iOS)
    if #available(iOS 15.0, *) {
      sbPipBridge?.dispose()
      sbPipBridge = nil
    }
    #endif

    disposed = true
''',
    "output deinit",
)
replace_once(
    output,
    '''  private func _init() {
''',
    '''  #if os(iOS)
  @available(iOS 15.0, *)
  public func startPictureInPicture() {
    DispatchQueue.main.async {
      let bridge: SBMediaKitPiPBridge
      if let existing = self.sbPipBridge {
        bridge = existing
      } else {
        bridge = SBMediaKitPiPBridge(
          onEvent: { [weak self] event, value in
            self?.pipEventCallback?(event, value)
          }
        )
        self.sbPipBridge = bridge
      }

      if let unmanaged = self.texture?.copyPixelBuffer() {
        bridge.enqueue(pixelBuffer: unmanaged.takeRetainedValue())
      }
      bridge.start()
    }
  }

  @available(iOS 15.0, *)
  public func stopPictureInPicture() {
    DispatchQueue.main.async {
      self.sbPipBridge?.stop()
    }
  }
  #endif

  private func _init() {
''',
    "output methods",
)
replace_once(
    output,
    '''    texture.render(size)
    DispatchQueue.main.sync { [weak self] in
''',
    '''    texture.render(size)

    #if os(iOS)
    if #available(iOS 15.0, *),
       let bridge = sbPipBridge,
       let unmanaged = texture.copyPixelBuffer() {
      bridge.enqueue(pixelBuffer: unmanaged.takeRetainedValue())
    }
    #endif

    DispatchQueue.main.sync { [weak self] in
''',
    "output frame forwarding",
)

print("Patched media_kit_video iOS PiP:")
print(" plugin:", plugin)
print(" manager:", manager)
print(" output:", output)
print(" bridge:", bridge_path)
