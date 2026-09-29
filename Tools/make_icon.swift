#!/usr/bin/env swift

// Generates LookNice's app icon at every size macOS asks for.
//
//   swift Tools/make_icon.swift
//
// Writes PNGs into Sources/LookNice/Assets.xcassets/AppIcon.appiconset/.
// The mark is 👀 — a pair of eyes — so it reads the same as the emoji used
// everywhere else for this project. Kept in the repo so the icon stays
// editable: tweak the constants and re-run rather than editing bitmaps.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Design constants (all as a fraction of the icon's edge)

let cornerRadiusRatio: CGFloat = 0.2237   // Apple's rounded-rect proportion

let eyeOffsetX: CGFloat  = 0.176          // each eye's centre, from the middle
let eyeHalfW: CGFloat    = 0.156
let eyeHalfH: CGFloat    = 0.188
let irisRadius: CGFloat  = 0.077
let irisShiftX: CGFloat  = -0.020         // both pupils drift left, as 👀 does
let glintRadius: CGFloat = 0.024

let backgroundTop    = CGColor(red: 0.180, green: 0.196, blue: 0.235, alpha: 1)
let backgroundBottom = CGColor(red: 0.051, green: 0.059, blue: 0.082, alpha: 1)
let scleraColor      = CGColor(red: 0.988, green: 0.992, blue: 0.996, alpha: 1)
let irisColor        = CGColor(red: 0.075, green: 0.149, blue: 0.196, alpha: 1)
let glintColor       = CGColor(red: 1, green: 1, blue: 1, alpha: 0.95)

// MARK: - Drawing

func drawIcon(size S: CGFloat) -> CGImage? {
    let px = Int(S)
    guard let ctx = CGContext(
        data: nil, width: px, height: px,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    // Rounded-rect ground. macOS does not mask app icons, so the shape is art.
    let rect = CGRect(x: 0, y: 0, width: S, height: S)
    ctx.saveGState()
    ctx.addPath(CGPath(
        roundedRect: rect,
        cornerWidth: S * cornerRadiusRatio,
        cornerHeight: S * cornerRadiusRatio,
        transform: nil
    ))
    ctx.clip()
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [backgroundTop, backgroundBottom] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: S),
            end: CGPoint(x: 0, y: 0),
            options: []
        )
    }
    ctx.restoreGState()

    // A pair of eyes, drawn as simply as possible so they survive 16pt.
    let cy = S * 0.5
    for sign in [CGFloat(-1), CGFloat(1)] {
        let cx = S * 0.5 + sign * S * eyeOffsetX

        ctx.setFillColor(scleraColor)
        ctx.fillEllipse(in: CGRect(
            x: cx - S * eyeHalfW, y: cy - S * eyeHalfH,
            width: S * eyeHalfW * 2, height: S * eyeHalfH * 2
        ))

        let ix = cx + S * irisShiftX
        ctx.setFillColor(irisColor)
        ctx.fillEllipse(in: CGRect(
            x: ix - S * irisRadius, y: cy - S * irisRadius,
            width: S * irisRadius * 2, height: S * irisRadius * 2
        ))

        // Skip the catchlight on the smallest sizes — it just turns to mush.
        if S >= 64 {
            ctx.setFillColor(glintColor)
            ctx.fillEllipse(in: CGRect(
                x: ix - S * irisRadius * 0.40 - S * glintRadius,
                y: cy + S * irisRadius * 0.34 - S * glintRadius,
                width: S * glintRadius * 2, height: S * glintRadius * 2
            ))
        }
    }

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
    .appendingPathComponent("Sources/LookNice/Assets.xcassets/AppIcon.appiconset")
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
