#!/usr/bin/env swift

//
//  make-icon.swift
//  Renders the app icon from the same design language as the game.
//
//  The icon is generated rather than drawn by hand so it cannot drift from the
//  in-app brass/felt treatment: same colours, same wordmark construction, same
//  guilloche. Re-run it any time the palette changes.
//
//  Usage:  swift Tools/make-icon.swift <output-directory>
//

import AppKit
import Foundation

// MARK: - Palette (mirrors NinetyNine/Design/Palette.swift)

func srgb(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

let feltCore = srgb(0x0C2E26)
let feltMid = srgb(0x07211B)
let feltEdge = srgb(0x03110E)
let brassLight = srgb(0xF4DE9B)
let brassMid = srgb(0xD8AE45)
let brass = srgb(0xC9992F)
let brassDeep = srgb(0x8A6318)
let brassShadow = srgb(0x4A3208)

// MARK: - Drawing

/// Draws the icon at `side` points into the current graphics context.
/// The composition is deliberately simple: a lit felt field, a brass ring, and
/// the "99" wordmark. At 40pt on a home screen anything more becomes mud.
func drawIcon(side: CGFloat, context: CGContext) {
    let rect = CGRect(x: 0, y: 0, width: side, height: side)

    // Felt field, lit from above-left.
    let field = NSGradient(colors: [feltCore, feltMid, feltEdge])!
    field.draw(in: NSBezierPath(rect: rect), relativeCenterPosition: NSPoint(x: -0.15, y: 0.45))

    // Vignette so the corners fall away.
    context.saveGState()
    let vignette = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor.black.withAlphaComponent(0).cgColor,
            NSColor.black.withAlphaComponent(0.55).cgColor,
        ] as CFArray,
        locations: [0.45, 1.0]
    )!
    context.drawRadialGradient(
        vignette,
        startCenter: CGPoint(x: side / 2, y: side * 0.55), startRadius: side * 0.18,
        endCenter: CGPoint(x: side / 2, y: side * 0.55), endRadius: side * 0.72,
        options: []
    )
    context.restoreGState()

    // Guilloche rosette, very faint — texture rather than detail.
    context.saveGState()
    context.setLineWidth(max(0.4, side * 0.0035))
    context.setStrokeColor(brass.withAlphaComponent(0.16).cgColor)
    let centre = CGPoint(x: side / 2, y: side / 2)
    for index in 0..<14 {
        let angle = CGFloat(index) / 14 * .pi
        context.saveGState()
        context.translateBy(x: centre.x, y: centre.y)
        context.rotate(by: angle)
        context.addEllipse(in: CGRect(
            x: -side * 0.40, y: -side * 0.21,
            width: side * 0.80, height: side * 0.42
        ))
        context.strokePath()
        context.restoreGState()
    }
    context.restoreGState()

    // Brass ring. Clipping to an oval path would fill the whole disc, so the
    // clip is built from the *stroke outline* — a true annulus — which lets the
    // felt show through the middle.
    func strokeOutline(inset: CGFloat, width: CGFloat) -> CGPath? {
        CGPath(ellipseIn: rect.insetBy(dx: inset, dy: inset), transform: nil)
            .copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
    }

    if let ring = strokeOutline(inset: side * 0.085, width: side * 0.030) {
        context.saveGState()
        context.addPath(ring)
        context.clip()
        NSGradient(colors: [brassDeep, brassLight, brassMid, brassShadow, brassLight])!
            .draw(in: NSBezierPath(rect: rect), angle: 55)
        context.restoreGState()
    }

    // Inner keyline, same construction at a hairline weight.
    if let keyline = strokeOutline(inset: side * 0.140, width: max(1, side * 0.008)) {
        context.saveGState()
        context.addPath(keyline)
        context.clip()
        NSGradient(colors: [brassMid, brassDeep])!.draw(in: NSBezierPath(rect: rect), angle: 235)
        context.restoreGState()
    }

    // The wordmark. Serif, heavy, tight — same construction as the app's title.
    let pointSize = side * 0.46
    let font = NSFont(descriptor:
        NSFontDescriptor(name: "NewYork-Heavy", size: pointSize)
    , size: pointSize)
        ?? NSFont(name: "Times New Roman Bold", size: pointSize)
        ?? NSFont.boldSystemFont(ofSize: pointSize)

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: brassLight,
        .kern: -pointSize * 0.07,
    ]
    let text = NSAttributedString(string: "99", attributes: attributes)
    let textSize = text.size()
    let origin = CGPoint(
        x: (side - textSize.width) / 2,
        y: (side - textSize.height) / 2 + side * 0.005
    )

    // Drop shadow under the numerals so they lift off the felt.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -side * 0.012),
        blur: side * 0.03,
        color: NSColor.black.withAlphaComponent(0.7).cgColor
    )
    text.draw(at: origin)
    context.restoreGState()

    // Brass gradient over the glyphs, clipped to their shape.
    context.saveGState()
    let glyphPath = NSBezierPath()
    // Re-draw the text as a clip by rendering it into a mask via a transparency
    // layer; simplest reliable route on AppKit is to draw the gradient inside a
    // clip built from the text's outline.
    if let ctFont = attributes[.font] as? NSFont {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: "99", attributes: [.font: ctFont])
        )
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRangeMake(0, count), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, count), &positions)
            let runFont = unsafeBitCast(
                CFDictionaryGetValue(
                    CTRunGetAttributes(run),
                    Unmanaged.passUnretained(kCTFontAttributeName).toOpaque()
                ),
                to: CTFont.self
            )
            for index in 0..<count {
                guard let letter = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) else { continue }
                var transform = CGAffineTransform(
                    translationX: origin.x + positions[index].x,
                    y: origin.y + positions[index].y + textSize.height * 0.22
                )
                if let moved = letter.copy(using: &transform) {
                    glyphPath.append(NSBezierPath(cgPath: moved))
                }
            }
        }
    }
    if !glyphPath.isEmpty {
        glyphPath.addClip()
        NSGradient(colors: [brassDeep, brassMid, brassLight, brass, brassDeep])!
            .draw(in: NSBezierPath(rect: rect), angle: 60)
    }
    context.restoreGState()
}

