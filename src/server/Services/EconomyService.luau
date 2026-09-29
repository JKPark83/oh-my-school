--!nonstrict
--[[
	용돈·구매·스티커·별·스킨. 기획서 §2.2·§3.2·§5·§7.5·§9.1·§11.5, 계획서 §3.2.
	  1Hz 틱   수입 지급 → 활성 패드 위에 서 있고 돈이 되면 자동 구매 → ProfileSync
	  스티커   PlotService.StickerTouched → 검증(주인·간격·속도·거리) → 가치·콤보·판 → 15초 뒤 리스폰(금 판단)
	  별       PlotService.StarTouched → 방문자 판 +1 (부지·60초당 2개)
	  SetSkin  기획서 §11.5 검증 ①~⑦
	  GoHome   PlotService.goHome (5초 쿨다운)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local SkinConfig = require(ReplicatedStorage.Shared.Config.SkinConfig)
local StudentConfig = require(ReplicatedStorage.Shared.Config.StudentConfig)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StudentService = require(script.Parent.StudentService)
local MissionService = require(script.Parent.MissionService)
local RemoteGuard = require(script.Parent.Parent.RemoteGuard)

local EconomyService = {}

local SKIN_COOLDOWN = 0.5
local HOME_COOLDOWN = 5
local TOUCH_RANGE = 12

type ComboState = { count: number, last: number }
type StarWindow = { start: number, count: number, taken: { [BasePart]: boolean } }

local combos: { [Player]: ComboState } = {}
local lastStickerAt: { [Player]: number } = {}
local lastStickerPos: { [Player]: Vector3 } = {}
local starWindows: { [Player]: { [number]: StarWindow } } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function addCoins(profile: Types.Profile, amount: number)
	profile.coins += amount
	profile.stats.totalCoins += amount
end

--- DevCheat 용 직접 지급
function EconomyService.grant(player: Player, amount: number)
	local profile: Types.Profile? = DataService.get(player)
	if not profile or amount <= 0 then
		return
	end
	addCoins(profile, amount)
	DataService.syncNow(player)
end

--- 시설 구매. 돈은 호출자가 확인했다
local function buy(player: Player, profile: Types.Profile, row: FacilityConfig.Facility)
	local price = FacilityConfig.priceOf(row.id, profile.graduations)
	profile.coins -= price
	profile.facilities[row.id] = true
	profile.tickets += 1
	local plotId = PlotService.plotOf(player)
	PlotService.buildFacility(player, row.id)
	Remotes.event(nil, "FacilityBuilt", { plot = plotId, facilityId = row.id })

	-- 이미 데리고 있던 학생 중 이 시설에 자리가 있는 아이들이 걸어 들어온다
	for studentId, count in profile.students do
		local student = StudentConfig.BY_ID[studentId]
		if count > 0 and student and student.seat.facilityId == row.id and plotId then
			Remotes.event(nil, "StudentJoined", { plot = plotId, studentId = studentId, walk = true })
		end
	end
	-- 이미 데리고 있는 학생(2회차 이후)은 위에서 걸어 들어왔다. 다시 주면 도감에 중복(×2)으로 잡힌다
	if row.student and (profile.students[row.student] or 0) == 0 then
		StudentService.grant(player, row.student, true)
	end
	MissionService.onBuilt(player)
	DataService.syncNow(player)
	DataService.saveDebounced(player, EconomyConfig.SAVE_DEBOUNCE)
end

local function tick()
	for _, player in Players:GetPlayers() do
		local profile: Types.Profile? = DataService.get(player)
		if not profile then
			continue
		end
		profile.stats.playSeconds += EconomyConfig.TICK
		if PlotService.isLocked(player) then
			continue
		end
		local income = EconomyConfig.incomePerSecond(profile) * EconomyConfig.TICK
		if income > 0 then
			addCoins(profile, income)
		end
		local nextRow = FacilityConfig.nextOf(profile.facilities)
		if nextRow and PlotService.plotOf(player) then
			local price = FacilityConfig.priceOf(nextRow.id, profile.graduations)
			if profile.coins >= price and PlotService.occupants(player)[nextRow.id] then
				buy(player, profile, nextRow)
				continue
			end
		end
		if income > 0 then
			DataService.markDirty(player)
		end
	end
end

--- 이 부지에 아직 안 주운 금 스티커가 있나
local function goldOut(plotId: number): boolean
	for _, part in PlotService.activeStickers(plotId) do
		if part:GetAttribute(Keys.ATTR_GOLD) and not part:GetAttribute(Keys.ATTR_COLLECTED) then
			return true
		end
	end
	return false
end

local function respawnSticker(player: Player, plotId: number, part: BasePart)
	task.delay(EconomyConfig.RESPAWN, function()
		if not part.Parent or not part:GetAttribute("Enabled") then
			return
		end
		if PlotService.ownerOf(plotId) ~= player then
			return -- 주인이 바뀌었으면 PlotService.release 가 이미 다시 켰다
		end
		local profile: Types.Profile? = DataService.get(player)
		local gold = profile ~= nil and EconomyConfig.isGoldNext(profile.stats.totalStickers) and not goldOut(plotId)
		part:SetAttribute(Keys.ATTR_GOLD, gold)
		part:SetAttribute(Keys.ATTR_COLLECTED, false)
		part.CanTouch = true
	end)
end

local function onSticker(player: Player, part: BasePart)
	local plotId = PlotService.plotOf(player)
	local profile: Types.Profile? = DataService.get(player)
	if not plotId or not profile or PlotService.isLocked(player) then
		return
	end
	local folder = part.Parent
	if not folder or folder.Parent ~= PlotService.folder(plotId) then
		return -- 남의 부지 스티커는 반응하지 않는다
	end
	if not part:GetAttribute("Enabled") or part:GetAttribute(Keys.ATTR_COLLECTED) then
		return
	end
	local now = os.clock()
	if now - (lastStickerAt[player] or 0) < EconomyConfig.STICKER_TOUCH_INTERVAL then
		return
	end
	local root = rootOf(player)
	if not root or (root.Position - part.Position).Magnitude > TOUCH_RANGE then
		return
	end
	-- 속도는 서버가 본 두 줍기 사이 이동으로 잰다. AssemblyLinearVelocity 는 클라가 소유한 값이라 순간이동하면 0 이다
	local lastPos = lastStickerPos[player]
	local tooFast = lastPos ~= nil
		and (root.Position - lastPos).Magnitude / (now - lastStickerAt[player]) > EconomyConfig.STICKER_MAX_SPEED
	-- 거절해도 기준점은 옮긴다. 안 옮기면 같은 스티커의 Touched 마다 위반이 쌓여 한 번의 순간이동으로 킥에 가까워진다
	lastStickerAt[player] = now
	lastStickerPos[player] = root.Position
	if tooFast then
		RemoteGuard.violation(player, "스티커 과속")
		return
	end

	part:SetAttribute(Keys.ATTR_COLLECTED, true)
	part.CanTouch = false

	local gold = part:GetAttribute(Keys.ATTR_GOLD) == true
	local value = EconomyConfig.stickerValue(profile)
	if gold then
		value *= EconomyConfig.GOLD_MULT
	end
	local combo = combos[player]
	if combo and now - combo.last <= EconomyConfig.COMBO_WINDOW then
		combo.count += 1
		combo.last = now
	else
		combo = { count = 1, last = now }
		combos[player] = combo
	end

	addCoins(profile, value)
	profile.stats.totalStickers += 1
	profile.stickerBoard += 1
	if combo.count % EconomyConfig.COMBO_BONUS_EVERY == 0 then
		profile.stickerBoard += 1
	end
	StudentService.settleBoard(profile)

	Remotes.event(player, "StickerCollected", {
		stickerId = part:GetAttribute(Keys.ATTR_STICKER_ID),
		value = value,
		combo = combo.count,
		boardCells = profile.stickerBoard,
		gold = gold,
	})
	MissionService.onSticker(player, 1)
	DataService.syncNow(player)
	DataService.saveDebounced(player, EconomyConfig.SAVE_DEBOUNCE)
	respawnSticker(player, plotId, part)
end

local function onStar(player: Player, plotId: number, part: BasePart)
	local profile: Types.Profile? = DataService.get(player)
	if not profile or PlotService.isLocked(player) then
		return
	end
	if PlotService.plotOf(player) == plotId or PlotService.ownerOf(plotId) == nil then
		return -- 주인은 반응 없음, 빈 학교도 없음
	end
	local root = rootOf(player)
	if not root or (root.Position - part.Position).Magnitude > TOUCH_RANGE then
		return
	end
	local now = os.clock()
	local windows = starWindows[player]
	if not windows then
		windows = {}
		starWindows[player] = windows
	end
	local window = windows[plotId]
	if not window or now - window.start >= EconomyConfig.STAR_COOLDOWN then
		window = { start = now, count = 0, taken = {} }
		windows[plotId] = window
	end
	-- 걷는 동안 Touched 가 여러 번 온다. 같은 별은 창 안에서 한 번만 센다(클라에서는 이미 사라졌다)
	if window.count >= EconomyConfig.VISITOR_STARS or window.taken[part] then
		return
	end
	window.count += 1
	window.taken[part] = true

	profile.stickerBoard += 1
	StudentService.settleBoard(profile)
	Remotes.event(player, "StickerCollected", {
		stickerId = part.Name,
		plot = plotId, -- 별 이름(Star01·Star02)은 부지마다 같다
		value = 0,
		combo = 0,
		boardCells = profile.stickerBoard,
		gold = false,
	})
	MissionService.onSticker(player, 1) -- 미션 1 은 남의 부지 별도 센다(§6.3)
	DataService.syncNow(player)
end

--- 기획서 §11.5 ①~⑦
local function onSetSkin(player: Player, facilityId: string, skinIndex: number)
	local profile: Types.Profile? = DataService.get(player)
	if not profile or not FacilityConfig.BY_ID[facilityId] or not SkinConfig.isValidIndex(skinIndex) then
		return
	end
	if not profile.facilities[facilityId] or PlotService.isLocked(player) then
		return
	end
	if skinIndex == SkinConfig.GRADUATION_INDEX and profile.graduations < 1 then
		return
	end
	local key = SkinConfig.key(facilityId, skinIndex)
	if skinIndex > 1 and not profile.skinsOwned[key] then
		local price = SkinConfig.priceOf(facilityId, skinIndex, profile.graduations)
		if profile.coins < price then
			Remotes.deny(player, "coins")
			return
		end
		profile.coins -= price
		profile.skinsOwned[key] = true
	end
	profile.skinsApplied[facilityId] = skinIndex
	PlotService.applySkin(player, facilityId, skinIndex)
	Remotes.event(
		nil,
		"SkinApplied",
		{ plot = PlotService.plotOf(player), facilityId = facilityId, skinIndex = skinIndex }
	)
	DataService.syncNow(player)
	DataService.saveDebounced(player, EconomyConfig.SAVE_DEBOUNCE)
end

function EconomyService.Start()
	PlotService.StickerTouched:Connect(onSticker)
	PlotService.StarTouched:Connect(onStar)

	RemoteGuard.wrap(Remotes.SetSkin, { cooldown = SKIN_COOLDOWN, args = { "string", "number" } }, onSetSkin)
	RemoteGuard.wrap(Remotes.GoHome, { cooldown = HOME_COOLDOWN, args = {} }, function(player)
		PlotService.goHome(player)
		lastStickerPos[player] = nil -- 귀가 순간이동을 과속으로 보지 않는다
	end)

	Players.PlayerRemoving:Connect(function(player)
		combos[player] = nil
		lastStickerAt[player] = nil
		lastStickerPos[player] = nil
		starWindows[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(EconomyConfig.TICK)
			local ok, err = pcall(tick)
			if not ok then
				warn(`[EconomyService] tick: {err}`)
			end
		end
	end)
end

return EconomyService
