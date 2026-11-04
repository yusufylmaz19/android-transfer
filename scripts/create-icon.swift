import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let bounds = NSRect(x: 42, y: 42, width: 940, height: 940)
let tile = NSBezierPath(roundedRect: bounds, xRadius: 210, yRadius: 210)
NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.91, alpha: 1).setFill()
tile.fill()
NSColor(calibratedRed: 0.87, green: 0.85, blue: 0.83, alpha: 1).setStroke()
tile.lineWidth = 12
tile.stroke()

func drawArrow(from start: NSPoint, to end: NSPoint, color: NSColor, pointsRight: Bool) {
    let path = NSBezierPath()
    path.lineWidth = 86
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: start)
    path.line(to: end)
    color.setStroke()
    path.stroke()

    let head = NSBezierPath()
    head.lineWidth = 86
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    if pointsRight {
        head.move(to: NSPoint(x: end.x - 130, y: end.y + 115))
        head.line(to: end)
        head.line(to: NSPoint(x: end.x - 130, y: end.y - 115))
    } else {
        head.move(to: NSPoint(x: end.x + 130, y: end.y + 115))
        head.line(to: end)
        head.line(to: NSPoint(x: end.x + 130, y: end.y - 115))
    }
    head.stroke()
}

drawArrow(
    from: NSPoint(x: 270, y: 650), to: NSPoint(x: 735, y: 650),
    color: NSColor(calibratedRed: 0.34, green: 0.48, blue: 0.91, alpha: 1), pointsRight: true
)
drawArrow(
    from: NSPoint(x: 754, y: 365), to: NSPoint(x: 289, y: 365),
    color: NSColor(calibratedRed: 0.91, green: 0.40, blue: 0.57, alpha: 1), pointsRight: false
)

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Icon PNG üretilemedi")
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: output)
