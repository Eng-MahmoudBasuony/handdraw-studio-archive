import Cocoa
import AVFoundation
import Accelerate
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var projectSaveScopes: [String: (destination: URL, directory: URL, accessing: Bool)] = [:]
  private var launchSplashView: LaunchSplashView?
  private var previewAudioPlayer: AVAudioPlayer?
  private var voiceGuidePlayer: AVAudioPlayer?
  private var startupAudioPlayer: AVAudioPlayer?
  private var startupAudioCompletion: DispatchWorkItem?
  private var activeVoiceURL: URL?
  private var isAccessingVoiceURL = false
  private var previewClockOffset = 0.0
  private var previewClockStartedAt = 0.0
  private var previewClockDuration = 0.0
  private var previewClockIsPlaying = false
  private var activeExportURL: URL?
  private var isAccessingExportURL = false
  private var proResStreamSessions: [String: ProResStreamingSession] = [:]

  private enum WindowMetrics {
    static let minimumSize = NSSize(width: 720, height: 560)
    static let preferredSize = NSSize(width: 1440, height: 900)
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let launchAppearance = LaunchSplashView.preferredAppearance(
      fallback: self.effectiveAppearance)
    let launchBackground = LaunchSplashView.backgroundColor(
      for: launchAppearance)
    // Flutter owns its root rendering layer and backing-scale calculations.
    // Color the window behind it instead of forcing the Flutter view to become
    // layer-backed, which can make the surface render at half size on Retina.
    self.backgroundColor = launchBackground
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = WindowMetrics.minimumSize
    self.setContentSize(WindowMetrics.preferredSize)
    self.center()

    installLaunchSplash(
      on: flutterViewController.view,
      appearance: launchAppearance)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerVideoExporter(with: flutterViewController)
    registerLaunchLifecycle(with: flutterViewController)
    registerStartupSound(with: flutterViewController)

    super.awakeFromNib()
    activateLaunchWindow()
  }

  private func activateLaunchWindow() {
    // `flutter run` starts the executable directly, and LaunchServices can fail
    // to foreground that process. Focus the window from inside the app so an
    // otherwise healthy editor is never left hidden behind the IDE.
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if #available(macOS 14.0, *) {
        NSApplication.shared.activate()
      } else {
        NSApplication.shared.activate(ignoringOtherApps: true)
      }
      self.makeKeyAndOrderFront(nil)
    }
  }

  private func registerStartupSound(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "handdraw_studio/startup_sound",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      let arguments = call.arguments as? [String: Any]
      switch call.method {
      case "play":
        guard let path = arguments?["path"] as? String else {
          result(FlutterError(
            code: "invalid_startup_sound",
            message: "The startup sound path is missing.",
            details: nil))
          return
        }
        do {
          try self?.playStartupSound(
            path: path,
            volume: arguments?["volume"] as? Double ?? 0.3,
            fadeInMilliseconds: arguments?["fadeInMilliseconds"] as? Int ?? 220,
            fadeOutMilliseconds: arguments?["fadeOutMilliseconds"] as? Int ?? 420)
          result(nil)
        } catch {
          result(FlutterError(
            code: "startup_sound_failed",
            message: error.localizedDescription,
            details: nil))
        }
      case "stop":
        self?.stopStartupSound(
          fadeOutMilliseconds: arguments?["fadeOutMilliseconds"] as? Int ?? 140)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func playStartupSound(
    path: String,
    volume: Double,
    fadeInMilliseconds: Int,
    fadeOutMilliseconds: Int
  ) throws {
    stopStartupSound(fadeOutMilliseconds: 0)
    let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
    let targetVolume = Float(min(max(volume, 0), 1))
    let fadeIn = max(0, Double(fadeInMilliseconds) / 1_000)
    let fadeOut = max(0, Double(fadeOutMilliseconds) / 1_000)
    player.volume = fadeIn > 0 ? 0 : targetVolume
    player.prepareToPlay()
    player.play()
    if fadeIn > 0 {
      player.setVolume(targetVolume, fadeDuration: fadeIn)
    }
    startupAudioPlayer = player

    let fadeStart = max(0, player.duration - fadeOut)
    let completion = DispatchWorkItem { [weak self, weak player] in
      guard let self, let player, self.startupAudioPlayer === player else { return }
      if fadeOut > 0 {
        player.setVolume(0, fadeDuration: fadeOut)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + fadeOut) { [weak self, weak player] in
        guard let self, let player, self.startupAudioPlayer === player else { return }
        player.stop()
        self.startupAudioPlayer = nil
        self.startupAudioCompletion = nil
      }
    }
    startupAudioCompletion = completion
    DispatchQueue.main.asyncAfter(deadline: .now() + fadeStart, execute: completion)
  }

  private func stopStartupSound(fadeOutMilliseconds: Int) {
    startupAudioCompletion?.cancel()
    startupAudioCompletion = nil
    guard let player = startupAudioPlayer else { return }
    let fadeOut = max(0, Double(fadeOutMilliseconds) / 1_000)
    if fadeOut <= 0 {
      player.stop()
      startupAudioPlayer = nil
      return
    }
    player.setVolume(0, fadeDuration: fadeOut)
    DispatchQueue.main.asyncAfter(deadline: .now() + fadeOut) { [weak self, weak player] in
      guard let self, let player, self.startupAudioPlayer === player else { return }
      player.stop()
      self.startupAudioPlayer = nil
    }
  }

  private func installLaunchSplash(
    on hostView: NSView,
    appearance: NSAppearance
  ) {
    let splash = LaunchSplashView(frame: hostView.bounds)
    splash.apply(appearance: appearance)
    splash.autoresizingMask = [.width, .height]
    hostView.addSubview(splash)
    launchSplashView = splash
  }

  private func registerLaunchLifecycle(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "handdraw_studio/lifecycle",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "appReady":
        self?.dismissLaunchSplash(animated: true)
        result(nil)
      case "isLaunchSplashVisible":
        result(self?.launchSplashView != nil)
      case "prepareForNativeDialog":
        // Ensure the sheet opened by file_selector starts as the key UI. When
        // the app is inactive, macOS otherwise consumes the first click merely
        // to activate the panel instead of selecting the intended file.
        if #available(macOS 14.0, *) {
          NSApplication.shared.activate()
        } else {
          NSApplication.shared.activate(ignoringOtherApps: true)
        }
        self?.makeKeyAndOrderFront(nil)
        self?.orderFrontRegardless()
        DispatchQueue.main.async {
          self?.makeKey()
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func dismissLaunchSplash(animated: Bool) {
    guard let splash = launchSplashView else { return }
    if !animated {
      splash.removeFromSuperview()
      launchSplashView = nil
      return
    }
    // Flutter has already rasterized the editor. Fade immediately instead of
    // adding a second artificial launch delay after the app is ready.
    NSAnimationContext.runAnimationGroup { context in
      context.duration = LaunchSplashTiming.fadeDuration
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      splash.animator().alphaValue = 0
    } completionHandler: { [weak self, weak splash] in
      splash?.removeFromSuperview()
      self?.launchSplashView = nil
    }
  }

  private func registerVideoExporter(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "handdraw_studio/exporter",
      binaryMessenger: controller.engine.binaryMessenger)

    channel.setMethodCallHandler { call, result in
      if call.method == "getExporterVersion" {
        result(ProResExporter.version)
        return
      }
      if call.method == "inspectVoiceGuide" {
        guard let arguments = call.arguments as? [String: Any] else {
          result(FlutterError(
            code: "invalid_voice_guide",
            message: "The voice guide arguments are missing.",
            details: nil))
          return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let inspected = try VoiceGuideMedia.inspect(arguments: arguments)
            DispatchQueue.main.async { result(inspected) }
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(
                code: "voice_guide_unavailable",
                message: error.localizedDescription,
                details: nil))
            }
          }
        }
        return
      }
      if call.method == "playPreviewAudio" {
        guard let arguments = call.arguments as? [String: Any] else {
          result(FlutterError(
            code: "invalid_preview_audio",
            message: "The preview audio arguments are missing.",
            details: nil))
          return
        }
        do {
          try self.startPreviewAudio(arguments: arguments)
          result(nil)
        } catch {
          result(FlutterError(
            code: "preview_audio_failed",
            message: error.localizedDescription,
            details: nil))
        }
        return
      }
      if call.method == "pausePreviewAudio" {
        self.pausePreviewAudio()
        result(nil)
        return
      }
      if call.method == "resumePreviewAudio" {
        self.resumePreviewAudio()
        result(nil)
        return
      }
      if call.method == "seekPreviewAudio" {
        let arguments = call.arguments as? [String: Any]
        self.seekPreviewAudio(to: arguments?["positionSeconds"] as? Double ?? 0)
        result(nil)
        return
      }
      if call.method == "setPreviewAudioVolume" {
        let arguments = call.arguments as? [String: Any]
        self.setPreviewAudioVolume(arguments?["volume"] as? Double ?? 1)
        result(nil)
        return
      }
      if call.method == "getPreviewPosition" {
        result(self.currentPreviewPosition())
        return
      }
      if call.method == "stopPreviewAudio" {
        self.stopPreviewAudio()
        result(nil)
        return
      }
      if call.method == "playWritingAudio" {
        guard
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String
        else {
          result(FlutterError(
            code: "invalid_audio_path",
            message: "The preview audio path is missing.",
            details: nil))
          return
        }
        do {
          self.previewAudioPlayer?.stop()
          let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
          player.prepareToPlay()
          player.play()
          self.previewAudioPlayer = player
          result(nil)
        } catch {
          result(FlutterError(
            code: "audio_preview_failed",
            message: error.localizedDescription,
            details: nil))
        }
        return
      }
      if call.method == "pauseWritingAudio" {
        self.previewAudioPlayer?.pause()
        result(nil)
        return
      }
      if call.method == "resumeWritingAudio" {
        self.previewAudioPlayer?.play()
        result(nil)
        return
      }
      if call.method == "stopWritingAudio" {
        self.stopPreviewAudio()
        result(nil)
        return
      }
      if call.method == "prepareProjectSave" {
        guard let args = call.arguments as? [String: Any], let path = args["destination"] as? String else {
          result(FlutterError(code: "invalid_project_path", message: "Missing project destination", details: nil)); return
        }
        let destination = URL(fileURLWithPath: path)
        let accessing = destination.startAccessingSecurityScopedResource()
        do {
          let directory = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)
          let temporary = directory.appendingPathComponent("project.koni")
          self.projectSaveScopes[temporary.path] = (destination, directory, accessing)
          result(temporary.path)
        } catch {
          if accessing { destination.stopAccessingSecurityScopedResource() }
          result(FlutterError(code: "project_staging_failed", message: error.localizedDescription, details: nil))
        }
        return
      }
      if call.method == "commitProjectSave" || call.method == "finishProjectSave" {
        guard let args = call.arguments as? [String: Any], let path = args["temporary"] as? String,
              let scope = self.projectSaveScopes[path] else {
          result(FlutterError(code: "invalid_project_save", message: "Unknown project save session", details: nil)); return
        }
        do {
          if call.method == "commitProjectSave" {
            let temporary = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: scope.destination.path) {
              _ = try FileManager.default.replaceItemAt(scope.destination, withItemAt: temporary)
            } else {
              try FileManager.default.moveItem(at: temporary, to: scope.destination)
            }
          } else {
            defer {
              if scope.accessing { scope.destination.stopAccessingSecurityScopedResource() }
              self.projectSaveScopes.removeValue(forKey: path)
            }
            if FileManager.default.fileExists(atPath: scope.directory.path) {
              try FileManager.default.removeItem(at: scope.directory)
            }
          }
          result(nil)
        } catch {
          result(FlutterError(code: "project_save_failed", message: error.localizedDescription, details: nil))
        }
        return
      }
      if call.method == "beginExportAccess" {
        guard
          let arguments = call.arguments as? [String: Any],
          let path = arguments["outputPath"] as? String
        else {
          result(FlutterError(
            code: "invalid_export_path",
            message: "The export destination is missing.",
            details: nil))
          return
        }
        self.endExportAccess()
        let url = URL(fileURLWithPath: path)
        self.activeExportURL = url
        self.isAccessingExportURL = url.startAccessingSecurityScopedResource()
        result(self.isAccessingExportURL)
        return
      }
      if call.method == "endExportAccess" {
        self.endExportAccess()
        result(nil)
        return
      }
      if call.method == "inspectExport" {
        guard
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String
        else {
          result(FlutterError(
            code: "invalid_inspection_path",
            message: "The exported movie path is missing.",
            details: nil))
          return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let inspection = try ExportInspection.inspect(
              URL(fileURLWithPath: path))
            DispatchQueue.main.async { result(inspection) }
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(
                code: "export_inspection_failed",
                message: error.localizedDescription,
                details: nil))
            }
          }
        }
        return
      }
      if call.method == "startProRes4444Stream" {
        guard
          let arguments = call.arguments as? [String: Any],
          let outputPath = arguments["outputPath"] as? String,
          let width = arguments["width"] as? Int,
          let height = arguments["height"] as? Int,
          let frameRate = arguments["frameRate"] as? Int,
          let frameCount = arguments["frameCount"] as? Int
        else {
          result(FlutterError(
            code: "invalid_stream_arguments",
            message: "The streaming export settings are incomplete.",
            details: nil))
          return
        }
        do {
          let sessionId = UUID().uuidString
          let session = try ProResStreamingSession(
            outputURL: URL(fileURLWithPath: outputPath),
            width: width,
            height: height,
            frameRate: frameRate,
            frameCount: frameCount,
            alphaMode: arguments["alphaMode"] as? String ?? "premultiplied",
            expectsAudio: arguments["expectsAudio"] as? Bool ?? false)
          self.proResStreamSessions[sessionId] = session
          result(sessionId)
        } catch {
          result(FlutterError(
            code: "prores_stream_start_failed",
            message: error.localizedDescription,
            details: nil))
        }
        return
      }
      if call.method == "appendProRes4444Frame" {
        guard
          let arguments = call.arguments as? [String: Any],
          let sessionId = arguments["sessionId"] as? String,
          let frameIndex = arguments["frameIndex"] as? Int,
          let typedData = arguments["rgba"] as? FlutterStandardTypedData,
          let session = self.proResStreamSessions[sessionId]
        else {
          result(FlutterError(
            code: "invalid_stream_frame",
            message: "The streaming frame or encoder session is missing.",
            details: nil))
          return
        }
        session.append(rgba: typedData.data, frameIndex: frameIndex) { appendResult in
          DispatchQueue.main.async {
            switch appendResult {
            case .success:
              result(nil)
            case .failure(let error):
              result(FlutterError(
                code: "prores_stream_append_failed",
                message: error.localizedDescription,
                details: nil))
            }
          }
        }
        return
      }
      if call.method == "finishProRes4444Stream" {
        guard
          let arguments = call.arguments as? [String: Any],
          let sessionId = arguments["sessionId"] as? String,
          let session = self.proResStreamSessions.removeValue(forKey: sessionId)
        else {
          result(FlutterError(
            code: "invalid_stream_session",
            message: "The streaming encoder session is missing.",
            details: nil))
          return
        }
        let audioURL = (arguments["audioPath"] as? String)
          .map(URL.init(fileURLWithPath:))
        session.finish(audioURL: audioURL) { finishResult in
          DispatchQueue.main.async {
            switch finishResult {
            case .success(let path):
              result(path)
            case .failure(let error):
              result(FlutterError(
                code: "prores_stream_finish_failed",
                message: error.localizedDescription,
                details: nil))
            }
          }
        }
        return
      }
      if call.method == "cancelProRes4444Stream" {
        let arguments = call.arguments as? [String: Any]
        if
          let sessionId = arguments?["sessionId"] as? String,
          let session = self.proResStreamSessions.removeValue(forKey: sessionId)
        {
          session.cancel()
        }
        result(nil)
        return
      }
      guard call.method == "encodeProRes4444" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let framesDirectory = arguments["framesDirectory"] as? String,
        let outputPath = arguments["outputPath"] as? String,
        let width = arguments["width"] as? Int,
        let height = arguments["height"] as? Int,
        let frameRate = arguments["frameRate"] as? Int,
        let frameCount = arguments["frameCount"] as? Int
      else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "The export settings are incomplete.",
          details: nil))
        return
      }

      ProResExporter.encode(
        framesDirectory: URL(fileURLWithPath: framesDirectory),
        outputURL: URL(fileURLWithPath: outputPath),
        width: width,
        height: height,
        frameRate: frameRate,
        frameCount: frameCount,
        alphaMode: arguments["alphaMode"] as? String ?? "premultiplied",
        audioURL: (arguments["audioPath"] as? String).map(URL.init(fileURLWithPath:))
      ) { exportResult in
        DispatchQueue.main.async {
          switch exportResult {
          case .success(let path):
            result(path)
          case .failure(let error):
            result(FlutterError(
              code: "prores_export_failed",
              message: error.localizedDescription,
              details: nil))
          }
        }
      }
    }
  }

  private func startPreviewAudio(arguments: [String: Any]) throws {
    stopPreviewAudio()
    previewClockDuration = arguments["durationSeconds"] as? Double ?? 0
    previewClockOffset = max(
      0,
      min(arguments["positionSeconds"] as? Double ?? 0, previewClockDuration))

    if let path = arguments["writingPath"] as? String, !path.isEmpty {
      previewAudioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
    }
    if arguments["voicePath"] != nil || arguments["voiceBookmark"] != nil {
      var voiceArguments: [String: Any] = [:]
      if let path = arguments["voicePath"] as? String {
        voiceArguments["path"] = path
      }
      if let bookmark = arguments["voiceBookmark"] as? String {
        voiceArguments["securityBookmark"] = bookmark
      }
      let url = try VoiceGuideMedia.resolveURL(arguments: voiceArguments)
      activeVoiceURL = url
      isAccessingVoiceURL = url.startAccessingSecurityScopedResource()
      voiceGuidePlayer = try AVAudioPlayer(contentsOf: url)
    }
    setPreviewAudioVolume(arguments["volume"] as? Double ?? 1)
    preparePlayers(at: previewClockOffset)
    previewClockStartedAt = ProcessInfo.processInfo.systemUptime
    previewClockIsPlaying = true
    playPreparedPlayers()
  }

  private func preparePlayers(at position: Double) {
    for player in [previewAudioPlayer, voiceGuidePlayer].compactMap({ $0 }) {
      player.currentTime = min(max(0, position), player.duration)
      player.prepareToPlay()
    }
  }

  private func playPreparedPlayers() {
    let players = [previewAudioPlayer, voiceGuidePlayer].compactMap({ $0 })
    guard !players.isEmpty else { return }
    let startTime = (players.first?.deviceCurrentTime ?? 0) + 0.035
    for player in players where player.currentTime < player.duration {
      player.play(atTime: startTime)
    }
  }

  private func pausePreviewAudio() {
    previewClockOffset = currentPreviewPosition()
    previewClockIsPlaying = false
    previewAudioPlayer?.pause()
    voiceGuidePlayer?.pause()
  }

  private func resumePreviewAudio() {
    guard !previewClockIsPlaying else { return }
    if previewClockOffset >= previewClockDuration { previewClockOffset = 0 }
    preparePlayers(at: previewClockOffset)
    previewClockStartedAt = ProcessInfo.processInfo.systemUptime
    previewClockIsPlaying = true
    playPreparedPlayers()
  }

  private func seekPreviewAudio(to position: Double) {
    previewClockOffset = max(0, min(position, previewClockDuration))
    preparePlayers(at: previewClockOffset)
    if previewClockIsPlaying {
      previewClockStartedAt = ProcessInfo.processInfo.systemUptime
      playPreparedPlayers()
    }
  }

  private func setPreviewAudioVolume(_ volume: Double) {
    let resolved = Float(max(0, min(volume, 1)))
    previewAudioPlayer?.volume = resolved
    voiceGuidePlayer?.volume = resolved
  }

  private func currentPreviewPosition() -> Double {
    guard previewClockIsPlaying else { return previewClockOffset }
    let elapsed = ProcessInfo.processInfo.systemUptime - previewClockStartedAt
    let position = min(previewClockDuration, previewClockOffset + elapsed)
    if position >= previewClockDuration {
      previewClockOffset = previewClockDuration
      previewClockIsPlaying = false
    }
    return position
  }

  private func stopPreviewAudio() {
    previewAudioPlayer?.stop()
    previewAudioPlayer = nil
    voiceGuidePlayer?.stop()
    voiceGuidePlayer = nil
    if isAccessingVoiceURL {
      activeVoiceURL?.stopAccessingSecurityScopedResource()
    }
    activeVoiceURL = nil
    isAccessingVoiceURL = false
    previewClockOffset = 0
    previewClockStartedAt = 0
    previewClockDuration = 0
    previewClockIsPlaying = false
  }

  private func endExportAccess() {
    if isAccessingExportURL {
      activeExportURL?.stopAccessingSecurityScopedResource()
    }
    activeExportURL = nil
    isAccessingExportURL = false
  }
}

