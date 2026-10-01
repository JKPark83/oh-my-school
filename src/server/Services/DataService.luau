--!nonstrict
--[[
	플레이어 프로필. ProfileStore 위에 얇게 얹었다. 기획서 §11.6.
	  - 프로필 형태는 TEMPLATE 하나뿐이다. 필드를 추가하면 Reconcile 이 채운다.
	  - 형태가 바뀌면 SCHEMA_VERSION 을 올리고 MIGRATIONS[이전 버전] 에 변환을 적는다.
	  - 저장 시점: 미션 완료·퇴장은 save(), 구매·스티커는 saveDebounced(player, 30).
	  - ProfileSync: markDirty() 로 예약하면 1초 틱이 모아서 보낸다(≤1Hz, seq 단조 증가). syncNow() 는 즉시.
	    decorPlaced 는 빼고 보낸다. 40개면 1.6KB 라 2KB 예산을 넘고, 클라는 PlotState Decor 어트리뷰트로 읽는다.
	Studio 에서는 "_Dev" 스토어 + Mock 이다. 실제 DataStore 를 쓰려면
	ServerScriptService 에 UseLiveDataStore = true 어트리뷰트를 둔다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local DecorConfig = require(ReplicatedStorage.Shared.Config.DecorConfig)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local DecorGrid = require(ReplicatedStorage.Shared.DecorGrid)
local Migrations = require(script.Parent.Parent.Migrations)

local DataService = {}

-- 2026-10-01 졸업 폐기로 새 스토어에서 버전 1 부터 다시 센다(옛 데이터는 옮기지 않는다)
local STORE_NAME = "PrincipalSchool"
local SCHEMA_VERSION = 1
local SYNC_INTERVAL = 1

local TEMPLATE: Types.Profile = {
	version = SCHEMA_VERSION,
	coins = EconomyConfig.START_COINS,
	stickerBoard = 0,
	giftIndex = 0,
	facilities = {},
	buildParts = 0,
	students = {},
	missions = { day = 0, stickers = 0, built = 0, chair = false, done = { false, false, false } },
	settings = { shake = true, sfx = true, music = true, haptic = true },
	stats = { totalCoins = 0, totalStickers = 0, playSeconds = 0 },
	-- 빈 표로 둔다. 중첩 키를 두면 Reconcile 이 0 이 되어 지워진 키를 로드마다 다시 채운다(ProfileStore ReconcileTable)
	decorOwned = {},
	decorPlaced = {},
	decorPaid = {},
	decorStarter = false, -- load 가 false 면 튜토리얼 화분을 넣고 true 로 바꾼다
	-- 층 쌓기(개선계획 2026-10-01 §2.1). 쓰는 곳은 P2
	floors = {},
	rooftop = {},
	towerRoom = "",
	towerParts = 0,
	likes = 0,
}

-- [이전 버전] = 그 버전의 데이터를 다음 버전으로 바꾸는 함수. version 증가는 루프가 한다. 규칙은 Migrations.luau 머리말
local MIGRATIONS: { [number]: (data: any) -> () } = Migrations

local store
local profiles: { [Player]: any } = {}
local releasing: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}
local seqs: { [Player]: number } = {}
local savePending: { [Player]: boolean } = {}

local function migrate(data)
	while data.version < SCHEMA_VERSION do
		local step = MIGRATIONS[data.version]
		if not step then
			warn(
				`[DataService] version {data.version} → {data.version + 1} 마이그레이션이 없다. 그대로 올린다`
			)
		else
			step(data)
		end
		data.version += 1
	end
end

local function push(player: Player)
	local profile = profiles[player]
	if not profile or not player:IsDescendantOf(Players) then
		return
	end
	seqs[player] = (seqs[player] or 0) + 1
	local data = table.clone(profile.Data)
	data.decorPlaced = nil -- Decor 어트리뷰트가 같은 내용을 짧게 싣는다(≤2KB 예산)
	data.decorPaid = nil -- 환불 계산용. 서버만 쓴다(≤2KB 예산)
	Remotes.ProfileSync:FireClient(player, { seq = seqs[player], profile = data })
end

function DataService.Start()
	local isStudio = RunService:IsStudio()
	local useLive = isStudio and ServerScriptService:GetAttribute("UseLiveDataStore") == true
	local name = if isStudio then STORE_NAME .. "_Dev" else STORE_NAME
	local base = ProfileStore.New(name, TEMPLATE)
	store = if isStudio and not useLive then base.Mock else base
	if isStudio then
		print(`[DataService] {name} ({if useLive then "실제 DataStore" else "Mock"})`)
	end

	task.spawn(function()
		while true do
			task.wait(SYNC_INTERVAL)
			for player in dirty do
				dirty[player] = nil
				push(player)
			end
		end
	end)
end

--- 세션 시작. 실패하면 Kick 하고 nil
function DataService.load(player: Player): Types.Profile?
	local profile = store:StartSessionAsync(tostring(player.UserId), {
		Cancel = function()
			return player:IsDescendantOf(Players) == false
		end,
	})
	if not profile then
		player:Kick(Keys.KICK_RELOAD)
		return nil
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	migrate(profile.Data)
	-- 부지 배치가 바뀌어(2026-10-01 현관 확장 등) 정적 장애물에 묻힌 꾸미기는 보관함으로 돌린다. 산 값은 그대로다
	local placed = profile.Data.decorPlaced
	for i = #placed, 1, -1 do
		local p = placed[i]
		for _, cell in DecorGrid.footprint(p.item, p.cx, p.cz, p.rot) do
			if DecorGrid.isStaticBlocked(cell.X, cell.Y) then
				profile.Data.decorOwned[p.item] = (profile.Data.decorOwned[p.item] or 0) + 1
				table.remove(placed, i)
				break
			end
		end
	end
	-- 튜토리얼 ⑤ 화분(새 프로필·옛 프로필 한 번씩). 산 값이 없으니 돌려줘도 0
	local data = profile.Data
	if not data.decorStarter then
		local item = DecorConfig.TUTORIAL_ITEM
		local room = DecorConfig.MAX_OWNED - DecorConfig.heldCount(data.decorOwned, data.decorPlaced, item)
		local add = math.clamp(DecorConfig.TUTORIAL_FREE, 0, math.max(room, 0))
		if add > 0 then
			data.decorOwned[item] = (data.decorOwned[item] or 0) + add
		end
		data.decorStarter = true
	end

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if releasing[player] then
			releasing[player] = nil
			return
		end
		player:Kick(Keys.KICK_RELOAD)
	end)

	if not player:IsDescendantOf(Players) then
		profile:EndSession()
		return nil
	end

	profiles[player] = profile
	seqs[player] = 0
	return profile.Data
