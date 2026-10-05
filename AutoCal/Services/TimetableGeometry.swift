import Foundation
import Vision
import CoreGraphics
import ImageIO

/// 從課表截圖「量」出每個課程方塊：文字辨識（Vision，離線）+ 像素分析，不靠語言模型估位置。
/// 起訖時間 = 方塊上下緣旁邊那兩個時間文字；星期 = 方塊位置對照星期標題；課名 = 方塊裡面的文字。
struct GeoBlock {
    var name: String
    var startMinute: Int?
    var endMinute: Int?
    var startPeriod: String?
    var endPeriod: String?
    var xCenter: Double          // 方塊水平中心，佔圖片寬度 %
    var weekday: Int             // 0 = 沒有標題或對不上
    var location: String?
    var hasHeader: Bool
    var clippedTop: Bool
    var clippedBottom: Bool
}

enum TimetableGeometry {
    struct Text { var s: String; var x: Double; var y: Double; var w: Double; var h: Double; var conf: Float
        var cx: Double { x + w / 2 }; var cy: Double { y + h / 2 } }

    static let periodTimes: [String: (Int, Int)] = [
        "0": (430, 480), "1": (490, 540), "2": (550, 600), "3": (620, 670), "4": (680, 730), "5": (740, 790),
        "6": (800, 850), "7": (860, 910), "8": (930, 980), "9": (990, 1040), "10": (1050, 1100),
        "A": (1105, 1155), "B": (1160, 1210), "C": (1215, 1265), "D": (1270, 1320)]

