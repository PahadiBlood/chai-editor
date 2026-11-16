// Regenerate the vector logo's PNG companion: swift tools/render_logo.swift
// Geometry mirrors assets/branding/chai-logo.svg. No third-party renderer needed.
import AppKit

let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024,
  pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let context = NSGraphicsContext.current!.cgContext
context.translateBy(x: 0, y: 1024)
context.scaleBy(x: 1, y: -1)
func color(_ hex: UInt32) -> CGColor {
  CGColor(red: CGFloat((hex >> 16) & 255) / 255,
    green: CGFloat((hex >> 8) & 255) / 255,
    blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func fill(_ path: CGPath, _ hex: UInt32) {
  context.addPath(path); context.setFillColor(color(hex)); context.fillPath()
}
func line(_ points: [CGPoint], _ hex: UInt32, _ width: CGFloat) {
  context.beginPath(); context.move(to: points[0])
  for point in points.dropFirst() { context.addLine(to: point) }
  context.setStrokeColor(color(hex)); context.setLineWidth(width)
  context.setLineCap(.round); context.strokePath()
}
fill(CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
  cornerWidth: 208, cornerHeight: 208, transform: nil), 0x17191f)
let page = CGMutablePath()
page.move(to: CGPoint(x: 308, y: 200)); page.addLine(to: CGPoint(x: 584, y: 200))
page.addLine(to: CGPoint(x: 744, y: 360)); page.addLine(to: CGPoint(x: 744, y: 748))
page.addQuadCurve(to: CGPoint(x: 692, y: 800), control: CGPoint(x: 744, y: 800))
page.addLine(to: CGPoint(x: 308, y: 800))
page.addQuadCurve(to: CGPoint(x: 256, y: 748), control: CGPoint(x: 256, y: 800))
page.addLine(to: CGPoint(x: 256, y: 252))
page.addQuadCurve(to: CGPoint(x: 308, y: 200), control: CGPoint(x: 256, y: 200))
page.closeSubpath(); fill(page, 0xf3eadd)
let fold = CGMutablePath()
fold.move(to: CGPoint(x: 584, y: 200)); fold.addLine(to: CGPoint(x: 584, y: 316))
fold.addQuadCurve(to: CGPoint(x: 628, y: 360), control: CGPoint(x: 584, y: 360))
fold.addLine(to: CGPoint(x: 744, y: 360)); fold.closeSubpath(); fill(fold, 0xc9baa8)
line([CGPoint(x: 352, y: 350), CGPoint(x: 496, y: 350)], 0x777069, 24)
line([CGPoint(x: 352, y: 414), CGPoint(x: 630, y: 414)], 0x777069, 24)
let handle = CGMutablePath()
handle.move(to: CGPoint(x: 602, y: 536)); handle.addLine(to: CGPoint(x: 626, y: 536))
handle.addCurve(to: CGPoint(x: 626, y: 648), control1: CGPoint(x: 706, y: 536), control2: CGPoint(x: 706, y: 648))
handle.addLine(to: CGPoint(x: 598, y: 648))
context.addPath(handle); context.setStrokeColor(color(0xbb6a37)); context.setLineWidth(32); context.strokePath()
let cup = CGMutablePath()
cup.move(to: CGPoint(x: 352, y: 520)); cup.addLine(to: CGPoint(x: 614, y: 520))
cup.addLine(to: CGPoint(x: 614, y: 604))
cup.addQuadCurve(to: CGPoint(x: 514, y: 704), control: CGPoint(x: 614, y: 704))
cup.addLine(to: CGPoint(x: 452, y: 704))
cup.addQuadCurve(to: CGPoint(x: 352, y: 604), control: CGPoint(x: 352, y: 704))
cup.closeSubpath(); fill(cup, 0xbb6a37)
line([CGPoint(x: 384, y: 550), CGPoint(x: 582, y: 550)], 0xe9b278, 16)
line([CGPoint(x: 350, y: 742), CGPoint(x: 630, y: 742)], 0x777069, 20)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(
  to: URL(fileURLWithPath: "assets/branding/chai-logo.png"))
