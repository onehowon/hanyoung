# hanyoung — 한/영 자동 변환 프로토타입

한/영 키를 잘못 놓고 친 단어를 알아서 바꿔 준다. `rPthrgo` → `계속해`, `녀ㅔㄷ게ㅐㅈㄷㄱ` → `superpower`.

## 원리
1. 사용자가 친 단어를 **키 입력 문자열**로 되돌린다 (`녀ㅔㄷ게ㅐㅈㄷㄱ` → `superpower`).
2. 같은 키 입력을 영어로 읽은 것과 두벌식 한글로 조합한 것을, 각 언어의 문자 5-gram 모델로 채점한다.
   두 모델 모두 키 입력 공간에서 학습해서 같은 기준으로 비교할 수 있다.
3. 한글로 조합되지 않고 혼자 남는 자모(`ㅔ`, `ㅐ`)는 감점, 사전에 있는 단어는 가산점.
4. 차이가 `MARGIN`을 넘을 때만 바꾼다. 애매한 단어는 옆 단어의 언어를 따른다 (`dd rPthrgo` → `ㅇㅇ 계속해`).

## 정확도
학습에 안 쓴 단어 약 9,600개, 문맥 없이 단어 하나만 보고 (`src/evaluate.py`)

| | 잘못 친 걸 고침 | 멀쩡한 걸 잘못 바꿈 |
|---|---|---|
| 한국어 | 99.2% | 0.5% |
| 영어 | 99.3% | 0.4% |

1~2글자 단어가 약점이다 (`좀`↔`wha`). 실제로는 사전과 옆 단어 문맥이 보완한다.

## 실행
```
scripts/download_data.sh                                # 단어 빈도 데이터 받기
python3 src/hanyoung.py "dd rPthrgo 녀ㅔㄷ게ㅐㅈㄷㄱ"   # 변환 해보기
python3 src/evaluate.py -v                              # 정확도 측정

mac/build.sh                                            # 맥 앱 빌드 → build/Hanyoung.app
build/Hanyoung.app/Contents/MacOS/Hanyoung --test "dd rPthrgo"   # 권한 없이 판별만
open build/Hanyoung.app                                 # 메뉴 막대에 "가A"
```
데이터: [FrequencyWords](https://github.com/hermitdave/FrequencyWords) 2018 ko/en 50k (OpenSubtitles 빈도). 저장소에는 넣지 않는다.

## 맥 앱 (`mac/`)
- `Hangul.swift`, `Detector.swift`: 파이썬 판별기를 그대로 옮긴 것. `src/export_model.py`가 만든 `model.json`을 읽는다.
- `AutoSwitch.swift`: 이벤트 탭으로 물리 키 입력을 모으다가 띄어쓰기 순간 판단 → 영문 자판으로 바꾸고 지운 뒤 다시 입력 → 맞는 자판으로 전환.
  - 바꾼 직후 ⌫를 누르면 되돌리고 그 단어는 다시 안 바꾼다 (`~/Library/Application Support/Hanyoung/ignored.txt`).
  - 비밀번호 칸(보안 입력), 터미널, 코드 편집기에서는 동작하지 않는다. 두벌식만 지원.
- 손쉬운 사용 권한이 필요하다. 빌드할 때마다 서명이 바뀌어 권한을 다시 켜야 할 수 있다.

## 다음 단계
- 실사용하며 다듬기: 빠르게 칠 때의 타이밍, 앱별 동작 차이
- 문장부호, 숫자가 붙은 단어 처리
- 애매한 경우만 로컬 판단 모델([Laya](https://github.com/NandhaKishorM/laya))에 물어보기
