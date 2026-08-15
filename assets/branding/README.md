# 브랜딩 에셋 — 게임 아이콘 / 썸네일

크리에이터 대시보드 **콘텐츠 설정 → 아이콘·썸네일**에 업로드하는 이미지와 그 원본 소스다.
이미지는 전부 HTML + CSS + 인라인 SVG로 그려서 헤드리스 Chrome으로 렌더링한다.
그 덕분에 포토샵 없이도 문구·색·구도를 코드로 고쳐 다시 뽑아낼 수 있다.

## 파일

| 파일 | 크기 | 용도 |
|---|---|---|
| `icon.png` | 512×512 | 게임 아이콘 |
| `thumbnail-a-classroom.png` | 1920×1080 | 썸네일 A — 교실 장면형 |
| `thumbnail-b-closeup.png` | 1920×1080 | 썸네일 B — 클로즈업 대비형 |

원본은 `src/` 아래에 같은 이름의 `.html`로 들어 있다.

## 다시 렌더링하기

```bash
cd assets/branding
./src/render.sh "$PWD/src/icon.html" "$PWD/icon.png" 512 512
./src/render.sh "$PWD/src/thumbnail-a-classroom.html" "$PWD/thumbnail-a-classroom.png" 1920 1080
./src/render.sh "$PWD/src/thumbnail-b-closeup.html" "$PWD/thumbnail-b-closeup.png" 1920 1080
```

`render.sh`는 `/Applications/Google Chrome.app`을 `--headless=new --screenshot`으로 호출한다.
인자는 `<html 절대경로> <출력 png> <가로> <세로>` 순이다. HTML 안의 `html,body` 크기와
넘기는 가로·세로가 어긋나면 잘리므로 둘을 같이 고쳐야 한다.

## 디자인 규칙

두 썸네일과 아이콘이 한 세트로 보이도록 아래를 공유한다. 새 시안을 만들 때도 유지한다.

- **레드 `#ff2b3a`** — 선생님, 발각, 위험. 시야 콘과 눈빛에만 쓴다.
- **시안 `#5df0ff`** — 플레이어, 빈자리, 안전. 목표 지점 표시 전용이다.
- **옐로 `#ffc21f` / `#ffd63d`** — 플레이어 후드와 부제("6학년").
- **칠판 그린 `#23443a`** — 배경 기준색.
- 제목은 항상 흰색 + `#0b0f13` 두꺼운 외곽선. 로블록스 목록에서 200px로 줄어들어도
  글자가 배경에 먹히지 않게 하려는 것이다.

폰트는 macOS 기본 **Apple SD Gothic Neo Heavy**를 쓴다. Black Han Sans 같은 한글 디스플레이
폰트를 설치하면 `font-family`만 바꿔서 제목을 더 강하게 만들 수 있다.

## 업로드 전 확인

- 축소 확인: 썸네일을 200px 폭으로 줄여서 제목이 읽히는지 본다. 안 읽히면 글자를 키운다.
- 게임에 없는 요소는 넣지 않는다. 현재 시안의 선생님·교실·빈자리는 전부 기획서에 나오는 요소다.
