import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let bounds = NSRect(x: 42, y: 42, width: 940, height: 940)
let tile = NSBezierPath(roundedRect: bounds, xRadius: 210, yRadius: 210)
NSColor(calibratedRed: 0.065, green: 0.09, blue: 0.15, alpha: 1).setFill()
tile.fill()
NSColor(calibratedWhite: 1, alpha: 0.13).setStroke()
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
    color: NSColor(calibratedRed: 0.37, green: 0.88, blue: 0.80, alpha: 1), pointsRight: true
)
drawArrow(
    from: NSPoint(x: 754, y: 365), to: NSPoint(x: 289, y: 365),
    color: NSColor(calibratedRed: 1, green: 0.43, blue: 0.36, alpha: 1), pointsRight: false
)

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Icon PNG üretilemedi")
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: output)
