# CLAUDE.md — 「교장이 되어보자!」 작업 지침

로블록스 학교 타이쿤 + 전학생 수집 게임. 대상은 초등 1~5학년, 서버 12명(부지 12 + 가운데 광장).

## 문서

- 기획서(기준): `docs/기획서-교장이-되어보자.md`. 확정 수치는 부록 B, 성능 예산 §12.1, 어린이 안전 §12.2, 주간 게이트 §13.1.
  부록 A 와 문서 앞쪽 심사 반영 목록은 이력이다. 고치지 않는다.
- 층 쌓기 재설계(2026-10-01, 단계 P1~P5): `docs/개선계획-2026-10-01-층-쌓기.md`.
- 구현 계획: `plans/구현계획-교장이-되어보자.md`. 경제 시뮬: `docs/sim/`(사용법은 기획서 부록 C).
- 기획서와 코드가 다르면 어느 쪽이 맞는지 정한 뒤 같은 변경에서 둘을 맞춘다.

## 명령어

툴체인은 `rokit.toml` 로 고정한다. PATH 앞에 Homebrew rojo 7.6.1 이 있으니 rokit 경로를 먼저 넣는다.

```bash
# 처음 세팅
rokit install && wally install
curl -sL -o globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau

# 검사(커밋 전 전부 통과). 소스맵을 먼저 새로 만들어야 가짜 Unknown require 가 안 난다
export PATH="$HOME/.rokit/bin:$PATH" && stylua src && rojo sourcemap default.project.json -o sourcemap.json \
  && selene src && stylua --check src \
  && luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json --no-strict-dm-types $(find src -name "*.luau")

# 방 레시피 검사(파트 수·방 안·금지 구역·좌석·뜬 파트·빨강·통로). 방 id 를 붙이면 그 방만
luau tools/check_rooms.luau -a "$(for f in $(find src/shared src/client/Rooms -name '*.luau'); do echo "--@@FILE $f"; cat "$f"; done)" [방id]

# Studio
~/.rokit/bin/rojo serve default.project.json   # Studio Rojo 플러그인에서 Connect(포트 34872)
```

- Studio 에서 스크립트를 고치지 않는다. 파일이 기준이다.
- Studio 는 `PrincipalSchool_Dev` + Mock 이다. 실제 DataStore 는 ServerScriptService 어트리뷰트 `UseLiveDataStore = true`.
- `DevCheat` 는 Studio 에서만 켜진다: `ServerScriptService.DevCheat.FastForward:Invoke(player, 초)`, `GiveCoins:Invoke(player, n)`, `GiveDecor:Invoke(player, itemId, n)`, `MetricsNow:Invoke(player)`(세션을 끝내지 않고 `[Metrics]` 지금까지 요약 줄), `BuildFloor:Invoke(player, roomId)`(강당·돈·패드 없이 그 방 1층 완공).

## 구조

- `src/server/Services/` 서비스 7개(Data·Plot·Economy·Student·Decor·Mission·Leaderboard). 부팅 순서는 `init.server.luau`.
- `src/server/Geometry/` 시설·부지·광장을 파트로 짓는 모듈. 층 쌓기 탑(층 바닥판·옥상·층 패드·엘리베이터)은 `Tower.luau`. 나무·화단·광장 Creator Store 모델은 `PropLibrary.luau`(메시 id 가 없거나 실패하면 파트 폴백). 공용 헬퍼는 `src/server/BuildKit.luau`(Geometry 밖).
- `src/client/Controllers/` 컨트롤러 12개(`InteriorRenderController` = 1층 방 안 소품, `TowerRenderController` = 12부지 층 쌓기 탑 외관·방 안). 방 레시피는 `src/client/Rooms/`: 방마다 `<id>.luau` 12개(`{big, props, finish}` = 부품 2·3·4), 공용 도우미 `Kit.luau`(벽 안쪽 면·금지 구역 상수, 의자·책상·선반 등), `init.luau` 의 `Rooms.get`(파일이 없으면 공통 임시 레시피). 층 방 ≤ 60 파트, 옥상 방 ≤ 45. 주인공 소품 메시는 `src/client/MeshCache.luau` 가 불러오고 레시피는 `if not Kit.hero(...) then <파트> end` 로 폴백을 같이 둔다(1층 시설은 `InteriorRenderController` 의 `hero`, 방당 ≤ 16 파트). `src/client/MaterialSetup.luau` 가 PBR 재질로 WoodPlanks 를 통째로 덮으니 바닥이 아닌 파트에 WoodPlanks 를 쓰지 않는다(나무 가구는 `Wood`). 리모트 구독은 `init.client.luau` 한 곳에서만 한다.
- `src/shared/Config/` 수치의 단일 소스. 가격·확률·시간·문구는 여기서만 바꾼다.
- `src/shared/Remotes.luau`(프로토콜은 기획서 §11.5), `Types.luau`, `Seats.luau`, `CharacterBuilder.luau`, 꾸미기 공용 `DecorGrid`·`DecorCodec`·`DecorBuilder`(수치는 `Config/DecorConfig.luau`). `src/first/` 로딩 화면.

