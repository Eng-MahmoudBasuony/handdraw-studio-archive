import AppKit
import FlutterMacOS
import Vision

public class HandDrawSmartPathPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "handdraw_studio/smart_path",
      binaryMessenger: registrar.messenger)
    let instance = HandDrawSmartPathPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "detectText" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let typedData = arguments["image"] as? FlutterStandardTypedData,
      let image = NSImage(data: typedData.data),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
      result(FlutterError(
        code: "invalid_image",
        message: "The drawing image could not be decoded.",
        details: nil))
      return
    }

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.006
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        let observations = request.results ?? []
        let payload = observations.compactMap { observation -> [String: Any]? in
          guard let candidate = observation.topCandidates(1).first else { return nil }
          let box = Self.topLeftRect(observation.boundingBox)
          var characters: [[String: Any]] = []
          for index in candidate.string.indices {
            let next = candidate.string.index(after: index)
            guard let characterBox = try? candidate.boundingBox(for: index..<next) else {
              continue
            }
            let character = String(candidate.string[index..<next])
            characters.append([
              "value": character,
              "bounds": Self.rectList(Self.topLeftRect(characterBox.boundingBox)),
            ])
          }
          return [
            "text": candidate.string,
            "confidence": Double(candidate.confidence),
            "bounds": Self.rectList(box),
            "characters": characters,
          ]
        }
        DispatchQueue.main.async { result(payload) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "vision_failed",
            message: error.localizedDescription,
            details: nil))
        }
      }
    }
  }

  private static func topLeftRect(_ rect: CGRect) -> CGRect {
    CGRect(
      x: rect.minX,
      y: 1.0 - rect.maxY,
      width: rect.width,
      height: rect.height)
  }

  private static func rectList(_ rect: CGRect) -> [Double] {
    [Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)]
  }
}
