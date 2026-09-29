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

return TowerConfig
