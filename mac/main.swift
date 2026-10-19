import Cocoa

// Hanyoung --test "dd rPthrgo"  : 권한 없이 판별 결과만 출력 (파이썬 결과와 비교용)
let args = CommandLine.arguments
guard let modelURL = Bundle.main.url(forResource: "model", withExtension: "json"),
      let detector = try? Detector(contentsOf: modelURL) else {
    FileHandle.standardError.write("model.json을 찾을 수 없습니다. mac/build.sh로 빌드하세요.\n".data(using: .utf8)!)
    exit(1)
}

if args.count > 2, args[1] == "--test" {
    let words = args[2].split(separator: " ").map(String.init)
    for (w, d) in zip(words, detector.analyze(words)) {
        print(w, "→", d.output, d.action, String(format: "%.1f", d.confidence))
    }
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let auto: AutoSwitch
    var item: NSStatusItem!
    var waiting: Timer?

    init(detector: Detector) {
        auto = AutoSwitch(detector: detector)
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        auto.onChange = { [weak self] in self?.refresh() }
        if !auto.start() {
            // 손쉬운 사용 권한을 켜면 바로 시작한다
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            waiting = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
                if self?.auto.start() == true { t.invalidate(); self?.refresh() }
            }
        }
        refresh()
    }

    func refresh() {
        let running = waiting?.isValid != true
        item.button?.title = auto.enabled && running ? "가A" : "가A ⏸"
        let menu = NSMenu()
        if !running {
            menu.addItem(withTitle: "손쉬운 사용 권한을 켜 주세요", action: nil, keyEquivalent: "")
        }
        let toggle = menu.addItem(withTitle: "자동 한/영 변환", action: #selector(toggle), keyEquivalent: "")
        toggle.state = auto.enabled ? .on : .off
        if let c = auto.lastChange {
            menu.addItem(withTitle: "최근: \(c.from) → \(c.to)  (바로 ⌫ 누르면 되돌림)", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "되돌린 단어 \(auto.ignoredCount)개 잊기", action: #selector(clearIgnored), keyEquivalent: "")
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for i in menu.items where i.action != #selector(NSApplication.terminate(_:)) { i.target = self }
        item.menu = menu
    }

    @objc func toggle() {
        auto.enabled.toggle()
        refresh()
    }

    @objc func clearIgnored() {
        auto.clearIgnored()
        refresh()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate(detector: detector)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
