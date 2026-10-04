import AppKit
import Foundation

struct Block { let name: String; let day: Int; let p1: String; let p2: String; var room: String? = nil }
let PT: [String: (Int, Int)] = ["1": (490,540),"2":(550,600),"3":(620,670),"4":(680,730),"5":(740,790),"6":(800,850),"7":(860,910),
  "8":(930,980),"9":(990,1040),"10":(1050,1100),"A":(1105,1155),"B":(1160,1210),"C":(1215,1265)]
func hm(_ m: Int) -> String { String(format: "%02d:%02d", m/60, m%60) }

struct Style { var dark: Bool; var axisMode: Int /*0: time+label+time, 1: time-only range, 2: label only*/; var showRoom: Bool = false }

func render(file: String, days: [String], header: Bool, rows: [String], blocks: [Block], style: Style, width: CGFloat = 1179) {
    let axisW: CGFloat = 165, rowH: CGFloat = 212, headH: CGFloat = header ? 90 : 0, gap: CGFloat = 4
    let colW = (width - axisW - 12) / CGFloat(days.count)
    let height = headH + rowH * CGFloat(rows.count) + 10
    let bg = style.dark ? NSColor.black : NSColor.white
    let fg = style.dark ? NSColor.white : NSColor.black
    let sub = style.dark ? NSColor(white: 0.62, alpha: 1) : NSColor(white: 0.45, alpha: 1)
    let img = NSImage(size: NSSize(width: width, height: height))
    img.lockFocus()
    bg.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
    func y(_ top: CGFloat, _ h: CGFloat) -> CGFloat { height - top - h }   // flip
    func text(_ s: String, size: CGFloat, bold: Bool, color: NSColor, rect: NSRect, align: NSTextAlignment = .center) {
        let p = NSMutableParagraphStyle(); p.alignment = align; p.lineBreakMode = .byWordWrapping
        let f = NSFont(name: bold ? "PingFangTC-Semibold" : "PingFangTC-Regular", size: size) ?? NSFont.systemFont(ofSize: size)
        let a = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color, .paragraphStyle: p])
        let h = a.boundingRect(with: NSSize(width: rect.width, height: 1000), options: [.usesLineFragmentOrigin]).height
        a.draw(in: NSRect(x: rect.minX, y: rect.minY + (rect.height - h) / 2, width: rect.width, height: h))
    }
    if header {
        for (i, d) in days.enumerated() {
            text(d, size: 44, bold: true, color: sub, rect: NSRect(x: axisW + CGFloat(i) * colW, y: y(0, headH), width: colW, height: headH))
        }
    }
    for (r, p) in rows.enumerated() {
        let top = headH + CGFloat(r) * rowH
        let rect = NSRect(x: 0, y: y(top, rowH), width: axisW, height: rowH)
        if let t = PT[p] {
            switch style.axisMode {
            case 0:
                text(hm(t.0), size: 30, bold: false, color: sub, rect: NSRect(x: rect.minX, y: rect.minY + rowH * 0.62, width: axisW, height: 40))
                text(p, size: 52, bold: true, color: fg, rect: NSRect(x: rect.minX, y: rect.minY + rowH * 0.33, width: axisW, height: 70))
                text(hm(t.1), size: 30, bold: false, color: sub, rect: NSRect(x: rect.minX, y: rect.minY + rowH * 0.08, width: axisW, height: 40))
            case 1:
                text(hm(t.0) + "\n–\n" + hm(t.1), size: 30, bold: false, color: fg, rect: rect)
            default:
                text(p, size: 56, bold: true, color: fg, rect: rect)
            }
        }
        // 淡淡的格線
        sub.withAlphaComponent(0.2).setFill()
        NSRect(x: axisW, y: y(top, 1), width: width - axisW, height: 1).fill()
    }
    let palette: [NSColor] = style.dark
      ? [NSColor(red: 0.13, green: 0.24, blue: 0.36, alpha: 1), NSColor(red: 0.34, green: 0.14, blue: 0.11, alpha: 1), NSColor(red: 0.36, green: 0.29, blue: 0.1, alpha: 1), NSColor(red: 0.14, green: 0.28, blue: 0.2, alpha: 1)]
      : [NSColor(red: 0.8, green: 0.9, blue: 1, alpha: 1), NSColor(red: 1, green: 0.85, blue: 0.82, alpha: 1), NSColor(red: 1, green: 0.95, blue: 0.75, alpha: 1), NSColor(red: 0.82, green: 0.95, blue: 0.84, alpha: 1)]
    for (bi, b) in blocks.enumerated() {
        guard let r1 = rows.firstIndex(of: b.p1), let r2 = rows.firstIndex(of: b.p2) else { continue }
        let top = headH + CGFloat(r1) * rowH + gap, h = CGFloat(r2 - r1 + 1) * rowH - 2 * gap
        let x = axisW + CGFloat(b.day - 1) * colW + gap
        let rr = NSRect(x: x, y: y(top, h), width: colW - 2 * gap, height: h)
        palette[bi % palette.count].setFill()
        NSBezierPath(roundedRect: rr, xRadius: 22, yRadius: 22).fill()
        var label = b.name
        if style.showRoom, let room = b.room { label += "\n" + room }
        text(label, size: colW > 190 ? 38 : 32, bold: true, color: fg, rect: rr.insetBy(dx: 8, dy: 8))
    }
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])!.write(to: URL(fileURLWithPath: file))
}

