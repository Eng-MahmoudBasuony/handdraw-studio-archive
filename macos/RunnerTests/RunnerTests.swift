import Cocoa
import AVFoundation
import FlutterMacOS
import XCTest
@testable import HandDraw_Studio

class RunnerTests: XCTestCase {

  func testLaunchSplashFadeNeverAddsAVisibleStartupPause() {
    XCTAssertLessThanOrEqual(LaunchSplashTiming.fadeDuration, 0.12)
  }

  func testExporterVersionRejectsStaleNativeBuilds() {
    XCTAssertGreaterThanOrEqual(ProResExporter.version, 7)
  }

  func testProRes4444ExporterIncludesSynchronizedWritingAudio() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("handdraw-audio-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for index in 0..<2 {
      let image = NSImage(size: NSSize(width: 64, height: 64))
      image.lockFocus()
      NSColor.clear.setFill()
      NSRect(x: 0, y: 0, width: 64, height: 64).fill(using: .copy)
      NSColor.systemOrange.setFill()
      NSRect(x: 8 + index * 4, y: 24, width: 28, height: 8).fill()
      image.unlockFocus()
      let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
      let png = representation.representation(using: .png, properties: [:])!
      try png.write(
        to: directory.appendingPathComponent(
          String(format: "frame_%06d.png", index)))
    }

    let audioURL = directory.appendingPathComponent("writing.wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    var audioFile: AVAudioFile? = try AVAudioFile(
      forWriting: audioURL,
      settings: format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3_200)!
    buffer.frameLength = 3_200
    if let channel = buffer.floatChannelData?[0] {
      for index in 0..<Int(buffer.frameLength) {
        channel[index] = sin(Float(index) * 0.08) * 0.15
      }
    }
    try audioFile?.write(from: buffer)
    audioFile = nil

    let movieURL = directory.appendingPathComponent("with-audio.mov")
    let exportExpectation = expectation(description: "ProRes export with audio")
    var receivedError: Error?
    ProResExporter.encode(
      framesDirectory: directory,
      outputURL: movieURL,
      width: 64,
      height: 64,
      frameRate: 30,
      frameCount: 2,
      audioURL: audioURL
    ) { result in
      if case .failure(let error) = result {
        receivedError = error
      }
      exportExpectation.fulfill()
    }

