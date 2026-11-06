import AppKit
import Foundation

// Native raster rendering avoids SVG filter/gradient differences between converters.
let size = NSSize(width: 1024, height: 1024)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = size
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
NSColor.clear.setFill()
NSRect(origin: .zero, size: size).fill()

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: alpha)
}
let plate = NSBezierPath(roundedRect: NSRect(x: 24, y: 24, width: 976, height: 976), xRadius: 220, yRadius: 220)
NSGradient(colors: [color(49, 46, 129), color(79, 70, 229), color(129, 140, 248)])!
    .draw(in: plate, angle: 70)
color(255, 255, 255, 0.22).setStroke()
plate.lineWidth = 2
plate.stroke()

let phone = NSBezierPath(roundedRect: NSRect(x: 300, y: 174, width: 424, height: 676), xRadius: 88, yRadius: 88)
NSGradient(starting: color(255, 255, 255, 0.04), ending: color(255, 255, 255, 0.22))!
    .draw(in: phone, angle: 90)
NSColor.white.setStroke()
phone.lineWidth = 32
phone.stroke()

func stroke(_ points: [NSPoint], width: CGFloat, ink: NSColor = .white) {
    let path = NSBezierPath()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    ink.setStroke()
    path.stroke()
}
stroke([NSPoint(x: 461, y: 804), NSPoint(x: 563, y: 804)], width: 25,
    ink: color(255, 255, 255, 0.8))

stroke([NSPoint(x: 402, y: 598), NSPoint(x: 622, y: 598)], width: 42)
stroke([NSPoint(x: 552, y: 668), NSPoint(x: 622, y: 598), NSPoint(x: 552, y: 528)], width: 42)

let returnInk = color(189, 242, 255)
stroke([NSPoint(x: 622, y: 418), NSPoint(x: 402, y: 418)], width: 42, ink: returnInk)
stroke([NSPoint(x: 472, y: 488), NSPoint(x: 402, y: 418), NSPoint(x: 472, y: 348)],
    width: 42, ink: returnInk)

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Assets/AppIcon.png"
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Rendered \(output)")
