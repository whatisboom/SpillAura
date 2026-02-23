#!/usr/bin/env swift
// generate_background.swift — DMG background generator (zero dependencies)
// Usage: swift dmg/generate_background.swift

import CoreGraphics
import Foundation
import ImageIO

// MARK: - Configuration

let centerColor: [CGFloat] = [26.0/255, 26.0/255, 46.0/255, 1]  // #1a1a2e navy
let edgeColor: [CGFloat]   = [22.0/255, 33.0/255, 62.0/255, 1]  // #16213e charcoal
let arrowComponents: [CGFloat] = [1, 1, 1, 80.0/255]            // white, low opacity

let canvasWidth  = 660
let canvasHeight = 440
let arrowY: CGFloat       = 260   // below icon center, above labels
let arrowLeftX: CGFloat   = 230   // right edge of app icon area
let arrowRightX: CGFloat  = 430   // left edge of Applications area
let dashLength: CGFloat   = 12
let gapLength: CGFloat    = 8
let lineWidth: CGFloat    = 2
let arrowheadSize: CGFloat = 10

// MARK: - Generator

func generateBackground(scale: Int) -> CGImage {
    let w = canvasWidth * scale
    let h = canvasHeight * scale
    let s = CGFloat(scale)
    let space = CGColorSpaceCreateDeviceRGB()

    let ctx = CGContext(
        data: nil, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: w * 4,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Radial gradient (center → edge)
    let gradient = CGGradient(
        colorSpace: space,
        colorComponents: centerColor + edgeColor,
        locations: [0, 1],
        count: 2
    )!

    let center = CGPoint(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
    let radius = hypot(center.x, center.y)
    ctx.drawRadialGradient(
        gradient,
        startCenter: center, startRadius: 0,
        endCenter: center, endRadius: radius,
        options: .drawsAfterEndLocation
    )

    // Dashed arrow (CoreGraphics origin = bottom-left, flip Y)
    let fy = CGFloat(h) - arrowY * s
    let left = arrowLeftX * s
    let right = arrowRightX * s
    let ah = arrowheadSize * s
    let arrowColor = CGColor(colorSpace: space, components: arrowComponents)!

    // Dashed line
    ctx.setStrokeColor(arrowColor)
    ctx.setLineWidth(lineWidth * s)
    ctx.setLineDash(phase: 0, lengths: [dashLength * s, gapLength * s])
    ctx.move(to: CGPoint(x: left, y: fy))
    ctx.addLine(to: CGPoint(x: right - ah, y: fy))
    ctx.strokePath()

    // Arrowhead (solid triangle)
    ctx.setFillColor(arrowColor)
    ctx.move(to: CGPoint(x: right, y: fy))
    ctx.addLine(to: CGPoint(x: right - ah, y: fy + ah / 2))
    ctx.addLine(to: CGPoint(x: right - ah, y: fy - ah / 2))
    ctx.closePath()
    ctx.fillPath()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(
        url as CFURL, "public.png" as CFString, 1, nil
    )!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        fatalError("Failed to write \(url.path)")
    }
    print("Wrote \(url.path) (\(image.width)x\(image.height))")
}

// MARK: - Main

let outputDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

writePNG(generateBackground(scale: 1),
         to: outputDir.appendingPathComponent("background.png"))
writePNG(generateBackground(scale: 2),
         to: outputDir.appendingPathComponent("background@2x.png"))