struct Truth: Codable { let name: String; let weekday: Int; let start: Int; let end: Int }
struct Scenario: Codable { let name: String; let images: [String]; let truth: [Truth] }
var manifest: [Scenario] = []
func truth(_ bs: [Block]) -> [Truth] { bs.map { Truth(name: $0.name, weekday: $0.day, start: PT[$0.p1]!.0, end: PT[$0.p2]!.1) } }
let wd5 = ["一","二","三","四","五"], wd7 = ["一","二","三","四","五","六","日"]
let allRows = ["1","2","3","4","6","7","8","9","10","A","B","C"]

// G1：淺色、五欄、節次列有時間+節次；第一張有標題（1–7 節），第二張沒標題（6–C 節）
let g1: [Block] = [
 Block(name: "資料結構", day: 1, p1: "2", p2: "4"), Block(name: "線性代數", day: 2, p1: "1", p2: "2"),
 Block(name: "計算機組織", day: 3, p1: "3", p2: "4"), Block(name: "機率與統計", day: 5, p1: "2", p2: "3"),
 Block(name: "作業系統", day: 2, p1: "6", p2: "7"), Block(name: "離散數學", day: 4, p1: "6", p2: "7"),
 Block(name: "英文閱讀", day: 1, p1: "8", p2: "9"), Block(name: "體育(游泳)", day: 3, p1: "8", p2: "9"),
 Block(name: "演算法", day: 5, p1: "9", p2: "10"), Block(name: "日文(二)", day: 2, p1: "B", p2: "C"), Block(name: "系統程式", day: 4, p1: "A", p2: "B")]
render(file: "g1_a.jpg", days: wd5, header: true, rows: ["1","2","3","4","6","7"], blocks: g1, style: Style(dark: false, axisMode: 0))
render(file: "g1_b.jpg", days: wd5, header: false, rows: ["6","7","8","9","10","A","B","C"], blocks: g1, style: Style(dark: false, axisMode: 0))
manifest.append(Scenario(name: "G1 淺色五欄(有標題+沒標題)", images: ["g1_a.jpg","g1_b.jpg"], truth: truth(g1)))

// G2：深色、七欄（含週六日）；第一張有標題 1–7，第二張沒標題 6–C
let g2: [Block] = [
 Block(name: "微積分", day: 1, p1: "2", p2: "3"), Block(name: "普通物理", day: 3, p1: "3", p2: "4"),
 Block(name: "專題討論", day: 6, p1: "2", p2: "4"), Block(name: "社團活動", day: 7, p1: "3", p2: "4"),
 Block(name: "電路學", day: 4, p1: "6", p2: "7"), Block(name: "物理實驗", day: 2, p1: "8", p2: "10"),
 Block(name: "補課(週六)", day: 6, p1: "8", p2: "9"), Block(name: "樂團練習", day: 7, p1: "A", p2: "B"), Block(name: "管理學", day: 5, p1: "A", p2: "C")]
render(file: "g2_a.jpg", days: wd7, header: true, rows: ["1","2","3","4","6","7"], blocks: g2, style: Style(dark: true, axisMode: 0))
render(file: "g2_b.jpg", days: wd7, header: false, rows: ["6","7","8","9","10","A","B","C"], blocks: g2, style: Style(dark: true, axisMode: 0))
manifest.append(Scenario(name: "G2 深色七欄(含週六日)", images: ["g2_a.jpg","g2_b.jpg"], truth: truth(g2)))

