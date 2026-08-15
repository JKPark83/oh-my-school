# 🛠 「얼음! 6학년」 MVP 구현 계획서 — 1학년 12반까지

> 원본 기획서: [`ideas/roblox-korean-school-stealth-2026-08-15.md`](../ideas/roblox-korean-school-stealth-2026-08-15.md)
> 작성일: 2026-08-15 · 범위: **MVP(1학년 1반~12반) 전용** · Phase 5개

---

## 0. 이 문서를 읽는 법

기획서는 "무엇을 만들 것인가"를 정의한다. 이 문서는 "어떤 순서로, 어떤 파일에, 무엇을 넣고, 무엇으로 끝났다고 판정할 것인가"만 다룬다.

**세 가지 원칙**

1. **Phase는 순서가 있는 의존 관계다.** Phase N의 완료 기준을 통과하지 못한 채 N+1로 넘어가면, 나중에 원인을 못 찾는다. 특히 Phase 1(감지)과 Phase 2(이동)는 게임의 재미 그 자체이므로, 여기서 "억울하다"는 느낌이 남으면 뒤에서 아무리 꾸며도 못 살린다.
2. **완료 기준은 전부 관찰 가능해야 한다.** "잘 동작한다"가 아니라 "20판 중 억울한 죽음 0회"처럼 세어서 판정한다.
3. **수치는 전부 초기값이다.** 이 문서의 숫자는 시작점이지 정답이 아니다. `shared/Config/`에 몰아둔 이유가 그것이다. 코드를 고치지 않고 숫자만 바꿔 테스트할 수 있어야 한다.