enum LaunchSplashTiming {
  static let fadeDuration: TimeInterval = 0.12
}

private final class LaunchSplashView: NSView {
  private enum Metrics {
    static let logoSize: CGFloat = 132
    static let contentSpacing: CGFloat = 14
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = Self.backgroundColor(
      for: effectiveAppearance).cgColor
    setAccessibilityLabel("HandDraw Studio")

    let logo = NSImageView()
    logo.image = NSImage(named: NSImage.Name("BrandSplash"))
    logo.imageScaling = .scaleProportionallyUpOrDown
    logo.translatesAutoresizingMaskIntoConstraints = false

    let title = NSTextField(labelWithString: "HandDraw Studio")
    title.font = .systemFont(ofSize: 24, weight: .semibold)
    title.textColor = .labelColor
    title.alignment = .center

    let subtitle = NSTextField(labelWithString: Self.localizedSubtitle)
    subtitle.font = .systemFont(ofSize: 12, weight: .regular)
    subtitle.textColor = .secondaryLabelColor
    subtitle.alignment = .center

    let progress = NSProgressIndicator()
    progress.style = .spinning
    progress.controlSize = .small
    progress.startAnimation(nil)

    let stack = NSStackView(views: [logo, title, subtitle, progress])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = Metrics.contentSpacing
    stack.setCustomSpacing(7, after: title)
    stack.setCustomSpacing(22, after: subtitle)
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)

