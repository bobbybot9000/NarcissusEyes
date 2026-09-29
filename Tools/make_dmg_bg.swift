#!/usr/bin/env swift

// Draws the background for the install window you see when the DMG is opened.
//
//   swift Tools/make_dmg_bg.swift
//
// Writes build/dmg-bg.png at 600x400 — the DMG window's content size, set to
// match in make_dmg.sh. The app icon sits at x=150, the Applications alias at
// x=450, so everything drawn here has to live in the gap between them.

import AppKit
import CoreGraphics
import Foundation

let W: CGFloat = 600
let H: CGFloat = 400

let ground = CGColor(red: 0.043, green: 0.055, blue: 0.075, alpha: 1)
let iris   = CGColor(red: 0.243, green: 0.561, blue: 0.710, alpha: 1)
let faint  = CGColor(red: 0.373, green: 0.424, blue: 0.475, alpha: 1)

guard let ctx = CGContext(
    data: nil, width: Int(W), height: Int(H),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

ctx.setAllowsAntialiasing(true)
ctx.setFillColor(ground)
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

// Core Graphics is y-up; the Finder icons sit visually centred, which is
// y = 200 either way.
let midY: CGFloat = 212

// Arrow from just right of the app icon to just left of the Applications alias.
ctx.setStrokeColor(iris)
ctx.setLineWidth(2)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 242, y: midY))
ctx.addLine(to: CGPoint(x: 352, y: midY))
ctx.strokePath()

ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: 340, y: midY + 9))
ctx.addLine(to: CGPoint(x: 356, y: midY))
ctx.addLine(to: CGPoint(x: 340, y: midY - 9))
ctx.strokePath()

func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: CGColor, centerX: CGFloat, y: CGFloat) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: color) ?? .white,
        .kern: size * 0.06
    ]
    let str = NSAttributedString(string: text, attributes: attrs)
    let line = CTLineCreateWithAttributedString(str)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.textPosition = CGPoint(x: centerX - bounds.width / 2, y: y)
    CTLineDraw(line, ctx)
}

draw("DRAG TO INSTALL", size: 10, weight: .medium, color: faint, centerX: 299, y: midY - 30)
draw("LookNice", size: 15, weight: .semibold, color: faint, centerX: W / 2, y: 44)

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
rep.size = NSSize(width: W, height: H)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }

let out = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("build/dmg-bg.png")
try FileManager.default.createDirectory(
    at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
try data.write(to: out)
print("wrote \(out.path)")