## 규칙

- 클라→서버 리모트는 전부 `RemoteGuard.wrap` 으로 받는다. 서버가 판정한다. `AssemblyLinearVelocity` 같은 클라 소유 값을 믿지 않는다.
- 방문객이 주인을 느리게 하거나 주인 화면을 가리는 것은 없어야 한다(§7.5). 연출·카드·소리는 주인 화면에서만.
- Robux 결제·유료 무작위 아이템·출석/오프라인 보상·자유 텍스트 입력·빨강 같은 부정 피드백은 넣지 않는다(예외: 꾸미기 배치 고스트는 놓을 수 없으면 반투명 빨강). 화면에는 Username 대신 DisplayName 만 쓴다(§12.2).
- 새 파일은 `--!strict`. 주석·문서·커밋 메시지는 한국어, 식별자는 영어. 커밋은 `type(scope): 요약`, 본문에 "왜".
- 메시·텍스처 업로드는 허용한다(에셋 품질 우선). id 는 `CharacterAssets`(학생)·`PropAssets`(창 텍스처·소품 메시·주인공 소품 `HERO`·Creator Store 모델 출처 표)에만 적고(예외: 바닥 PBR MaterialVariant 는 스크립트가 못 만들어 `default.project.json` 의 `MaterialService` 에 둔다. 맵 uri 는 속성과 같은 이름의 `$attributes` 에 한 번 더 적는다 — 클라 `MaterialSetup` 이 그걸로 불러오기를 확인한다), id 0 이거나 불러오기에 실패하면 파트 폴백이 반드시 동작해야 한다. Creator Store 모델은 광장 비핵심 소품 ≤ 3개, 안의 스크립트는 전부 지운다.
- `CharacterAssets`·`PropAssets` 의 메시·텍스처 ID 는 게임 소유자 계정에 업로드된 것이다. 다른 계정·그룹 게임으로 옮기면 가장 먼저 깨진다.
- `.claude/skills/` 에 로블록스 스킬 29개가 있다. 일반 로블록스 규칙은 거기서 찾는다.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
- ⚠️ graphify 0.9.72 원본은 `.luau` 를 plain-Lua 문법기로 읽어서 Luau 구문(타입·`::`·`+=`·`if` 표현식·보간 문자열)에서 조용히 끊긴다(upstream #2520). 이 맥의 설치본은 `tree-sitter-luau` 로 바꾸는 로컬 패치가 들어가 있어 src 함수 97% 가 잡힌다. **`uv tool upgrade graphifyy` 를 하면 패치가 사라진다** — 업그레이드 후 `graphify update .` 결과에서 "syntax errors" 경고가 다시 나오면 패치를 다시 적용해야 한다(`tools/graphify-luau.patch`, 설치본 `graphify/` 폴더에서 `patch -p0` 대신 파일별로 적용 + `uv pip install --python $(uv tool dir)/graphifyy/bin/python tree-sitter-luau`). 그래프에 없다고 코드가 없는 것은 아니다.
