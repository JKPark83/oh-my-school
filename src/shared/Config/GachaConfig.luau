--!strict
--[[
	입학 원서 뽑기. 기획서 §5.1·§5.4.
	  확률 반장 75% / 전교1등 22% / 전설 3%. 전설 천장 50장.
	  풀 = 졸업 횟수로 열린 gacha 학생. 등급 안에서는 미보유를 먼저 준다.
	roll 은 순수 함수다(Random 을 넘겨 받는다). 10만 회 검증 테스트가 그대로 돌린다.
]]

local Types = require(script.Parent.Parent.Types)
local StudentConfig = require(script.Parent.StudentConfig)

local GachaConfig = {}

local RATES: { { tier: Types.Tier, p: number } } = {
	{ tier = "반장", p = 0.75 },
	{ tier = "전교1등", p = 0.22 },
	{ tier = "전설", p = 0.03 },
}
GachaConfig.PITY = 50 -- 50장째 전설 확정
local DUPE_CELLS: { [Types.Tier]: number } = {
	["평범"] = 0,
	["반장"] = 12,
	["전교1등"] = 24,
	["전설"] = 60,
}
GachaConfig.PITY_STUDENT = "s22" -- 천장 실루엣(코스모)
GachaConfig.RATES = RATES
GachaConfig.DUPE_CELLS = DUPE_CELLS

export type Roll = {
	studentId: Types.StudentId,
	tier: Types.Tier,
	byPity: boolean,
}

--- 졸업 횟수로 열린 뽑기 풀. 등급별 목록
function GachaConfig.unlockedPool(graduations: number): { [Types.Tier]: { Types.StudentId } }
	local pool: { [Types.Tier]: { Types.StudentId } } =
		{ ["평범"] = {}, ["반장"] = {}, ["전교1등"] = {}, ["전설"] = {} }
	for _, row in StudentConfig.LIST do
		if row.unlock.kind == "gacha" and (row.unlock.value :: number) <= graduations then
			table.insert(pool[row.tier], row.id)
		end
	end
	return pool
end

local function pickTier(rng: Random): Types.Tier
	local r = rng:NextNumber()
	local acc = 0
	for _, rate in RATES do
		acc += rate.p
		if r < acc then
			return rate.tier
		end
	end
	return RATES[1].tier
end

--- 한 장 뽑기. pity = 마지막 전설 이후 뽑은 횟수(이번 장 포함 전).
--- 미보유 우선, 풀이 비면 낮은 등급으로 내려간다(졸업 0회에도 등급마다 1명은 있으므로 실제로는 안 일어난다).
function GachaConfig.roll(rng: Random, graduations: number, owned: { [Types.StudentId]: number }, pity: number): Roll
	local pool = GachaConfig.unlockedPool(graduations)
	local byPity = pity + 1 >= GachaConfig.PITY
	local tier: Types.Tier = if byPity then "전설" else pickTier(rng)

	local candidates = pool[tier]
	if #candidates == 0 then
		-- 안전망. 어느 등급이든 비어 있지 않은 곳에서 준다
		for _, fallback in { "전설", "전교1등", "반장" } do
			if #pool[fallback :: Types.Tier] > 0 then
				tier = fallback :: Types.Tier
				candidates = pool[tier]
				break
			end
		end
	end
	assert(#candidates > 0, "뽑기 풀이 비었다")

	local unowned = {}
	for _, id in candidates do
		if (owned[id] or 0) == 0 then
			table.insert(unowned, id)
		end
	end
	local from = if #unowned > 0 then unowned else candidates
	local studentId = from[rng:NextInteger(1, #from)]
	return { studentId = studentId, tier = tier, byPity = byPity }
end

--- 다음 전설 확정까지 남은 장 수
function GachaConfig.pityLeft(pity: number): number
	return math.max(0, GachaConfig.PITY - pity)
end

return GachaConfig
