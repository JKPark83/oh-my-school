--!nonstrict
--[[
	플레이어 프로필. ProfileStore 위에 얇게 얹었다. 기획서 §11.6.
	  - 프로필 형태는 TEMPLATE 하나뿐이다. 필드를 추가하면 Reconcile 이 채운다.
	  - 형태가 바뀌면 SCHEMA_VERSION 을 올리고 MIGRATIONS[이전 버전] 에 변환을 적는다.
	  - 저장 시점: 졸업·미션 완료·퇴장은 save(), 구매·뽑기는 saveDebounced(player, 30).
	  - ProfileSync: markDirty() 로 예약하면 1초 틱이 모아서 보낸다(≤1Hz, seq 단조 증가). syncNow() 는 즉시.
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

local DataService = {}

local STORE_NAME = "PrincipalProfile"
local SCHEMA_VERSION = 1
local SYNC_INTERVAL = 1

-- 색 바꾸기 필드 두 개를 지우며 버전을 올리지 않았다. 실 데이터가 없고 Reconcile 은 남는 키를 건드리지 않는다
local TEMPLATE: Types.Profile = {
	version = SCHEMA_VERSION,
	coins = 10,
	tickets = 0,
	stickerBoard = 0,
	graduations = 0,
	facilities = {},
	students = {},
	pity = 0,
	missions = { day = 0, stickers = 0, built = 0, chair = false, done = { false, false, false } },
	settings = { shake = true, sfx = true, haptic = true },
	stats = { totalCoins = 0, totalStickers = 0, totalPulls = 0, playSeconds = 0 },
}

-- [이전 버전] = 그 버전의 데이터를 다음 버전으로 바꾸는 함수. version 증가는 루프가 한다.
local MIGRATIONS: { [number]: (data: any) -> () } = {}

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
	Remotes.ProfileSync:FireClient(player, { seq = seqs[player], profile = profile.Data })
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
