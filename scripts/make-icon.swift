import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tile = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.white.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.27, alpha: 1),
               ending: NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.11, alpha: 1))?
        .draw(in: tile, angle: -90)

    let frame = NSRect(x: 222, y: 352, width: 580, height: 320)
    let outline = NSBezierPath(roundedRect: frame, xRadius: 52, yRadius: 52)
    outline.lineWidth = 34
    NSColor.white.setStroke()
    outline.stroke()

    let m = NSBezierPath()
    m.move(to: NSPoint(x: 300, y: 432))
    m.line(to: NSPoint(x: 300, y: 592))
    m.line(to: NSPoint(x: 370, y: 512))
    m.line(to: NSPoint(x: 440, y: 592))
    m.line(to: NSPoint(x: 440, y: 432))
    m.lineWidth = 40
    m.lineJoinStyle = .round
    m.lineCapStyle = .round
    m.stroke()

    let stem = NSBezierPath()
    stem.move(to: NSPoint(x: 620, y: 592))
    stem.line(to: NSPoint(x: 620, y: 470))
    stem.lineWidth = 40
    stem.lineCapStyle = .round
    stem.stroke()

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 552, y: 492))
    arrow.line(to: NSPoint(x: 620, y: 424))
    arrow.line(to: NSPoint(x: 688, y: 492))
    arrow.close()
    NSColor.white.setFill()
    arrow.lineWidth = 16
    arrow.lineJoinStyle = .round
    arrow.fill()
    arrow.stroke()
    return true
}

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: output)
