--!nonstrict
--[[
	용돈·구매·스티커·별. 기획서 §2.2·§3.2·§5·§7.5·§9.1·§11.5, 계획서 §3.2.
	  1Hz 틱   수입 지급 → 활성 패드 위에 서 있고 돈이 되면 다음 부품 1개 자동 구매(개선계획 §3.4) → ProfileSync
	  스티커   PlotService.StickerTouched → 검증(주인·간격·속도·거리) → 가치·콤보·판 → 15초 뒤 리스폰(금 판단)
	  별       PlotService.StarTouched → 방문자 판 +1 (부지·60초당 2개)
	  GoHome   PlotService.goHome (5초 쿨다운)
	  층 쌓기  ChooseRoom(주인) → towerRoom. 시설 14개 뒤 층 패드("tower")에 서 있으면 방 부품 자동 구매,
	           PARTS 번째에 완공(floors·rooftop, 전학생, 순위 제출, 저장). 이벤트는 주인에게만(개선계획 §3·§5)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local StudentConfig = require(ReplicatedStorage.Shared.Config.StudentConfig)
local RoomConfig = require(ReplicatedStorage.Shared.Config.RoomConfig)
local PlotLayout = require(ReplicatedStorage.Shared.PlotLayout)
local Seats = require(ReplicatedStorage.Shared.Seats)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local StudentService = require(script.Parent.StudentService)
local MissionService = require(script.Parent.MissionService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local Tower = require(script.Parent.Parent.Geometry.Tower)
local GiftBoard = require(script.Parent.Parent.GiftBoard)
local RemoteGuard = require(script.Parent.Parent.RemoteGuard)
local Metrics = require(script.Parent.Parent.Metrics)

local EconomyService = {}

local HOME_COOLDOWN = 5
local TOUCH_RANGE = 12
local CHOOSE_COOLDOWN = 0.5
local CELEBRATE_DELAY = 4.5 -- 층 완공 연출이 끝난 뒤 그 층에 서 있던 주인을 새 옥상으로 올린다

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

--- 부품 1개 구매. 돈은 호출자가 확인했다. 마지막 부품이면 시설 완공(수입·전학생은 완공 때만)
local function buy(player: Player, profile: Types.Profile, nextPart: FacilityConfig.NextPart)
	local row = nextPart.facility
	local price = FacilityConfig.partPriceOf(row.id, nextPart.index)
	local done = nextPart.index >= nextPart.count
	profile.coins -= price
	-- 프로필을 먼저 바꾼다. buildPart 가 이 값으로 패드·실루엣·스티커를 갱신한다
	if done then
		profile.buildParts = 0
		profile.facilities[row.id] = true
	else
		profile.buildParts = nextPart.index
	end
	local plotId = PlotService.plotOf(player)
	PlotService.buildPart(player, row.id, nextPart.index)
	Metrics.partBuilt(player)
	Remotes.event(nil, "PartBuilt", {
		plot = plotId,
		facilityId = row.id,
		partIndex = nextPart.index,
		partCount = nextPart.count,
	})
	if not done then
		DataService.syncNow(player)
		DataService.saveDebounced(player, EconomyConfig.SAVE_DEBOUNCE)
		return
	end

	Metrics.facilityBuilt(player)
	Remotes.event(nil, "FacilityBuilt", { plot = plotId, facilityId = row.id })

	-- 이미 데리고 있던 학생 중 이 시설에 자리가 있는 아이들이 제자리에 "짠" 하고 나타난다
	for studentId, count in profile.students do
		local student = StudentConfig.BY_ID[studentId]
		if count > 0 and student and student.seat.facilityId == row.id and plotId then
			Remotes.event(nil, "StudentJoined", { plot = plotId, studentId = studentId, walk = true })
		end
	end
	-- 이미 데리고 있는 학생은 위에서 나타났다. 다시 주면 도감에 중복(×2)으로 잡힌다
	if row.student and (profile.students[row.student] or 0) == 0 then
		StudentService.grant(player, row.student, true)
	end
	MissionService.onBuilt(player)
	DataService.syncNow(player)
	DataService.saveDebounced(player, EconomyConfig.SAVE_DEBOUNCE)
end

--- 층 완공 뒤 floorNo 층 발자국 안에 서 있으면 새 옥상(floorNo + 1) 도착 자리로 올린다
local function liftToRoof(player: Player, floorNo: number)
	local plotId = PlotService.plotOf(player)
	local root = rootOf(player)
	if not plotId or not root then
		return
	end
	local p = PlotService.cframe(plotId):PointToObjectSpace(root.Position)
	local foot = PlotLayout.TOWER_FOOTPRINT
	local inside = p.X >= foot.x0 and p.X <= foot.x1 and p.Z >= foot.z0 and p.Z <= foot.z1
	if inside and p.Y >= RoomConfig.floorY(floorNo) and p.Y < RoomConfig.floorY(floorNo + 1) then
		PlotService.teleport(player, Tower.arrival(PlotService.cframe(plotId), floorNo + 1))
	end
end

--- 짓던 방(towerRoom) 완공. 부품 수·돈은 호출자가 처리했다
local function finishRoom(player: Player, profile: Types.Profile)
	local roomId = profile.towerRoom
	local room = RoomConfig.BY_ID[roomId]
	local floorNo = 0
	if room.kind == "floor" then
		table.insert(profile.floors, roomId)
		floorNo = RoomConfig.topFloor(#profile.floors)
	else
		profile.rooftop[roomId] = true
	end
	profile.towerParts = 0
	profile.towerRoom = ""
	PlotService.refreshTower(player)
	local plotId = PlotService.plotOf(player)
	Remotes.event(player, "FloorBuilt", { plot = plotId, room = roomId, floor = floorNo, floors = #profile.floors })
	if room.student then
		if (profile.students[room.student] or 0) == 0 then
			StudentService.grant(player, room.student, true)
		elseif
			(room.kind == "roof" or table.find(profile.floors, roomId) == #profile.floors)
			and Seats.roomSeat(room.student, profile.floors, RoomConfig.rooftopList(profile.rooftop))
		then
			-- 이미 데리고 있던 아이가 새 방 자리에 나타난다(시설 완공과 같다).
			-- 반복 층이면 자리는 처음 지은 층 그대로라 다시 등장시키지 않는다
			Remotes.event(nil, "StudentJoined", { plot = plotId, studentId = room.student, walk = true })
		end
	end
	MissionService.onBuilt(player)
	LeaderboardService.submit(player, #profile.floors)
	if floorNo > 0 then
		task.delay(CELEBRATE_DELAY, liftToRoof, player, floorNo)
	end
	DataService.syncNow(player)
	DataService.save(player)
end

--- 방 부품 1개 구매. 돈은 호출자가 확인했다. PARTS 번째면 완공
local function buyRoomPart(player: Player, profile: Types.Profile, step: number)
	local k = profile.towerParts + 1
	profile.coins -= RoomConfig.partPrice(step, k)
	Metrics.partBuilt(player)
	if k >= RoomConfig.PARTS then
		finishRoom(player, profile)
		return
	end
	profile.towerParts = k
	PlotService.refreshTower(player)
	local room = RoomConfig.BY_ID[profile.towerRoom]
	Remotes.event(player, "FloorPart", {
		plot = PlotService.plotOf(player),
		room = profile.towerRoom,
		partIndex = k,
		floor = if room.kind == "floor" then RoomConfig.topFloor(#profile.floors) + 1 else 0,
	})
	DataService.syncNow(player)
	DataService.saveDebounced(player, EconomyConfig.SAVE_DEBOUNCE)
end

--- ChooseRoom(roomId). 주인만(자기 프로필), 강당 완공·짓는 방 없음·고를 수 있는 방(canChoose 가 전부 본다)
local function chooseRoom(player: Player, roomId: string)
	local profile: Types.Profile? = DataService.get(player)
	local plotId = PlotService.plotOf(player)
	if not profile or not plotId or not RoomConfig.canChoose(profile, roomId) then
		return
	end
	profile.towerRoom = roomId
	profile.towerParts = 0
	PlotService.refreshTower(player)
	Remotes.event(player, "RoomChosen", { plot = plotId, room = roomId })
	DataService.syncNow(player)
	DataService.saveDebounced(player, EconomyConfig.SAVE_DEBOUNCE)
end

--- DevCheat BuildFloor: 강당·돈·패드 없이 그 방을 바로 완공한다(평소 완공 경로 그대로). 못 지으면 false
function EconomyService.buildRoom(player: Player, roomId: string): boolean
	local profile: Types.Profile? = DataService.get(player)
	local room = RoomConfig.BY_ID[roomId]
	if not profile or not room or not PlotService.plotOf(player) then
		return false
	end
	if room.kind == "roof" and profile.rooftop[roomId] then
		return false
	end
	if room.kind == "floor" and RoomConfig.topFloor(#profile.floors) >= RoomConfig.MAX_FLOOR then
		return false
	end
	-- 정상 경로와 같이 안 지은 층 방 종류가 남아 있으면 이미 지은 방은 다시 못 짓는다(§3.2)
	if room.kind == "floor" and table.find(profile.floors, roomId) then
		for _, other in RoomConfig.LIST do
			if other.kind == "floor" and not table.find(profile.floors, other.id) then
				return false
			end
		end
	end
	-- 짓던 방이 있으면 그 부품은 버린다(치트)
	profile.towerRoom = roomId
	finishRoom(player, profile)
	return true
end

local function tick()
	for _, player in Players:GetPlayers() do
		local profile: Types.Profile? = DataService.get(player)
		if not profile then
			continue
		end
		profile.stats.playSeconds += EconomyConfig.TICK
		local income = EconomyConfig.incomePerSecond(profile) * EconomyConfig.TICK
		if income > 0 then
			addCoins(profile, income)
			DataService.markDirty(player)
		end
	end
end

--- 발판 확인. 수입 틱(1초)과 떼어 PAD_TICK 마다 돈다. 1초면 올라선 뒤 최대 1초를 기다리고, 그 사이 내려서면 놓친다
local function padTick()
	for _, player in Players:GetPlayers() do
		local profile: Types.Profile? = DataService.get(player)
		if not profile or not PlotService.plotOf(player) then
			continue
		end
		-- 틱당 부품 1개. nil 이면 14개 완공이라 살 것이 없다
		local nextPart = FacilityConfig.nextPartOf(profile.facilities, profile.buildParts)
		if nextPart then
			local id = nextPart.facility.id
			local price = FacilityConfig.partPriceOf(id, nextPart.index)
			if profile.coins >= price and PlotService.occupants(player)[id] then
				buy(player, profile, nextPart)
			end
		elseif profile.towerRoom ~= "" then
			-- 시설 14개 뒤: 고른 방의 다음 부품(층 패드)
			local step = RoomConfig.nextStep(profile)
			if
				step
				and profile.coins >= RoomConfig.partPrice(step, profile.towerParts + 1)
				and PlotService.occupants(player)[Tower.PAD_ID]
			then
				buyRoomPart(player, profile, step)
			end
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
		-- 튜토리얼 중(총 스티커 < STICKER_HOME_UNTIL)은 홈 자리, 그 뒤는 무작위(§3.2 #4·#5). 자리를 먼저 옮기고 Collected 를 푼다
		local home = profile == nil or profile.stats.totalStickers < EconomyConfig.STICKER_HOME_UNTIL
		PlotService.moveSticker(plotId, part, home)
		local gold = profile ~= nil and EconomyConfig.isGoldNext(profile.stats.totalStickers) and not goldOut(plotId)
		part:SetAttribute(Keys.ATTR_GOLD, gold)
		part:SetAttribute(Keys.ATTR_COLLECTED, false)
		part.CanTouch = true
		Metrics.stickerSpawned(player, part)
	end)
end

local function onSticker(player: Player, part: BasePart)
	local plotId = PlotService.plotOf(player)
	local profile: Types.Profile? = DataService.get(player)
	if not plotId or not profile then
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
	Metrics.stickerCollected(player, part)
	profile.stickerBoard += 1
	if combo.count % EconomyConfig.COMBO_BONUS_EVERY == 0 then
		profile.stickerBoard += 1
	end
	-- StickerCollected 의 boardCells 가 정산 뒤 값이 되게 먼저 정산한다(GiftOpened 가 먼저 간다)
	GiftBoard.settleBoard(player, profile)

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
	if not profile then
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
	GiftBoard.settleBoard(player, profile)
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

function EconomyService.Start()
	PlotService.StickerTouched:Connect(onSticker)
	PlotService.StarTouched:Connect(onStar)
	-- 순간이동 직후 첫 줍기를 과속으로 보지 않는다(개선계획 §3.6 #1)
	PlotService.Teleported:Connect(function(player)
		lastStickerPos[player] = nil
	end)

	RemoteGuard.wrap(Remotes.GoHome, { cooldown = HOME_COOLDOWN, args = {} }, function(player)
		PlotService.goHome(player)
	end)
	RemoteGuard.wrap(Remotes.ChooseRoom, { cooldown = CHOOSE_COOLDOWN, args = { "string" } }, chooseRoom)

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
	task.spawn(function()
		while true do
			task.wait(EconomyConfig.PAD_TICK)
			local ok, err = pcall(padTick)
			if not ok then
				warn(`[EconomyService] padTick: {err}`)
			end
		end
	end)
end

return EconomyService
