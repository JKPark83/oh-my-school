--!strict
--[[
	탑(층 올리기). 개선계획 §3.6 #4·#6·#13·#14·#15.
	층은 FacilityConfig.LIST 밖의 선택 트랙이다. 시설 14개를 다 지으면 강당(2층) 위에 3층부터 한 층씩 산다.
	  - 수입 0. 졸업 조건(FacilityConfig.COUNT)과 부품 가격표는 그대로다.
	  - 프로필 towerFloors = 산 층 수. 층 번호는 3..2+towerFloors. 졸업해도 유지한다(질문 13).
	  - 서버 파트는 층마다 SERVER_PARTS_PER_FLOOR(바닥판 1 + 엘리베이터 앵커 1) + 고정 FIXED_PARTS.
	    벽·칸 외형·층 번호·기본 가구는 클라가 그린다(질문 14).
	가격식은 docs/sim/sim-parts.py 의 tower_price 와 같다(check-config.py 가 STEP·GAP_SECONDS·MAX 를 대조한다).
]]

local DecorConfig = require(script.Parent.DecorConfig)
local FacilityConfig = require(script.Parent.FacilityConfig)
local PlotLayout = require(script.Parent.Parent.PlotLayout)

local TowerConfig = {}

export type Furniture = {
	id: string, -- DecorConfig 일반 1×1 소품 id
	name: string,
	color: Color3, -- 클라 렌더 대표색
}

