/// 두벌식 자판의 키 입력 <-> 한글 변환. src/hangul.py와 같은 규칙.
enum Hangul {
    static let cho = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    static let jung = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    static let jong = Array(" ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")  // 0번은 받침 없음

    static let keyToJamo = Dictionary(uniqueKeysWithValues: zip(
        "qwertyuiopasdfghjklzxcvbnmQWERTOP",
        "ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔㅁㄴㅇㄹㅎㅗㅓㅏㅣㅋㅌㅊㅍㅠㅜㅡㅃㅉㄸㄲㅆㅒㅖ"))
    static let jamoToKey = Dictionary(uniqueKeysWithValues: keyToJamo.map { ($0.value, $0.key) })

    // 겹모음, 겹받침: 앞뒤 자모 -> 합친 글자
    static let vowelPairs: [String: Character] = [
        "ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ", "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ", "ㅡㅣ": "ㅢ"]
    static let finalPairs: [String: Character] = [
        "ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ", "ㄹㄱ": "ㄺ", "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ",
        "ㄹㅅ": "ㄽ", "ㄹㅌ": "ㄾ", "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ"]
    static let split: [Character: [Character]] = Dictionary(
        uniqueKeysWithValues: vowelPairs.merging(finalPairs) { a, _ in a }.map { ($0.value, Array($0.key)) })

    /// 키 입력을 두벌식 오토마타로 조합한다. 혼자 남은 자모 수도 같이 돌려준다.
    static func compose(_ keys: String) -> (text: String, orphans: Int) {
        var out = "", orphans = 0
        var initial: Character?, medial: Character?, final: Character?

        func flush() {
            if let i = initial, let m = medial {
                let f = final.map { jong.firstIndex(of: $0)! } ?? 0
                let code = 0xAC00 + (cho.firstIndex(of: i)! * 21 + jung.firstIndex(of: m)!) * 28 + f
                out.append(Character(Unicode.Scalar(code)!))
            } else if let j = initial ?? medial {
                out.append(j)
                orphans += 1
            }
            initial = nil; medial = nil; final = nil
        }

        for k in keys {
            guard let j = keyToJamo[k] ?? keyToJamo[Character(k.lowercased())] else {
                flush()
                out.append(k)
                continue
            }
            if jung.contains(j) {
                if let f = final {
                    // 받침이 다음 글자의 초성으로 넘어간다 (겹받침은 뒷자리만)
                    let parts = split[f]
                    final = parts?[0]
                    flush()
                    initial = parts?[1] ?? f
                    medial = j
                } else if let m = medial, initial != nil, let pair = vowelPairs[String([m, j])] {
                    medial = pair
                } else if initial != nil && medial == nil {
                    medial = j
                } else {
                    flush()
                    medial = j
                }
            } else {
                if initial != nil, medial != nil, final == nil, jong.contains(j) {
                    final = j
                } else if let f = final, let pair = finalPairs[String([f, j])] {
                    final = pair
                } else {
                    flush()
                    initial = j
                }
            }
        }
        flush()
        return (out, orphans)
    }

    private static func keys(for jamo: Character) -> String {
        String((split[jamo] ?? [jamo]).compactMap { jamoToKey[$0] })
    }

    /// 한글을 그 글자를 치는 데 필요한 키 입력으로 바꾼다.
    static func decompose(_ text: String) -> String {
        var out = ""
        for ch in text {
            let scalars = ch.unicodeScalars
            if scalars.count == 1, let s = scalars.first, (0xAC00..<0xAC00 + 11172).contains(s.value) {
                let code = Int(s.value) - 0xAC00
                out += keys(for: cho[code / 588]) + keys(for: jung[code % 588 / 28])
                if code % 28 > 0 { out += keys(for: jong[code % 28]) }
            } else if jamoToKey[ch] != nil || split[ch] != nil {
                out += keys(for: ch)
            } else {
                out.append(ch)
            }
        }
        return out
    }
}

extension Character {
    var isHangul: Bool {
        guard unicodeScalars.count == 1, let v = unicodeScalars.first?.value else { return false }
        return (0x3131...0x3163).contains(v) || (0xAC00...0xD7A3).contains(v)
    }

    var isEnglishLetter: Bool { isASCII && isLetter }
}
