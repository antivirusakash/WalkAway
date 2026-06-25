#!/usr/bin/env swift

import AppKit
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesURL = rootURL.appendingPathComponent("Resources", isDirectory: true)
let iconsetURL = resourcesURL.appendingPathComponent("WalkAway.iconset", isDirectory: true)
let previewURL = resourcesURL.appendingPathComponent("WalkAway-icon-preview.png")
let statusIconURL = resourcesURL.appendingPathComponent("WalkAwayStatusIcon.png")
let statusIcon2xURL = resourcesURL.appendingPathComponent("WalkAwayStatusIcon@2x.png")
let statusIcon3xURL = resourcesURL.appendingPathComponent("WalkAwayStatusIcon@3x.png")

try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

struct IconSize {
  let filename: String
  let pixels: Int
}

let sizes: [IconSize] = [
  .init(filename: "icon_16x16.png", pixels: 16),
  .init(filename: "icon_16x16@2x.png", pixels: 32),
  .init(filename: "icon_32x32.png", pixels: 32),
  .init(filename: "icon_32x32@2x.png", pixels: 64),
  .init(filename: "icon_128x128.png", pixels: 128),
  .init(filename: "icon_128x128@2x.png", pixels: 256),
  .init(filename: "icon_256x256.png", pixels: 256),
  .init(filename: "icon_256x256@2x.png", pixels: 512),
  .init(filename: "icon_512x512.png", pixels: 512),
  .init(filename: "icon_512x512@2x.png", pixels: 1024)
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
  NSColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha).cgColor
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
  CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawIcon(into context: CGContext, pixelSize: Int) {
  let scale = CGFloat(pixelSize) / 1024

  context.saveGState()
  context.scaleBy(x: scale, y: scale)
  context.setShouldAntialias(true)
  context.setAllowsAntialiasing(true)
  context.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))

  let iconRect = CGRect(x: 72, y: 72, width: 880, height: 880)
  let iconPath = roundedRect(iconRect, radius: 210)

  context.saveGState()
  context.setShadow(offset: CGSize(width: 0, height: -22), blur: 46, color: color(0, 0, 0, 0.24))
  context.addPath(iconPath)
  context.clip()

  let bgColors = [
    color(18, 47, 63),
    color(22, 109, 123),
    color(106, 193, 172)
  ] as CFArray
  let bgStops: [CGFloat] = [0, 0.55, 1]
  let bgGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: bgColors,
    locations: bgStops
  )!
  context.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 140, y: 910),
    end: CGPoint(x: 880, y: 100),
    options: []
  )

  context.setFillColor(color(255, 255, 255, 0.12))
  context.fillEllipse(in: CGRect(x: 148, y: 660, width: 520, height: 300))
  context.setFillColor(color(0, 0, 0, 0.12))
  context.fillEllipse(in: CGRect(x: 455, y: 68, width: 450, height: 260))
  context.restoreGState()

  context.addPath(iconPath)
  context.setStrokeColor(color(255, 255, 255, 0.24))
  context.setLineWidth(5)
  context.strokePath()

  let strapPath = CGMutablePath()
  strapPath.addPath(roundedRect(CGRect(x: 418, y: 104, width: 188, height: 286), radius: 60))
  strapPath.addPath(roundedRect(CGRect(x: 418, y: 634, width: 188, height: 286), radius: 60))
  context.setFillColor(color(22, 28, 36))
  context.addPath(strapPath)
  context.fillPath()

  let strapHighlight = CGMutablePath()
  strapHighlight.addPath(roundedRect(CGRect(x: 455, y: 126, width: 42, height: 242), radius: 21))
  strapHighlight.addPath(roundedRect(CGRect(x: 455, y: 656, width: 42, height: 242), radius: 21))
  context.setFillColor(color(255, 255, 255, 0.10))
  context.addPath(strapHighlight)
  context.fillPath()

  let caseRect = CGRect(x: 276, y: 290, width: 472, height: 444)
  let casePath = roundedRect(caseRect, radius: 110)
  context.saveGState()
  context.setShadow(offset: CGSize(width: 0, height: -16), blur: 24, color: color(0, 0, 0, 0.35))
  context.addPath(casePath)
  context.setFillColor(color(31, 37, 45))
  context.fillPath()
  context.restoreGState()

  context.addPath(casePath)
  context.setStrokeColor(color(235, 245, 244, 0.34))
  context.setLineWidth(14)
  context.strokePath()

  let screenRect = CGRect(x: 324, y: 338, width: 376, height: 348)
  let screenPath = roundedRect(screenRect, radius: 78)
  context.saveGState()
  context.addPath(screenPath)
  context.clip()

  let screenGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
      color(17, 24, 39),
      color(11, 105, 119),
      color(33, 186, 163)
    ] as CFArray,
    locations: [0, 0.6, 1]
  )!
  context.drawLinearGradient(
    screenGradient,
    start: CGPoint(x: 340, y: 690),
    end: CGPoint(x: 690, y: 330),
    options: []
  )

  context.setFillColor(color(255, 255, 255, 0.13))
  context.fillEllipse(in: CGRect(x: 348, y: 574, width: 220, height: 92))
  context.restoreGState()

  context.addPath(screenPath)
  context.setStrokeColor(color(255, 255, 255, 0.15))
  context.setLineWidth(6)
  context.strokePath()

  let crownRect = CGRect(x: 735, y: 470, width: 34, height: 92)
  context.addPath(roundedRect(crownRect, radius: 17))
  context.setFillColor(color(235, 245, 244, 0.70))
  context.fillPath()

  let lockBody = CGRect(x: 386, y: 394, width: 252, height: 188)
  context.saveGState()
  context.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0, 0, 0, 0.28))
  context.addPath(roundedRect(lockBody, radius: 44))
  context.setFillColor(color(246, 250, 247))
  context.fillPath()
  context.restoreGState()

  let shackle = CGMutablePath()
  shackle.move(to: CGPoint(x: 430, y: 544))
  shackle.addCurve(
    to: CGPoint(x: 594, y: 544),
    control1: CGPoint(x: 430, y: 664),
    control2: CGPoint(x: 594, y: 664)
  )
  context.addPath(shackle)
  context.setStrokeColor(color(246, 250, 247))
  context.setLineWidth(44)
  context.setLineCap(.round)
  context.strokePath()

  context.addPath(shackle)
  context.setStrokeColor(color(36, 157, 145))
  context.setLineWidth(18)
  context.strokePath()

  context.addPath(roundedRect(lockBody.insetBy(dx: 0, dy: 0), radius: 44))
  let lockGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(255, 255, 255), color(218, 237, 229)] as CFArray,
    locations: [0, 1]
  )!
  context.clip()
  context.drawLinearGradient(
    lockGradient,
    start: CGPoint(x: 386, y: 582),
    end: CGPoint(x: 638, y: 394),
    options: []
  )

  context.resetClip()
  context.setFillColor(color(31, 54, 61))
  context.fillEllipse(in: CGRect(x: 487, y: 468, width: 50, height: 50))
  context.addPath(roundedRect(CGRect(x: 502, y: 436, width: 20, height: 54), radius: 10))
  context.fillPath()

  context.restoreGState()
}

