--!strict
--[[
	경제 상수와 공식. 기획서 §1·§5.1. docs/sim/sim-final.py 와 같은 값(docs/sim/check-config.py 로 대조)이어야 한다.
	  초당 수입 = Σ(지은 시설 income) × (1 + Σ 보유 학생 기여) × (1 + 0.5 × 졸업)
	서버(EconomyService)와 클라(HUD 예상 시간·패드 링)가 같은 함수를 쓴다.
]]

local Types = require(script.Parent.Parent.Types)
local FacilityConfig = require(script.Parent.FacilityConfig)
local StudentConfig = require(script.Parent.StudentConfig)

local EconomyConfig = {}

EconomyConfig.START_COINS = 10 -- 졸업 후 10 × 1.4^N
EconomyConfig.PRICE_SCALE = FacilityConfig.PRICE_SCALE
EconomyConfig.GRAD_STEP = 0.5 -- 졸업 1회당 배율 +0.5
EconomyConfig.CONTRIB = StudentConfig.CONTRIB
EconomyConfig.TICK = 1 -- 수입·패드 확인 주기(초)

-- 칭찬스티커
EconomyConfig.STICKER_MIN = 10 -- ×1.4^졸업
EconomyConfig.STICKER_SECONDS = 1.2 -- 가치 = max(최소, 초당 수입 × 1.2)
EconomyConfig.GOLD_EVERY = 12 -- 12장마다 금 스티커
EconomyConfig.GOLD_MULT = 5
EconomyConfig.RESPAWN = 15 -- 초
EconomyConfig.STICKER_HOME_UNTIL = 3 -- 총 스티커가 이보다 적으면 리스폰도 홈 자리(튜토리얼 빛기둥 1~3번 수. TutorialController 가 이 값을 읽는다)
EconomyConfig.BOARD_CELLS = 60 -- 60칸 = 입학원서 1장
EconomyConfig.COMBO_WINDOW = 6 -- 초. 이 안에 다음 스티커면 콤보 유지
EconomyConfig.COMBO_BONUS_EVERY = 5 -- 콤보 5마다 스티커판 +1칸
EconomyConfig.STICKER_TOUCH_INTERVAL = 0.4 -- 초. 토큰 버킷 최소 간격
EconomyConfig.STICKER_MAX_SPEED = 40 -- 스터드/초. 넘으면 무시 + 위반

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

--- 배율 = (1 + 학생 기여 합) × (1 + 0.5 × 졸업)
function EconomyConfig.multiplier(profile: Types.Profile): number
	local students = 1 + StudentConfig.contribSum(profile.students)
	local grads = 1 + EconomyConfig.GRAD_STEP * profile.graduations
	return students * grads
end

--- 초당 수입
function EconomyConfig.incomePerSecond(profile: Types.Profile): number
	return EconomyConfig.facilityIncome(profile) * EconomyConfig.multiplier(profile)
end

--- 스티커 1장 가치(금 스티커 제외)
function EconomyConfig.stickerValue(profile: Types.Profile): number
	local minimum = EconomyConfig.STICKER_MIN * EconomyConfig.PRICE_SCALE ^ profile.graduations
	return math.floor(math.max(minimum, EconomyConfig.incomePerSecond(profile) * EconomyConfig.STICKER_SECONDS) + 0.5)
end

--- 졸업 후 시작 용돈
function EconomyConfig.startCoins(graduations: number): number
	return math.floor(EconomyConfig.START_COINS * EconomyConfig.PRICE_SCALE ^ graduations + 0.5)
end

--- 활성 스티커 스폰 수(3 → 5 → 8)
function EconomyConfig.spawnCount(facilities: { [Types.FacilityId]: boolean }): number
	local n = 0
	for _, row in FacilityConfig.LIST do
		if facilities[row.id] then
			n += row.spawns
		end
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
