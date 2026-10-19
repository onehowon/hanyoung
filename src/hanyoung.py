"""한/영 자동 판별기.

같은 키 입력을 영어로 읽었을 때와 두벌식 한글로 읽었을 때, 각 언어 모델에서의
로그 확률을 비교한다. 두 언어 모두 '키 입력 문자열' 공간에서 학습하기 때문에
사용자가 어느 모드로 쳤든 같은 기준으로 판단할 수 있다.

    python3 hanyoung.py "dd rPthrgo 녀ㅔㄷ게ㅐㅈㄷㄱ"
"""
import math
import os
import random
import re
import sys
from collections import defaultdict

from hangul import compose, decompose

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "data", "raw")

ORDER = 5
ORPHAN_PENALTY = 4.0   # 조합되지 않고 혼자 남은 자모 하나당 한국어 점수 감점 (nats)
DICT_BONUS = 3.0       # 사전에 있는 단어면 가산점
MARGIN = 2.0           # 이만큼 확실할 때만 바꾼다 (잘못 바꾸는 게 안 바꾸는 것보다 훨씬 거슬리므로)
CONTEXT_BONUS = 3.0    # 애매한 단어는 확실한 옆 단어의 언어 쪽으로 기운다 ("dd rPthrgo" -> "ㅇㅇ 계속해")

HANGUL_WORD = re.compile(r"^[가-힣]+$")
# 자막 말뭉치에 없는 채팅체. 키 입력으로는 영어처럼 보여도(dd, zz) 한글이 맞는 경우가 많다
KO_CHAT = {w: 3000 for w in "ㅋㅋ ㅋㅋㅋ ㅋㅋㅋㅋ ㅎㅎ ㅎㅎㅎ ㅇㅇ ㅇㅋ ㅠㅠ ㅜㅜ ㄱㄱ ㄴㄴ ㄱㅅ ㅈㅅ ㅊㅋ ㅂㅂ ㅎㅇ ㄷㄷ ㅇㅈ".split()}
ENGLISH_WORD = re.compile(r"^[a-z]+$")


def load_words(lang, pattern, limit=50000):
    words = []
    with open(os.path.join(RAW, f"{lang}_50k.txt"), encoding="utf-8") as f:
        for line in f.readlines()[:limit]:
            w, c = line.split()
            if pattern.match(w):
                words.append((w, int(c)))
    return words


class CharLM:
    """보간 Witten-Bell 스무딩을 쓴 문자 n-gram 모델."""

    def __init__(self, order=ORDER):
        self.order = order
        self.counts = defaultdict(lambda: defaultdict(float))
        self.vocab = set()

    def train(self, samples):
        for keys, weight in samples:
            seq = "^" * (self.order - 1) + keys + "$"
            for i in range(self.order - 1, len(seq)):
                self.vocab.add(seq[i])
                for n in range(self.order):
                    self.counts[seq[i - n:i]][seq[i]] += weight
        # 확률 계산에 필요한 합계, 종류 수를 미리 계산
        self.totals = {ctx: (sum(nx.values()), len(nx)) for ctx, nx in self.counts.items()}
        self.counts = {ctx: dict(nx) for ctx, nx in self.counts.items()}

    def prob(self, ctx, ch):
        p = 1 / (len(self.vocab) + 1)
        for n in range(self.order):
            c = ctx[len(ctx) - n:] if n else ""
            if c not in self.totals:
                break
            total, types = self.totals[c]
            lam = total / (total + types)
            p = lam * self.counts[c].get(ch, 0) / total + (1 - lam) * p
        return p

    def logprob(self, keys):
        seq = "^" * (self.order - 1) + keys + "$"
        return sum(math.log(self.prob(seq[i - self.order + 1:i], seq[i])) for i in range(self.order - 1, len(seq)))


class Detector:
    def __init__(self, ko_words, en_words):
        # 빈도의 로그를 가중치로: 자주 쓰는 단어를 더 반영하되 몇몇 단어가 독점하지 않게
        self.ko = CharLM()
        self.ko.train((decompose(w), math.log1p(c)) for w, c in ko_words)
        self.en = CharLM()
        self.en.train((w, math.log1p(c)) for w, c in en_words)
        self.ko_dict = {w for w, _ in ko_words}
        self.en_dict = {w for w, _ in en_words}

    def scores(self, keys):
        """키 입력 -> (한국어 점수, 영어 점수, 한글 조합 결과). 점수는 로그 확률(nats)."""
        hangul, orphans = compose(keys)
        known = hangul in self.ko_dict
        ko = self.ko.logprob(keys) + (DICT_BONUS if known else -ORPHAN_PENALTY * orphans)
        low = keys.lower()
        en = self.en.logprob(low) + DICT_BONUS * (low in self.en_dict)
        return ko, en, hangul

    def convert_word(self, word, bias=0.0):
        """사용자가 친 단어 하나를 받아, 바꿔야 하면 바꾼 결과를 돌려준다. (결과, 판단, 확신도)"""
        # 앞뒤 문장부호는 떼어 두고 가운데만 판단한다 ("해요?" -> "해요")
        head, core, tail = re.fullmatch(r"([^\w]*)(.*?)([^\w]*)", word).groups()
        has_ko, has_en = bool(re.search(r"[ㄱ-ㅣ가-힣]", core)), bool(re.search(r"[A-Za-z]", core))
        keys = decompose(core) if has_ko else core
        if has_ko == has_en or not re.fullmatch(r"[A-Za-z]+", keys):
            return word, "skip", 0.0  # 숫자, 기호, "github에"처럼 섞인 입력은 일부러 친 것이다
        ko, en, hangul = self.scores(keys)
        diff = en - ko + bias  # 양수면 영어 쪽이 더 그럴듯함
        if has_ko and diff > MARGIN:
            return head + keys + tail, "→en", diff
        if has_en and -diff > MARGIN:
            return head + hangul + tail, "→ko", -diff
        return word, "keep", abs(diff)

    def analyze(self, words):
        """단어 목록 -> [(결과, 판단, 확신도)]. 애매한 단어는 앞뒤 단어를 보고 한 번 더 판단한다."""
        first = [self.convert_word(w) for w in words]

        def lang(r):
            out, action, conf = r
            if action == "skip" or (action == "keep" and conf < MARGIN):
                return 0
            return 1 if re.search(r"[A-Za-z]", out) else -1  # 영어 +1, 한글 -1

        result = []
        for i, (w, r) in enumerate(zip(words, first)):
            if r[1] == "keep" and r[2] < MARGIN:
                around = sum(lang(first[j]) for j in (i - 1, i + 1) if 0 <= j < len(first))
                r = self.convert_word(w, CONTEXT_BONUS * around)
            result.append(r)
        return result

    def convert(self, text):
        words = text.split()
        outs = iter(self.analyze(words))
        return re.sub(r"\S+", lambda m: next(outs)[0], text)


def split(words, test_ratio, seed):
    rng = random.Random(seed)
    words = words[:]
    rng.shuffle(words)
    k = int(len(words) * test_ratio)
    return words[k:], words[:k]


def train():
    return Detector(load_words("ko", HANGUL_WORD) + list(KO_CHAT.items()), load_words("en", ENGLISH_WORD))


if __name__ == "__main__":
    det = train()
    text = " ".join(sys.argv[1:]) or "dd rPthrgo 녀ㅔㄷ게ㅐㅈㄷㄱ"
    for w, (out, action, conf) in zip(text.split(), det.analyze(text.split())):
        print(f"{w:>16}  {action:>5}  {out:<16} (확신도 {conf:.1f})")
    print("\n→", det.convert(text))
