"""학습에 안 쓴 단어로 정확도를 잰다.

단어마다 두 상황을 흉내 낸다.
  - 잘못된 모드로 친 경우: 올바르게 바꿔 주면 성공 (고침률)
  - 맞는 모드로 친 경우: 건드리면 실패 (오변환율, 사용자가 가장 싫어하는 실수)
문맥 없이 단어 하나만 보고 판단하므로 실제보다 보수적인 숫자다.
"""
import sys
from collections import defaultdict

from hangul import compose, decompose
from hanyoung import ENGLISH_WORD, HANGUL_WORD, KO_CHAT, Detector, load_words, split


def run(det, ko_test, en_test):
    stats = defaultdict(lambda: defaultdict(float))
    mistakes = defaultdict(list)
    for lang, words in (("ko", ko_test), ("en", en_test)):
        for w, c in words:
            wrong_mode = decompose(w) if lang == "ko" else compose(w)[0]
            bucket = "1-2자" if len(w) <= 2 else "3-4자" if len(w) <= 4 else "5자+"
            for key, typed, expect in (("fix", wrong_mode, w), ("keep", w, w)):
                ok = det.convert_word(typed)[0] == expect
                for b in ("전체", bucket):
                    s = stats[(lang, key, b)]
                    s["n"] += 1; s["ok"] += ok; s["wn"] += c; s["wok"] += c * ok
                if not ok and len(mistakes[(lang, key)]) < 12:
                    mistakes[(lang, key)].append(f"{typed}→{det.convert_word(typed)[0]}")
    return stats, mistakes


def main():
    ko_train, ko_test = split(load_words("ko", HANGUL_WORD), 0.1, seed=0)
    en_train, en_test = split(load_words("en", ENGLISH_WORD), 0.1, seed=0)
    print(f"학습: 한국어 {len(ko_train)}, 영어 {len(en_train)} / 평가: 한국어 {len(ko_test)}, 영어 {len(en_test)} 단어\n")

    det = Detector(ko_train + list(KO_CHAT.items()), en_train)
    stats, mistakes = run(det, ko_test, en_test)

    print(f"{'':12}{'':6}{'단어 기준':>10}{'빈도 가중':>10}")
    for lang, name in (("ko", "한국어 단어"), ("en", "영어 단어")):
        for key, label in (("fix", "고침률"), ("keep", "오변환율")):
            for b in ("전체", "1-2자", "3-4자", "5자+"):
                s = stats[(lang, key, b)]
                if not s["n"]:
                    continue
                acc, wacc = s["ok"] / s["n"], s["wok"] / s["wn"]
                if key == "keep":
                    acc, wacc = 1 - acc, 1 - wacc
                print(f"{name:10}{label:5} {b:5}{acc:>9.1%}{wacc:>10.1%}   (n={int(s['n'])})")
        print()

    if "-v" in sys.argv:
        for k, v in mistakes.items():
            print(k, " ".join(v))


if __name__ == "__main__":
    main()