    NSLayoutConstraint.activate([
      logo.widthAnchor.constraint(equalToConstant: Metrics.logoSize),
      logo.heightAnchor.constraint(equalToConstant: Metrics.logoSize),
      stack.centerXAnchor.constraint(equalTo: centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -8),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    layer?.backgroundColor = Self.backgroundColor(
      for: effectiveAppearance).cgColor
  }

  func apply(appearance: NSAppearance) {
    self.appearance = appearance
    layer?.backgroundColor = Self.backgroundColor(for: appearance).cgColor
  }

  static func preferredAppearance(fallback: NSAppearance) -> NSAppearance {
    switch UserDefaults.standard.string(forKey: "app.theme") {
    case "dark":
      return NSAppearance(named: .darkAqua) ?? fallback
    case "light":
      return NSAppearance(named: .aqua) ?? fallback
    default:
      return fallback
    }
  }

  private static var localizedSubtitle: String {
    let storedLocale = UserDefaults.standard.string(forKey: "app.locale")
    let usesArabic = storedLocale == "ar"
      || (storedLocale == nil && Locale.preferredLanguages.first?.hasPrefix("ar") == true)
    return usesArabic
      ? "ارسم الحركة. واحكِ قصتك."
      : "Draw motion. Tell your story."
  }

  static func backgroundColor(for appearance: NSAppearance) -> NSColor {
    let match = appearance.bestMatch(from: [.darkAqua, .aqua])
    return match == .darkAqua
      ? NSColor(srgbRed: 16 / 255, green: 18 / 255, blue: 23 / 255, alpha: 1)
      : NSColor(srgbRed: 244 / 255, green: 246 / 255, blue: 249 / 255, alpha: 1)
  }
}

private enum VoiceGuideMedia {
  static func resolveURL(arguments: [String: Any]) throws -> URL {
    if
      let encoded = arguments["securityBookmark"] as? String,
      let data = Data(base64Encoded: encoded)
    {
      var stale = false
      return try URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &stale)
    }
    guard let path = arguments["path"] as? String, !path.isEmpty else {
      throw VoiceGuideError.missingPath
    }
    return URL(fileURLWithPath: path)
  }

