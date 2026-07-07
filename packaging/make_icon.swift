import AppKit

// Рисует иконку приложения: зелёный скруглённый квадрат + кремовый полумесяц.
// Запуск: swift packaging/make_icon.swift <путь_к_png>

let S = 1024.0
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()

NSColor.clear.set()
NSRect(x: 0, y: 0, width: S, height: S).fill()

// Фон — зелёный скруглённый квадрат с небольшим отступом.
let inset = S * 0.06
let side = S - 2 * inset
let green = NSColor(srgbRed: 0x0E/255.0, green: 0x9F/255.0, blue: 0x6E/255.0, alpha: 1)
let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: side, height: side),
                      xRadius: side * 0.23, yRadius: side * 0.23)
green.setFill(); bg.fill()

// Полумесяц: кремовый круг минус смещённый вырез цвета фона.
let cream = NSColor(srgbRed: 0xF4/255.0, green: 0xF2/255.0, blue: 0xEC/255.0, alpha: 1)
let cx = S * 0.5, cy = S * 0.5
let outerR = S * 0.27
cream.setFill()
NSBezierPath(ovalIn: NSRect(x: cx - outerR, y: cy - outerR, width: 2 * outerR, height: 2 * outerR)).fill()

let cutR = outerR * 0.9
let cutCx = cx + S * 0.135, cutCy = cy + S * 0.05
green.setFill()
NSBezierPath(ovalIn: NSRect(x: cutCx - cutR, y: cutCy - cutR, width: 2 * cutR, height: 2 * cutR)).fill()

img.unlockFocus()

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png")
if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: out)
    print("✓ icon: \(out.path)")
} else {
    print("✗ не удалось отрендерить иконку")
}