**MVP에서 의도적으로 제외한 것** — 2~6학년, 명예의 전당 랭킹, 수익화, 코스메틱 상점, 방해물 카탈로그 전체(1학년용 2종만 구현). 확장 방법은 [§9 확장 가이드](#9-확장-가이드-mvp-이후)에 요약한다.

---

## 1. 전체 로드맵

| Phase | 이름 | 한 줄 목표 | 예상 기간 | 끝나면 할 수 있는 것 |
|---|---|---|---|---|
| **1** | 뼈대와 눈 | 툴체인 + 회색상자 교실 + 선생님 상태머신 + 감지 판정 | 4일 | 회색 방에서 선생님이 돌아보고, 움직이면 잡힌다 |
| **2** | 손맛 | 3단계 이동 + 감속 커브 + 예고 신호 | 3일 | "얼음!" 순간의 긴장이 실제로 느껴진다 |
| **3** | 한 판 완성 | 교실 아트 + 학생 NPC + 착석 + 성공/실패 연출 | 5일 | 30~60초짜리 완결된 한 판이 돌아간다 |
| **4** | 12반 루프 | 슬롯 인스턴싱 + 난이도 곡선 + 별·업그레이드 + 저장 | 5일 | 1반→12반을 이어서 플레이하고, 껐다 켜도 이어진다 |
| **5** | 포장과 검증 | 운동장 허브 + 사운드 + HUD + 조명 + 플레이테스트 | 4일 | 남에게 링크를 보낼 수 있다 |

합계 약 3주(솔로 + AI 보조 기준). 각 Phase 끝에 **반드시 플레이 테스트**를 넣는다. 만들고 나서 몰아서 테스트하면 어느 변경이 재미를 죽였는지 알 수 없다.

---

## 2. 사전 준비 — 프로젝트 골격

Phase 1의 첫 반나절에 해당하지만, 이후 모든 Phase가 이 구조 위에 얹히므로 따로 뺀다.

### 2.1 툴체인

**모든 것의 기준은 파일이다.** Studio는 (a) 맵 배치, (b) 실행 테스트, 이 두 가지에만 쓴다. Studio에서 스크립트를 고치는 순간 파일과 어긋나고, 그때부터 무엇이 최신인지 알 수 없게 된다.

```toml
# rokit.toml  — Aftman은 아카이브됨. 신규 프로젝트는 Rokit을 쓴다.
# Wally는 실제 의존성이 생기는 Phase 4(ProfileStore)에서 추가한다.
[tools]
rojo = "rojo-rbx/rojo@7.7.0"
selene = "Kampfkarren/selene@0.31.0"
stylua = "JohnnyMorganz/StyLua@2.5.2"
luau-lsp = "JohnnyMorganz/luau-lsp@1.69.0"
```

```bash
rokit install

# 로블록스 API 타입 정의. 이게 없으면 luau-lsp가 Enum도 Vector3도 모른다.
curl -sL -o globalTypes.d.luau \
  https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau

rojo sourcemap default.project.json --output sourcemap.json --watch   # luau-lsp가 Roblox 인스턴스를 이해하게 함
rojo serve                                                            # Studio 플러그인에서 Connect

# 커밋 전 3종 검사
stylua --check src/
selene src/
luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau src/
```

Wally 의존성은 최소로 시작한다. 지금은 **하나도 없다.** 실제로 쓰는 순간이 오면 그때 추가한다. Promise, Signal, Janitor 류를 미리 넣으면 쓰지도 않는 추상화 위에 코드를 쌓게 된다.

첫 의존성은 Phase 4의 저장 기능에서 생긴다.

```toml
# wally.toml — Phase 4에서 만든다
# ProfileStore 는 realm 이 server 라 [dependencies] 에 넣으면 설치가 거부된다.
# 서버 전용 모듈이 클라이언트로 복제되면 안 되므로 이게 맞다.
[server-dependencies]
ProfileStore = "lm-loleris/profilestore@1.0.3"
```

### 2.2 폴더 구조

```
oh-my-school/
├── rokit.toml
├── wally.toml
├── default.project.json
├── selene.toml / stylua.toml
└── src/
    ├── server/
    │   ├── init.server.luau            -- 부트스트랩 (유일하게 순서를 아는 곳)
    │   ├── BuildKit.luau               -- part() / surfaceText() 조립 도구 (교실·운동장 공용)
    │   ├── Classroom/
    │   │   └── Template.luau           -- 교실 한 칸을 통째로 조립 (좌석/엄폐물 포함)
    │   ├── Playground/
    │   │   └── Template.luau           -- 운동장 허브 + 본관 정면 + 신발장 로비
    │   └── Services/
    │       ├── ClassroomService.luau   -- 슬롯 할당, 교실 조립/해체
    │       ├── PlaygroundService.luau  -- 허브 소유, 신발장·문구점 프롬프트
    │       ├── TeacherAI.luau          -- 선생님 상태머신
    │       ├── DetectionService.luau   -- 감지 판정 (게임의 심장)
    │       ├── ProgressService.luau    -- 반 클리어/실패, 별 지급, 허브↔교실 왕복
    │       └── DataService.luau        -- 저장/불러오기
    ├── shared/
    │   ├── Remotes.luau                -- 리모트 정의 한 곳 (전부 서버→클라 단방향)
    │   ├── Types.luau                  -- 공용 타입
    │   ├── CharacterBuilder.luau       -- 얼굴 있는 사람 모델 (선생님·학생 공용)
    │   └── Config/
    │       ├── DifficultyTable.luau    -- 학년/반별 수치
    │       ├── MovementConfig.luau     -- 이동 3단계 수치
    │       ├── SoundConfig.luau        -- 사운드 10종 정의 (음원 교체 지점)
    │       ├── RoomKeys.luau           -- 태그/폴더명/어트리뷰트 이름 (서버·클라 공용)
    │       └── Upgrades.luau           -- 업그레이드 정의 + 매대 진열 순서
    └── client/
        ├── init.client.luau
        ├── RoomRef.luau                -- 배정받은 교실 모델 해석
        └── Controllers/
            ├── MovementController.luau      -- 3단계 이동 + 감속 커브
            ├── CameraController.luau        -- 어깨너머 고정 카메라
            ├── SignalController.luau        -- 예고 신호 연출 + 분필/수업 소리
            ├── StudentRenderController.luau -- 학생 NPC 클라 렌더
            ├── FeedbackController.luau      -- 적발/클리어 연출
            ├── SoundController.luau         -- 발소리·의자·호통·종·복도 소리
            ├── TransitionController.luau    -- 허브↔교실 전환 검은 화면
            └── HudController.luau           -- 진행도/별/이동 모드/알림 UI
```

뒤쪽 다섯 개(`BuildKit` / `Playground` / `PlaygroundService` / `SoundConfig` / `Sound`·`Transition` 컨트롤러)는 Phase 5에서 늘어난 것이다. 자세한 내용은 §7.

**서비스 경계 원칙 — 한 상태에 주인은 하나다.**

| 상태 | 유일한 주인 | 다른 곳은 |
|---|---|---|
| 선생님 현재 상태 | `TeacherAI` | 읽기만. 상태 변경은 반드시 TeacherAI를 통한다 |
| 좌석 점유 여부 | `ClassroomService` | `ProgressService`가 물어보고, 직접 안 고친다 |
| 플레이어 진행도(학년/반/별) | `ProgressService` | `DataService`는 저장만, 판정은 안 한다 |
| 적발 판정 | `DetectionService` | 다른 서비스는 결과를 구독만 한다 |

전역 이벤트 버스나 DI 컨테이너를 만들지 않는다. 서비스는 서로를 `require`해서 직접 부른다. 순환 참조가 생기면 그건 경계가 잘못 그어졌다는 신호지, 이벤트 버스가 필요하다는 신호가 아니다.

### 2.3 부트스트랩

```luau
-- src/server/init.server.luau
local Services = script.Services

-- 순서가 중요한 것만 명시적으로, 순차적으로. task.spawn 남발 금지.
local DataService = require(Services.DataService)
local ClassroomService = require(Services.ClassroomService)
local PlaygroundService = require(Services.PlaygroundService)
local ProgressService = require(Services.ProgressService)
local DetectionService = require(Services.DetectionService)

DataService.Start()        -- 프로필 세션 관리 시작
ClassroomService.Start()   -- 슬롯 풀 초기화 (교실 12칸)
PlaygroundService.Start()  -- 운동장 조립. ProgressService 보다 먼저 — 스폰 지점의 주인이다
ProgressService.Start()    -- 플레이어 입장/퇴장 훅, 핸들러 연결
DetectionService.Start()   -- 감지 루프 (20Hz)
```

모듈 최상위(top-level)에서는 아무것도 하지 않는다. `require`는 값만 반환하고, 실제 작업은 `Start()`에서 한다. 그래야 부트스트랩 한 곳만 보면 순서가 파악된다.

---

## 3. Phase 1 — 뼈대와 눈

> **목표:** 회색 상자 교실 안에서 선생님이 예고 후 돌아보고, 그때 움직인 플레이어를 서버가 잡아낸다.

이 Phase가 게임의 전부다. 아트도 없고 학생도 없지만, **여기서 재미가 안 나오면 이 게임은 재미가 없는 게임이다.** 아트로 덮을 수 있다고 생각하지 말 것.

### 3.1 산출물

- `src/shared/Config/DifficultyTable.luau`
- `src/shared/Remotes.luau`, `src/shared/Types.luau`
- `src/server/Services/TeacherAI.luau`
- `src/server/Services/DetectionService.luau`
- `src/server/Greybox.luau` — 회색상자 교실 1개

> 회색상자는 Studio 배치 대신 **코드로 생성**한다. 아트가 하나도 없어도 감지 판정을 검증할 수 있어야 하고, 치수를 바꿔가며 튜닝하는 데는 상수 하나 고치는 쪽이 훨씬 빠르다. Phase 3에서 아트 템플릿으로 교체되면서 이 파일은 지워진다.

### 3.2 회색상자 교실 규격

숫자를 지금 확정해야 나중에 아트가 들어올 때 다시 안 짠다.

| 요소 | 값 | 근거 |
|---|---|---|
| 교실 내부 | 46 × 38 studs (가로 × 세로) | 6열 × 3분단 책상 + 통로 |
| 천장 높이 | 16 studs | 한국 교실 특유의 낮고 답답한 느낌 |
| 칠판 | 앞쪽 벽, 폭 24 | 선생님 기준점 |
| 교탁 | 칠판 앞 4 studs | 선생님 시작 위치 |
| 뒷문 | 뒤쪽 벽 우측 | 플레이어 진입점 |
| **뒷문 앞 안전지대** | 문에서 4 studs | `MAX_SIGHT` 밖 → 관찰 후 출발할 수 있는 숨돌리기 구간 |
| 좌석 | 18개 (6×3) | 기획 확정값 |
| 빈자리 | 1~2개, 매 판 랜덤 | 서버가 결정 |

**MAX_SIGHT = 30 studs.** 시야는 교실 앞벽이 아니라 **선생님 머리**에서 잰다. 교탁이 z = -15, 뒷벽이 z = +19이므로 30스터드는 z ≈ +15까지 닿고, 뒷문 앞 약 4스터드가 구조적 사각지대로 남는다. 이건 버그가 아니라 설계다 — 플레이어가 패턴을 관찰하고 출발 타이밍을 스스로 고를 수 있도록 "들어가긴 했는데 아직 안 잡힌" 안전 구간을 일부러 남긴 것이다.

> 좌표 규약은 이후 모든 Phase에 공통으로 적용된다. **-Z = 교실 앞(칠판), +Z = 교실 뒤(뒷문), -X = 창가, +X = 복도 쪽, y = 0이 바닥 윗면.**

### 3.3 선생님 상태머신

```luau
-- src/shared/Types.luau
export type TeacherState = "TEACHING" | "WARNING" | "TURNING" | "WATCHING" | "RETURNING"

export type TeacherConfig = {
    teachTime: number,   -- 판서 중 (등 돌림). ±20% 랜덤
    warnTime: number,    -- 예고 신호 지속 (분필 멈춤 + 어깨 들썩)
    turnTime: number,    -- 몸을 돌리는 데 걸리는 시간
    watchTime: number,   -- 학생을 응시하는 시간. ±25% 랜덤
    fovDeg: number,      -- 시야각 (전체 각도)
    fakeChance: number,  -- 페이크 턴 확률 (1학년은 0)
}
```

```
        ┌──────────────────────────────────────────────┐
        ▼                                              │
   [TEACHING] ──teachTime──▶ [WARNING] ──warnTime──▶ [TURNING]
    등 돌림                   예고 신호                 회전 중
    안전                      아직 안전                 후반 50%부터 감지 시작
                                 │                        │
                                 │ fakeChance             ▼ turnTime
                                 └──────────────▶     [WATCHING]
                                   (다시 TEACHING)     정면 응시 · 감지 ON
                                   ※ 2연속 페이크 금지        │ watchTime
                                                             ▼
                                                        [RETURNING] ──turnTime──┐
                                                         감지 OFF               │
                                                                                └─▶ TEACHING
```

**감지가 켜지는 구간은 `TURNING`의 후반 50% + `WATCHING` 전체.** `TURNING` 전반부까지 감지를 켜면 예고를 보고 멈춘 플레이어가 억울하게 죽는다. 후반부에 켜는 이유는, 이미 반쯤 돌아온 선생님 눈앞에서 뛰는 건 잡히는 게 맞기 때문이다.

```luau
-- src/server/Services/TeacherAI.luau (핵심만)
local TeacherAI = {}
TeacherAI.__index = TeacherAI

export type Teacher = {
    state: TeacherState,
    stateVersion: number,      -- 단조 증가. 클라가 순서 뒤바뀐 패킷을 버리는 데 씀
    stateEndsAt: number,       -- os.clock() 기준
    config: TeacherConfig,
    lastWasFake: boolean,
    model: Model,
}

function TeacherAI.new(model: Model, config: TeacherConfig): Teacher
function TeacherAI:SetState(teacher: Teacher, newState: TeacherState, duration: number)
function TeacherAI:Update(teacher: Teacher, now: number)   -- 서버 루프에서 호출
function TeacherAI:IsWatching(teacher: Teacher, now: number): boolean
```

`SetState`는 상태 변경 + `stateVersion` 증가 + `TeacherStateChanged` 브로드캐스트를 **원자적으로** 처리하는 유일한 지점이다. 다른 곳에서 `teacher.state = ...`를 직접 대입하면 클라이언트와 어긋난다.

```luau
function TeacherAI:SetState(teacher, newState, duration)
    teacher.state = newState
    teacher.stateVersion += 1
    teacher.stateEndsAt = os.clock() + duration

    Remotes.TeacherStateChanged:FireClient(teacher.owner, {
        version = teacher.stateVersion,
        state = newState,
        duration = duration,
    })
end
```

**어트리뷰트로도 상태를 노출하는 이중 채널을 만들지 않는다.** `RemoteEvent`는 어트리뷰트·프로퍼티 복제와 순서가 보장되지 않는다. 채널이 둘이면 클라이언트가 어느 쪽을 믿어야 할지 모르는 순간이 반드시 생긴다.

### 3.4 감지 알고리즘 — 이 게임에서 가장 중요한 30줄

```luau
-- src/server/Services/DetectionService.luau
local MOVE_EPSILON = 0.05    -- stud / tick. 20Hz 기준 약 1 stud/s
local GRACE = 0.20           -- 감지 시작 후 유예 (초)
local MAX_SIGHT = 30         -- studs

local lastPositions: { [Player]: Vector3 } = {}

local function check(player: Player, teacher: Teacher, now: number)
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    -- 위치는 감지 여부와 무관하게 항상 갱신한다.
    -- 이걸 조기 return 뒤에 두면, 감지가 꺼진 동안 이동한 거리가
    -- 감지가 켜지는 첫 틱에 한꺼번에 델타로 잡혀 억울한 죽음이 된다.
    local prev = lastPositions[player]
    lastPositions[player] = hrp.Position

    if not TeacherAI:IsWatching(teacher, now) then return end
    if now - teacher.watchStartedAt < GRACE then return end

    local toPlayer = hrp.Position - teacher.head.Position
    local dist = toPlayer.Magnitude
    if dist > MAX_SIGHT then return end                                   -- (1) 거리

    local cos = teacher.head.CFrame.LookVector:Dot(toPlayer.Unit)
    if cos < math.cos(math.rad(teacher.config.fovDeg / 2)) then return end -- (2) 시야각

    local hit = workspace:Raycast(teacher.head.Position, toPlayer, coverParams)
    if hit and hit.Instance:HasTag("Cover") then return end               -- (3) 엄폐

    if prev and (hrp.Position - prev).Magnitude > MOVE_EPSILON then       -- (4) 움직임
        DetectionService:Catch(player, "moved_in_sight")
    end
end
```

**순서를 지킨다: 거리 → 시야각 → 레이캐스트.** 레이캐스트가 가장 비싸다. 거리와 각도로 대부분을 먼저 걸러내면 실제 레이캐스트는 "정말 위험한 순간"에만 나간다.

**🔴 절대 하지 말 것 — `AssemblyLinearVelocity`로 움직임을 판정하지 않는다.**
클래식 복제에서 캐릭터의 물리 소유권은 클라이언트에 있다. 즉 서버가 읽는 속도값은 *클라이언트가 보고한 값*이다. 익스플로잇 유저는 속도 0을 보고하면서 자유롭게 걸어다닐 수 있고, 그러면 이 게임은 게임이 아니게 된다. 반드시 **서버가 직접 기록한 위치 델타**를 쓴다. 위치도 클라가 보내지만, 텔레포트·비정상 이동은 별개의 검증으로 걸러낼 수 있고 "안 움직인 척"은 불가능하다.

**억울함 방지 3종 세트** — 이게 없으면 플레이어는 게임을 접는다.

| 장치 | 값 | 효과 |
|---|---|---|
| `GRACE` | 0.20초 | 응시 시작 직후 관성으로 미끄러진 프레임을 봐준다 |
| `MOVE_EPSILON` | 0.05 stud/tick | 캐릭터 idle 흔들림·발판 미세 진동을 무시 |
| 적발 사유 전송 | `"moved_in_sight"` 등 | 클라이언트가 왜 죽었는지 표시 → 억울함이 학습으로 바뀐다 |

### 3.5 감지 루프

```luau
-- 20Hz. Heartbeat 매 프레임(60Hz)은 낭비다.
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
    accumulator += dt
    if accumulator < 1 / 20 then return end
    accumulator = 0

    local now = os.clock()
    for player, teacher in activeSessions do
        TeacherAI:Update(teacher, now)
        check(player, teacher, now)
    end
end)
```

플레이어당 교실이 1개이므로 루프는 최대 12회. `PathfindingService`는 쓰지 않는다 — 선생님은 교탁 주변에서만 움직이고, 순찰(5학년)조차 고정 웨이포인트로 충분하다.

### 3.6 난이도 테이블 (1학년)

```luau
-- src/shared/Config/DifficultyTable.luau
local Grade1 = {
    class1  = { teachTime = 5.0, warnTime = 0.75, turnTime = 0.45, watchTime = 1.6, fovDeg = 90, fakeChance = 0 },
    class12 = { teachTime = 3.5, warnTime = 0.60, turnTime = 0.45, watchTime = 2.2, fovDeg = 90, fakeChance = 0 },
}

-- 2~11반은 선형 보간. 반마다 표를 손으로 쓰지 않는다.
function DifficultyTable.Get(grade: number, class: number): TeacherConfig
```

1학년은 **페이크 턴 0%**이다. 첫 학년에서 배워야 할 규칙은 "예고를 보면 멈춘다" 하나뿐이다. 여기에 페이크를 섞으면 규칙 자체를 못 배운다.

### 3.7 ✅ Phase 1 완료 기준

1. Studio에서 실행 → 회색 교실에서 선생님이 `TEACHING → WARNING → TURNING → WATCHING → RETURNING`을 무한 반복하고, 출력 로그에 상태 전이가 순서대로 찍힌다.
2. `WATCHING` 중 걸어가면 **20/20회** 잡힌다.
3. `WATCHING` 중 가만히 있으면 **20/20회** 안 잡힌다.
4. 엄폐물(`Cover` 태그) 뒤에서 움직이면 안 잡힌다.
5. 선생님 등 뒤 90° 밖(교실 측면)에서 움직이면 안 잡힌다.
6. 뒷문 앞 4스터드 구간에서는 움직여도 안 잡힌다.
7. **20판 연속 플레이 중 "이건 억울한데" 싶은 죽음이 0회.** 1회라도 나오면 `GRACE`/`MOVE_EPSILON`을 조정하고 다시 20판. 이 항목만은 타협하지 않는다.
8. 서버 heartbeat < 16ms (Developer Console F9 → Server Stats).

---

## 4. Phase 2 — 손맛

> **목표:** "빨리 가고 싶다" vs "멈출 수 있어야 한다"의 긴장을 이동 조작 자체에 심는다.

### 4.1 이동 3단계

| 모드 | 속도 | `stopTime` | 미끄러지는 거리 | 멈출 때까지 | 소음 | 조작 |
|---|---|---|---|---|---|---|
| 살금살금 | 4 st/s | 0.08초 | 0.2 studs | **0.11초** | 없음 | `Ctrl` 홀드 / 모바일 버튼 |
| 걷기 | 10 st/s | 0.35초 | 3.2 studs | **0.81초** | 없음 | 기본 |
| 달리기 | 17 st/s | 0.75초 | 12 studs | **2.13초** | 있음 | `Shift` 홀드 / 모바일 버튼 |

> 감속은 선형이 아니라 지수 감쇠(`v = v₀·e^(-t/stopTime)`)다. 따라서 `stopTime`은 "완전히 멈추는 데 걸리는 시간"이 아니라 시상수이고, 뒤의 두 열은 거기서 유도된다. "멈췄다"의 기준은 **1 stud/s** — 서버 감지의 `MOVE_EPSILON`(0.05 stud/tick @ 20Hz)이 정확히 이 값이라, "멈췄다"가 "감지에 안 걸린다"와 같은 뜻이 된다.

**이 표가 게임 디자인의 전부다.** 굵게 표시한 "멈출 때까지" 열이 실제로 게임을 결정한다. 1학년의 반응 예산은 `warnTime`(0.60~0.75) + `turnTime` 전반부(0.23) + `GRACE`(0.20) = **약 1.0~1.2초**이고, 여기서 사람의 반응 시간 0.25초를 빼면 실제로 쓸 수 있는 감속 시간은 0.75~0.95초다.

- 살금살금 0.11초 → **항상 여유 있게 멈춘다.** 느리게 움직인 보상이다.
- 걷기 0.81초 → **아슬아슬하다.** 여기가 이 게임의 긴장이다.
- 달리기 2.13초 → **못 멈춘다.** 예고를 보고 브레이크를 밟으면 이미 늦었다.

즉 달리기는 "예고를 보고 멈추는" 수단이 아니라 **"미리 멈출 자신이 있을 때 쓰는"** 수단이다. 이 한 줄에서 게임의 모든 판단이 나온다.

달리기는 추가로 **선생님의 판서를 멈추게 한다**(소음). `TEACHING` 중이어도 달리면 선생님이 판서 시간이 끝나기를 기다리지 않고 바로 예고에 들어간다. 단 `WARNING`을 건너뛰지는 않는다 — 예고 없는 적발은 억울함이고, 억울함은 이 게임에서 유일하게 타협하지 않는 항목이다.

서버는 클라이언트가 보고하는 이동 모드를 쓰지 않는다. 익스플로이터는 "살금살금 중"이라고 보고하면서 달릴 수 있다. **서버가 기록한 위치 델타로 직접 속도를 계산**해 `RUN_NOISE_SPEED`(13.5 st/s, 걷기와 달리기 사이)와 비교한다. 수직 성분은 뺀다 — 낙하는 발소리가 아니다.

### 4.2 감속 커브 — `WalkSpeed = 0`을 쓰지 않는 이유

`Humanoid.WalkSpeed = 0`은 즉시 정지다. 즉시 정지는 (a) 손맛이 없고, (b) 위 표의 "정지 거리" 개념 자체를 없애버려 게임을 무너뜨린다.

`AssemblyLinearVelocity`에 직접 쓰는 방법도 답이 아니다. 입력을 뗀 순간 `Humanoid`의 지면 컨트롤러는 목표 속도를 0으로 잡고 강한 힘으로 감속시킨다. 매 프레임 속도를 덮어써도 다음 물리 스텝에서 대부분 상쇄되어, **미끄러지는 대신 덜덜 떨다 선다.**

대신 `WalkSpeed`를 곡선으로 낮추면서 마지막 이동 방향을 `humanoid:Move()`로 계속 먹인다. 물리와 싸우지 않으므로 부드럽고, 걷기 애니메이션도 같이 느려진다.

```luau
-- src/client/Controllers/MovementController.luau
-- Stepped 는 기본 컨트롤 모듈이 Move 를 호출하는 렌더 스텝 다음,
-- 물리 스텝 직전이다. 여기서 Move 를 부르면 우리 값이 최종적으로 반영된다.
RunService.Stepped:Connect(function(_, deltaTime)
    -- "입력이 들어오고 있는가"는 MoveDirection 이 아니라 컨트롤 모듈에게 묻는다.
    -- 감속 중에는 우리가 직접 Move() 를 호출하므로 MoveDirection 이 0 이 아니게 되고,
    -- 그걸 입력으로 오해하면 영원히 감속이 끝나지 않는다.
    if controls:GetMoveVector().Magnitude > 0.01 then
        sliding = false
        humanoid.WalkSpeed = MODES[mode].speed
        slideDir = humanoid.MoveDirection
        return
    end

    if not sliding then
        sliding = true
        slideSpeed = horizontalSpeed()        -- 입력을 뗀 순간의 실제 속도
        slideStopTime = MODES[mode].stopTime  -- 시상수도 이 순간에 고정한다
    end

    slideSpeed *= math.exp(-deltaTime / slideStopTime)
    if slideSpeed <= STOP_CUTOFF then
        sliding = false
        humanoid.WalkSpeed = MODES[mode].speed
        return
    end

    humanoid.WalkSpeed = slideSpeed
    humanoid:Move(slideDir, false)
end)
```

**시상수는 미끄러지는 도중에 절대 바꾸지 않는다.** 바꾸면 미끄러지다가 `Ctrl`을 눌러 즉시 설 수 있게 된다. 그건 브레이크 버튼이고, 이 게임에는 브레이크가 없어야 한다. 같은 이유로 모드가 바뀌어도 미끄러지는 중이면 `WalkSpeed`를 건드리지 않는다.

서버는 이 값을 **믿지 않는다.** 감속 커브는 순전히 클라이언트 체감용이고, 적발 판정은 Phase 1의 위치 델타가 그대로 담당한다. 클라가 감속을 조작해도 얻을 게 없다 — 어차피 서버는 "실제로 움직였는가"만 본다.

### 4.3 입력 바인딩

`UserInputService.InputBegan` 대신 `ContextActionService`를 쓴다. 이유는 두 가지, 둘 다 공짜다.

- 채팅창이 열려 있을 때 채팅이 `Shift`를 먹는 충돌을 알아서 처리한다.
- `createTouchButton = true` 한 번으로 **모바일 터치 버튼이 자동 생성**된다. 모바일 UI를 따로 안 짜도 된다.

```luau
local CAS = game:GetService("ContextActionService")

local function onSprint(_, state)
    setMode(state == Enum.UserInputState.Begin and "RUN" or "WALK")
    return Enum.ContextActionResult.Sink
end

CAS:BindAction("Sprint", onSprint, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonR2)
CAS:BindAction("Sneak", onSneak, true, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonL2)
```

### 4.4 카메라

3인칭 어깨너머 고정. `CameraController`는 `CameraSubject`를 캐릭터로 두되, 카메라 오프셋을 오른쪽 어깨로 밀고 시야를 살짝 좁힌다. **1인칭 전환은 막는다** — 이 게임은 "내 몸이 지금 얼마나 튀는가"를 봐야 하는 게임이다.

### 4.5 예고 신호 (`SignalController`)

`WARNING` 상태 진입 패킷을 받으면 클라이언트가 연출한다. 서버는 상태만 보내고, 연출은 전부 클라 몫이다.

1. **분필 소리가 뚝 끊긴다** (가장 강한 신호. 청각은 반사 신경을 직접 건드린다)
2. **어깨가 한 번 들썩인다** (시각 백업. 소리를 끈 플레이어도 알 수 있어야 한다)
3. 화면 가장자리에 아주 옅은 비네트

세 가지 모두 `warnTime` **안에** 완결되어야 한다. 0.60초 안에 인지 → 판단 → 손가락까지 가야 하므로, 신호가 늦게 시작하면 그 자체가 억울함이 된다. 그래서 비네트 페이드인은 0.12초, 어깨 들썩임은 왕복 0.2초로 잡았다.

> 분필 소리 에셋은 Phase 5(사운드)에서 채운다. Phase 2에서는 `CHALK_SOUND_ID`가 빈 값이라 소리가 나지 않지만, **재생·정지 로직은 이미 구현되어 있다.** 그때까지 예고는 어깨와 비네트가 감당한다. 순서를 이렇게 잡은 이유는, 소리가 없는 상태에서 시각 신호만으로 반응할 수 있는지 먼저 확인해야 하기 때문이다. 소리를 끄고 노는 플레이어에게도 이 게임은 공평해야 한다.

`WARNING`과 `FAKE_TURN`은 플레이어에게 **똑같이** 보여야 한다. 낚시인지 아닌지 구분되면 그건 낚시가 아니다.

### 4.6 ✅ Phase 2 완료 기준

1. 세 모드 전환이 PC(Shift/Ctrl)와 모바일(자동 생성 버튼) 모두에서 동작한다.
2. 각 모드에서 입력을 뗀 뒤 멈출 때까지 걸리는 시간을 재서 표(0.11 / 0.81 / 2.13초) ±20% 안에 든다. 거리보다 시간이 기준이다 — 예고와 겨루는 대상이 시간이기 때문이다.
3. **달리는 중에 예고 신호를 보고 반응해서 멈추면 "간발의 차로 늦는다."** 여유롭게 멈춰지면 `stopTime`을 늘리거나 `warnTime`을 줄인다. 이 감각이 이 게임의 손맛 전부다.
4. 살금살금으로는 예고를 보고 멈추면 **항상** 안전하다. (느림에 대한 보상)
5. 채팅창을 열고 `Shift`를 눌러도 캐릭터가 달리지 않는다.
6. 클라 FPS: 데스크톱 60, 모바일 45 이상.

---

## 5. Phase 3 — 한 판 완성

> **목표:** 회색 상자를 한국 초등학교 교실로 바꾸고, 들어가서 앉고 나오는 한 판을 완결시킨다.

### 5.1 교실 아트 체크리스트

한국 초등학교라는 인상은 **몇 개의 결정적 오브젝트**에서 나온다. 전부 만들 필요 없다.

| 필수 | 이유 |
|---|---|
| 초록 칠판 + 분필가루 자국 | 첫눈에 "한국 학교" |
| 나무 무늬 마루 바닥 | 소리와 질감의 근거 |
| 뒤쪽 게시판 (시간표·급훈·작품) | 배경이 살아있게 만드는 유일한 요소 |
| 뒤쪽 사물함 | **엄폐물 겸용** — 게임플레이 오브젝트다 |
| 청소도구함 | 엄폐물 |
| 태극기 + 교훈 액자 (칠판 위) | 결정타 |
| 창가 커튼 + 화분 | 빛 방향의 근거 |

엄폐물에는 반드시 `CollectionService` 태그 `Cover`를 붙인다. Phase 1의 레이캐스트가 이 태그만 본다.

> **구현 결과(2026-08-15):** `src/server/Classroom/Template.luau` 하나가 교실 전체를 만든다. 외부 에셋은 하나도 쓰지 않았다 — 한국 교실이라는 인상은 `SurfaceGui` 텍스트(판서 내용·급훈·게시판 제목·시간표)와 파트로 조립한 태극기(4괘 포함)에서 나온다.
>
> **게임플레이에 영향을 주는 치수는 Phase 1과 하나도 바꾸지 않았다.** 내부 46×38, 교탁 z = −15, 문 x = 14, 3×6 책상 배치, 엄폐물 3개의 X/Z 치수가 전부 그대로다. Studio에서 검증한 난이도가 아트 교체로 흐트러지면 안 되기 때문이다.
>
> 유일한 변경은 **천장 높이 16 → 11**이다. 16스터드는 사람 키(5.6)의 세 배라 "낮고 답답한 한국 교실"과 정반대였다. 감지는 전부 수평 판정이므로 순수하게 시각적인 변경이다.

### 5.2 학생 NPC — 클라이언트 전용 렌더

18명 × 12슬롯 = 216 모델. 이걸 서버에 두면 서버가 죽는다. **서버는 학생을 모른다.**

| | 서버 | 클라이언트 |
|---|---|---|
| 소유물 | 좌석 파트 18개 (`Seat` 태그 + `IsEmpty` 어트리뷰트) | 학생 모델 18개 |
| 인스턴스 수 | 슬롯당 18 → 총 216 | 자기 교실 18개만 |
| 목적 | 착석 검증의 근거 | 보이는 것 전부 |

```luau
-- src/client/Controllers/StudentRenderController.luau
-- 좌석 폴더를 훑어 빈자리가 아닌 곳에만 학생을 세우고,
-- 이후 IsEmpty 변화를 구독해 자동으로 붙였다 뗀다.
local function track(seat: BasePart)
    seat:GetAttributeChangedSignal("IsEmpty"):Connect(function()
        refresh(seat)
    end)
    refresh(seat)
end
```

> **구현 결과:** 좌석 발견은 태그가 아니라 **복제되는 `Seats` 폴더**로 한다(`Classroom/Seats/Seat01…Seat18`). 태그는 클라이언트에 언제 도착할지 예측하기 어려워서, 폴더 + `ChildAdded` 쪽이 렌더 타이밍을 잡기 쉽다. `Cover` 태그는 서버 레이캐스트 전용이므로 그대로 태그를 쓴다.
>
> 학생 모델은 서버 선생님과 **같은 `CharacterBuilder`**(`src/shared/CharacterBuilder.luau`)로 만든다. 얼굴(눈·코·입·머리카락)이 한 곳에서만 정의되므로 선생님과 학생의 인상이 어긋나지 않는다. 클라이언트 전용 모델은 반드시 `CanCollide = false`다 — 클라이언트에만 있는 충돌체는 플레이어 위치를 서버가 보는 위치와 어긋나게 만든다.
>
> idle은 30Hz로 돌리고, 파트를 하나씩이 아니라 `Model:PivotTo`로 **모델 전체를 한 번에** 옮긴다. 머리·머리카락·눈·코·입이 별개 파트라서, 머리만 돌리면 얼굴이 머리에서 떨어져 나간다.

학생 모델에는 **`Humanoid`를 넣지 않는다.** 앉아만 있는 더미에 `Humanoid`는 순수한 낭비다(상태 머신, 물리, 렌더 스텝을 전부 돌린다). 파트 조립체 + 미세한 idle 트윈(고개 아주 살짝, 어깨 호흡)이면 충분하고, 오히려 더 "수업 중"처럼 보인다.

**전원이 칠판을 본다.** 이건 분위기가 아니라 게임 규칙이다 — 학생이 아무도 뒤를 안 보기 때문에 플레이어가 뒤에서 들어올 수 있다는 설정이 성립한다.

### 5.3 착석 — 서버 검증

입력은 `RemoteEvent`가 아니라 **`ProximityPrompt`**로 받는다. 엔진이 좌석 인스턴스를 직접 넘겨주므로 `seatId`를 위조할 여지가 아예 사라지고, E키·터치·게임패드 UI가 공짜로 딸려온다. 대신 `MaxActivationDistance`는 **신뢰하지 않는다** — 원격으로 프롬프트를 발동시키는 익스플로잇이 실재하므로 서버가 거리를 다시 잰다.

```luau
-- src/server/Services/ProgressService.luau
function ProgressService.onSeatTriggered(player: Player, seat: BasePart)
    if now - (lastTrigger[player] or 0) < TRIGGER_INTERVAL then return end  -- 레이트 리밋
    if busy[player] then return end                            -- 상태 (연출 중)
    if not seat:IsDescendantOf(session.model) then return end  -- 내 교실 좌석인가 (Phase 4)
    if not ClassroomService.isEmpty(seat) then return end      -- 실제로 빈자리인가

    local _, _, hrp = getParts(player)
    if not hrp then return end
    local dist = (hrp.Position - seat.Position).Magnitude
    if dist ~= dist or dist > SIT_RANGE then return end        -- NaN 방어 + 거리

    clear(player, seat)
end
```

**거리 검증이 없으면 텔레포트 치트로 72반이 3초에 뚫린다.** `dist ~= dist`는 NaN 체크다 — NaN은 `>` 비교가 항상 false라서 범위 검사를 그냥 통과해버린다. `SIT_RANGE = 12`로 잡았다. 분단 간격이 14이므로 옆 분단 좌석에 원격으로 앉는 것은 막히면서, 자기 앞 좌석에는 여유롭게 닿는다.

**소속 검증은 교실이 12개가 된 Phase 4에서 필수가 된다.** 거리(12)에 비해 슬롯 간격이 5000이라 옆 교실 좌석은 거리 검사에 걸리긴 한다. 하지만 그건 우연히 막히는 것이지 막은 것이 아니다. 좌석이 내 세션 모델의 자손인지 직접 묻는 편이 배치 수치에 기대지 않아 안전하다.

좌석 소유권은 `ClassroomService`가 쥔다 — `IsEmpty`를 바꾸는 곳도, 프롬프트를 켜고 끄는 곳도 여기 하나뿐이다.

레이트 리밋은 서버를 보호할 뿐, 검증을 대신하지 않는다. 둘 다 한다.

### 5.4 성공 / 실패 연출

**성공(앉는 순간 즉시 클리어):** 화면 살짝 줌 → "✨ 1학년 3반 통과" → 별 획득 → 0.8초 후 다음 반 문 앞으로.
느슨한 확인 절차를 넣지 않는다. 앉으면 끝, 이게 기획 확정 사항이다.

**실패:** 선생님이 플레이어를 향해 손가락질 → 화면 정지 0.4초 → "야! 너 뭐야!" → 페이드 → **해당 교실 문 앞** 재시작.
운동장으로 돌려보내지 않는다. 진행도는 유지된다. 실패의 비용은 "시간"이지 "진행도"가 아니다.

적발 사유(`moved_in_sight` 등)를 작게 표시한다. 왜 죽었는지 알아야 다음 판이 학습이 된다.

> **구현 결과:** 성공과 실패를 **`ProgressService` 한 곳**에 넣었다. 둘 다 "플레이어를 얼려서 연출을 보여주고 문 앞으로 되돌린다"는 같은 절차이고, 이게 흩어지면 성공 직후 적발 같은 이중 처리가 반드시 생긴다. `DetectionService`는 판정만 하고 `caughtHandler` 콜백으로 넘긴다.
>
> 순간이동(부활·착석) 직후에는 항상 `DetectionService.forget(player)`를 부른다. 이걸 빠뜨리면 이동한 거리가 다음 틱에 통째로 델타로 잡혀 "가만히 있었는데 죽었다"가 된다.
>
> 클라이언트 `FeedbackController`의 연출 길이는 서버가 얼려두는 시간(성공 0.9초 / 실패 1.0초)에 맞춰 잘라뒀다. 연출이 서버보다 길면 이미 문 앞으로 돌아온 플레이어 위에 "통과!" 글자가 남고, 짧으면 아무것도 안 하는 정적이 생긴다.

### 5.5 ✅ Phase 3 완료 기준

1. 스크린샷을 아무에게나 보여주면 "한국 초등학교 교실"이라고 답한다.
2. 한 판(문 앞 진입 → 착석)이 **30~60초**에 끝난다. 시간을 재서 확인한다.
3. 학생 18명이 전원 칠판을 보고 있고, 미세하게 움직인다.
4. 12슬롯을 전부 채운 상태에서 **모바일 실기기** FPS 30 이상, 서버 heartbeat 16ms 미만 (MicroProfiler `Ctrl+F6`으로 확인).
5. 좌석에서 멀리 떨어져 `fireproximityprompt`로 프롬프트를 직접 발동시켜도 클리어되지 않는다. (Studio에서 클라 콘솔로 직접 테스트)
6. 성공/실패 연출이 각각 1초 안에 완결되어 다음 시도로 넘어간다.

---

## 6. Phase 4 — 12반 루프

> **목표:** 1반부터 12반까지 이어지는 진행, 난이도 상승, 성장, 그리고 껐다 켜도 남는 저장.

### 6.1 슬롯 인스턴싱

교실은 **1개 템플릿을 X축 5000 studs 간격으로 복제**한다. 플레이어마다 자기 슬롯을 받으므로 서로 간섭이 없다.

```luau
-- src/server/Services/ClassroomService.luau
function ClassroomService.acquire(player: Player)   -- 빈 슬롯 할당 + 소유자 지정
function ClassroomService.release(player: Player)   -- 방해물·선생님 리셋 + 슬롯 반납
```

**구현 결과.** 슬롯은 서버 부팅 때 12개를 한 번에 지어두고, 입·퇴장은 소유자만 갈아끼운다. 매번 짓고 부수면 12명이 동시에 반을 넘길 때 조립 비용이 몰린다.

- 좌표는 `x = 10000 + (index - 1) * 5000`. **월드 원점을 비워두는 것이 핵심이다** — Phase 5의 운동장 허브가 원점에 들어와도 이미 튜닝을 끝낸 감지 수치를 옮길 일이 없다.
- `Template.build()` 는 반환 직전 `room.WorldPivot = CFrame.new()` 를 못박는다. 이게 없으면 `PivotTo(slotOrigin)` 이 바운딩박스 중심을 기준으로 움직여 슬롯 배치가 순수 평행이동이 아니게 된다.
- 교실 12개가 동시에 살아있으므로 **선생님 상태 패킷은 `FireAllClients` 가 아니라 소유자 한 명에게 `FireClient`** 로 나간다. 방송하면 남의 교실 선생님이 돌아볼 때마다 내 화면에 비네트가 번쩍인다.
- 반이 바뀌어도 `stateVersion` 은 **리셋하지 않는다.** 클라이언트의 순서 필터가 단조 증가를 전제로 하므로, 리셋하면 새 반의 첫 패킷이 통째로 버려진다.

**클라이언트는 자기 교실을 어떻게 찾는가.** 서버가 `acquire` 시점에 `Player` 아래에 `ObjectValue "Room"` 을 만들어 교실 모델을 가리킨다. 클라는 `RoomRef.await()` 로 한 번 해석해 컨트롤러 네 개에 인자로 넘긴다. 숨은 전역이 없고, 스트리밍 때문에 `.Value` 가 잠깐 `nil` 인 구간은 마감시한이 있는 폴링으로 넘긴다.

이름 문자열(태그·폴더명·어트리뷰트·`ObjectValue` 이름)은 서버와 클라가 같은 걸 봐야 하므로 `src/shared/Config/RoomKeys.luau` 한 곳에만 둔다. 양쪽에 리터럴을 흩뿌리면 오타 하나가 런타임까지 살아남는다.

**⚠️ 스트리밍 함정.** `StreamingEnabled`의 기본 타깃 반경은 1024 studs다. 5000 studs 떨어진 슬롯으로 그냥 텔레포트하면 도착 순간 교실이 아직 없다. 바닥을 뚫고 떨어지거나, 좌석을 못 찾아 스크립트가 멈춘다.

**구현 결과 — 텔레포트 자체를 없앴다.** 캐릭터를 원점에 띄워놓고 슬롯으로 옮기면 "스폰과 텔레포트 중 무엇이 먼저인가"라는 경쟁이 생긴다. `CharacterAdded` 를 붙잡고 이기려 드는 대신, 캐릭터를 **처음부터 슬롯에 만든다.**

```luau
Players.CharacterAutoLoads = false          -- 부팅 때 한 번
-- 입장 처리
player.RespawnLocation = session.spawn      -- 슬롯 안의 SpawnLocation
pcall(function() player:RequestStreamAroundAsync(session.spawn.Position) end)
player:LoadCharacterAsync()                 -- 바닥이 존재하는 것이 보장된 뒤에 생성
```

`RequestStreamAroundAsync` 는 `pcall` 로 감싼다. 실패해도 스폰은 진행되어야 하고, `StreamingIntegrityMode` 가 뒤를 받친다. 잡혀서 되돌아갈 때만 `PivotTo(doorCFrame)` 를 쓴다 — 이때는 교실이 이미 스트리밍되어 있다.

이 0.3~1초는 Phase 5에서 **교실 문이 열리는 연출 뒤에 숨긴다.** 로딩 화면을 띄우면 리듬이 끊긴다. 문고리를 잡고 문이 삐걱 열리는 1초가 정확히 그 자리다.

또한 `StreamingIntegrityMode`를 설정해, 스트리밍이 못 따라갈 때 플레이어가 빈 공간으로 떨어지는 대신 대기하도록 한다. 스트림 아웃된 인스턴스는 **삭제된 게 아니라 `Parent = nil`** 이므로, 클라에서 `FindFirstChild`가 `nil`을 반환할 수 있다. 반드시 타임아웃 있는 `WaitForChild`를 쓴다.

### 6.2 별과 업그레이드

| 획득 | 별 |
|---|---|
| 반 클리어 | 1 |
| 무적발 클리어(퍼펙트) | +1 |
| 학년 최초 클리어 | +3 |

1학년 전체에서 얻는 별은 대략 20~30개. 업그레이드 3종은 이 예산 안에서 **전부는 못 사도록** 가격을 매긴다. 선택이 강제되어야 선택이 의미를 갖는다.

```luau
-- src/shared/Config/Upgrades.luau
local Upgrades = {
    quietShoes = { cost = 8,  desc = "실내화 — 걷기 소음 반경 절반" },
    balance    = { cost = 10, desc = "균형감각 — 모든 정지 거리 25% 감소" },
    instinct   = { cost = 12, desc = "눈치 — 예고 신호가 0.1초 먼저 온다" },
}
```

가격은 서버 정의에서만 읽는다. 클라이언트가 보낸 가격은 물론이고, 클라가 보낸 "구매 성공" 같은 것도 믿지 않는다.

**별 예산 확정.** 12(반 클리어) + 12(퍼펙트) + 3(학년 최초 수료) = **최대 27개**, 업그레이드 3종 합계는 **30개**. 완벽하게 밀어도 하나는 못 산다. 완료 기준 6번이 산수로 보장된다.

같은 반을 다시 깨도 별이 또 나오지는 않는다. `cleared["1-3"]` / `perfect["1-3"]` 로 반별 최초 1회만 지급한다. 이게 없으면 1반을 반복해 별을 무한히 캘 수 있다.

**업그레이드가 실제로 적용되는 지점은 셋 다 다르다.**

| 업그레이드 | 적용 위치 | 방식 |
|---|---|---|
| 실내화 | 서버 | `session.noiseRadius` 를 절반으로 |
| 균형감각 | 클라 | 프로필 스냅샷을 받아 `stopTime` 에 계수를 곱함 |
| 눈치 | 서버 | 난이도 설정 조립 시 `teachTime` 에서 0.1초를 떼어 `warnTime` 에 붙임 |

눈치가 사이클 **길이를 바꾸지 않는 것**이 중요하다. 예고를 0.1초 앞당기는 대신 판서 시간을 그만큼 줄이므로, 한 사이클의 총 길이는 그대로다. 사이클이 길어지면 "반응 여유를 준다"가 아니라 "게임이 쉬워진다"가 되고, 난이도 테이블에 적어둔 수치가 전부 의미를 잃는다.

균형감각만 클라에 있는 이유는 정지 거리가 순전히 체감이기 때문이다. 조작해봐야 스스로 건 페널티가 사라질 뿐, 적발 판정은 여전히 서버가 기록한 위치 델타로만 난다.

구매 UI 는 Phase 5다. 지금은 숫자키 1·2·3에 임시로 붙여둔다 — 별 경제가 실제로 도는지 확인하려면 직접 사봐야 하는데, 이를 위해 상점 UI를 기다릴 필요는 없다.

### 6.3 방해물 (1학년용 2종만)

기획서의 방해물 카탈로그 전체를 지금 만들지 않는다. 1학년에는 규칙 학습을 방해하지 않는 순한 것 2종만 넣는다.

- **삐걱거리는 마룻바닥** — 특정 타일을 밟으면 소리. 걷기 이상 속도에서만 발동. 선생님이 즉시 회전.
- **굴러다니는 지우개/필통** — 통로에 놓인 오브젝트. 밟으면 미끄러져 정지 거리가 늘어난다.

둘 다 6반 이후에만 등장시킨다. 1~5반은 순수하게 규칙을 배우는 구간이다.

**구현 결과 — 판정 주체가 서로 다르다.**

| 방해물 | 판정 위치 | 이유 |
|---|---|---|
| 삐걱거리는 마룻바닥 | 서버 | 선생님을 즉시 돌리면 적발로 이어진다. 클라가 정할 수 없다 |
| 굴러다니는 지우개·필통 | 클라 | 정지 거리만 늘린다. 조작해봐야 스스로 건 페널티가 사라질 뿐이다 |

마룻바닥은 감지 틱(20Hz) 안에서 위치와 속도를 함께 본다. 발동 속도는 `CREAK_SPEED = 7` — 살금살금(4)은 통과하고 걷기(10) 이상이면 밟힌다. 계획서에 "걷기 이상"이라고만 적혀 있던 값을 두 속도 사이의 실제 수치로 못박았다.

지우개는 반대로 서버에 올리면 안 된다. 20Hz 틱은 밟고 지나가는 순간을 놓치고, 그러면 "분명 밟았는데 안 미끄러졌다"가 생긴다. 매 프레임 도는 클라가 판정해야 손맛이 맞는다.

**별도의 `ObstacleService` 는 만들지 않았다.** 방해물은 교실의 일부이므로 조립은 `Template`, 켜고 끄기는 `ClassroomService`, 삐걱 판정은 이미 20Hz로 도는 `DetectionService` 안에 들어간다. 서비스를 하나 더 세우면 같은 상태에 주인이 둘이 된다.

**방해물이 켜지면 눈에 보이게 만든다.** 삐걱 타일은 투명도를 0으로 내려 나뭇결이 드러나고, 지우개도 그때 나타난다. 보이지 않는 함정은 억울함이고, 억울함은 이 게임에서 가장 피해야 할 감정이다. 5반까지는 투명도 1로 숨겨둔 채 자리만 잡고 있다.

### 6.4 데이터 저장

```luau
-- src/server/Services/DataService.luau
local DEFAULT_PROFILE = {
    version = 1,
    grade = 1, class = 1,
    stars = 0,
    upgrades = {},                          -- 산 것만 들어간다
    cleared = {}, perfect = {},             -- "1-3" 같은 키. 별 중복 지급 방지
    gradeCleared = {},
    totalSeconds = 0,
    attempts = 0, caught = 0,
}
```

계획서 초안의 중첩 구조(`progress.grade`, `run.totalSeconds`)를 한 겹으로 폈다. 중첩은 `Reconcile` 이 새 필드를 채워 넣을 때 한 단계마다 기본값 표를 따라 내려가야 해서, 얻는 것 없이 마이그레이션만 까다로워진다.

**저장 시점은 세 곳뿐이다.**

| 시점 | 이유 |
|---|---|
| ProfileStore 자동 저장(약 5분) | 크래시 대비 |
| 학년 수료 시 | 가장 중요한 이정표. `Profile:Save()` 를 명시 호출 |
| 퇴장 시 `EndSession()` + ProfileStore 자체 `BindToClose` | `PlayerRemoving`만으로는 서버 종료를 못 막는다 |

**60초 수동 저장 루프는 만들지 않았다.** ProfileStore 가 이미 주기적으로 자동 저장하고 `BindToClose` 도 스스로 등록한다. 그 위에 12명 × 60초 루프를 얹으면 DataStore 쓰기 예산만 태우고 얻는 것이 없다. 명시 저장은 학년 수료 한 곳뿐이다.

**`OnSessionEnd` 는 우리가 부른 `EndSession()` 에도 똑같이 발동한다.** 그래서 여기서 무조건 킥을 하면, 그냥 나가는 플레이어를 잡으려 드는 꼴이 된다. `releasing[player]` 플래그를 `EndSession()` 직전에 세워 정상 퇴장과 세션 탈취를 구분한다.

**반 클리어마다 저장하지 않는다.** 72반 = 72회 쓰기이고, 2026년부터 경험별 DataStore 쿼터가 실제로 적용된다(초과 시 에러가 아니라 **스로틀**이므로 조용히 느려진다). 진행도는 세션 테이블에 들고 있다가 위 세 시점에만 내려쓴다.

**세션 락은 필수다.** 같은 유저의 프로필을 두 서버가 동시에 쓰면 진행도가 사라진다. ProfileStore의 `StartSessionAsync` / `Profile.OnSessionEnd` / `EndSession`을 문서대로 쓴다. `Steal` 옵션은 일반 로딩에 쓰지 않는다.

Studio 테스트에는 `ProfileStore.Mock`을 쓴다. 개발 중 실서비스 키를 오염시키면 되돌릴 수 없다.

`version` 필드는 지금 당장 쓸 일이 없어도 **반드시 넣는다.** 스키마가 바뀌는 날 이 필드가 없으면 기존 플레이어 데이터를 통째로 버려야 한다.

### 6.5 ✅ Phase 4 완료 기준

1. 1반 → 12반이 끊김 없이 이어진다. 각 반 사이 전환이 1.5초 이내.
2. 반마다 `teachTime`이 실제로 줄어드는 것이 체감된다. (1반과 12반을 연속으로 플레이해 비교)
3. **1반 실패율 15% 미만, 12반 실패율 40~60%.** 20판씩 돌려 센다. 1반이 어려우면 학습이 안 되고, 12반이 쉬우면 성장이 안 느껴진다.
4. 강제 종료(Studio Stop) 후 재접속 시 학년/반/별/업그레이드가 그대로다.
5. 12슬롯 동시 사용 상태에서 서버 heartbeat 16ms 미만 유지.
6. 별 예산으로 업그레이드 3종을 다 못 산다.
7. Studio 테스트가 실 DataStore를 건드리지 않는다. (Data Stores Manager로 확인)

이 중 6번은 산수로 이미 확정됐고(27 < 30), 7번은 `RunService:IsStudio()` 분기로 `ProfileStore.Mock` 을 쓰도록 코드에 박혀 있다. **1·2·3·4·5번은 Studio 플레이테스트로만 확인된다** — 특히 3번(실패율)은 20판씩 돌려 세는 것 외에 방법이 없고, 그 결과가 `DifficultyTable` 을 고칠 유일한 근거다.

---

## 7. Phase 5 — 포장과 검증

> **목표:** 남에게 링크를 보낼 수 있는 상태로 만든다.

### 7.1 운동장 허브

잠입 구간이 아니다. 안전한 로비다.

- 스폰 지점: 운동장 한가운데. **첫 시야에 학교 본관이 정면으로 들어와야 한다.**
- 조회대, 구령대, 축구 골대, 철봉, 정글짐, 이순신 동상 또는 책 읽는 소녀상
- 본관 입구로 걸어가면 **신발장 앞 전환** → 실내화로 갈아신는 짧은 연출 → 현재 반의 문 앞으로
- 허브에 업그레이드 상점(별 사용)과 진행도 표시

신발장 연출은 두 가지 일을 동시에 한다: (a) 한국 학교 정서의 결정타, (b) `RequestStreamAroundAsync` 대기 시간을 가려주는 자연스러운 장치.

> **구현 결과(2026-08-15) — 허브는 월드 원점에 짓는다.** Phase 4에서 교실 슬롯을 `x = 10000 + (i-1) × 5000`에 깐 것은 원점을 허브 몫으로 비워두기 위해서였다. 그 자리에 `src/server/Playground/Template.luau` 하나가 운동장 전체를 만든다.
>
> | 요소 | 위치 | 비고 |
> |---|---|---|
> | 스폰 | `(0, 0.5, 40)` | `SpawnLocation`, Neutral, 투명 + 충돌 없음 |
> | 본관 정면 | `z = -80`, 폭 160, 높이 44 | 3층 창문 격자, 차양, 현관 계단, "**행복초등학교**" 간판 |
> | 축구 골대 | `(±72, 0, 28)` | 서로 마주 본다 |
> | 구령대 | `(-46, 0, -56)` | 계단·난간·"행복초등학교" 표지 |
> | 철봉 | `(58, 0, -44)` | 3단(5 / 6.5 / 8) |
> | 정글짐 | `(-72, 0, -18)` | 12칸 3층, 빨간 철제 |
> | 책 읽는 소녀상 | `(30, 0, -62)` | 좌대 + 명판 |
> | 국기 게양대 | `(-26, 0, -64)` | |
>
> **"첫 시야에 본관이 정면으로"는 좌표가 아니라 회전으로 푼다.** 로블록스 `CFrame`의 LookVector는 로컬 −Z다. 스폰을 회전 없이 `(0, 0.5, 40)`에 두면 캐릭터는 자동으로 −Z, 즉 `z = -80`의 본관을 정면으로 보고 서게 된다. 이 게임의 모든 기하가 −Z = 앞으로 통일돼 있어서 생기는 공짜 결과다.
>
> **교실 템플릿과 겹치는 조립 코드는 `src/server/BuildKit.luau`로 뽑았다.** `part()`와 `surfaceText()` 두 개뿐이고, `Classroom/Template.luau`도 여기로 옮겼다. 세 번째 건물이 생기기 전에 뽑은 게 아니라, 두 번째가 생겼을 때 같은 40줄이 그대로 복제되는 것을 보고 뽑았다.

### 7.1b 허브 ↔ 교실 왕복 — 리모트를 하나도 안 늘렸다

> **구현 결과 — 클라이언트→서버 `RemoteEvent`가 이 게임에 0개다.**
>
> 신발장을 누르면 교실로 들어가야 하고, 문구점 매대를 누르면 업그레이드를 사야 한다. 평범하게 짜면 리모트 두 개가 늘어나고, 그 순간 "인자를 위조하면?"이라는 질문이 두 개 늘어난다. 대신 Phase 3의 좌석 방식을 그대로 확장했다 — **`ProximityPrompt`가 입력 채널이다.** 엔진이 어떤 인스턴스가 눌렸는지를 직접 알려주므로 위조할 인자 자체가 없다.
>
> - 신발장 프롬프트 `실내화로 갈아신기` → `ProgressService.enterClass`
> - 문구점 매대 3개 `Shop_<key>` → `ProgressService.onUpgradeRequested(player, key)`
> - 교실 문 안쪽 `ExitDoor` 프롬프트 `복도로 나가기` → `ProgressService.exitToHub`
>
> 그래서 Phase 4의 `RequestUpgrade` 리모트는 **삭제했다.** 지금 남은 리모트 8개는 전부 서버→클라 단방향이다: `TeacherStateChanged` `Caught` `ClassCleared` `ProfileUpdated` `GradeCleared` 그리고 Phase 5에서 늘어난 `Transition`(화면 덮기) `Notice`(HUD 한 줄) `Cue`(짧은 소리 하나).
>
> **12명 공용 허브의 대가.** 프롬프트는 인스턴스 하나를 12명이 같이 본다. 플레이어별로 껐다 켤 수가 없으므로 매대 프롬프트는 항상 켜두고, **살 수 없는 이유는 서버가 `Notice`로 설명한다**("이미 가지고 있다" / "★N개가 모자란다"). 눌러보고 알게 되는 편이 눌리지도 않는 것보다 낫다.
>
> **`RespawnLocation`을 같이 갈아끼운다.** 허브에서 시작하도록 바꾸면 새 구멍이 하나 생긴다 — 교실 안에서 Reset Character를 누르면 운동장에서 되살아나는데 `session.inClass`는 여전히 참이라, 아무도 없는 교실에서 수업이 계속 돈다. `enterClass`에서 `player.RespawnLocation = session.spawn`으로, `exitToHub`에서 허브 스폰으로 되돌려 막았다. 같은 이유로 `DetectionService`의 감지 루프와 `ProgressService.fail`·`onSeatTriggered`가 전부 `session.inClass`를 먼저 본다.
>
> **클라이언트 부팅이 두 단계가 됐다.** 첫 화면이 운동장이면 교실은 10,000 스터드 밖이고 `StreamingEnabled` 때문에 내려오지도 않는다. 부트 시점에 `RoomRef.await`를 부르면 20초를 기다리다 터진다. 그래서 컨트롤러를 갈랐다.
>
> - 허브에서도 도는 것 — `Camera` `Movement` `Hud` `Sound` `Transition`
> - 교실이 있어야 하는 것 — `Signal` `StudentRender` `Feedback`
>
> 뒤쪽은 첫 `Transition {to = "class"}`가 올 때 딱 한 번 붙인다. **검은 전환 화면이 정확히 그 대기를 가리는 물건이다** — 신발장 연출이 스트리밍을 숨긴다는 §7.1의 설계가 코드에서도 그대로 성립한다.

### 7.2 사운드 8종

사운드가 이 게임의 절반이다. 예고 신호가 청각이기 때문이다.

| # | 소리 | 역할 |
|---|---|---|
| 1 | 분필 판서 (루프) | **가장 중요.** 이게 멈추는 것이 예고 신호 |
| 2 | 선생님 목소리 (웅얼거리는 수업, 루프) | 안전 구간의 배경 |
| 3 | 마룻바닥 삐걱 | 방해물 |
| 4 | 실내화 발소리 (모드별 3종) | 자기 소음의 자각 |
| 5 | 의자 끄는 소리 | 착석 성공 |
| 6 | "야!" 호통 | 적발 |
| 7 | 복도 웅성거림 / 멀리서 나는 다른 반 소리 | 학교라는 공간감 |
| 8 | 수업 종 | 학년 승급 |

1번과 4번은 3D 사운드로, 나머지는 상황에 따라 2D로 둔다. 분필 소리는 반드시 선생님 위치에서 나야 한다 — 방향으로 선생님을 인지할 수 있어야 한다.

> **구현 결과 — 11개 정의가 `src/shared/Config/SoundConfig.luau` 한 곳에 있다.** 발소리 3종을 따로 세고, 나중에 붙은 9번 교실 배경음(§7.8)까지 세어서 11개다. `SoundConfig.DEFS[key]` → `SoundConfig.create(key)`가 `Sound` 인스턴스를 만들고, `rollOff`가 있는 정의만 `InverseTapered` + `RollOffMaxDistance`를 받아 3D가 된다.
>
> **⚠️ 음원 ID는 전부 `rbxasset://sounds/*` 대역품이다.** 엔진에 기본 내장된 경로라 아무것도 업로드하지 않고도 게임이 소리를 낸다. 다만 이건 음높이와 볼륨으로 흉내 낸 것이지 진짜 분필 소리가 아니고, **경로 중 일부는 존재하지 않아 조용히 안 울릴 수 있다 — Studio에서 하나씩 확인해야 한다.** 교체 지점은 `SoundConfig.DEFS` 한 곳뿐이므로, 진짜 음원을 올린 뒤 ID 문자열만 갈아끼우면 끝난다. 이 파일 하나로 좁혀둔 것이 이 절의 실제 산출물이다.
>
> **소리 주인이 세 곳으로 갈린다. 각각 이유가 있다.**
>
> | 소리 | 주인 | 이유 |
> |---|---|---|
> | 분필, 수업 목소리 | `SignalController` (클라, 선생님 Head에 부착) | 예고 신호와 한 몸이다. 신호가 멈추는 것과 소리가 멈추는 것이 한 프레임이라도 어긋나면 억울함이 된다 |
> | 발소리, 의자, 호통, 종, 복도 웅성거림 | `SoundController` (클라, `SoundService`) | 발소리는 20Hz 서버 틱으로는 발 닿는 순간을 못 맞춘다. 여기서 속이면 자기 귀만 속는다 |
> | 마룻바닥 삐걱 | **서버** `DetectionService` → `Remotes.Cue` | 소리와 판정이 갈라지면 안 된다. 삐걱 소리가 났는데 안 걸리거나 그 반대면 규칙이 무너진다 |
>
> 삐걱만 서버에 둔 대가로 중복 발사를 막아야 한다 — 판정이 20Hz로 도니까 그냥 두면 초당 20번 울린다. `CREAK_COOLDOWN = 0.5`로 플레이어별 쿨다운을 뒀다.
>
> **첫 분필 소리는 `SignalController.Start` 끝에서 직접 튼다.** 이 컨트롤러는 교실 전환 도중에 붙는데, 그때 서버는 이미 첫 `TEACHING`을 보내고 지나간 뒤다. 그 패킷을 놓치면 하필 **첫 판 첫 사이클에 예고 신호가 없다.** 수업은 항상 `TEACHING`으로 시작하므로 여기서 한 번 트는 것이 안전하다.
>
> 발소리 간격은 모드별로 다르다 — 살금살금 0.62초 / 걷기 0.42초 / 달리기 0.28초. 수평 속도가 `STEP_MIN_SPEED = 2` 미만이거나, 앉아 있거나, 공중이면 아예 틀지 않는다.

### 7.3 HUD

최소로. 화면을 가리면 안 되는 게임이다.

- 좌상단: `1학년 3반` + 별 개수
- 하단 중앙: 현재 이동 모드 아이콘 (작게)
- 모바일: 자동 생성된 Sneak/Sprint 버튼 (Phase 2에서 이미 나옴)
- 적발 시에만: 사유 텍스트

체력바, 미니맵, 퀘스트 로그 같은 건 없다. 이 게임에 필요 없다.

> **구현 결과 — `src/client/Controllers/HudController.luau` 하나가 다섯 줄을 그린다.** 좌상단 `N학년 N반`, 그 아래 금색 `★ N`, 하단 중앙 이동 모드(투명도 0.25로 옅게), 화면 아래쪽 알림 한 줄, 학년 승급 배너.
>
> 여섯 번째 줄은 나중에 붙었다 — 좌상단 별 아래의 `🔊 소리 켬 / 🔇 소리 끔` 토글이다. 표시가 아니라 조작인 유일한 요소인데, 최소 HUD 원칙을 깨면서까지 화면에 남겨둔 이유는 §7.7에 있다.
>
> **없애는 것도 HUD 작업이다.** Phase 1~4를 지나며 쌓인 디버그 라벨을 전부 걷어냈고, `StarterGui:SetCoreGuiEnabled`로 **체력바와 배낭을 껐다.** 이 게임에는 체력도 아이템도 없는데 로블록스 기본 UI가 둘 다 그려주고 있었다. `pcall`로 감싼 것은 이게 실패해도 게임이 안 죽어야 하기 때문이다.
>
> 이동 모드는 `MovementController.getMode()`를 `RenderStepped`에서 읽는다. 모드 변경 이벤트를 따로 만들지 않았다 — 이미 매 프레임 도는 컨트롤러가 들고 있는 값이라 굳이 신호를 하나 더 만들 이유가 없다.
>
> **전환 화면은 별도 컨트롤러(`TransitionController`)다.** 검은 오버레이 + 가운데 문구 한 줄이고, 페이드 0.18초 → 유지 0.42초 → 페이드아웃 0.3초. 문구는 방향에 따라 "실내화로 갈아신는 중…" / "복도로 나가는 중…". 서버 쪽 `TRANSITION_HOLD = 0.55`는 이 페이드인+유지 구간 안에 텔레포트가 끝나도록 맞춘 값이다. HUD와 섞지 않고 `DisplayOrder = 8`로 따로 띄운 건, 이게 **다른 모든 것을 덮는 게 일**이기 때문이다.

### 7.4 조명

한국 초등학교 교실의 빛은 **창가 쪽이 밝고 복도 쪽이 어둡다.** 이 비대칭이 교실을 진짜처럼 만들고, 동시에 게임플레이가 된다 — 어두운 복도 쪽 벽을 따라 이동하면 심리적으로 안전하게 느껴진다.

`Lighting.Technology = Future`, 창문에서 들어오는 낮 시간대 방향광, 살짝 뿌연 공기 원근. 형광등은 켜져 있되 약하게.

> **구현 결과 — 절반은 `default.project.json`, 절반은 교실 템플릿이다.**
>
> 전역은 프로젝트 파일에 박았다: `Technology = Future`, `ClockTime = 10`(오전 수업 시간), `Brightness = 2.4`, `GeographicLatitude = 37.5`(서울), 그리고 `Atmosphere`(`Density 0.36`, `Haze 1.6`, `Glare 0.35`)가 뿌연 공기 원근을 맡는다.
>
> 비대칭은 교실 안에서 만든다. `Classroom/Template.luau`의 `buildStructure`가 형광등 4개를 좌우로 다르게 켠다.
>
> | | 창가 쪽(`x = -11`) | 복도 쪽(`x = +11`) |
> |---|---|---|
> | 등갓 투명도 | 0 | 0.25 |
> | `PointLight.Brightness` | 0.9 | 0.4 |
> | `Range` | 50 | 48 |
>
> 여기에 창가 벽면(`x = -HALF_W + 2.4`)을 따라 보이지 않는 `SunGlow` 파트 3개를 두고, 각각 따뜻한 색(255, 244, 214)의 `PointLight`를 1.0 밝기 / `Range` 58로 물렸다. 실제 창문에서 빛이 들어오는 것처럼 보이게 하는 값싼 흉내다.
>
> **밝기와 `Range`는 처음 값(1.3·1.6 / 26~36)에서 한 번 갈아엎었다.** `Range`가 방보다 작으면 밝기 차이가 아니라 경계선이 생긴다 — 자세한 것은 §7.8에 있다.
>
> 모든 조명의 `Shadows`는 꺼져 있다. 교실 하나에 광원이 7개인데 12슬롯이 동시에 살아 있을 수 있고, **이 게임에서 그림자는 아무 정보도 주지 않는다** — 선생님 위치는 소리와 시야로 알아야지 그림자로 알면 안 된다.

### 7.5 플레이테스트 — 이 Phase의 진짜 목적

**지인 3명에게 튜토리얼 없이 링크를 준다.** 아무 설명도 하지 않는다.

관찰할 것:
- 규칙을 스스로 알아내는 데 몇 판 걸리는가 (목표: 3판 이내)
- 어디서 처음 웃는가 / 어디서 처음 짜증내는가
- 몇 반까지 가는가 (목표: 3반 이상)
- **자발적으로 "한 판만 더"를 하는가** — 이게 유일하게 중요한 지표다

여기서 나온 피드백은 다음 개발 사이클에 반영할 몫이지, Phase 5 안에서 전부 고치려 하지 않는다. 단, "규칙을 못 알아냄"이나 "억울해서 껐음"이 나오면 그건 Phase 1~2로 돌아가야 한다는 뜻이다.

### 7.6 ✅ Phase 5 완료 기준

1. 운동장 스폰 → 본관 진입 → 1반 클리어까지 안내 없이 이어진다.
2. 사운드 8종이 전부 들어가 있고, 소리를 끄고 플레이해도 예고 신호를 시각으로 알 수 있다.
3. 지인 3명 전원이 **3반 이상** 도달한다.
4. 3명 중 최소 2명이 요청 없이 "한 판 더"를 한다.
5. 모바일 실기기에서 처음부터 끝까지 한 번 완주된다.
6. 5분 연속 플레이 시 메모리가 지속적으로 증가하지 않는다. (F9 → Memory)

**여기서부터는 코드로 확인할 수 없다.** Phase 1~4는 정적 게이트 네 개(`stylua --check` / `selene` / `luau-lsp analyze` / `rojo build`)가 통과하면 적어도 "돌아가긴 한다"를 말할 수 있었지만, Phase 5의 완료 기준은 성질이 다르다.

| 기준 | 확인 방법 |
|---|---|
| 1. 무안내 연결 | 코드 경로는 이어져 있다(스폰 → 신발장 프롬프트 → 전환 → 교실 문 앞). **"안내 없이 알아낼 수 있는가"는 Studio 플레이로만 확인된다** |
| 2. 사운드 8종 | 정의는 10개 다 있다. 다만 `rbxasset://` 대역품이라 **실제로 울리는지는 Studio에서 하나씩 들어봐야 한다**(§7.2) |
| 2. 소리 꺼도 인지 | 시각 백업(어깨 들썩 + 비네트)은 Phase 2에서 들어갔다. 실제로 인지되는지는 플레이로 확인한다 |
| 3·4·5 | **전적으로 플레이테스트다.** 지인 3명, "한 판 더", 모바일 실기기 — 코드가 대신 답할 수 없다 |
| 6. 메모리 | F9 → Memory. 5분 연속 |

3·4번이 이 문서 전체에서 유일하게 **설계가 틀렸는지를 알려주는 기준**이다. 나머지는 전부 "만들었는가"를 묻지만 이 둘만 "재미있는가"를 묻는다. 여기서 실패하면 고칠 곳은 Phase 5가 아니라 Phase 1~2다.

### 7.7 첫 Studio 플레이에서 나온 것 (2026-08-15)

정적 게이트 네 개가 다 통과한 뒤 처음 직접 돌려보고 나온 것들이다. 하나같이 게이트가 잡을 수 없는 종류였다 — 문법도 타입도 맞고, 빌드도 되는데, 보고 들으면 틀렸다는 것을 바로 안다.

| 나온 것 | 진짜 원인 | 고친 곳 |
|---|---|---|
| 배경음이 학교 같지 않다 | `lecture`·`hallway` 가 `uuhhh.mp3`(사람 신음)를 피치 낮춰 무한 루프하고 있었다 | `SoundConfig` — 둘 다 무음 처리, `chalk` 는 피치 0.5 → 1.7 |
| 복도로 나가면 떨어진다 | 교실 뒷문 밖에 바닥이 아예 없었다 | `Classroom/Template` 에 `buildCorridor` 추가 |
| 운동장에서 못 뛴다 | 점프를 다루는 코드가 어디에도 없었다 | `MovementController.applyJump` — 어디서나 켠다 |
| 눈코입이 없어서 심심하다 | 있긴 했다. 1.5 스터드 머리에 붙은 0.2 스터드 파트라 안 보였을 뿐이다 | `CharacterBuilder.emitFace` — SurfaceGui 표정 |
| 소리를 끄고 싶다 | 끌 방법이 아예 없었다 | `SoundConfig.master` 그룹 + HUD 토글 |

**무음이 틀린 소리보다 낫다.** 배경음은 한 번 틀리면 플레이 내내 틀린 채로 깔린다. 게다가 `hallway` 는 2D라 어디에 있든 계속 들린다 — 분필 소리가 멈추는 것을 알아채야 하는 게임에서, 계속 울리는 잘못된 소리는 그냥 노이즈가 아니라 **예고 신호를 덮는 방해물**이다. `SoundConfig` 에 `SILENT` 상수를 두고, 흉내조차 안 되는 소리는 id 를 비웠다. `Sound` 인스턴스는 그대로 만들어지고 `Play()` 가 아무 일도 안 할 뿐이라, 진짜 음원이 생기면 표 한 줄만 채우면 된다. 반대로 `chalk` 는 어설퍼도 무음으로 두지 않았다 — 이건 빠지면 규칙이 무너지는 유일한 소리다(§7.2).

**복도는 지나다니는 곳이 아니라 안 떨어지는 곳이다.** 나가는 길은 여전히 `ProximityPrompt` 하나뿐이므로 양쪽 끝을 벽으로 막은 막다른 상자로 지었다. 대신 사물함 5개, 창틀, 게시판을 넣어 "학교가 여기서 끝나는 게 아니라 계속된다"로 읽히게 했다. 게시판은 처음에 뒷벽에 붙였다가 문 앞을 가려서 왼쪽 끝벽으로 옮겼다 — **복도에 무엇을 놓든 문 앞은 비어 있어야 한다.**

**점프는 어디서나 된다.** 처음에는 교실에서만 껐었다. 이유는 분위기가 아니라 감속 커브였다 — 공중에 뜨면 `WalkSpeed` 를 낮춰도 수평 속도가 안 줄어든다. 발이 땅에 없으니 지면 컨트롤러가 일을 못 하고, 그러면 "멈추려고 뗐는데 안 멈췄다"가 생긴다. Phase 1부터 없애려고 애쓴 바로 그 억울함이다.

그럼에도 되돌렸다. **뛸 수 없다는 것 자체가 더 답답하다**고 판단했기 때문이다. 억울한 죽음은 §7.6 의 측정 항목이라 나중에 숫자로 잡히지만, 답답함은 어느 항목에도 안 잡힌 채 그냥 재미없어지기만 한다. 대신 감속이 이상하다는 말이 나오면 여기가 첫 번째로 의심할 곳이라고 `MovementController` 주석에 못 박아뒀다.

기본값에 맡기지 않고 `UseJumpPower = false` + `JumpHeight` 로 명시하되, 캐릭터가 생길 때마다 다시 건다. 잡혀서 리스폰될 때마다 캐릭터가 새로 생기는데, 그때 점프 높이를 이 파일이 아니라 StarterPlayer 설정이 정하게 되면 "왜 어떤 판에서는 안 뛰어지지"를 코드에서 찾을 수 없게 된다.

**소리는 그룹 하나로 끈다.** `SoundConfig` 에 마스터 `SoundGroup` 을 두고 `create()` 가 만드는 모든 `Sound` 를 여기 묶었다. 음소거는 이 그룹의 `Volume` 을 0 으로 두는 것이 전부다. 만들어진 `Sound` 를 순회하며 끄지 않는 이유는, 소리가 여기저기서 만들어지기 때문이다 — 발소리는 `SoundService` 아래, 분필은 선생님 머리에, 수업 목소리는 교탁 위에. 게다가 선생님은 교실에 들어간 뒤에야 생긴다. 순회는 **앞으로 만들어질 소리를 반드시 빠뜨린다.** `create()` 가 이 프로젝트에서 `Sound` 를 만드는 유일한 곳이라 여기서 묶으면 샐 곳이 없다.

`Pause` 하지 않고 볼륨만 0 으로 둔다. 멈췄다가 다시 틀면 분필 루프가 끊기는데, 분필이 멈추는 것이 예고 신호의 본체라 **"소리를 껐다 켰더니 예고 신호가 타이밍을 잃었다"** 가 된다. 볼륨만 0 이면 루프는 제자리를 계속 돈다.

**버튼이 곧 표시등이다.** 좌상단 별 아래에 `🔊 소리 켬 / 🔇 소리 끔` 토글을 뒀다(키보드는 `M`, 게임패드는 `Y`). 껐다는 게 화면에 보이지 않으면 음소거해놓고 잊은 사람에게는 그냥 "소리가 안 나는 게임"이 된다. 우상단은 로블록스 플레이어 목록 자리고 우하단은 달리기/살금 터치 버튼 자리라, 좌상단 열이 유일하게 비어 있는 곳이다. 설정은 저장하지 않는다 — 소리 스위치 하나 때문에 프로필 스키마를 올리고 마이그레이션을 붙일 일이 아니다.

덤으로 §7.6 완료 기준 2번("소리를 끄고 플레이해도 예고 신호를 시각으로 알 수 있다")이 이제 게임 안에서 확인된다. 전에는 시스템 볼륨을 내려야 했다.

**표정은 눈이 아니라 눈썹 각도와 입꼬리 방향이 만든다.** 파트로 만든 눈은 크게 하면 얼굴에서 튀어나온 검은 블록이 되고, 작게 하면 안 보인다 — 크기를 고를 수 있는 범위 자체가 없다. 머리 앞면(`NormalId.Front` = -Z, 얼굴 방향 규약과 같다)에 `SurfaceGui` 를 붙이고 `Frame` + `UICorner` 로 그리면 그 제약이 사라진다. 이미지를 안 쓰는 이유는 업로드 없이 돌아가는 것이 이 프로젝트의 규칙이기 때문이다. 코만 파트로 남겼다 — 옆에서 봐도 얼굴로 읽히려면 하나는 튀어나와 있어야 하고, 평면에 그린 얼굴은 앞으로 나온 코가 자연스럽게 가려준다.

표정은 6종이다. 학생은 자리 번호 시드로 뽑되 무표정·지루함에 가중치를 뒀다 — 여섯 표정을 같은 확률로 돌리면 교실이 아니라 놀이터가 된다. 선생님은 `STERN` 하나로 고정하고 눈썹을 가장 세게 꺾었다. **선생님 얼굴이 보이는 순간은 돌아본 순간뿐이고, 그 순간은 이미 늦은 순간이다.**

### 7.8 두 번째 Studio 플레이에서 나온 것 (2026-08-15)

| 나온 것 | 진짜 원인 | 고친 곳 |
|---|---|---|
| 교실 천장이 낮다 | 비율이 아니라 카메라였다. 3인칭 카메라가 천장에 눌렸다 | `Classroom/Template` — `HEIGHT` 11 → 14 |
| 갑자기 조명이 밝아진다 | `PointLight.Range`가 방보다 작아 방 한가운데에 경계선이 있었다 | 교실·복도·로비 광원 `Range` 전부 확대 |
| 벽에 붙으면 벽이 화면을 가린다 | 카메라를 당길 자리가 없다. 좁은 방에서는 늘 그렇다 | `CameraController.updateFade` + `RoomKeys.FADE_TAG` |
| 태극기가 어색하다 | 파트로는 태극의 S자 곡선을 못 만든다 | `buildFrontWall` — `buildFlag` 삭제 |
| 교실에 긴장감이 없다 | 교실 전용 배경음이 아예 없었다 | `SoundConfig.tension` + 전환에서 켜고 끈다 |

**천장 높이는 비율 문제가 아니라 카메라 문제였다.** 처음 16이었던 것을 "한국 교실은 낮고 답답하다"며 11로 내렸는데, 이번엔 진짜로 답답했다. 원인은 사람 키(5.6) 대비 비율이 아니다 — 카메라가 11 스터드 뒤에서 비스듬히 내려다보는데 천장도 11이면 카메라가 천장에 눌려 앞으로 밀린다. 로비(`LOBBY_H = 15`)를 지나 교실에 들어갔을 때만 눌린 느낌이 난 것도 같은 이유다. 14는 카메라가 천장을 안 건드리는 최저값이다. **감지 판정은 전부 수평이라 난이도는 그대로다.**

천장을 올리자 복도 바깥벽이 천장을 뚫고 나갔다. `HEIGHT - 8.4` 만큼의 벽을 `HEIGHT - 1.3` 높이에 두는 코드였는데, 이 숫자들은 `HEIGHT = 11`일 때만 맞는 값이었다. **상수에서 유도한 것처럼 보이지만 실제로는 한 번 계산해서 적어둔 숫자**가 가장 위험하다 — 창틀 위아래(`WIN_LOW`, `WIN_HIGH`)를 상수로 꺼내고 나머지를 거기서 계산하도록 고쳤다.

**`PointLight.Range`는 도달 거리가 아니라 잘리는 선이다.** 밝기가 서서히 0에 수렴하는 지점이 아니라, 그 거리에서 조명이 딱 끊긴다. 창가 `SunGlow` 3개의 `Range`가 30이었고 광원이 `x = -20.6`에 있었으니, 경계선은 정확히 `x = +9.4` — 복도 쪽 통로 한가운데였다. 거기를 걸어서 넘는 순간 광원 세 개가 한꺼번에 사라졌다. "갑자기 조명이 밝아진다"의 정체가 이거다.

고치는 방법은 밝기를 만지는 게 아니라 **경계선을 벽 밖으로 밀어내는 것**이다. 모든 `Range`를 방 대각선보다 크게 잡으면 방 안에는 기울기만 남는다. 대신 밝기는 낮춘다 — `Range`를 늘리면 같은 거리에서 더 밝아지기 때문이다. 같은 결함이 복도(`Range` 28, 구석까지 32)와 현관 로비(`Range` 40, 구석까지 43)에도 있어서 같이 고쳤다.

**창가/복도 비대칭은 살아 있다. 다만 계단이 아니라 기울기가 됐다.** 이게 오히려 원래 의도에 가깝다 — §7.4가 말한 것은 "어두운 쪽 벽을 따라가면 안전하게 느껴진다"이지 "여기서부터 어둡다는 선이 보인다"가 아니었다.

**카메라를 옮기는 대신 가리는 것을 지운다.** 벽에 등을 붙이면 화면이 벽면으로 꽉 찬다. 로블록스 기본 카메라는 이걸 "카메라를 앞으로 당기기"로 푸는데, 좁은 교실에는 당길 자리가 없다. 카메라를 직접 굴리는 것은 §7.3 이래로 계속 피해온 선택이다 — 충돌 처리·모바일 제스처·게임패드를 전부 다시 짜야 한다.

그래서 `Camera:GetPartsObscuringTarget`으로 카메라와 내 머리 사이에 낀 파트를 찾아 반투명하게 만든다. `Transparency`가 아니라 `LocalTransparencyModifier`를 쓴다 — 클라이언트 전용 속성이라 서버가 정한 원래 투명도를 안 건드리고, 되돌릴 때 원래 값을 백업해둘 필요도 없다.

**지워도 되는 것은 벽뿐이다.** 가리는 것을 전부 투명하게 만들면 뒤돌아섰을 때 선생님과 옆자리 학생까지 사라진다. 그건 해결이 아니라 더 큰 문제다. `RoomKeys.FADE_TAG`가 붙은 파트만 지우고, 태그는 `BuildKit.part`가 `fade = true` 한 줄을 보고 붙인다 — 벽·천장·굽도리·복도 사물함·로비 벽이 전부다. 굽도리를 같이 넣은 것은, 벽만 지우면 허리 높이 나무 띠가 공중에 떠서 더 이상해지기 때문이다.

**교실 배경음은 §7.2의 "무음이 낫다" 규칙을 깨는 유일한 예외다.** 2·7번을 무음으로 만든 이유는 사람 목소리라서 흉내가 아예 안 됐기 때문인데, 긴장감은 낮게 깔리는 한 음이면 절반은 된다. 베이스 음 하나를 피치 0.35로 늘려 루프한다. ⚠️ **한 음짜리 루프라 이어지는 지점에서 맥이 끊길 수 있다 — 이것도 Studio에서 들어보고 판단할 몫이고, 거슬리면 `SoundConfig.DEFS.tension.id` 한 줄만 갈아끼우면 된다.**

볼륨은 0.16으로, 분필(0.45)보다 훨씬 낮게 뒀다. **배경이 신호를 덮으면 게임이 아니라 운이 된다.** 다행히 주파수도 갈라져 있다 — 분필은 피치 1.7로 높고 이건 0.35로 낮다.

**선생님 상태에 반응시키지 않았다.** 예고 신호가 뜰 때 음악이 같이 고조되면 분필이 멈추는 것을 안 듣고도 위험을 알게 된다. 상태를 소리로 읽어내는 것이 이 게임의 실력인데, 그게 통째로 공짜가 된다. 배경음은 "지금 교실에 있다"만 알려주면 된다. 반대로 운동장에서는 끈다 — 계속 깔아두면 긴장감이 아니라 그냥 이 게임의 소리가 되고, **교실 문을 넘는 순간 소리가 바뀌어야 넘었다는 것이 느껴진다.**

**태극기는 지웠다.** 국기는 "한국 교실"의 기호로는 강한 만큼 잘못 그리면 바로 티가 난다. 파트로는 태극의 S자 곡선을 자를 수 없어서 원판 두 장을 위아래로 어긋나게 겹친 흉내였는데, 결국 흉내로 읽혔다. 급훈 액자와 시계만으로도 앞벽은 이미 한국 교실이다. 운동장의 국기게양대는 그대로 뒀다 — 그건 멀리서 보는 실루엣이라 흉내가 통한다.

---

## 8. 전 Phase 공통 — 절대 하지 말 것

Phase를 진행하다 보면 유혹이 오는 지점들이다. 미리 못 박아둔다.

| 하지 말 것 | 이유 |
|---|---|
| `AssemblyLinearVelocity`로 움직임 판정 | 클라가 보고하는 값. 게임이 통째로 무력화된다 |
| 선생님 상태를 어트리뷰트로도 노출 | `RemoteEvent`와 순서 보장 없음. 이중 채널은 어긋난다 |
| `RequestSit`에서 거리 검증 생략 | 텔레포트 치트로 72반이 3초 |
| 반 클리어마다 DataStore 쓰기 | 쿼터 스로틀. 조용히 느려진다 |
| `Humanoid.WalkSpeed = 0`으로 정지 | 정지 거리 개념이 사라져 게임이 무너진다 |
| 학생 NPC에 `Humanoid` 추가 | 앉아있는 더미에 상태머신·물리·렌더스텝 낭비 |
| 5000 studs 슬롯으로 선행 스트리밍 없이 텔레포트 | 바닥 뚫림 / 좌석 못 찾음 |
| Studio에서 스크립트 직접 수정 | 파일과 어긋나는 순간 기준이 사라진다 |
| 안 쓰는 Wally 패키지 미리 설치 | 안 쓰는 추상화 위에 코드를 쌓게 된다 |
| Phase 완료 기준을 건너뛰고 다음으로 | 나중에 원인을 못 찾는다 |

---

## 9. 확장 가이드 (MVP 이후)

MVP가 검증된 뒤에 붙일 것들. 지금 설계에 이미 자리는 비워져 있다.

### 9.1 2~6학년

**코드는 거의 추가되지 않는다.** `DifficultyTable`에 학년별 항목을 추가하고, 학년마다 축을 하나씩 얹는다.

| 학년 | 추가되는 축 | 필요한 새 코드 |
|---|---|---|
| 2학년 | 페이크 턴 (`fakeChance` 15~30%) | 없음. 상태머신에 이미 있음 |
| 3학년 | 바닥 방해물 본격화 | `ObstacleService`에 종류 추가 |
| 4학년 | 시야각 확대 + 창문 반사 | 감지에 반사 레이 1개 추가 |
| 5학년 | 선생님 순찰 (고정 웨이포인트) | `TeacherAI`에 이동 상태 추가. `PathfindingService` 여전히 불필요 |
| 6학년 | 복수 감시자(반장·CCTV) | `DetectionService`를 감시자 배열로 일반화 |

`DetectionService`의 `check()`가 이미 `teacher` 하나를 인자로 받는 형태이므로, 6학년의 복수 감시자는 루프를 한 겹 씌우는 것으로 끝난다.

### 9.2 명예의 전당

졸업 총 소요시간 랭킹. `OrderedDataStore`로 상위 100명, `MessagingService`로 신규 졸업자 서버 간 공지. 운동장 한쪽에 명예의 전당 건물을 세우고 졸업장을 전시한다. **6학년 12반이 실제로 완성된 뒤에** 만든다 — 아무도 도달 못 하는 랭킹은 빈 표일 뿐이다.

### 9.3 수익화

외형 + 편의 중심. **속도나 감지 회피를 파는 것은 금지** — 이 게임에서 그건 클리어를 파는 것이다.

- 코스메틱: 교복/체육복/책가방/실내화 스킨
- 편의: 별 획득 2배 패스, 실패 시 즉시 재시작(광고 대체)
- 절대 안 되는 것: `MOVE_EPSILON` 완화, `warnTime` 연장, FOV 축소

### 9.4 방해물 카탈로그 전체

기획서의 방해물 목록을 학년별로 배분한다. 원칙 하나: **모든 방해물은 예측 가능해야 한다.** 랜덤하게 죽이는 방해물은 억울함을 만들고, 억울함은 이 게임의 유일한 사망 원인이다.

---

## 10. 요약 한 장

```
Phase 1  뼈대와 눈    → 선생님이 돌아본다. 움직이면 잡힌다.        [억울한 죽음 0/20]
Phase 2  손맛        → 달리면 못 멈춘다. 살금살금이면 멈춘다.     [정지거리 ±15%]
Phase 3  한 판 완성   → 한국 교실에서 30~60초짜리 한 판이 돈다.   [모바일 30FPS]
Phase 4  12반 루프    → 1반→12반, 성장하고, 저장된다.            [1반 15% / 12반 40~60%]
Phase 5  포장과 검증  → 남에게 보낼 수 있다.                     [지인 3명 3반 도달]
```

**한 문장으로:** Phase 1~2에서 재미를 확정하고, Phase 3~4에서 그것을 12번 반복 가능하게 만들고, Phase 5에서 남에게 보여줄 수 있게 다듬는다.
