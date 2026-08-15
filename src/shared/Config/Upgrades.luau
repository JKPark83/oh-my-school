--!strict
--[[
	업그레이드 정의. 가격의 유일한 출처다.

	★ 별 예산보다 총액이 비싸야 한다.
	  1학년 전체에서 얻는 별은 최대 27개다(반 클리어 12 + 퍼펙트 12 + 학년 수료 3).
	  총액 30 은 그보다 3 많다. 전부 살 수 없어야 선택이 선택이 된다.

	클라이언트가 보낸 가격은 물론이고, 클라가 보낸 "구매 성공"도 믿지 않는다.
	서버는 항상 이 표를 다시 읽는다.
]]

export type Upgrade = {
	cost: number,
	name: string,
	desc: string,
}

local DEFS: { [string]: Upgrade } = {
	quietShoes = { cost = 8, name = "실내화", desc = "발소리 반경이 절반으로 줄어든다" },
	balance = { cost = 10, name = "균형감각", desc = "모든 정지 거리가 25% 줄어든다" },
	instinct = { cost = 12, name = "눈치", desc = "예고 신호가 0.1초 먼저 온다" },
}

local Upgrades = {}

Upgrades.DEFS = DEFS

-- 문구점 매대에 놓이는 순서. 표는 딕셔너리라 순회 순서가 실행마다 달라지는데,
-- 매대 위치가 매번 바뀌면 "가운데 게 균형감각"이라는 기억이 안 생긴다.
-- 싼 것부터 왼쪽에 둔다.
Upgrades.ORDER = { "quietShoes", "balance", "instinct" }

-- ── 효과 수치 ────────────────────────────────────────────────────
-- 효과를 적용하는 쪽(서버 감지 / 클라 이동 / 난이도 조립)이 각각 다르므로
-- 수치는 정의 옆에 같이 둔다. 흩어지면 "실내화가 얼마나 조용한가"를 아는 곳이 없어진다.
Upgrades.QUIET_SHOES_RADIUS_SCALE = 0.5
Upgrades.BALANCE_STOP_SCALE = 0.75
Upgrades.INSTINCT_LEAD = 0.1 -- 초. 판서에서 떼어 예고에 붙인다(사이클 총 길이는 그대로)

function Upgrades.exists(key: string): boolean
	return DEFS[key] ~= nil
end

function Upgrades.cost(key: string): number
	local def = DEFS[key]
	assert(def, `정의되지 않은 업그레이드: {key}`)
	return def.cost
end

return Upgrades
