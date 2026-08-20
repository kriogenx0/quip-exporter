#!/usr/bin/env swift
import Foundation
import AppKit

let args = CommandLine.arguments
guard args.count == 3 else { print("Usage: compose_icon.swift input output"); exit(1) }

let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])

guard let quipLogo = NSImage(contentsOf: inputURL), let rep = quipLogo.representations.first else {
    print("Cannot load \(args[1])"); exit(1)
}

let size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
let result = NSImage(size: size)
result.lockFocus()

// Blue rounded-square background, matching macOS's own icon corner-radius convention.
let cornerRadius = size.width * 0.2237
let background = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: cornerRadius, yRadius: cornerRadius)
background.addClip()
let gradient = NSGradient(
    colors: [
        NSColor(calibratedRed: 0.36, green: 0.62, blue: 0.98, alpha: 1.0),
        NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.88, alpha: 1.0),
        NSColor(calibratedRed: 0.04, green: 0.22, blue: 0.62, alpha: 1.0)
    ]
)!
gradient.draw(in: NSRect(origin: .zero, size: size), angle: -90)

// The Quip logo itself, shrunk and pinned near the top.
let logoSide = size.width * 0.58
let logoRect = NSRect(
    x: (size.width - logoSide) / 2,
    y: size.height - logoSide - size.height * 0.08,
    width: logoSide,
    height: logoSide
)
quipLogo.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1.0)

// A white down arrow underneath it.
let symConfig = NSImage.SymbolConfiguration(pointSize: size.width * 0.24, weight: .bold)
if let arrow = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil)?
        .withSymbolConfiguration(symConfig) {
    let tinted = NSImage(size: arrow.size)
    tinted.lockFocus()
    arrow.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
    NSColor.white.set()
    NSRect(origin: .zero, size: arrow.size).fill(using: .sourceAtop)
    tinted.unlockFocus()

    let arrowRect = NSRect(
        x: (size.width - arrow.size.width) / 2,
        y: logoRect.minY - arrow.size.height - size.height * 0.02,
        width: arrow.size.width,
        height: arrow.size.height
    )
    tinted.draw(in: arrowRect, from: .zero, operation: .sourceOver, fraction: 1.0)
}

result.unlockFocus()

guard let tiff = result.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: outputURL)
