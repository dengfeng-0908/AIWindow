#!/usr/bin/env swift

import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = Array(CommandLine.arguments.dropFirst())
let allowsOverwrite = arguments.first == "--overwrite"
let paths = allowsOverwrite ? Array(arguments.dropFirst()) : arguments

guard paths.count == 1 else {
    fputs("Usage: render_app_icon.swift [--overwrite] <output.png>\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: paths[0])
if FileManager.default.fileExists(atPath: outputURL.path), !allowsOverwrite {
    fputs("Refusing to overwrite existing output without --overwrite.\n", stderr)
    exit(73)
}

let pixelSize = 1024
guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
          data: nil,
          width: pixelSize,
          height: pixelSize,
          bitsPerComponent: 8,
          bytesPerRow: pixelSize * 4,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      ) else {
    fputs("Unable to create the bitmap context.\n", stderr)
    exit(70)
}

func color(_ red: Int, _ green: Int, _ blue: Int) -> CGColor {
    CGColor(
        colorSpace: colorSpace,
        components: [
            CGFloat(red) / 255,
            CGFloat(green) / 255,
            CGFloat(blue) / 255,
            1,
        ]
    )!
}

func fill(_ rect: CGRect, radius: CGFloat, with fillColor: CGColor) {
    context.setFillColor(fillColor)
    context.addPath(
        CGPath(
            roundedRect: rect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    )
    context.fillPath()
}

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let canvas = CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
context.setFillColor(color(244, 247, 242))
context.fill(canvas)

fill(CGRect(x: 128, y: 128, width: 768, height: 768), radius: 152, with: color(28, 36, 40))
fill(CGRect(x: 212, y: 212, width: 600, height: 600), radius: 72, with: color(252, 253, 250))

let bands: [(rect: CGRect, color: CGColor, lineWidth: CGFloat)] = [
    (CGRect(x: 288, y: 632, width: 424, height: 100), color(0, 166, 143), 214),
    (CGRect(x: 382, y: 462, width: 330, height: 100), color(244, 99, 82), 120),
    (CGRect(x: 288, y: 292, width: 424, height: 100), color(245, 200, 75), 214),
]

for band in bands {
    fill(band.rect, radius: 50, with: band.color)
    fill(
        CGRect(x: band.rect.minX + 28, y: band.rect.minY + 28, width: 44, height: 44),
        radius: 22,
        with: color(252, 253, 250)
    )
    fill(
        CGRect(
            x: band.rect.minX + 94,
            y: band.rect.minY + 35,
            width: band.lineWidth,
            height: 30
        ),
        radius: 15,
        with: color(252, 253, 250)
    )
}

guard let image = context.makeImage() else {
    fputs("Unable to create the icon image.\n", stderr)
    exit(70)
}

let encodedData = NSMutableData()
guard let destination = CGImageDestinationCreateWithData(
    encodedData,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fputs("Unable to create the PNG destination.\n", stderr)
    exit(70)
}

CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Unable to encode PNG data.\n", stderr)
    exit(70)
}

do {
    let pngData = encodedData as Data
    try pngData.write(to: outputURL, options: Data.WritingOptions.atomic)
} catch {
    fputs("Unable to write the icon: \(error.localizedDescription)\n", stderr)
    exit(74)
}