  static func inspect(arguments: [String: Any]) throws -> [String: Any] {
    let url = try resolveURL(arguments: arguments)
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw VoiceGuideError.fileMissing
    }
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    let totalFrames = max(1, Int(file.length))
    let duration = Double(totalFrames) / format.sampleRate
    let binCount = 320
    var peaks = Array(repeating: Float(0), count: binCount)
    let capacity: AVAudioFrameCount = 4096
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
      throw VoiceGuideError.waveformUnavailable
    }
    var frameCursor = 0
    while frameCursor < totalFrames {
      try file.read(into: buffer, frameCount: capacity)
      let frameLength = Int(buffer.frameLength)
      if frameLength == 0 { break }
      guard let channels = buffer.floatChannelData else {
        throw VoiceGuideError.waveformUnavailable
      }
      let channelCount = Int(format.channelCount)
      for frame in 0..<frameLength {
        var peak: Float = 0
        for channel in 0..<channelCount {
          peak = max(peak, abs(channels[channel][frame]))
        }
        let bin = min(binCount - 1, (frameCursor + frame) * binCount / totalFrames)
        peaks[bin] = max(peaks[bin], peak)
      }
      frameCursor += frameLength
    }
    let maximum = max(peaks.max() ?? 0, 0.0001)
    let normalized = peaks.map { Double(sqrt($0 / maximum)) }
    let bookmark = try url.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil)
    return [
      "path": url.path,
      "name": url.lastPathComponent,
      "durationSeconds": duration,
      "waveform": normalized,
      "securityBookmark": bookmark.base64EncodedString(),
    ]
  }
}

