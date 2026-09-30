// Builds the 1200x630 card shown when the site is linked.
// The app icon on the same dark the site's second section uses, so a share
// and the page look like the same product.
//
//   swift Tools/make_og.swift
//
// Writes build/og.png; convert to site/og.jpg (32 KB vs 710 KB) with:
//   sips -s format jpeg -s formatOptions 82 build/og.png --out site/og.jpg
// Run both whenever the icon changes; site/og.jpg is committed.

import AppKit

let W = 1200.0, H = 630.0

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconURL = root.appendingPathComponent(
    "Sources/LookNice/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png")
let outURL = root.appendingPathComponent("build/og.png")

guard let icon = NSImage(contentsOf: iconURL) else {
    FileHandle.standardError.write("cannot read \(iconURL.path)\n".data(using: .utf8)!)
    exit(1)
}

guard let ctx = CGContext(data: nil,
                          width: Int(W), height: Int(H),
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}

let space = CGColorSpaceCreateDeviceRGB()
func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r / 255, g / 255, b / 255, a])!
}

// Base: the site's --night, lifted slightly toward the top.
let base = CGGradient(colorsSpace: space,
                      colors: [rgb(16, 48, 43), rgb(8, 23, 18)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

// The same two washes the dark band uses, so the card feels lit by the screen.
func wash(_ cx: Double, _ cy: Double, _ r: Double, _ c: CGColor) {
    let g = CGGradient(colorsSpace: space,
                       colors: [c, c.copy(alpha: 0)!] as CFArray,
                       locations: [0, 1])!
    ctx.drawRadialGradient(g,
                           startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                           endCenter: CGPoint(x: cx, y: cy), endRadius: r,
                           options: [])
}
wash(W * 0.30, H * 0.74, 520, rgb(118, 194, 200, 0.28))
wash(W * 0.76, H * 0.30, 460, rgb(124, 176, 126, 0.22))

// The icon, centred, with room to breathe. Social crops nibble the edges, so
// it sits well inside the safe area.
let side = 340.0
let rect = CGRect(x: (W - side) / 2, y: (H - side) / 2, width: side, height: side)

ctx.setShadow(offset: CGSize(width: 0, height: -24),
              blur: 60,
              color: rgb(0, 0, 0, 0.55))

var box = rect
if let cg = icon.cgImage(forProposedRect: &box, context: nil, hints: nil) {
    ctx.draw(cg, in: rect)
}

guard let out = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: out)
rep.size = NSSize(width: W, height: H)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: outURL)

print("wrote \(outURL.path) — \(Int(W))x\(Int(H)), \(data.count / 1024) KB")