    wait(for: [exportExpectation], timeout: 15)
    XCTAssertNil(receivedError)
    let asset = AVURLAsset(url: movieURL)
    XCTAssertEqual(asset.tracks(withMediaType: .video).count, 1)
    XCTAssertEqual(asset.tracks(withMediaType: .audio).count, 1)
  }

  func testProRes4444ExporterCreatesMovie() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("handdraw-native-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for index in 0..<2 {
      let image = NSImage(size: NSSize(width: 64, height: 64))
      image.lockFocus()
      NSColor.clear.setFill()
      NSRect(x: 0, y: 0, width: 64, height: 64).fill(using: .copy)
      NSColor.systemBlue.withAlphaComponent(0.8).setFill()
      NSBezierPath(
        ovalIn: NSRect(x: 8 + index * 8, y: 16, width: 30, height: 30)
      ).fill()
      image.unlockFocus()

      guard
        let tiff = image.tiffRepresentation,
        let representation = NSBitmapImageRep(data: tiff),
        let png = representation.representation(using: .png, properties: [:])
      else {
        XCTFail("Could not create the PNG test frame.")
        return
      }
      let name = String(format: "frame_%06d.png", index)
      try png.write(to: directory.appendingPathComponent(name))
    }

    let movieURL = directory.appendingPathComponent("result.mov")
    let expectation = expectation(description: "ProRes export")
    var receivedError: Error?
    ProResExporter.encode(
      framesDirectory: directory,
      outputURL: movieURL,
      width: 64,
      height: 64,
      frameRate: 30,
      frameCount: 2
    ) { result in
      if case .failure(let error) = result {
        receivedError = error
      }
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 15)
    XCTAssertNil(receivedError)
    XCTAssertTrue(FileManager.default.fileExists(atPath: movieURL.path))
    let attributes = try FileManager.default.attributesOfItem(atPath: movieURL.path)
    XCTAssertGreaterThan(attributes[.size] as? UInt64 ?? 0, 0)
  }

  func testStreamingProResExporterAcceptsRawRGBAFrames() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("handdraw-stream-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let movieURL = directory.appendingPathComponent("stream.mov")
    let session = try ProResStreamingSession(
      outputURL: movieURL,
      width: 64,
      height: 64,
      frameRate: 30,
      frameCount: 2,
      alphaMode: "premultiplied",
      expectsAudio: false)

    for frameIndex in 0..<2 {
      var rgba = Data(count: 64 * 64 * 4)
      rgba.withUnsafeMutableBytes { rawBytes in
        let pixels = rawBytes.bindMemory(to: UInt8.self)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
          pixels[offset] = frameIndex == 0 ? 255 : 0
          pixels[offset + 1] = 0
          pixels[offset + 2] = frameIndex == 0 ? 0 : 255
          pixels[offset + 3] = 255
        }
      }
      let appendExpectation = expectation(
        description: "Append raw frame \(frameIndex)")
      var appendError: Error?
      session.append(rgba: rgba, frameIndex: frameIndex) { result in
        if case .failure(let error) = result { appendError = error }
        appendExpectation.fulfill()
      }
      wait(for: [appendExpectation], timeout: 15)
      XCTAssertNil(appendError)
    }

    let finishExpectation = expectation(description: "Finish raw stream")
    var finishError: Error?
    session.finish(audioURL: nil) { result in
      if case .failure(let error) = result { finishError = error }
      finishExpectation.fulfill()
    }
    wait(for: [finishExpectation], timeout: 15)
    XCTAssertNil(finishError)
    XCTAssertTrue(FileManager.default.fileExists(atPath: movieURL.path))

    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movieURL))
    let firstFrame = try generator.copyCGImage(at: .zero, actualTime: nil)
    let bitmap = NSBitmapImageRep(cgImage: firstFrame)
    let color = try XCTUnwrap(bitmap.colorAt(x: 32, y: 32))
      .usingColorSpace(.deviceRGB)!
    XCTAssertGreaterThan(color.redComponent, color.blueComponent)
  }

  func testProRes4444ExporterPreservesVerticalOrientation() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("handdraw-orientation-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fixtureURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/flutter_orientation.png")
    guard
      let png = try? Data(contentsOf: fixtureURL),
      let sourceBitmap = NSBitmapImageRep(data: png)
    else {
      XCTFail("Could not load the Flutter-style orientation fixture.")
      return
    }
    try png.write(to: directory.appendingPathComponent("frame_000000.png"))
    guard
      let sourceTop = sourceBitmap.colorAt(
        x: sourceBitmap.pixelsWide / 2,
        y: sourceBitmap.pixelsHigh / 8),
      let sourceBottom = sourceBitmap.colorAt(
        x: sourceBitmap.pixelsWide / 2,
        y: sourceBitmap.pixelsHigh * 7 / 8)
    else {
      XCTFail("Could not sample the source orientation frame.")
      return
    }

    let movieURL = directory.appendingPathComponent("orientation.mov")
    let exportExpectation = expectation(description: "Orientation export")
    var receivedError: Error?
    ProResExporter.encode(
      framesDirectory: directory,
      outputURL: movieURL,
      width: 64,
      height: 64,
      frameRate: 30,
      frameCount: 1
    ) { result in
      if case .failure(let error) = result {
        receivedError = error
      }
      exportExpectation.fulfill()
    }
    wait(for: [exportExpectation], timeout: 15)
    XCTAssertNil(receivedError)

    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movieURL))
    generator.appliesPreferredTrackTransform = true
    let movieFrame = try generator.copyCGImage(at: .zero, actualTime: nil)
    let decoded = NSBitmapImageRep(cgImage: movieFrame)
    guard
      let movieTop = decoded.colorAt(x: 32, y: 8),
      let movieBottom = decoded.colorAt(x: 32, y: 56)
    else {
      XCTFail("Could not sample the exported orientation frame.")
      return
    }

    XCTAssertGreaterThan(sourceTop.redComponent, sourceTop.blueComponent)
    XCTAssertGreaterThan(sourceBottom.blueComponent, sourceBottom.redComponent)
    XCTAssertLessThan(
      colorDistance(movieTop, sourceTop),
      colorDistance(movieTop, sourceBottom),
      "The top of the ProRes frame was vertically flipped: \(movieTop)")
    XCTAssertLessThan(
      colorDistance(movieBottom, sourceBottom),
      colorDistance(movieBottom, sourceTop),
      "The bottom of the ProRes frame was vertically flipped: \(movieBottom)")
  }

  private func colorDistance(_ first: NSColor, _ second: NSColor) -> CGFloat {
    let a = first.usingColorSpace(.deviceRGB) ?? first
    let b = second.usingColorSpace(.deviceRGB) ?? second
    return abs(a.redComponent - b.redComponent)
      + abs(a.greenComponent - b.greenComponent)
      + abs(a.blueComponent - b.blueComponent)
  }

}
