--!strict
--[[
	경제 상수와 공식. 기획서 §1·§5.1. docs/sim/sim-parts.py 와 같은 값(docs/sim/check-config.py 로 대조)이어야 한다.
	  초당 수입 = Σ(지은 시설 income) × (1 + Σ 보유 학생 기여)
	  ★ 개선계획 §3.4: 층 쌓기(P2)에서 Σ 완공 단계 income(RoomConfig.incomeOf)을 시설 합에 더한다.
	    sim-parts.py 의 단계 가격은 그 수입을 전제로 맞췄다. P1 에서는 단계를 완공할 수 없어 0 이다.
	서버(EconomyService)와 클라(HUD 예상 시간·패드 링)가 같은 함수를 쓴다.
]]

local Types = require(script.Parent.Parent.Types)
local FacilityConfig = require(script.Parent.FacilityConfig)
local StudentConfig = require(script.Parent.StudentConfig)

local EconomyConfig = {}

EconomyConfig.START_COINS = 10 -- 새 프로필 시작 용돈
EconomyConfig.CONTRIB = StudentConfig.CONTRIB
EconomyConfig.TICK = 1 -- 수입 주기(초)
EconomyConfig.PAD_TICK = 0.1 -- 발판 확인 주기(초). 걷는 속도 16 이면 틱 사이 1.6 스터드라 반경 3.2 를 놓치지 않는다

-- 칭찬스티커
EconomyConfig.STICKER_MIN = 10
EconomyConfig.STICKER_SECONDS = 1.2 -- 가치 = max(최소, 초당 수입 × 1.2)
EconomyConfig.GOLD_EVERY = 12 -- 12장마다 금 스티커
EconomyConfig.GOLD_MULT = 5
EconomyConfig.RESPAWN = 15 -- 초
EconomyConfig.STICKER_HOME_UNTIL = 3 -- 총 스티커가 이보다 적으면 리스폰도 홈 자리(튜토리얼 빛기둥 1~3번 수. TutorialController 가 이 값을 읽는다)
EconomyConfig.BOARD_CELLS = 40 -- 40칸 = 선물 1개
EconomyConfig.COMBO_WINDOW = 6 -- 초. 이 안에 다음 스티커면 콤보 유지
EconomyConfig.COMBO_BONUS_EVERY = 5 -- 콤보 5마다 스티커판 +1칸
EconomyConfig.STICKER_TOUCH_INTERVAL = 0.4 -- 초. 토큰 버킷 최소 간격
EconomyConfig.STICKER_MAX_SPEED = 40 -- 스터드/초. 넘으면 무시 + 위반

-- 선물판 선물. 코인 선물 = 활동형 첫 40칸까지 스티커로 번 코인(sim-parts.py gift_coin_basis)
EconomyConfig.GIFT_COIN_VALUE = 6900

-- 방문객 별
EconomyConfig.VISITOR_STARS = 2
EconomyConfig.STAR_COOLDOWN = 60

-- 저장
EconomyConfig.SAVE_DEBOUNCE = 30

--- 지은 시설 초당 수입 합
function EconomyConfig.facilityIncome(profile: Types.Profile): number
	local sum = 0
	for _, row in FacilityConfig.LIST do
		if profile.facilities[row.id] then
			sum += row.income
		end
	end
	return sum
end

--- 배율 = 1 + 학생 기여 합
function EconomyConfig.multiplier(profile: Types.Profile): number
	return 1 + StudentConfig.contribSum(profile.students)
end

--- 초당 수입
function EconomyConfig.incomePerSecond(profile: Types.Profile): number
	return EconomyConfig.facilityIncome(profile) * EconomyConfig.multiplier(profile)
end

--- 스티커 1장 가치(금 스티커 제외)
function EconomyConfig.stickerValue(profile: Types.Profile): number
	local value = EconomyConfig.incomePerSecond(profile) * EconomyConfig.STICKER_SECONDS
	return math.floor(math.max(EconomyConfig.STICKER_MIN, value) + 0.5)
end

--- 선물판 코인 선물 1개 값
function EconomyConfig.giftCoins(): number
	return EconomyConfig.GIFT_COIN_VALUE
end

--- 활성 스티커 스폰 수(3 → 5 → 8)
function EconomyConfig.spawnCount(facilities: { [Types.FacilityId]: boolean }, buildParts: number): number
	local n = 0
	for _, row in FacilityConfig.LIST do
		if facilities[row.id] then
			n += row.spawns
		end
	end
	-- 기본 3(책상)은 책상 첫 부품을 사면 켜진다. 수입은 완공 때만 붙으므로 책상 부품 2·3 은 스티커로 산다(기획서 §3.1)
	local first = FacilityConfig.LIST[1]
	if not facilities[first.id] and buildParts >= 1 then
		n += first.spawns
	end
	return n
end

--- 다음 스티커가 금인가
function EconomyConfig.isGoldNext(totalStickers: number): boolean
	return (totalStickers + 1) % EconomyConfig.GOLD_EVERY == 0
end

--- price 까지 남은 초. 수입 0 이면 math.huge
function EconomyConfig.etaSeconds(profile: Types.Profile, price: number): number
	local remain = price - profile.coins
	if remain <= 0 then
		return 0
	end
	local income = EconomyConfig.incomePerSecond(profile)
	if income <= 0 then
		return math.huge
	end
	return remain / income
end

return EconomyConfig
