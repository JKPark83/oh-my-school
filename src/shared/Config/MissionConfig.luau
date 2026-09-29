--!strict
--[[
	일일 미션 3개. 기획서 §6.3. KST 자정에 리셋(타이머 UI 없음).
]]

local MissionConfig = {}

export type Mission = {
	id: "stickers" | "built" | "chair",
	text: string, -- ≤12자
	target: number,
}

local LIST: { Mission } = {
	{ id = "stickers", text = "스티커 30장 줍기", target = 30 },
	{ id = "built", text = "시설 1개 짓기", target = 1 },
	{ id = "chair", text = "교장 의자 앉기", target = 1 },
}
MissionConfig.LIST = LIST
MissionConfig.REWARD_TICKETS = 1
MissionConfig.KST_OFFSET = 9 * 3600
MissionConfig.CHECK_INTERVAL = 60 -- 초. 날짜 바뀜 확인 주기
MissionConfig.ALL_DONE_TEXT = "오늘 미션 다 했어요!"

--- KST 기준 일 번호
function MissionConfig.dayOf(unixTime: number): number
	return math.floor((unixTime + MissionConfig.KST_OFFSET) / 86400)
end

--- 미션 번호(1~3)의 현재 진행도
function MissionConfig.progressOf(missions: { stickers: number, built: number, chair: boolean }, index: number): number
	local row = LIST[index]
	if row.id == "stickers" then
		return math.min(missions.stickers, row.target)
	elseif row.id == "built" then
		return math.min(missions.built, row.target)
	end
	return if missions.chair then 1 else 0
end

return MissionConfig