    static func analyze(_ img: CGImage) throws -> [GeoBlock] {
        let W = img.width, H = img.height
        let texts = try recognize(img)
        // ---- 左邊的時間文字與節次標籤 ----
        func timeValue(_ s: String) -> Int? {
            let p = s.replacingOccurrences(of: "：", with: ":").split(separator: ":")
            guard p.count == 2, p[0].count <= 2, p[1].count == 2, let h = Int(p[0]), let m = Int(p[1]), h < 24, m < 60 else { return nil }
            return h * 60 + m
        }
        let timeTexts = texts.compactMap { t -> (t: Text, v: Int)? in timeValue(t.s).map { (t, $0) } }
            .filter { $0.t.cx < Double(W) * 0.3 }
        let periodSet = Set(periodTimes.keys)
        let periodTexts = texts.filter { periodSet.contains($0.s.uppercased()) && $0.cx < Double(W) * 0.3 }
        var axisRight = 0.0
        for t in timeTexts.map(\.t) + periodTexts { axisRight = max(axisRight, t.x + t.w) }
        guard axisRight > 0 else { return [] }   // 看不到左邊的時間／節次欄

        // ---- 像素 ----
        var buf = [UInt8](repeating: 0, count: W * H * 4)
        let ctx = CGContext(data: &buf, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
        let x0 = Int(axisRight) + 6
        // 背景色：格子區域最常見的顏色（量化）
        var hist: [Int: Int] = [:]
        for y in stride(from: 0, to: H, by: 7) { for x in stride(from: x0, to: W, by: 7) {
            let i = (y * W + x) * 4
            hist[(Int(buf[i]) >> 3) << 10 | (Int(buf[i+1]) >> 3) << 5 | (Int(buf[i+2]) >> 3), default: 0] += 1 } }
        let bgKey = hist.max { $0.value < $1.value }!.key
        let bg = ((bgKey >> 10) << 3, ((bgKey >> 5) & 31) << 3, (bgKey & 31) << 3)
        // 遮罩 + 侵蝕（去掉細格線與文字筆畫）
        let gw = W - x0
        var mask = [Bool](repeating: false, count: gw * H)
        for y in 0..<H { for x in 0..<gw {
            let i = (y * W + x + x0) * 4
            let d = abs(Int(buf[i]) - bg.0) + abs(Int(buf[i+1]) - bg.1) + abs(Int(buf[i+2]) - bg.2)
            mask[y * gw + x] = d > 45 } }
        let r = 3
        var integral = [Int32](repeating: 0, count: (gw + 1) * (H + 1))
        for y in 0..<H { var row: Int32 = 0; for x in 0..<gw {
            row += mask[y * gw + x] ? 1 : 0
            integral[(y + 1) * (gw + 1) + x + 1] = integral[y * (gw + 1) + x + 1] + row } }
        func full(_ x: Int, _ y: Int) -> Bool {
            let xa = x - r, ya = y - r, xb = x + r + 1, yb = y + r + 1
            guard xa >= 0, ya >= 0, xb <= gw, yb <= H else { return false }
            let s = integral[yb * (gw + 1) + xb] - integral[ya * (gw + 1) + xb] - integral[yb * (gw + 1) + xa] + integral[ya * (gw + 1) + xa]
            return s == Int32((2 * r + 1) * (2 * r + 1))
        }
        var eroded = [Bool](repeating: false, count: gw * H)
        for y in 0..<H { for x in 0..<gw where mask[y * gw + x] { eroded[y * gw + x] = full(x, y) } }
        // 連通元件（4 鄰接，stack）
        var label = [Int32](repeating: 0, count: gw * H)
        struct Box { var minX: Int, minY: Int, maxX: Int, maxY: Int, area: Int }
        var boxes: [Box] = []
        var next: Int32 = 0
        for sy in 0..<H { for sx in 0..<gw where eroded[sy * gw + sx] && label[sy * gw + sx] == 0 {
            next += 1
            var b = Box(minX: sx, minY: sy, maxX: sx, maxY: sy, area: 0)
            var stack = [(sx, sy)]; label[sy * gw + sx] = next
            while let (x, y) = stack.popLast() {
                b.area += 1; b.minX = min(b.minX, x); b.maxX = max(b.maxX, x); b.minY = min(b.minY, y); b.maxY = max(b.maxY, y)
                for (dx, dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0, ny >= 0, nx < gw, ny < H, eroded[ny * gw + nx], label[ny * gw + nx] == 0 { label[ny * gw + nx] = next; stack.append((nx, ny)) } } }
            boxes.append(b) } }
        // 每個方塊：把侵蝕掉的邊界補回來；太小或太空的不是課程方塊
        let blocksPx = boxes.compactMap { b -> (x: Double, y: Double, w: Double, h: Double)? in
            let w = b.maxX - b.minX + 1 + 2 * r, h = b.maxY - b.minY + 1 + 2 * r
            guard w >= 60, h >= 40, Double(b.area) / Double(w * h) > 0.55 else { return nil }
            return (Double(b.minX - r + x0), Double(b.minY - r), Double(w), Double(h))
        }
        guard !blocksPx.isEmpty else { return [] }

        // ---- 星期標題：在所有方塊上面的單一星期字 ----
        let firstTop = blocksPx.map(\.y).min()!
        let wdChars: [Character: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7]
        // 欄距：方塊水平位置分群後，相鄰兩欄的最小間距（只有一欄或沒有方塊時不知道）
        let bx = blocksPx.map { $0.x + $0.w / 2 }.sorted()
        var colXs: [Double] = []
        for x in bx { if let l = colXs.last, x - l < 30 { continue }; colXs.append(x) }
        let gaps = zip(colXs, colXs.dropFirst()).map { $1 - $0 }.filter { $0 > 60 }
        let pitchPx = gaps.min()
        var headerPts: [(w: Double, x: Double)] = []
        for t in texts where t.cy < firstTop && t.cx > axisRight {
            let s = t.s.replacingOccurrences(of: "週", with: "").replacingOccurrences(of: "周", with: "").replacingOccurrences(of: "星期", with: "")
            let chars = Array(s)
            guard !chars.isEmpty, chars.count <= 7, chars.allSatisfy({ wdChars[$0] != nil }) else { continue }
            if chars.count == 1 {
                headerPts.append((Double(wdChars[chars[0]]!), t.cx))
            } else if let p = pitchPx {
                // 相鄰的星期字被辨識成同一行（例如「三四五六日」常漏掉一個字）：
                // 用欄距推算它實際涵蓋幾欄，星期一定是連續的，從第一個字往後數。
                let slots = Int(((t.w - t.h) / p).rounded()) + 1
                guard slots >= chars.count, slots <= chars.count + 2, slots <= 7 else { continue }
                let first = wdChars[chars[0]]!
                guard first + slots - 1 <= 7 else { continue }
                for j in 0..<slots { headerPts.append((Double(first + j), t.x + t.h / 2 + Double(j) * p)) }
            }
        }
        var fit: (a: Double, b: Double)? = nil
        if Set(headerPts.map(\.w)).count >= 2 {
            let n = Double(headerPts.count), mw = headerPts.map(\.w).reduce(0, +) / n, mx = headerPts.map(\.x).reduce(0, +) / n
            let v = headerPts.map { ($0.w - mw) * ($0.w - mw) }.reduce(0, +)
            let slope = headerPts.map { ($0.w - mw) * ($0.x - mx) }.reduce(0, +) / v
            let icept = mx - slope * mw
            // 一致性：每個標題點離直線不能太遠（超過半個欄距就代表有讀錯的，整個標題不採用，改請使用者確認）
            let resid = headerPts.map { abs($0.x - (icept + slope * $0.w)) }.max() ?? 0
            if slope > Double(W) * 0.05, resid <= slope * 0.25 {
                fit = ((icept) / Double(W) * 100, slope / Double(W) * 100)
            }
        }

        // ---- 節次標籤的列位置（備援：沒有時間文字時）----
        let sortedPeriods = periodTexts.sorted { $0.cy < $1.cy }
        var pitch = 0.0
        let ys = (timeTexts.map { $0.t.cy }).sorted()
        if ys.count >= 3 { pitch = median(zip(ys, ys.dropFirst(2)).map { $1 - $0 }) }
        else if sortedPeriods.count >= 2 { pitch = median(zip(sortedPeriods, sortedPeriods.dropFirst()).map { $1.cy - $0.cy }) }

        var out: [GeoBlock] = []
        for b in blocksPx {
            let top = b.y, bottom = b.y + b.h
            let clippedTop = top <= 3, clippedBottom = bottom >= Double(H) - 3
            let win = max(pitch * 0.62, 40)
            // 起：方塊上緣往下一小段內，最近的時間文字；訖：下緣往上一小段內，最近的時間文字
            let startCand = timeTexts.filter { $0.t.cy >= top - 4 && $0.t.cy <= top + win }.min { abs($0.t.cy - top) < abs($1.t.cy - top) }
            let endCand = timeTexts.filter { $0.t.cy <= bottom + 4 && $0.t.cy >= bottom - win }.min { abs($0.t.cy - bottom) < abs($1.t.cy - bottom) }
            var sm = startCand?.v, em = endCand?.v
            var sp: String? = nil, ep: String? = nil
            if sm == nil || em == nil, pitch > 0, !sortedPeriods.isEmpty {
                // 備援：節次標籤是每列的中心
                func row(near y: Double) -> String? { sortedPeriods.min { abs($0.cy - y) < abs($1.cy - y) }.flatMap { abs($0.cy - y) <= pitch * 0.55 ? $0.s.uppercased() : nil } }
                if sm == nil, let p = row(near: top + pitch / 2), let t = periodTimes[p] { sm = t.0; sp = p }
                if em == nil, let p = row(near: bottom - pitch / 2), let t = periodTimes[p] { em = t.1; ep = p }
            }
            // 課名：中心在方塊裡面的文字
            let inside = texts.filter { $0.cx >= b.x && $0.cx <= b.x + b.w && $0.cy >= top && $0.cy <= bottom }
                .sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            func norm(_ x: String) -> String { x.replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")").filter { !$0.isWhitespace } }
            var lines = inside.map { norm($0.s) }
            // 最後一行像教室代號（英文字母＋數字，例如 IB-501、EE-lab、TR-212）就當成地點，不併進課名
            var location: String? = nil
            if lines.count >= 2, let last = lines.last,
               last.range(of: "^[A-Za-z]{1,4}[-－–]?[A-Za-z0-9]{1,6}$", options: .regularExpression) != nil,
               last.contains(where: \.isNumber) || last.contains("-") {
                location = last; lines.removeLast()
            }
            let name = lines.joined()
            let xc = (b.x + b.w / 2) / Double(W) * 100
            var wd = 0
            if let f = fit {
                let c = (1...7).compactMap { w -> (Int, Double)? in let x = f.a + f.b * Double(w); return x > -5 && x < 105 ? (w, x) : nil }
                if let best = c.min(by: { abs($0.1 - xc) < abs($1.1 - xc) }) { wd = best.0 }
            }
            out.append(GeoBlock(name: name, startMinute: sm, endMinute: em, startPeriod: sp, endPeriod: ep,
                                xCenter: xc, weekday: wd, location: location, hasHeader: fit != nil, clippedTop: clippedTop, clippedBottom: clippedBottom))
        }
        return out.sorted { ($0.xCenter, $0.startMinute ?? 0) < ($1.xCenter, $1.startMinute ?? 0) }
    }

    static func median(_ a: [Double]) -> Double { let s = a.sorted(); return s.isEmpty ? 0 : s[s.count / 2] }

    static func recognize(_ img: CGImage) throws -> [Text] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["zh-Hant", "en-US"]
        req.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: img, options: [:]).perform([req])
        let W = Double(img.width), H = Double(img.height)
        return (req.results ?? []).compactMap { o in
            guard let t = o.topCandidates(1).first else { return nil }
            let b = o.boundingBox
            return Text(s: t.string, x: b.minX * W, y: (1 - b.maxY) * H, w: b.width * W, h: b.height * H, conf: t.confidence)
        }
    }
}