// G3：同名課在不同天同時段（錨點不唯一）、沒標題那張的週一、週五兩欄是空的
let g3: [Block] = [
 Block(name: "體育(籃球)", day: 1, p1: "3", p2: "4"), Block(name: "體育(籃球)", day: 4, p1: "3", p2: "4"),
 Block(name: "國文", day: 2, p1: "1", p2: "2"), Block(name: "經濟學", day: 3, p1: "6", p2: "7"),
 Block(name: "經濟學", day: 4, p1: "6", p2: "7"), Block(name: "程式設計", day: 3, p1: "8", p2: "10"),
 Block(name: "會計學", day: 2, p1: "9", p2: "10")]
render(file: "g3_a.jpg", days: wd5, header: true, rows: ["1","2","3","4","6","7"], blocks: g3, style: Style(dark: false, axisMode: 0))
let g3b = g3.filter { $0.day >= 2 && $0.day <= 4 }   // 沒標題那張，週一與週五沒課（圖上是空欄）
render(file: "g3_b.jpg", days: wd5, header: false, rows: ["6","7","8","9","10"], blocks: g3b, style: Style(dark: false, axisMode: 0))
manifest.append(Scenario(name: "G3 同名課同時段+邊欄空", images: ["g3_a.jpg","g3_b.jpg"], truth: truth(g3)))

// G4：節次欄只印時間範圍（沒有節次標籤）
let g4: [Block] = [
 Block(name: "高等會計", day: 1, p1: "2", p2: "3"), Block(name: "稅務法規", day: 3, p1: "3", p2: "4"),
 Block(name: "統計學", day: 5, p1: "1", p2: "2"), Block(name: "財務管理", day: 2, p1: "6", p2: "7"),
 Block(name: "行銷學", day: 4, p1: "7", p2: "8")]
render(file: "g4_a.jpg", days: wd5, header: true, rows: ["1","2","3","4","6","7","8"], blocks: g4, style: Style(dark: false, axisMode: 1))
manifest.append(Scenario(name: "G4 只印時間(沒有節次)單張", images: ["g4_a.jpg"], truth: truth(g4)))

// G5：課名長、兩行、有教室；單張有標題
let g5: [Block] = [
 Block(name: "人工智慧導論與應用", day: 1, p1: "2", p2: "4", room: "IB-501"), Block(name: "資料庫系統概論", day: 2, p1: "3", p2: "4", room: "TR-212"),
 Block(name: "數位邏輯設計實驗", day: 3, p1: "6", p2: "8", room: "EE-lab"), Block(name: "技術寫作", day: 5, p1: "2", p2: "3", room: "RB-101"),
 Block(name: "網際網路程式設計", day: 4, p1: "7", p2: "9", room: "IB-302")]
render(file: "g5_a.jpg", days: wd5, header: true, rows: ["1","2","3","4","6","7","8","9"], blocks: g5, style: Style(dark: false, axisMode: 0, showRoom: true))
manifest.append(Scenario(name: "G5 長課名+教室 單張", images: ["g5_a.jpg"], truth: truth(g5)))

// G6：兩張都有標題，各看一半，中間重疊（不同寬度）
let g6: [Block] = [
 Block(name: "有機化學", day: 1, p1: "3", p2: "4"), Block(name: "分析化學", day: 3, p1: "6", p2: "7"),
 Block(name: "物理化學", day: 5, p1: "2", p2: "3"), Block(name: "化學實驗", day: 2, p1: "8", p2: "10"), Block(name: "儀器分析", day: 4, p1: "A", p2: "B")]
render(file: "g6_a.jpg", days: wd5, header: true, rows: ["1","2","3","4","6","7"], blocks: g6, style: Style(dark: true, axisMode: 0))
render(file: "g6_b.jpg", days: wd5, header: true, rows: ["6","7","8","9","10","A","B"], blocks: g6, style: Style(dark: true, axisMode: 0), width: 900)
manifest.append(Scenario(name: "G6 兩張都有標題、不同寬度", images: ["g6_a.jpg","g6_b.jpg"], truth: truth(g6)))

try! JSONEncoder().encode(manifest).write(to: URL(fileURLWithPath: "manifest.json"))
print("generated", manifest.count, "scenarios")
