--!strict
--[[
	꾸미기(W5). 개선계획 §3.5 #3~#5.
	  BuyDecor(itemId)                       상점 구매 → 보관함 +1. 친구 아이템이면 그 학생도 온다(처음 한 번)
	  ReturnDecor(itemId)                    보관함 1개를 산 값 그대로 돌려받는다(decorPaid 맨 뒤 값. 무료로 받은 것은 0). 친구 학생은 그대로 둔다
	  PlaceDecor(itemId, cx, cz, rot)        보관함 → 격자
	  MoveDecor(slot, cx, cz, rot)           배치 옮기기(자기 자리와 겹침·개수 상한 무시)
	  StoreDecor(slot)                       격자 → 보관함
	판정은 전부 서버가 DecorGrid·DecorConfig 로 한다. 가격도 서버가 계산한다(클라는 무엇을 할지만 보낸다).
	실패는 Remotes.deny 만 보낸다(위반 카운트 없음. 정상 클라도 겹침·상한은 낼 수 있다).
	성공하면 PlotState "Decor" 어트리뷰트(DecorCodec) → 클라가 모든 부지를 그린다. 서버 파트는 없다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DecorCodec = require(ReplicatedStorage.Shared.DecorCodec)
local DecorConfig = require(ReplicatedStorage.Shared.Config.DecorConfig)
local DecorGrid = require(ReplicatedStorage.Shared.DecorGrid)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StudentService = require(script.Parent.StudentService)
local Metrics = require(script.Parent.Parent.Metrics)
local RemoteGuard = require(script.Parent.Parent.RemoteGuard)

local DecorService = {}

local COOLDOWN = 0.2 -- 초. 리모트·플레이어별

-- DecorGrid 판정 → Deny 사유
local DENY_OF: { [string]: "owned" | "cell" | "limit" } = {
	item = "owned",
	cell = "cell",
	blocked = "cell",
	overlap = "cell",
	limit = "limit",
}

--- decorPlaced → 자기 부지 Decor 어트리뷰트
function DecorService.refreshAttribute(player: Player)
	local plotId = PlotService.plotOf(player)
	local profile = DataService.get(player)
	if not plotId or not profile then
		return
	end
	PlotService.state(plotId):SetAttribute(Keys.ATTR_DECOR, DecorCodec.encode(profile.decorPlaced))
end

local function takeOwned(profile: Types.Profile, itemId: string)
	local n = (profile.decorOwned[itemId] or 0) - 1
	-- 0 이면 키를 지운다(students 와 같은 규칙)
	local owned: { [string]: number? } = profile.decorOwned
	owned[itemId] = if n > 0 then n else nil
end

--- 보관함에 n 개 넣는다(MAX_OWNED 까지). 넣은 뒤 보관함 수를 돌려준다. DevCheat 용
function DecorService.give(player: Player, itemId: string, n: number): number
	local profile = DataService.get(player)
	if not profile or not DecorConfig.byId(itemId) then
		return 0
	end
	local room = DecorConfig.MAX_OWNED - DecorConfig.heldCount(profile.decorOwned, profile.decorPlaced, itemId)
	local add = math.clamp(math.floor(n), 0, math.max(room, 0))
	if add > 0 then
		profile.decorOwned[itemId] = (profile.decorOwned[itemId] or 0) + add
		DataService.markDirty(player)
	end
	return profile.decorOwned[itemId] or 0
end

local function buy(player: Player, itemId: string)
	local profile = DataService.get(player)
	local item = DecorConfig.byId(itemId)
	if not profile or not item then
		return
	end
	if not DecorConfig.isShown(item) then
		return -- gift 는 상점에 없다. 정상 클라는 보내지 않는다
	end
	local price = DecorConfig.priceOf(itemId)
	if profile.coins < price then
		Remotes.deny(player, "coins")
		return
	end
	if DecorConfig.heldCount(profile.decorOwned, profile.decorPlaced, itemId) >= DecorConfig.MAX_OWNED then
		Remotes.deny(player, "owned")
		return
	end
	-- 쓰기만 한다. totalCoins(번 돈 누계)는 건드리지 않는다
	profile.coins -= price
	profile.decorOwned[itemId] = (profile.decorOwned[itemId] or 0) + 1
	-- 산 값을 쌓아 둔다. 가격표가 바뀌어도 돌려받는 값은 이 값이다
	local paid = profile.decorPaid[itemId] or {}
	table.insert(paid, price)
	profile.decorPaid[itemId] = paid
	local newStudent: string? = nil
	local studentId = item.student
	if item.kind == "friend" and studentId and (profile.students[studentId] or 0) == 0 then
		newStudent = studentId
	end
	if newStudent then
		StudentService.grant(player, newStudent, true)
	end
	local packet: Types.DecorBought = { item = itemId, coins = price, student = newStudent }
	Remotes.event(player, "DecorBought", packet)
	DataService.markDirty(player)
	DataService.saveDebounced(player, EconomyConfig.SAVE_DEBOUNCE)
end

local function sell(player: Player, itemId: string)
	local profile = DataService.get(player)
	if not profile or not DecorConfig.byId(itemId) then
		return
	end
	if (profile.decorOwned[itemId] or 0) < 1 then
		Remotes.deny(player, "owned")
		return
	end
	-- 산 값 스택의 맨 뒤 값. 튜토리얼·선물처럼 무료로 받은 것은 스택에 없어 0
	local refund = 0
	local paidStack: { number }? = profile.decorPaid[itemId]
	if paidStack and #paidStack > 0 then
		refund = table.remove(paidStack) :: number
		if #paidStack == 0 then
			local paidMap: { [string]: { number }? } = profile.decorPaid
			paidMap[itemId] = nil
		end
	end
	takeOwned(profile, itemId)
	profile.coins += refund
	local packet: Types.DecorReturned = { item = itemId, coins = refund }
	Remotes.event(player, "DecorReturned", packet)
	DataService.markDirty(player)
	DataService.saveDebounced(player, EconomyConfig.SAVE_DEBOUNCE)
end

local function placedPacket(slot: number, p: Types.DecorPlacement, moved: boolean): Types.DecorPlaced
	return { slot = slot, item = p.item, cx = p.cx, cz = p.cz, rot = p.rot, moved = moved }
end

local function place(player: Player, itemId: string, cx: number, cz: number, rot: number)
	local profile = DataService.get(player)
	if not profile or not PlotService.plotOf(player) or not DecorConfig.byId(itemId) then
		return
	end
	if (profile.decorOwned[itemId] or 0) < 1 then
		Remotes.deny(player, "owned")
		return
	end
	local ok, reason = DecorGrid.canPlace(profile.decorPlaced, itemId, cx, cz, rot)
	if not ok then
		Remotes.deny(player, DENY_OF[reason] or "cell")
		return
	end
	takeOwned(profile, itemId)
	local placement: Types.DecorPlacement = {
		item = itemId,
		cx = cx,
		cz = cz,
		rot = rot,
	}
	table.insert(profile.decorPlaced, placement)
	DecorService.refreshAttribute(player)
	Remotes.event(player, "DecorPlaced", placedPacket(#profile.decorPlaced, placement, false))
	Metrics.decorPlaced(player)
	DataService.markDirty(player)
	DataService.saveDebounced(player, EconomyConfig.SAVE_DEBOUNCE)
end

local function validSlot(profile: Types.Profile, slot: number): boolean
	return slot == math.floor(slot) and slot >= 1 and slot <= #profile.decorPlaced
end

local function move(player: Player, slot: number, cx: number, cz: number, rot: number)
	local profile = DataService.get(player)
	if not profile or not PlotService.plotOf(player) then
		return
	end
	if not validSlot(profile, slot) then
		Remotes.deny(player, "cell")
		return
	end
	local placement = profile.decorPlaced[slot]
	local ok, reason = DecorGrid.canPlace(profile.decorPlaced, placement.item, cx, cz, rot, slot)
	if not ok then
		Remotes.deny(player, DENY_OF[reason] or "cell")
		return
	end
	placement.cx = cx
	placement.cz = cz
	placement.rot = rot
	DecorService.refreshAttribute(player)
	Remotes.event(player, "DecorPlaced", placedPacket(slot, placement, true))
	DataService.markDirty(player)
	DataService.saveDebounced(player, EconomyConfig.SAVE_DEBOUNCE)
end

local function store(player: Player, slot: number)
	local profile = DataService.get(player)
	if not profile or not PlotService.plotOf(player) then
		return
	end
	if not validSlot(profile, slot) then
		Remotes.deny(player, "cell")
		return
	end
	local placement = table.remove(profile.decorPlaced, slot) :: Types.DecorPlacement
	profile.decorOwned[placement.item] = (profile.decorOwned[placement.item] or 0) + 1
	DecorService.refreshAttribute(player)
	local packet: Types.DecorStored = { slot = slot, item = placement.item }
	Remotes.event(player, "DecorStored", packet)
	DataService.markDirty(player)
	DataService.saveDebounced(player, EconomyConfig.SAVE_DEBOUNCE)
end

function DecorService.Start()
	RemoteGuard.wrap(Remotes.BuyDecor, { cooldown = COOLDOWN, args = { "string" } }, buy)
	RemoteGuard.wrap(Remotes.ReturnDecor, { cooldown = COOLDOWN, args = { "string" } }, sell)
	RemoteGuard.wrap(
		Remotes.PlaceDecor,
		{ cooldown = COOLDOWN, args = { "string", "number", "number", "number" } },
		place
	)
	RemoteGuard.wrap(
		Remotes.MoveDecor,
		{ cooldown = COOLDOWN, args = { "number", "number", "number", "number" } },
		move
	)
	RemoteGuard.wrap(Remotes.StoreDecor, { cooldown = COOLDOWN, args = { "number" } }, store)
end

return DecorService