TowerConfig.MAX = 20 -- 꼭대기 층 번호(잠정, §3.6 #13). towerFloors ≤ MAX - 2
TowerConfig.FIRST_FLOOR = 3
TowerConfig.SERVER_PARTS_PER_FLOOR = 2 -- 바닥판 1 + 엘리베이터 앵커 1
TowerConfig.FIXED_PARTS = 3 -- 2층 엘리베이터 앵커 1 + TOWER_PAD 1 + 꼭대기 지붕 1(지붕은 towerFloors ≥ 1 일 때만. 0층이면 2)
TowerConfig.GAP_SECONDS = 60 -- 3층 1회차 가격 = 완공 수입 60초치
TowerConfig.STEP = 1.5 -- 잠정. sim-parts.py --tower 표에서 고른다
TowerConfig.PRICE_SCALE = FacilityConfig.PRICE_SCALE
TowerConfig.EVACUATE_Y = 30 -- 졸업 때 부지 로컬 y 가 이보다 높으면(3층 이상) 스폰으로 옮긴다(§3.6 #11). 2층 18.2 < 30 < 3층 37.25
TowerConfig.SEATS = 0 -- 층에는 학생 자리가 없다(§3.6 #14: 층을 넘어 걷지 않게)
TowerConfig.PLATE_T = 1 -- 서버 바닥판·지붕 두께(Geometry/Tower.luau)
TowerConfig.LIFT = 0.05 -- 바닥판 윗면 = floorY(n) + LIFT. 강당 지붕(윗면 37.2)과 면이 겹쳐 깜빡이지 않게 올린다

-- 완공 시설 income 원시 합. 층은 14개 완공 뒤에만 사므로 사실상 상수다
local completedIncome = 0
for _, row in FacilityConfig.LIST do
	completedIncome += row.income
end
assert(completedIncome == 7617, `TowerConfig: 완공 수입 합이 시뮬(7,617)과 다르다: {completedIncome}`)
TowerConfig.COMPLETED_INCOME = completedIncome

local rgb = Color3.fromRGB

-- 층 색 순환(빨강 계열 없음, 기획서 §12.2). 층 n 의 색 = COLORS[(n-3) % #COLORS + 1]
TowerConfig.COLORS = {
	rgb(135, 190, 235), -- 하늘
	rgb(140, 210, 170), -- 민트
	rgb(190, 170, 230), -- 라벤더
	rgb(245, 215, 120), -- 레몬
	rgb(160, 205, 225), -- 물빛
	rgb(200, 225, 140), -- 연두
}

-- 층 기본 가구(§3.6 #15). 층 n 의 가구 = DEFAULT_FURNITURE[(n-3) % 5 + 1]. DecorGrid 가 막는 발자국 x0·z0 모서리 1칸에 놓인다
TowerConfig.DEFAULT_FURNITURE = {
	{ id = "planter", name = "화분", color = rgb(110, 190, 80) },
	{ id = "lamp", name = "가로등", color = rgb(255, 236, 170) },
	{ id = "mailbox", name = "우체통", color = rgb(74, 128, 200) },
	{ id = "tree", name = "나무", color = rgb(80, 160, 70) },
	{ id = "signpost", name = "표지판", color = rgb(170, 120, 72) },
} :: { Furniture }

-- ── 클라 렌더(W7 TowerRenderController, §3.6 #6·#12·#15) ────────
-- 발자국은 x 40 × z 30(TOWER_FOOTPRINT). 긴 벽 = z0·z1 벽(x 방향 40), 짧은 벽 = x0·x1 벽(z 방향 30).
-- 벽은 바닥판 윗면(floorY + LIFT)에서 WALL_H 만큼 선다. WALL_H = FLOOR_STEP − PLATE_T 라
-- 벽 윗면이 위층 바닥판 아랫면(floorY(n+1) + LIFT − PLATE_T)에 딱 닿는다(틈·겹침 0).
TowerConfig.RENDER = {
	WALL_T = 0.6, -- 벽 두께. 발자국 안쪽으로 붙인다(바깥 면 = 발자국 변)
	WALL_H = PlotLayout.FLOOR_STEP - TowerConfig.PLATE_T, -- 18
	-- 창: 벽마다 SurfaceGui 1개 안 Frame. 긴 벽 40/4 = 짧은 벽 30/3 = 10 스터드 칸이라 두 벽의 창 크기·간격이 같다
	WINDOW_ROWS = 1,
	WINDOW_COLS = { LONG = 4, SHORT = 3 },
	-- 창 한 칸(가로 10 × 세로 WALL_H 18) 안에서 사방 여백 비율. 0.3 이면 창 4 × 7.2 스터드, 창 사이 6 스터드.
	-- 교문 쪽 벽 가운데(x −3~3) 가 빈다. 한 자리 층 번호(3~9)만 창과 안 겹치고, 두 자리(10~20)는 가운데 두 창 안쪽 끝을 조금 덮는다
	WINDOW_INSET = 0.3,
	WINDOW_COLOR = rgb(205, 235, 255), -- 연한 하늘색(텍스처 없음)
	-- 창은 단색 Frame 이라 해상도가 필요 없다. 캔버스를 작게(긴 벽 40 × 18 스터드 → 80 × 36 px)
	WINDOW_PIXELS_PER_STUD = 2,
	-- 창·층 번호 SurfaceGui 를 그리는 카메라 거리 상한(스터드). 멀면 GPU 가 그리지 않는다(PadController 선례)
	GUI_MAX_DISTANCE = 150,
	-- 층 번호: TextSize 는 100 이 로블록스 상한이라, SurfaceGui PixelsPerStud 로 실제 크기를 정한다.
	-- 100 px ÷ 16 px/스터드 = 글자 높이 약 6.25 스터드(벽 18 의 1/3). 줌 40 에서도 아이가 숫자를 읽는다
	NUMBER_SIZE = 100,
	NUMBER_PIXELS_PER_STUD = 16,
	NUMBER_COLOR = rgb(255, 255, 255), -- 흰 글씨
	NUMBER_STROKE_COLOR = rgb(0, 0, 0), -- 검정 테두리(UIStroke / TextStrokeColor3)
	NUMBER_STROKE = 2, -- 테두리 두께(px)
	-- 교문 쪽(+Z)을 보는 면. 회전 없는 파트에서 +Z 면은 NormalId.Back 이다(Front 는 −Z).
	-- 두 곳에 붙는다: z1 벽 바깥면(밖에서 교문 쪽으로 보인다)과 z0 벽 안쪽면(층 안에서 교문 쪽 카메라가 본다)
	NUMBER_FACE = Enum.NormalId.Back,
	SHAFT_COLOR = rgb(220, 225, 235), -- 엘리베이터 칸 뒤판(칸 북쪽 −Z 면). 층 색과 구별되는 밝은 회색
	FADE = 0.88, -- 가리는 벽 LocalTransparencyModifier. CameraController FADE 와 같은 값(§3.6 #12)
}

-- 클라 층당 파트: 벽 4 + 엘리베이터 칸 뒤판 1 + 기본 가구 1(DecorBuilder 모델 1개로 센다. 실제 파트 수는 통합에서 잰다)
TowerConfig.CLIENT_PARTS_PER_FLOOR = 6
-- 탑·꾸미기를 그리는 부지 수. 내 부지(있으면 항상) + 캐릭터에서 가까운 다른 부지로 채워 모두 NEAR_COUNT 개다
-- (DecorController·TowerRenderController 같은 값·같은 규칙). 그래서 부지 수는 늘 NEAR_COUNT 이하다
TowerConfig.NEAR_COUNT = 3
-- LOD 교체 이력(스터드). 지금 그리는 부지는 거리에서 이만큼 빼고 순위를 매긴다. 새 부지가 이만큼 더 가까워야
-- 자리를 뺏으므로 두 부지 사이 경계에서 매초 지웠다 다시 짓지 않는다(학생 LOD 230/260 의 폭 30 과 같다)
TowerConfig.NEAR_HYSTERESIS = 30
-- 클라 탑 파트 상한 = 6 × 18층 × 3부지 = 324. 기획서 §12.1 성능 예산 「클라이언트 탑 파트(W7)」 행.
-- 창·층 번호 SurfaceGui 도 층당 6(창 4 + 번호 2)이라 최악 개수가 같다(324)
TowerConfig.MAX_CLIENT_PARTS = TowerConfig.CLIENT_PARTS_PER_FLOOR
	* (TowerConfig.MAX - TowerConfig.FIRST_FLOOR + 1)
	* TowerConfig.NEAR_COUNT

--- n층 가격. 졸업 보정은 PRICE_SCALE^graduations 한 곳에서만(sim tower_price 와 같은 식)
function TowerConfig.priceOf(n: number, graduations: number): number
	return math.round(
		TowerConfig.GAP_SECONDS
			* TowerConfig.COMPLETED_INCOME
			* TowerConfig.STEP ^ (n - TowerConfig.FIRST_FLOOR)
			* TowerConfig.PRICE_SCALE ^ graduations
	)
end

--- 다음에 살 층 번호. 상한이면 nil
function TowerConfig.nextFloor(towerFloors: number): number?
	local n = TowerConfig.FIRST_FLOOR + towerFloors
	if n > TowerConfig.MAX then
		return nil
	end
	return n
end

--- n층 바닥판 윗면 y(부지 기준)
function TowerConfig.floorY(n: number): number
	return PlotLayout.TOWER_BASE_Y + (n - TowerConfig.FIRST_FLOOR) * PlotLayout.FLOOR_STEP
end

--- n층 색
function TowerConfig.colorOf(n: number): Color3
	return TowerConfig.COLORS[(n - TowerConfig.FIRST_FLOOR) % #TowerConfig.COLORS + 1]
end

--- n층 기본 가구
function TowerConfig.furnitureOf(n: number): Furniture
	local list = TowerConfig.DEFAULT_FURNITURE
	return list[(n - TowerConfig.FIRST_FLOOR) % #list + 1]
end

--- 층 기본 가구 칸(발자국 x0·z0 모서리). DecorGrid.isFloorBlocked 가 막는 칸과 같다
function TowerConfig.furnitureCell(): (number, number)
	local foot = PlotLayout.TOWER_FOOTPRINT
	return PlotLayout.cellOf(foot.x0 + PlotLayout.CELL / 2, foot.z0 + PlotLayout.CELL / 2)
end

-- ── 로드 검증 ───────────────────────────────────────────────────
assert(TowerConfig.SEATS == 0, "TowerConfig: 층에 좌석을 두면 학생이 층을 넘어 걷는다(§3.6 #14)")
assert(TowerConfig.MAX >= TowerConfig.FIRST_FLOOR, "TowerConfig: MAX 가 3층보다 낮다")
assert(
	TowerConfig.priceOf(3, 0) == 457020,
	`TowerConfig: 3층 1회차 가격이 시뮬과 다르다: {TowerConfig.priceOf(3, 0)}`
)
assert(#TowerConfig.DEFAULT_FURNITURE == 5, "TowerConfig: 기본 가구는 5종 순환")
for _, color in TowerConfig.COLORS do
	assert(not (color.R > 0.7 and color.G < 0.45 and color.B < 0.45), "TowerConfig: 층 색에 빨강 계열이 있다")
end
for _, furniture in TowerConfig.DEFAULT_FURNITURE do
	local item = DecorConfig.BY_ID[furniture.id]
	assert(item, `TowerConfig: 기본 가구 {furniture.id} 가 DecorConfig 에 없다`)
	assert(item.kind == "general", `TowerConfig: 기본 가구 {furniture.id} 는 일반 소품이어야 한다`)
	assert(
		item.w == 1 and item.d == 1,
		`TowerConfig: 기본 가구 {furniture.id} 는 1×1 칸이어야 한다(DecorGrid 가 1칸만 막는다)`
	)
end
local render = TowerConfig.RENDER
assert(render.FADE == 0.88, "TowerConfig: RENDER.FADE 는 CameraController FADE(0.88)와 같아야 한다")
assert(
	render.WALL_H + TowerConfig.PLATE_T <= PlotLayout.FLOOR_STEP,
	"TowerConfig: 벽 + 바닥판이 층 높이를 넘는다(위층 바닥판과 겹친다)"
)
local foot = PlotLayout.TOWER_FOOTPRINT
assert(
	(foot.x1 - foot.x0) / render.WINDOW_COLS.LONG == (foot.z1 - foot.z0) / render.WINDOW_COLS.SHORT,
	"TowerConfig: 긴 벽·짧은 벽의 창 칸 폭이 다르다"
)
assert(render.WINDOW_INSET > 0 and render.WINDOW_INSET < 0.5, "TowerConfig: WINDOW_INSET 은 0~0.5 사이")
assert(render.NUMBER_SIZE <= 100, "TowerConfig: TextSize 상한은 100")
assert(
	TowerConfig.MAX_CLIENT_PARTS == 324,
	"TowerConfig: 클라 탑 파트 상한이 기획서 §12.1(324)과 다르다"
)

return TowerConfig