extension NSBezierPath {
    convenience init(cgPath: CGPath) {
        self.init()
        cgPath.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                move(to: element.points[0])
            case .addLineToPoint:
                line(to: element.points[0])
            case .addQuadCurveToPoint:
                let control = element.points[0]
                let end = element.points[1]
                let start = currentPoint
                curve(
                    to: end,
                    controlPoint1: CGPoint(
                        x: start.x + 2.0 / 3.0 * (control.x - start.x),
                        y: start.y + 2.0 / 3.0 * (control.y - start.y)
                    ),
                    controlPoint2: CGPoint(
                        x: end.x + 2.0 / 3.0 * (control.x - end.x),
                        y: end.y + 2.0 / 3.0 * (control.y - end.y)
                    )
                )
            case .addCurveToPoint:
                curve(to: element.points[2], controlPoint1: element.points[0], controlPoint2: element.points[1])
            case .closeSubpath:
                close()
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Export

func render(side: Int) -> Data? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side, pixelsHigh: side,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
    NSGraphicsContext.current = graphicsContext
    drawIcon(side: CGFloat(side), context: graphicsContext.cgContext)
    NSGraphicsContext.restoreGraphicsState()

    return bitmap.representation(using: .png, properties: [:])
}

let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

// A single 1024 master; Xcode generates every other size from it.
for side in [1024, 180, 120] {
    guard let data = render(side: side) else {
        FileHandle.standardError.write("Failed to render \(side)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent("icon-\(side).png")
    try data.write(to: url)
    print("wrote \(url.path)")
}