private enum VoiceGuideError: LocalizedError {
  case missingPath
  case fileMissing
  case waveformUnavailable

  var errorDescription: String? {
    switch self {
    case .missingPath: return "The voice guide path is missing."
    case .fileMissing: return "The voice guide file could not be found."
    case .waveformUnavailable: return "The voice guide waveform could not be read."
    }
  }
}

final class ProResStreamingSession {
  private let outputURL: URL
  private let videoURL: URL
  private let width: Int
  private let height: Int
  private let frameRate: Int
  private let frameCount: Int
  private let alphaMode: String
  private let writer: AVAssetWriter
  private let input: AVAssetWriterInput
  private let adaptor: AVAssetWriterInputPixelBufferAdaptor
  private let queue = DispatchQueue(
    label: "com.mahmoudbasuony.handdraw.export.stream",
    qos: .userInitiated)
  private var nextFrameIndex = 0
  private var isClosed = false

  init(
    outputURL: URL,
    width: Int,
    height: Int,
    frameRate: Int,
    frameCount: Int,
    alphaMode: String = "premultiplied",
    expectsAudio: Bool
  ) throws {
    guard width > 0, height > 0, frameRate > 0, frameCount > 0 else {
      throw ExportError.invalidStreamConfiguration
    }
    self.outputURL = outputURL
    self.width = width
    self.height = height
    self.frameRate = frameRate
    self.frameCount = frameCount
    self.alphaMode = alphaMode
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }
    if expectsAudio {
      videoURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "handdraw-stream-video-\(UUID().uuidString).mov")
    } else {
      videoURL = outputURL
    }
    try? FileManager.default.removeItem(at: videoURL)

    writer = try AVAssetWriter(outputURL: videoURL, fileType: .mov)
    let settings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.proRes4444,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoColorPropertiesKey: [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
      ],
    ]
    input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      ])
    guard writer.canAdd(input) else {
      throw ExportError.writerCannotAddInput
    }
    writer.add(input)
    guard writer.startWriting() else {
      throw writer.error ?? ExportError.writerCouldNotStart
    }
    writer.startSession(atSourceTime: .zero)
  }

  func append(
    rgba: Data,
    frameIndex: Int,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    queue.async {
      do {
        guard !self.isClosed else { throw ExportError.streamAlreadyClosed }
        guard frameIndex == self.nextFrameIndex else {
          throw ExportError.unexpectedStreamFrame(
            expected: self.nextFrameIndex,
            actual: frameIndex)
        }
        guard rgba.count == self.width * self.height * 4 else {
          throw ExportError.invalidStreamFrameSize(
            expected: self.width * self.height * 4,
            actual: rgba.count)
        }
        while !self.input.isReadyForMoreMediaData {
          guard self.writer.status == .writing else {
            throw self.writer.error ?? ExportError.writerDidNotComplete
          }
          Thread.sleep(forTimeInterval: 0.001)
        }
        guard let pool = self.adaptor.pixelBufferPool else {
          throw ExportError.pixelBufferPoolUnavailable
        }
        var optionalBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer = optionalBuffer else {
          throw ExportError.pixelBufferCreationFailed(status)
        }
        try self.copyRGBA(rgba, into: pixelBuffer)
        let presentationTime = CMTime(
          value: CMTimeValue(frameIndex),
          timescale: CMTimeScale(self.frameRate))
        guard self.adaptor.append(
          pixelBuffer,
          withPresentationTime: presentationTime)
        else {
          throw self.writer.error ?? ExportError.frameAppendFailed(frameIndex)
        }
        self.nextFrameIndex += 1
        completion(.success(()))
      } catch {
        self.closeAfterFailure()
        completion(.failure(error))
      }
    }
  }

  func finish(
    audioURL: URL?,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    queue.async {
      guard !self.isClosed else {
        completion(.failure(ExportError.streamAlreadyClosed))
        return
      }
      guard self.nextFrameIndex == self.frameCount else {
        self.closeAfterFailure()
        completion(.failure(ExportError.incompleteStream(
          expected: self.frameCount,
          actual: self.nextFrameIndex)))
        return
      }
      self.isClosed = true
      self.input.markAsFinished()
      self.writer.finishWriting {
        guard self.writer.status == .completed else {
          try? FileManager.default.removeItem(at: self.videoURL)
          completion(.failure(
            self.writer.error ?? ExportError.writerDidNotComplete))
          return
        }
        guard let audioURL else {
          completion(.success(self.outputURL.path))
          return
        }
        ProResExporter.muxAudio(
          videoURL: self.videoURL,
          audioURL: audioURL,
          outputURL: self.outputURL
        ) { result in
          try? FileManager.default.removeItem(at: self.videoURL)
          completion(result)
        }
      }
    }
  }

  func cancel() {
    queue.async {
      self.closeAfterFailure()
    }
  }

  private func closeAfterFailure() {
    guard !isClosed else { return }
    isClosed = true
    input.markAsFinished()
    writer.cancelWriting()
    if videoURL != outputURL {
      try? FileManager.default.removeItem(at: videoURL)
    } else {
      try? FileManager.default.removeItem(at: outputURL)
    }
  }

  private func copyRGBA(_ rgba: Data, into pixelBuffer: CVPixelBuffer) throws {
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let destination = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      throw ExportError.graphicsContextUnavailable
    }
    let destinationRowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let error = rgba.withUnsafeBytes { rawBytes -> vImage_Error in
      guard let sourceAddress = rawBytes.baseAddress else {
        return kvImageNullPointerArgument
      }
      var source = vImage_Buffer(
        data: UnsafeMutableRawPointer(mutating: sourceAddress),
        height: vImagePixelCount(height),
        width: vImagePixelCount(width),
        rowBytes: width * 4)
      var target = vImage_Buffer(
        data: destination,
        height: vImagePixelCount(height),
        width: vImagePixelCount(width),
        rowBytes: destinationRowBytes)
      let channelMap: [UInt8] = [2, 1, 0, 3]
      return vImagePermuteChannels_ARGB8888(
        &source,
        &target,
        channelMap,
        vImage_Flags(kvImageNoFlags))
    }
    guard error == kvImageNoError else {
      throw ExportError.pixelConversionFailed(error)
    }
    if alphaMode == "straight" {
      let pixels = destination.assumingMemoryBound(to: UInt8.self)
      for y in 0..<height {
        for x in 0..<width {
          let offset = y * destinationRowBytes + x * 4
          let alpha = Int(pixels[offset + 3])
          if alpha > 0 && alpha < 255 {
            pixels[offset] = UInt8(min(255, Int(pixels[offset]) * 255 / alpha))
            pixels[offset + 1] = UInt8(
              min(255, Int(pixels[offset + 1]) * 255 / alpha))
            pixels[offset + 2] = UInt8(
              min(255, Int(pixels[offset + 2]) * 255 / alpha))
          }
        }
      }
    }
  }
}

