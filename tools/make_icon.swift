// 產生 AutoCal 的 App 圖示（1024×1024，不透明，iOS 會自己套圓角）。
// 用法：swift tools/make_icon.swift <輸出 png 路徑>
import AppKit

let size = 1024
guard CommandLine.arguments.count > 1 else { print("需要輸出路徑"); exit(1) }
let out = CommandLine.arguments[1]

// 先畫在有 alpha 的位圖上（NSGraphicsContext 對無 alpha 的位圖支援不穩），
// 最後再轉成「沒有 alpha」的 PNG——App Store 要求圖示不能透明。
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32),
      let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
    print("建立繪圖環境失敗"); exit(1)
}
NSGraphicsContext.current = ctx

func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
// 以左上為原點的矩形（AppKit 原點在左下）
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: CGFloat(size) - y - h, width: w, height: h)
}

// 背景：藍到紫的斜向漸層（滿版，不留圓角）
NSGradient(starting: c(0x4F7CFF), ending: c(0x7B4DFF))!
    .draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -45)

// 日曆卡片（白色，帶柔和陰影）
let card = rect(172, 232, 680, 624)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 46
shadow.shadowOffset = NSSize(width: 0, height: -22)
shadow.set()
c(0xFFFFFF).setFill()
NSBezierPath(roundedRect: card, xRadius: 92, yRadius: 92).fill()
NSGraphicsContext.restoreGraphicsState()

// 卡片上方的色帶（日曆的標頭），裁成和卡片同樣的圓角
NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: card, xRadius: 92, yRadius: 92).addClip()
c(0xFF5A5F).setFill()
NSBezierPath(rect: rect(172, 232, 680, 128)).fill()
NSGraphicsContext.restoreGraphicsState()

// 裝訂環
for x in [336.0, 688.0] {
    c(0xFFFFFF).setFill()
    NSBezierPath(roundedRect: rect(CGFloat(x) - 22, 184, 44, 112), xRadius: 22, yRadius: 22).fill()
    c(0xD9DCE6).setFill()
    NSBezierPath(roundedRect: rect(CGFloat(x) - 9, 206, 18, 68), xRadius: 9, yRadius: 9).fill()
}

// 時間塊：像課表一樣高低不同，其中一塊是綠色虛線的「空堂」
func block(_ r: NSRect, _ color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: r, xRadius: 30, yRadius: 30).fill()
}
block(rect(222, 404, 262, 168), c(0x3B82F6))     // 藍
block(rect(222, 596, 262, 206), c(0xF97316))     // 橘（比較長的一堂）
block(rect(540, 484, 262, 188), c(0x8B5CF6))     // 紫

let free = NSBezierPath(roundedRect: rect(540, 404, 262, 56), xRadius: 22, yRadius: 22)
free.lineWidth = 8
free.setLineDash([22, 14], count: 2, phase: 0)
c(0x10B981).setStroke()
free.stroke()
c(0x10B981, 0.14).setFill()
free.fill()

let free2 = NSBezierPath(roundedRect: rect(540, 696, 262, 106), xRadius: 22, yRadius: 22)
free2.lineWidth = 8
free2.setLineDash([22, 14], count: 2, phase: 0)
c(0x10B981).setStroke()
free2.stroke()
c(0x10B981, 0.14).setFill()
free2.fill()

// 右上角的閃光：代表「自動」
func sparkle(center: CGPoint, radius: CGFloat, inner: CGFloat = 0.30) {
    let p = NSBezierPath()
    for i in 0..<8 {
        let r = (i % 2 == 0) ? radius : radius * inner
        let a = CGFloat(i) * .pi / 4 - .pi / 2
        let pt = NSPoint(x: center.x + cos(a) * r, y: CGFloat(size) - (center.y + sin(a) * r))
        i == 0 ? p.move(to: pt) : p.line(to: pt)
    }
    p.close()
    p.lineJoinStyle = .round
    p.fill()
}
c(0xFFFFFF).setFill()
sparkle(center: CGPoint(x: 846, y: 168), radius: 92)
c(0xFFFFFF, 0.9).setFill()
sparkle(center: CGPoint(x: 930, y: 276), radius: 40)

NSGraphicsContext.current = nil

// 轉成不含 alpha 的 RGB 再輸出
let cs = CGColorSpaceCreateDeviceRGB()
let flat = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                     space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
flat.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: size, height: size))
let flatRep = NSBitmapImageRep(cgImage: flat.makeImage()!)
try! flatRep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote", out)