end

function DataService.get(player: Player): Types.Profile?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

--- 즉시 저장 요청. 세션이 없으면 false
function DataService.save(player: Player): boolean
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return false
	end
	savePending[player] = nil
	profile:Save()
	return true
end

--- seconds 안에 이미 예약된 저장이 있으면 합친다
function DataService.saveDebounced(player: Player, seconds: number)
	if savePending[player] then
		return
	end
	savePending[player] = true
	task.delay(seconds, function()
		if savePending[player] then
			DataService.save(player)
		end
	end)
end

--- 퇴장. 마지막 상태를 저장하고 세션을 닫는다
function DataService.release(player: Player)
	local profile = profiles[player]
	dirty[player] = nil
	seqs[player] = nil
	savePending[player] = nil
	if not profile then
		return
	end
	releasing[player] = true
	profile:EndSession()
end

--- 다음 1초 틱에 ProfileSync 를 보낸다
function DataService.markDirty(player: Player)
	if profiles[player] then
		dirty[player] = true
	end
end

--- 지금 바로 ProfileSync 를 보낸다
function DataService.syncNow(player: Player)
	dirty[player] = nil
	push(player)
end

DataService.TEMPLATE = TEMPLATE
DataService.SCHEMA_VERSION = SCHEMA_VERSION

return DataService