enum ProResExporter {
  static let version = 9

  static func encode(
    framesDirectory: URL,
    outputURL: URL,
    width: Int,
    height: Int,
    frameRate: Int,
    frameCount: Int,
    alphaMode: String = "premultiplied",
    audioURL: URL? = nil,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    do {
      if FileManager.default.fileExists(atPath: outputURL.path) {
        try FileManager.default.removeItem(at: outputURL)
      }

      let videoURL: URL
      if audioURL == nil {
        videoURL = outputURL
      } else {
        // Keep every intermediate media file inside the app container. An
        // AVFoundation helper process cannot read a hidden sibling file beside
        // the user-selected destination in a sandboxed/iCloud folder.
        videoURL = FileManager.default.temporaryDirectory.appendingPathComponent(
          "handdraw-video-\(UUID().uuidString).mov")
        if FileManager.default.fileExists(atPath: videoURL.path) {
          try FileManager.default.removeItem(at: videoURL)
        }
      }

      let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mov)
      let settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.proRes4444,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoColorPropertiesKey: [
          AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
          AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
          AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ],
      ]
      let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
      input.expectsMediaDataInRealTime = false

      let attributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      ]
      let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: attributes)

      guard writer.canAdd(input) else {
        throw ExportError.writerCannotAddInput
      }
      writer.add(input)
      guard writer.startWriting() else {
        throw writer.error ?? ExportError.writerCouldNotStart
      }
      writer.startSession(atSourceTime: .zero)

      let queue = DispatchQueue(label: "com.mahmoudbasuony.handdraw.export")
      var frameIndex = 0
      var didFinish = false
      input.requestMediaDataWhenReady(on: queue) {
        guard !didFinish else { return }
        do {
          while input.isReadyForMoreMediaData && frameIndex < frameCount {
            guard let pool = adaptor.pixelBufferPool else {
              throw ExportError.pixelBufferPoolUnavailable
            }
            var optionalBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(
              nil,
              pool,
              &optionalBuffer)
            guard status == kCVReturnSuccess, let pixelBuffer = optionalBuffer else {
              throw ExportError.pixelBufferCreationFailed(status)
            }

            let fileName = String(format: "frame_%06d.png", frameIndex)
            let frameURL = framesDirectory.appendingPathComponent(fileName)
            try drawPNG(
              at: frameURL,
              into: pixelBuffer,
              width: width,
              height: height,
              alphaMode: alphaMode)

            let presentationTime = CMTime(
              value: CMTimeValue(frameIndex),
              timescale: CMTimeScale(frameRate))
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
              throw writer.error ?? ExportError.frameAppendFailed(frameIndex)
            }
            frameIndex += 1
          }

          if frameIndex == frameCount {
            didFinish = true
            input.markAsFinished()
            writer.finishWriting {
              guard writer.status == .completed else {
                completion(.failure(writer.error ?? ExportError.writerDidNotComplete))
                return
              }
              guard let audioURL else {
                completion(.success(outputURL.path))
                return
              }
              muxAudio(
                videoURL: videoURL,
                audioURL: audioURL,
                outputURL: outputURL
              ) { result in
                try? FileManager.default.removeItem(at: videoURL)
                completion(result)
              }
            }
          }
        } catch {
          didFinish = true
          input.markAsFinished()
          writer.cancelWriting()
          completion(.failure(error))
        }
      }
    } catch {
      completion(.failure(error))
    }
  }

  static func muxAudio(
    videoURL: URL,
    audioURL: URL,
    outputURL: URL,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    do {
      let videoAsset = AVURLAsset(url: videoURL)
      let audioAsset = AVURLAsset(url: audioURL)
      guard
        let sourceVideo = videoAsset.tracks(withMediaType: .video).first,
        let sourceAudio = audioAsset.tracks(withMediaType: .audio).first
      else {
        throw ExportError.audioOrVideoTrackMissing
      }
      let composition = AVMutableComposition()
      guard
        let videoTrack = composition.addMutableTrack(
          withMediaType: .video,
          preferredTrackID: kCMPersistentTrackID_Invalid),
        let audioTrack = composition.addMutableTrack(
          withMediaType: .audio,
          preferredTrackID: kCMPersistentTrackID_Invalid)
      else {
        throw ExportError.compositionTrackUnavailable
      }
      let duration = videoAsset.duration
      try videoTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: duration),
        of: sourceVideo,
        at: .zero)
      videoTrack.preferredTransform = sourceVideo.preferredTransform
      try audioTrack.insertTimeRange(
        CMTimeRange(
          start: .zero,
          duration: CMTimeMinimum(duration, audioAsset.duration)),
        of: sourceAudio,
        at: .zero)

      guard let session = AVAssetExportSession(
        asset: composition,
        presetName: AVAssetExportPresetPassthrough)
      else {
        throw ExportError.audioMuxerUnavailable
      }
      // AVAssetExportSession does not inherit the security-scoped permission
      // granted by NSSavePanel reliably for iCloud-backed Desktop folders. Mux
      // into the app's writable temporary directory, then move the completed
      // movie with FileManager, which does retain that permission.
      let muxedURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "handdraw-muxed-\(UUID().uuidString).mov")
      try? FileManager.default.removeItem(at: muxedURL)
      session.outputURL = muxedURL
      session.outputFileType = .mov
      session.shouldOptimizeForNetworkUse = false
      session.exportAsynchronously {
        if session.status == .completed {
          do {
            if FileManager.default.fileExists(atPath: outputURL.path) {
              try FileManager.default.removeItem(at: outputURL)
            }
            // A rename from the app container into an iCloud-backed folder can
            // be rejected by the sandbox even though NSSavePanel granted write
            // access to the destination file. Copying creates that exact file
            // through the granted URL and works across container boundaries.
            try FileManager.default.copyItem(at: muxedURL, to: outputURL)
            try? FileManager.default.removeItem(at: muxedURL)
            completion(.success(outputURL.path))
          } catch {
            try? FileManager.default.removeItem(at: muxedURL)
            completion(.failure(
              ExportError.audioDestinationWriteFailed(error.localizedDescription)))
          }
        } else {
          try? FileManager.default.removeItem(at: muxedURL)
          completion(.failure(
            ExportError.audioMuxSessionFailed(
              session.error?.localizedDescription ?? "Unknown AVFoundation error")))
        }
      }
    } catch {
      completion(.failure(
        ExportError.audioMuxPreparationFailed(error.localizedDescription)))
    }
  }

  private static func drawPNG(
    at url: URL,
    into pixelBuffer: CVPixelBuffer,
    width: Int,
    height: Int,
    alphaMode: String
  ) throws {
    guard
      let image = NSImage(contentsOf: url),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
      throw ExportError.frameCouldNotBeRead(url.lastPathComponent)
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard
      let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
      let context = CGContext(
        data: baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
          | CGImageAlphaInfo.premultipliedFirst.rawValue)
    else {
      throw ExportError.graphicsContextUnavailable
    }

    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .high
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    if alphaMode == "straight" {
      let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
      let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
      for y in 0..<height {
        for x in 0..<width {
          let offset = y * bytesPerRow + x * 4
          let alpha = Int(pixels[offset + 3])
          if alpha > 0 && alpha < 255 {
            pixels[offset] = UInt8(min(255, Int(pixels[offset]) * 255 / alpha))
            pixels[offset + 1] = UInt8(
              min(255, Int(pixels[offset + 1]) * 255 / alpha))
            pixels[offset + 2] = UInt8(
              min(255, Int(pixels[offset + 2]) * 255 / alpha))
          }
        }
      }
    }
  }
}

