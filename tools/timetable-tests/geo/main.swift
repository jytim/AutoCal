import Foundation
import ImageIO
// usage: geo in.jpg [out.json]  → 輸出成和語言模型相同格式的 JSON，方便用同一套合併與計分程式比較
let path = CommandLine.arguments[1]
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
func hm(_ m: Int?) -> Any { m.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) as Any } ?? NSNull() }
let t0 = Date()
let bs = try TimetableGeometry.analyze(img)
if CommandLine.arguments.count > 2 {
    let arr: [[String: Any]] = bs.map { b in
        ["name": b.name, "weekday": b.weekday, "hasHeader": b.hasHeader, "axisType": "time",
         "start": hm(b.startMinute), "end": hm(b.endMinute), "xCenter": b.xCenter,
         "location": (b.location as Any?) ?? NSNull()]
    }
    try JSONSerialization.data(withJSONObject: arr).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
print("\(path.split(separator: "/").last!): \(bs.count) blocks in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
