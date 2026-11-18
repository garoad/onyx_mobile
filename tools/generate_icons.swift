#!/usr/bin/env swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let files = FileManager.default

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
  CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, 1])!
}
let background = color(17 / 255, 18 / 255, 20 / 255)
let copper = color(237 / 255, 136 / 255, 88 / 255)

func render(_ size: Int, _ path: String, launch: Bool = false) throws {
  let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  let side = CGFloat(size)
  context.setFillColor(background); context.fill(CGRect(x: 0, y: 0, width: side, height: side))
  if !launch {
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(29 / 255, 32 / 255, 38 / 255), background] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: side, y: side), end: .zero, options: [])
  }
  context.setStrokeColor(copper); context.setLineWidth(side * 0.032); context.setLineJoin(.round); context.setLineCap(.round)
  let hex = CGMutablePath(), radius = side * 0.315
  for index in 0..<6 {
    let angle = CGFloat(index) * .pi / 3 - .pi / 2
    let point = CGPoint(x: side / 2 + cos(angle) * radius, y: side / 2 + sin(angle) * radius)
    if index == 0 { hex.move(to: point) } else { hex.addLine(to: point) }
  }
  hex.closeSubpath(); context.addPath(hex); context.strokePath()
  let wave = CGMutablePath()
  for index in 0...100 {
    let x = CGFloat(index) / 100
    let point = CGPoint(x: side * (0.30 + x * 0.40), y: side * (0.50 + sin(x * .pi * 4) * sin(x * .pi) * 0.095))
    if index == 0 { wave.move(to: point) } else { wave.addLine(to: point) }
  }
  context.setLineWidth(side * 0.028); context.addPath(wave); context.strokePath()
  let target = root.appendingPathComponent(path)
  try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
  let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, context.makeImage()!, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("Could not save \(path)") }
}

let iconDirectory = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
let contents = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(iconDirectory + "/Contents.json"))) as! [String: Any]
for entry in contents["images"] as! [[String: Any]] {
  guard let filename = entry["filename"] as? String, let dimensions = entry["size"] as? String, let scale = entry["scale"] as? String else { continue }
  let size = Double(dimensions.components(separatedBy: "x")[0])! * Double(scale.replacingOccurrences(of: "x", with: ""))!
  try render(Int(size.rounded()), iconDirectory + "/" + filename)
}
for (density, size) in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)] {
  try render(size, "android/app/src/main/res/mipmap-\(density)/ic_launcher.png")
}
for (scale, suffix) in [(1, ""), (2, "@2x"), (3, "@3x")] {
  try render(168 * scale, "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage\(suffix).png", launch: true)
}
try render(1024, "assets/app-icon.png")

func svgPath(_ hex: Bool) -> String {
  var result = ""
  for index in 0...(hex ? 5 : 100) {
    let t = Double(index) / 100
    let angle = Double(index) * .pi / 3 - .pi / 2
    let x = hex ? 54 + cos(angle) * 34.02 : 108 * (0.30 + t * 0.40)
    let y = hex ? 54 + sin(angle) * 34.02 : 108 * (0.50 + sin(t * .pi * 4) * sin(t * .pi) * 0.095)
    result += String(format: "%@%.3f,%.3f ", index == 0 ? "M" : "L", x, y)
  }
  return result + (hex ? "Z" : "")
}
for (filename, stroke) in [("ic_launcher_foreground.xml", "#ED8858"), ("ic_launcher_monochrome.xml", "#FFFFFF")] {
  let xml = """
  <?xml version="1.0" encoding="utf-8"?>
  <vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">
    <path android:pathData="\(svgPath(true))" android:strokeColor="\(stroke)" android:fillColor="#00000000" android:strokeWidth="3.456" android:strokeLineJoin="round" />
    <path android:pathData="\(svgPath(false))" android:strokeColor="\(stroke)" android:fillColor="#00000000" android:strokeWidth="3.024" android:strokeLineCap="round" android:strokeLineJoin="round" />
  </vector>
  """
  try xml.write(to: root.appendingPathComponent("android/app/src/main/res/drawable/" + filename), atomically: true, encoding: .utf8)
}
print("Generated opaque iOS icons, Android icons and launch images.")