private enum ExportInspection {
  static func inspect(_ url: URL) throws -> [String: Any] {
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .video).first else {
      throw ExportError.inspectionVideoTrackMissing
    }
    guard let description = track.formatDescriptions.first else {
      throw ExportError.inspectionFormatMissing
    }
    let subtype = CMFormatDescriptionGetMediaSubType(
      description as! CMFormatDescription)
    let codec = fourCC(subtype)
    let transformed = track.naturalSize.applying(track.preferredTransform)
    let angle = atan2(track.preferredTransform.b, track.preferredTransform.a)
      * 180 / .pi
    let audioTrack = asset.tracks(withMediaType: .audio).first
    let audioDuration = audioTrack.map { CMTimeGetSeconds($0.timeRange.duration) }
    return [
      "codec": codec,
      "width": Int(abs(transformed.width).rounded()),
      "height": Int(abs(transformed.height).rounded()),
      "frameRate": Double(track.nominalFrameRate),
      "durationSeconds": CMTimeGetSeconds(asset.duration),
      "hasAlpha": codec == "ap4h" || codec == "ap4x",
      "orientationDegrees": Int(angle.rounded()),
      "hasAudio": audioTrack != nil,
      "audioDurationSeconds": audioDuration ?? 0,
    ]
  }

  private static func fourCC(_ value: FourCharCode) -> String {
    let bytes: [UInt8] = [
      UInt8((value >> 24) & 0xff),
      UInt8((value >> 16) & 0xff),
      UInt8((value >> 8) & 0xff),
      UInt8(value & 0xff),
    ]
    return String(bytes: bytes, encoding: .ascii) ?? "unknown"
  }
}

