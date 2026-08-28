#!/usr/bin/env swift

// Generates Narcissus's app icon at every size macOS asks for.
//
//   swift Tools/make_icon.swift
//
// Writes PNGs into Sources/NarcissusEyes/Assets.xcassets/AppIcon.appiconset/.
// Kept in the repo so the icon stays editable — tweak the constants below and
// re-run rather than hand-editing exported bitmaps.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Design constants

let cornerRadiusRatio: CGFloat = 0.2237  // Apple's rounded-rect proportion
let eyeHalfWidthRatio: CGFloat = 0.320
let eyeCurveRatio: CGFloat = 0.300       // how open the eye is
let irisRadiusRatio: CGFloat = 0.150
let pupilRadiusRatio: CGFloat = 0.068
let highlightRadiusRatio: CGFloat = 0.042

let backgroundTop = CGColor(red: 0.180, green: 0.196, blue: 0.235, alpha: 1)
let backgroundBottom = CGColor(red: 0.055, green: 0.063, blue: 0.086, alpha: 1)
let scleraColor = CGColor(red: 0.949, green: 0.961, blue: 0.980, alpha: 1)
let irisColor = CGColor(red: 0.180, green: 0.435, blue: 0.557, alpha: 1)
let irisRimColor = CGColor(red: 0.098, green: 0.255, blue: 0.345, alpha: 1)
let pupilColor = CGColor(red: 0.035, green: 0.047, blue: 0.067, alpha: 1)
let highlightColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.92)

// MARK: - Drawing

func drawIcon(size: CGFloat) -> CGImage? {
    let pixels = Int(size)
    guard let ctx = CGContext(
        data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    // Rounded-rect background with a vertical gradient. macOS does not mask app
    // icons, so the shape has to be part of the artwork.
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let bgPath = CGPath(
        roundedRect: rect,
        cornerWidth: size * cornerRadiusRatio,
        cornerHeight: size * cornerRadiusRatio,
        transform: nil
    )
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [backgroundTop, backgroundBottom] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: size),
            end: CGPoint(x: 0, y: 0),
            options: []
        )
    }
    ctx.restoreGState()

    // Almond eye: two quadratic curves meeting at the inner and outer corners.
    let center = CGPoint(x: size / 2, y: size / 2)
    let halfWidth = size * eyeHalfWidthRatio
    let curve = size * eyeCurveRatio
    let left = CGPoint(x: center.x - halfWidth, y: center.y)
    let right = CGPoint(x: center.x + halfWidth, y: center.y)

    let eyePath = CGMutablePath()
    eyePath.move(to: left)
    eyePath.addQuadCurve(to: right, control: CGPoint(x: center.x, y: center.y + curve))
    eyePath.addQuadCurve(to: left, control: CGPoint(x: center.x, y: center.y - curve))
    eyePath.closeSubpath()

    ctx.saveGState()
    ctx.addPath(eyePath)
    ctx.setFillColor(scleraColor)
    ctx.fillPath()

    // Iris and pupil are clipped to the eye so they never spill past the lids.
    ctx.addPath(eyePath)
    ctx.clip()

    let irisRadius = size * irisRadiusRatio
    ctx.setFillColor(irisColor)
    ctx.fillEllipse(in: CGRect(
        x: center.x - irisRadius, y: center.y - irisRadius,
        width: irisRadius * 2, height: irisRadius * 2
    ))

    ctx.setStrokeColor(irisRimColor)
    ctx.setLineWidth(max(size * 0.012, 1))
    ctx.strokeEllipse(in: CGRect(
        x: center.x - irisRadius, y: center.y - irisRadius,
        width: irisRadius * 2, height: irisRadius * 2
    ))

    let pupilRadius = size * pupilRadiusRatio
    ctx.setFillColor(pupilColor)
    ctx.fillEllipse(in: CGRect(
        x: center.x - pupilRadius, y: center.y - pupilRadius,
        width: pupilRadius * 2, height: pupilRadius * 2
    ))

    let highlightRadius = size * highlightRadiusRatio
    let highlightCenter = CGPoint(
        x: center.x - irisRadius * 0.42,
        y: center.y + irisRadius * 0.42
    )
    ctx.setFillColor(highlightColor)
    ctx.fillEllipse(in: CGRect(
        x: highlightCenter.x - highlightRadius, y: highlightCenter.y - highlightRadius,
        width: highlightRadius * 2, height: highlightRadius * 2
    ))
    ctx.restoreGState()

    // Crisp lid outline so the shape holds together at 16pt.
    ctx.addPath(eyePath)
    ctx.setStrokeColor(CGColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 0.55))
    ctx.setLineWidth(max(size * 0.008, 0.75))
    ctx.strokePath()

    return ctx.makeImage()
}

func write(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make_icon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
    try data.write(to: url)
}

// MARK: - Emit every size the asset catalog declares

// (pixel size, filename)
let outputs: [(CGFloat, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outDir = root
    .appendingPathComponent("Sources/NarcissusEyes/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for (size, name) in outputs {
    guard let image = drawIcon(size: size) else {
        FileHandle.standardError.write("Failed to render \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    try write(image, to: outDir.appendingPathComponent(name))
    print("wrote \(name) (\(Int(size))px)")
}

print("Icon set written to \(outDir.path)")
