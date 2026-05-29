#!/usr/bin/env swift
import Foundation
import AppKit
import CoreImage

let args = CommandLine.arguments
guard args.count == 4 else { print("Usage: hue_rotate.swift input output degrees"); exit(1) }

let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])
let radians = Float((Double(args[3]) ?? 220.0) * .pi / 180.0)

guard let ci = CIImage(contentsOf: inputURL) else { print("Cannot load \(args[1])"); exit(1) }
let f = CIFilter(name: "CIHueAdjust")!
f.setValue(ci, forKey: kCIInputImageKey)
f.setValue(radians, forKey: kCIInputAngleKey)
guard let out = f.outputImage else { exit(1) }

let ctx = CIContext()
guard let cg = ctx.createCGImage(out, from: out.extent) else { exit(1) }

let size = NSSize(width: cg.width, height: cg.height)
let result = NSImage(size: size)
result.lockFocus()

// Draw hue-rotated base
NSImage(cgImage: cg, size: size).draw(in: NSRect(origin: .zero, size: NSSize(width: size.width, height: size.height)))

let ptSize = size.width * 0.35
let symConfig = NSImage.SymbolConfiguration(pointSize: ptSize, weight: .semibold)
if let raw = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symConfig) {
    // Tint to white via sourceAtop
    let tinted = NSImage(size: raw.size)
    tinted.lockFocus()
    raw.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
    NSColor.black.set()
    NSRect(origin: .zero, size: raw.size).fill(using: .sourceAtop)
    tinted.unlockFocus()

    let symRect = NSRect(
        x: (size.width  - raw.size.width)  / 2 + size.width * 0.02,
        y: (size.height - raw.size.height) / 2,
        width:  raw.size.width,
        height: raw.size.height
    )
    tinted.draw(in: symRect, from: .zero, operation: .sourceOver, fraction: 0.9)
}

result.unlockFocus()

guard let tiff   = result.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png    = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: outputURL)