private enum ExportError: LocalizedError {
  case invalidStreamConfiguration
  case streamAlreadyClosed
  case unexpectedStreamFrame(expected: Int, actual: Int)
  case invalidStreamFrameSize(expected: Int, actual: Int)
  case incompleteStream(expected: Int, actual: Int)
  case pixelConversionFailed(vImage_Error)
  case writerCannotAddInput
  case writerCouldNotStart
  case pixelBufferPoolUnavailable
  case pixelBufferCreationFailed(CVReturn)
  case frameAppendFailed(Int)
  case frameCouldNotBeRead(String)
  case graphicsContextUnavailable
  case writerDidNotComplete
  case audioOrVideoTrackMissing
  case compositionTrackUnavailable
  case audioMuxerUnavailable
  case audioMuxFailed
  case audioMuxPreparationFailed(String)
  case audioMuxSessionFailed(String)
  case audioDestinationWriteFailed(String)
  case inspectionVideoTrackMissing
  case inspectionFormatMissing

  var errorDescription: String? {
    switch self {
    case .invalidStreamConfiguration:
      return "The streaming video settings are invalid."
    case .streamAlreadyClosed:
      return "The streaming video encoder is already closed."
    case .unexpectedStreamFrame(let expected, let actual):
      return "Expected video frame \(expected), but received frame \(actual)."
    case .invalidStreamFrameSize(let expected, let actual):
      return "The video frame contains \(actual) bytes instead of \(expected)."
    case .incompleteStream(let expected, let actual):
      return "The video stream ended after \(actual) of \(expected) frames."
    case .pixelConversionFailed(let status):
      return "The video frame color conversion failed (\(status))."
    case .writerCannotAddInput:
      return "The ProRes writer could not add its video input."
    case .writerCouldNotStart:
      return "The ProRes writer could not start."
    case .pixelBufferPoolUnavailable:
      return "The video pixel buffer pool is unavailable."
    case .pixelBufferCreationFailed(let status):
      return "A video frame buffer could not be created (\(status))."
    case .frameAppendFailed(let index):
      return "Frame \(index) could not be added to the movie."
    case .frameCouldNotBeRead(let name):
      return "The rendered frame \(name) could not be read."
    case .graphicsContextUnavailable:
      return "The graphics context for video encoding is unavailable."
    case .writerDidNotComplete:
      return "The ProRes writer did not complete the movie."
    case .audioOrVideoTrackMissing:
      return "The generated writing sound or video track could not be read."
    case .compositionTrackUnavailable:
      return "The movie could not create synchronized audio and video tracks."
    case .audioMuxerUnavailable:
      return "The QuickTime audio muxer is unavailable."
    case .audioMuxFailed:
      return "The writing sound could not be added to the movie."
    case .audioMuxPreparationFailed(let message):
      return "Writing audio preparation failed: \(message)"
    case .audioMuxSessionFailed(let message):
      return "Writing audio mux failed: \(message)"
    case .audioDestinationWriteFailed(let message):
      return "The completed movie could not be written to its destination: \(message)"
    case .inspectionVideoTrackMissing:
      return "The exported movie has no video track."
    case .inspectionFormatMissing:
      return "The exported movie format could not be inspected."
    }
  }
}