func drawStatusIcon(into context: CGContext, pixelSize: Int) {
  let scale = CGFloat(pixelSize) / 64

  context.saveGState()
  context.scaleBy(x: scale, y: scale)
  context.setShouldAntialias(true)
  context.setAllowsAntialiasing(true)
  context.clear(CGRect(x: 0, y: 0, width: 64, height: 64))

  context.setFillColor(NSColor.black.cgColor)
  context.addPath(roundedRect(CGRect(x: 25, y: 4, width: 14, height: 17), radius: 5))
  context.fillPath()
  context.addPath(roundedRect(CGRect(x: 25, y: 43, width: 14, height: 17), radius: 5))
  context.fillPath()

  context.addPath(roundedRect(CGRect(x: 15, y: 18, width: 34, height: 31), radius: 8))
  context.fillPath()

  context.setBlendMode(.clear)
  context.addPath(roundedRect(CGRect(x: 20, y: 23, width: 24, height: 21), radius: 5))
  context.fillPath()

  context.setBlendMode(.normal)
  context.setFillColor(NSColor.black.cgColor)
  context.addPath(roundedRect(CGRect(x: 21, y: 19, width: 22, height: 16), radius: 4))
  context.fillPath()

  let shackle = CGMutablePath()
  shackle.move(to: CGPoint(x: 25, y: 32))
  shackle.addCurve(
    to: CGPoint(x: 39, y: 32),
    control1: CGPoint(x: 25, y: 43),
    control2: CGPoint(x: 39, y: 43)
  )
  context.addPath(shackle)
  context.setStrokeColor(NSColor.black.cgColor)
  context.setLineWidth(4)
  context.setLineCap(.round)
  context.strokePath()

  context.setBlendMode(.clear)
  context.fillEllipse(in: CGRect(x: 29, y: 25, width: 6, height: 6))
  context.addPath(roundedRect(CGRect(x: 31, y: 22, width: 2, height: 6), radius: 1))
  context.fillPath()

  context.restoreGState()
}

func writePNG(pixelSize: Int, to url: URL, draw: (CGContext, Int) -> Void = drawIcon) throws {
  guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelSize,
    pixelsHigh: pixelSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ) else {
    throw NSError(domain: "WalkAwayIcon", code: 1)
  }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  draw(NSGraphicsContext.current!.cgContext, pixelSize)
  NSGraphicsContext.restoreGraphicsState()

  guard let data = rep.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "WalkAwayIcon", code: 2)
  }
  try data.write(to: url)
}

for size in sizes {
  try writePNG(pixelSize: size.pixels, to: iconsetURL.appendingPathComponent(size.filename))
}
try writePNG(pixelSize: 1024, to: previewURL)
try writePNG(pixelSize: 18, to: statusIconURL, draw: drawStatusIcon)
try writePNG(pixelSize: 36, to: statusIcon2xURL, draw: drawStatusIcon)
try writePNG(pixelSize: 54, to: statusIcon3xURL, draw: drawStatusIcon)
