import Carbon
import Cocoa

/// 키 입력을 지켜보다가 띄어쓰기 순간 방금 친 단어를 판단하고, 잘못된 언어면 지우고 다시 입력한다.
final class AutoSwitch {
    let detector: Detector
    var enabled = true
    var onChange: (() -> Void)?
    private(set) var lastChange: (from: String, to: String)?

    private var tap: CFMachPort?
    private var keys = ""        // 지금 치는 단어의 물리 키 입력 (쉬프트면 대문자)
    private var clean = true     // 글자 키만 쳤는지. 숫자, 기호, 백스페이스가 섞이면 이번 단어는 건드리지 않는다
    private var previous = 0     // 앞 단어의 언어: 영어 +1, 한글 -1
    private var undoable: (original: String, replacement: String, source: TISInputSource)?
    private var ignored: Set<String>

    private let marker: Int64 = 0x4859_4F55  // 우리가 보낸 키 이벤트 표시
    private let source = CGEventSource(stateID: .privateState)
    private let ignoredURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Hanyoung/ignored.txt")
    // 터미널, 코드 편집기에서는 일부러 친 영문 약어가 많아 끈다
    private let excludedApps: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode", "com.jetbrains.intellij",
    ]
    // ANSI 배열의 키 코드 -> 글자
    private let letters: [Int64: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 12: "q", 13: "w",
        14: "e", 15: "r", 16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m",
    ]

    init(detector: Detector) {
        self.detector = detector
        let saved = (try? String(contentsOf: ignoredURL, encoding: .utf8)) ?? ""
        ignored = Set(saved.split(separator: "\n").map(String.init))
    }

    var ignoredCount: Int { ignored.count }

    func clearIgnored() {
        ignored = []
        try? FileManager.default.removeItem(at: ignoredURL)
    }

    /// 손쉬운 사용 권한이 없으면 false
    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, info in
            let me = Unmanaged<AutoSwitch>.fromOpaque(info!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = me.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return me.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        return true
    }

    /// true를 돌려주면 그 키 입력을 삼킨다
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == marker { return false }
        guard type == .keyDown else { reset(); return false }  // 클릭하면 커서가 옮겨졌을 수 있다

        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let lastUndo = undoable
        undoable = nil
        if !flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate]) { reset(); return false }

        switch code {
        case 49:  // space
            finishWord()
        case 51:  // delete
            if let u = lastUndo, keys.isEmpty {
                undo(u)
                return true
            }
            // 영문은 한 번에 한 글자, 한글 입력기는 상황에 따라 자모나 글자 단위로 지워서 키 입력과 맞추기 어렵다
            if !keys.isEmpty, !isKorean(currentSource()) { keys.removeLast() } else { clean = false }
        case 36, 48, 53, 76, 115...126:  // return, tab, esc, enter, 이동 키
            reset()
        default:
            if let ch = letters[code] {
                keys.append(flags.contains(.maskShift) ? Character(ch.uppercased()) : ch)
            } else {
                clean = false
            }
        }
        return false
    }

    private func reset() {
        keys = ""
        clean = true
    }

    private func finishWord() {
        defer { reset() }
        guard enabled, clean, !keys.isEmpty, !IsSecureEventInputEnabled() else { return }
        if let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, excludedApps.contains(app) { return }

        let current = currentSource()
        let korean = isKorean(current)
        if korean && !sourceID(current).contains("2Set") { return }  // 두벌식만 지원
        let onScreen = korean ? Hangul.compose(keys).text : keys
        if ignored.contains(onScreen) { return }

        let d = detector.decide(onScreen, neighbors: previous)
        previous = detector.language(of: d)
        guard d.action == .toEnglish || d.action == .toKorean,
              let target = d.action == .toKorean ? koreanSource() : englishSource() else { return }

        replace(count: onScreen.count + 1, with: d.output + " ", then: target)
        undoable = (onScreen, d.output, current)
        lastChange = (onScreen, d.output)
        onChange?()
    }

    /// 변환 직후 백스페이스: 원래대로 되돌리고 그 단어는 앞으로 바꾸지 않는다
    private func undo(_ u: (original: String, replacement: String, source: TISInputSource)) {
        ignored.insert(u.original)
        try? FileManager.default.createDirectory(at: ignoredURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? ignored.sorted().joined(separator: "\n").write(to: ignoredURL, atomically: true, encoding: .utf8)
        replace(count: u.replacement.count + 1, with: u.original, then: u.source)
        lastChange = nil
        onChange?()
    }

    /// 띄어쓰기가 화면에 들어가 한글 조합이 끝난 뒤에 지우고 다시 친다.
    /// 다시 칠 때는 한글 입력기가 끼어들지 않도록 영문 자판으로 바꿔 둔다.
    private func replace(count: Int, with text: String, then target: TISInputSource) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [self] in
            if let abc = englishSource() { TISSelectInputSource(abc) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [self] in
                for _ in 0..<count { press(51) }
                for ch in text {
                    if ch == " " { press(49) } else { type(ch) }
                }
                TISSelectInputSource(target)
            }
        }
    }

    private func press(_ key: CGKeyCode) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
            e.setIntegerValueField(.eventSourceUserData, value: marker)
            e.post(tap: .cgSessionEventTap)
        }
    }

    private func type(_ ch: Character) {
        let utf16 = Array(String(ch).utf16)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
            e.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            e.setIntegerValueField(.eventSourceUserData, value: marker)
            e.post(tap: .cgSessionEventTap)
        }
    }

    // MARK: 입력 소스

    private func currentSource() -> TISInputSource { TISCopyCurrentKeyboardInputSource().takeRetainedValue() }

    private func englishSource() -> TISInputSource? { TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() }

    private func koreanSource() -> TISInputSource? {
        let filter = [kTISPropertyInputSourceIsSelectCapable as String: true] as CFDictionary
        let list = TISCreateInputSourceList(filter, false).takeRetainedValue() as! [TISInputSource]
        return list.first { sourceID($0).hasPrefix("com.apple.inputmethod.Korean.2Set") }
    }

    private func sourceID(_ s: TISInputSource) -> String {
        guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    }

    private func isKorean(_ s: TISInputSource) -> Bool { sourceID(s).contains("Korean") }
}
