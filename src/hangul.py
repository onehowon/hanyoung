"""두벌식 자판의 키 입력 <-> 한글 변환."""

CHO = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"
JUNG = "ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ"
JONG = ["", *"ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ"]

KEY_TO_JAMO = dict(zip(
    "qwertyuiopasdfghjklzxcvbnmQWERTOP",
    "ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔㅁㄴㅇㄹㅎㅗㅓㅏㅣㅋㅌㅊㅍㅠㅜㅡㅃㅉㄸㄲㅆㅒㅖ",
))
JAMO_TO_KEY = {j: k for k, j in KEY_TO_JAMO.items()}

# 겹모음, 겹받침: (앞, 뒤) -> 합친 글자
VOWEL_PAIRS = {("ㅗ", "ㅏ"): "ㅘ", ("ㅗ", "ㅐ"): "ㅙ", ("ㅗ", "ㅣ"): "ㅚ", ("ㅜ", "ㅓ"): "ㅝ",
               ("ㅜ", "ㅔ"): "ㅞ", ("ㅜ", "ㅣ"): "ㅟ", ("ㅡ", "ㅣ"): "ㅢ"}
FINAL_PAIRS = {("ㄱ", "ㅅ"): "ㄳ", ("ㄴ", "ㅈ"): "ㄵ", ("ㄴ", "ㅎ"): "ㄶ", ("ㄹ", "ㄱ"): "ㄺ",
               ("ㄹ", "ㅁ"): "ㄻ", ("ㄹ", "ㅂ"): "ㄼ", ("ㄹ", "ㅅ"): "ㄽ", ("ㄹ", "ㅌ"): "ㄾ",
               ("ㄹ", "ㅍ"): "ㄿ", ("ㄹ", "ㅎ"): "ㅀ", ("ㅂ", "ㅅ"): "ㅄ"}
SPLIT = {v: k for k, v in {**VOWEL_PAIRS, **FINAL_PAIRS}.items()}


def is_vowel(j):
    return j in JUNG


def compose(keys):
    """키 입력을 두벌식 오토마타로 조합한다. (결과 문자열, 혼자 남은 자모 수)"""
    out, orphans = [], 0
    cho = jung = jong = ""

    def flush():
        nonlocal cho, jung, jong, orphans
        if cho and jung:
            out.append(chr(0xAC00 + (CHO.index(cho) * 21 + JUNG.index(jung)) * 28 + JONG.index(jong)))
        elif cho or jung:
            out.append(cho or jung)
            orphans += 1
        cho = jung = jong = ""

    for k in keys:
        j = KEY_TO_JAMO.get(k) or KEY_TO_JAMO.get(k.lower())
        if j is None:
            flush()
            out.append(k)
        elif is_vowel(j):
            if jong:
                # 받침이 다음 글자의 초성으로 넘어간다 (겹받침은 뒷자리만)
                first, moved = SPLIT.get(jong, ("", jong))
                jong = first
                flush()
                cho, jung = moved, j
            elif jung and (jung, j) in VOWEL_PAIRS and cho:
                jung = VOWEL_PAIRS[(jung, j)]
            elif cho and not jung:
                jung = j
            else:
                flush()
                jung = j
        else:
            if cho and jung and not jong and j in JONG:
                jong = j
            elif jong and (jong, j) in FINAL_PAIRS:
                jong = FINAL_PAIRS[(jong, j)]
            else:
                flush()
                cho = j
    flush()
    return "".join(out), orphans


def _jamo_keys(j):
    return "".join(JAMO_TO_KEY[p] for p in SPLIT.get(j, (j,)))


def decompose(text):
    """한글을 그 글자를 치는 데 필요한 키 입력으로 바꾼다."""
    out = []
    for ch in text:
        code = ord(ch) - 0xAC00
        if 0 <= code < 11172:
            out += [_jamo_keys(j) for j in (CHO[code // 588], JUNG[code % 588 // 28], JONG[code % 28]) if j]
        elif ch in JAMO_TO_KEY or ch in SPLIT:
            out.append(_jamo_keys(ch))
        else:
            out.append(ch)
    return "".join(out)
