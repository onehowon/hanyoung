"""학습한 모델을 맥 앱이 읽는 JSON으로 내보낸다.

    python3 src/export_model.py build/model.json
"""
import json
import os
import sys

import hanyoung
from hanyoung import train


def lm(m):
    return {
        "order": m.order,
        "vocab": len(m.vocab),
        "ctx": {c: [round(t, 3), n, {ch: round(v, 3) for ch, v in m.counts[c].items()}] for c, (t, n) in m.totals.items()},
    }


if __name__ == "__main__":
    det = train()
    model = {
        "params": {k.lower(): getattr(hanyoung, k) for k in ("ORPHAN_PENALTY", "DICT_BONUS", "MARGIN", "CONTEXT_BONUS")},
        "ko": lm(det.ko),
        "en": lm(det.en),
        "ko_dict": sorted(det.ko_dict),
        "en_dict": sorted(det.en_dict),
    }
    out = sys.argv[1]
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(model, f, ensure_ascii=False, separators=(",", ":"))
    print(f"{out}: {os.path.getsize(out) / 1e6:.1f}MB")
