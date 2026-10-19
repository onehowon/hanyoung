import Foundation

/// src/hanyoung.py의 판별기를 옮긴 것. 모델 값은 src/export_model.py가 만든 model.json에서 읽는다.
final class CharLM {
    typealias Entry = (total: Double, types: Double, next: [String: Double])
    let order: Int
    let base: Double
    let ctx: [String: Entry]

    init(_ json: [String: Any]) {
        order = json["order"] as! Int
        base = 1 / Double((json["vocab"] as! Int) + 1)
        var ctx: [String: Entry] = [:]
        for (c, v) in json["ctx"] as! [String: [Any]] {
            ctx[c] = ((v[0] as! NSNumber).doubleValue, (v[1] as! NSNumber).doubleValue,
                      (v[2] as! [String: NSNumber]).mapValues(\.doubleValue))
        }
        self.ctx = ctx
    }

    /// 보간 Witten-Bell 스무딩 로그 확률
    func logprob(_ keys: String) -> Double {
        let seq = Array(String(repeating: "^", count: order - 1) + keys + "$")
        var sum = 0.0
        for i in (order - 1)..<seq.count {
            let ch = String(seq[i])
            var p = base
            for n in 0..<order {
                guard let e = ctx[String(seq[(i - n)..<i])] else { break }
                let lam = e.total / (e.total + e.types)
                p = lam * (e.next[ch] ?? 0) / e.total + (1 - lam) * p
            }
            sum += log(p)
        }
        return sum
    }
}

enum Action { case keep, skip, toEnglish, toKorean }

struct Decision {
    let output: String
    let action: Action
    let confidence: Double
}

final class Detector {
    let ko: CharLM, en: CharLM
    let koDict: Set<String>, enDict: Set<String>
    let orphanPenalty: Double, dictBonus: Double, margin: Double, contextBonus: Double

    init(contentsOf url: URL) throws {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let p = json["params"] as! [String: Double]
        orphanPenalty = p["orphan_penalty"]!
        dictBonus = p["dict_bonus"]!
        margin = p["margin"]!
        contextBonus = p["context_bonus"]!
        ko = CharLM(json["ko"] as! [String: Any])
        en = CharLM(json["en"] as! [String: Any])
        koDict = Set(json["ko_dict"] as! [String])
        enDict = Set(json["en_dict"] as! [String])
    }

    func scores(_ keys: String) -> (ko: Double, en: Double, hangul: String) {
        let (hangul, orphans) = Hangul.compose(keys)
        let ko = self.ko.logprob(keys) + (koDict.contains(hangul) ? dictBonus : -orphanPenalty * Double(orphans))
        let low = keys.lowercased()
        let en = self.en.logprob(low) + (enDict.contains(low) ? dictBonus : 0)
        return (ko, en, hangul)
    }

    /// 사용자가 친 단어 하나를 보고, 바꿔야 하면 바꾼 결과를 돌려준다.
    func decide(_ word: String, bias: Double = 0) -> Decision {
        let skip = Decision(output: word, action: .skip, confidence: 0)
        // 앞뒤 문장부호는 떼어 두고 가운데만 판단한다 ("gody?" -> "해요?")
        let isWord: (Character) -> Bool = { $0.isLetter || $0.isNumber || $0 == "_" }
        let chars = Array(word)
        guard let start = chars.firstIndex(where: isWord), let end = chars.lastIndex(where: isWord) else { return skip }
        let head = String(chars[..<start]), core = String(chars[start...end]), tail = String(chars[(end + 1)...])
        let hasKo = core.contains { $0.isHangul }, hasEn = core.contains { $0.isEnglishLetter }
        let keys = hasKo ? Hangul.decompose(core) : core
        // 숫자, 기호, "github에"처럼 섞인 입력은 일부러 친 것이다
        guard hasKo != hasEn, keys.allSatisfy({ $0.isEnglishLetter }) else { return skip }

        let s = scores(keys)
        let diff = s.en - s.ko + bias  // 양수면 영어 쪽이 더 그럴듯함
        if hasKo && diff > margin { return Decision(output: head + keys + tail, action: .toEnglish, confidence: diff) }
        if hasEn && -diff > margin { return Decision(output: head + s.hangul + tail, action: .toKorean, confidence: -diff) }
        return Decision(output: word, action: .keep, confidence: abs(diff))
    }

    /// 판단의 언어: 영어 +1, 한글 -1, 애매하면 0
    func language(of d: Decision) -> Int {
        if d.action == .skip || (d.action == .keep && d.confidence < margin) { return 0 }
        return d.output.contains { $0.isEnglishLetter } ? 1 : -1
    }

    /// 애매한 단어는 옆 단어들의 언어 쪽으로 기울여 한 번 더 판단한다.
    func decide(_ word: String, neighbors: Int) -> Decision {
        let d = decide(word)
        guard d.action == .keep, d.confidence < margin, neighbors != 0 else { return d }
        return decide(word, bias: contextBonus * Double(neighbors))
    }

    /// 문장 전체 (테스트용, 파이썬의 analyze와 같다)
    func analyze(_ words: [String]) -> [Decision] {
        let first = words.map { decide($0) }
        return words.indices.map { i in
            let around = [i - 1, i + 1].filter(first.indices.contains).map { language(of: first[$0]) }.reduce(0, +)
            return decide(words[i], neighbors: around)
        }
    }
}
