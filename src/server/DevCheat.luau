--!strict
--[[
	Studio 전용 치트. 계획서 §0 수치 검증용. Studio 가 아니면 아무것도 하지 않는다.
	ServerScriptService.DevCheat 폴더에 BindableFunction 5개를 둔다.
	  FastForward(player, seconds)  초당 수입 × seconds 만큼 용돈 지급. 지급액을 돌려준다
	  GiveCoins(player, n)          용돈 n. 지급 후 보유 용돈을 돌려준다
	  GiveDecor(player, itemId, n)  꾸미기 보관함 n 개(아이템당 MAX_OWNED 까지). 넣은 뒤 보관함 수를 돌려준다
	  GiveFloors(player, n)         탑 층 수를 n(0..MAX-2)으로 맞춘다. 강당이 있어야 보인다. 맞춘 층 수를 돌려준다
	  RideElevator(player, prompt)  엘리베이터 프롬프트(Up/Down)를 누른 것처럼 서버 판정을 돌린다. 옮겼으면 true
	MCP execute_luau 예:
	  game.ServerScriptService.DevCheat.FastForward:Invoke(game.Players:GetPlayers()[1], 600)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local TowerConfig = require(ReplicatedStorage.Shared.Config.TowerConfig)
local DataService = require(script.Parent.Services.DataService)
local DecorService = require(script.Parent.Services.DecorService)
local EconomyService = require(script.Parent.Services.EconomyService)
local PlotService = require(script.Parent.Services.PlotService)

local DevCheat = {}

local FOLDER_NAME = "DevCheat"
local FAST_FORWARD = "FastForward"
local GIVE_COINS = "GiveCoins"
local GIVE_DECOR = "GiveDecor"
local GIVE_FLOORS = "GiveFloors"
local RIDE_ELEVATOR = "RideElevator"

--- seconds 초 동안의 수입을 한 번에 지급. 지급액 반환
function DevCheat.fastForward(player: Player, seconds: number): number
	local profile = DataService.get(player)
	if not profile then
		return 0
	end
	local amount = EconomyConfig.incomePerSecond(profile) * seconds
	EconomyService.grant(player, amount)
	return amount
end

--- 용돈 n 지급. 보유 용돈 반환
function DevCheat.giveCoins(player: Player, n: number): number
	local profile = DataService.get(player)
	if not profile then
		return 0
	end
	EconomyService.grant(player, n)
	return profile.coins
end

--- 탑 층 수를 n 으로 맞춘다(0..MAX-2). 맞춘 층 수 반환
function DevCheat.giveFloors(player: Player, n: number): number
	local profile = DataService.get(player)
	if not profile then
		return 0
	end
	profile.towerFloors = math.clamp(math.floor(n), 0, TowerConfig.MAX - 2)
	PlotService.refreshWorld(player)
	DataService.markDirty(player)
	DataService.syncNow(player)
	return profile.towerFloors
end

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

function DevCheat.Start()
	if not RunService:IsStudio() then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	local fastForward = Instance.new("BindableFunction")
	fastForward.Name = FAST_FORWARD
	fastForward.OnInvoke = function(player: any, seconds: any): number
		if not isPlayer(player) or typeof(seconds) ~= "number" then
			warn(`[DevCheat] {FAST_FORWARD}(player, seconds) 인자가 틀렸다`)
			return 0
		end
		return DevCheat.fastForward(player, seconds)
	end
	fastForward.Parent = folder

	local giveCoins = Instance.new("BindableFunction")
	giveCoins.Name = GIVE_COINS
	giveCoins.OnInvoke = function(player: any, n: any): number
		if not isPlayer(player) or typeof(n) ~= "number" then
			warn(`[DevCheat] {GIVE_COINS}(player, n) 인자가 틀렸다`)
			return 0
		end
		return DevCheat.giveCoins(player, n)
	end
	giveCoins.Parent = folder

	local giveDecor = Instance.new("BindableFunction")
	giveDecor.Name = GIVE_DECOR
	giveDecor.OnInvoke = function(player: any, itemId: any, n: any): number
		if not isPlayer(player) or typeof(itemId) ~= "string" or typeof(n) ~= "number" then
			warn(`[DevCheat] {GIVE_DECOR}(player, itemId, n) 인자가 틀렸다`)
			return 0
		end
		local owned = DecorService.give(player, itemId, n)
		DataService.syncNow(player)
		return owned
	end
	giveDecor.Parent = folder

	local giveFloors = Instance.new("BindableFunction")
	giveFloors.Name = GIVE_FLOORS
	giveFloors.OnInvoke = function(player: any, n: any): number
		if not isPlayer(player) or typeof(n) ~= "number" then
			warn(`[DevCheat] {GIVE_FLOORS}(player, n) 인자가 틀렸다`)
			return 0
		end
		return DevCheat.giveFloors(player, n)
	end
	giveFloors.Parent = folder

	-- 프롬프트는 서버에서 누를 수 없어 판정 함수를 직접 부른다(W6 게이트: 거리·층·쿨다운 확인)
	local rideElevator = Instance.new("BindableFunction")
	rideElevator.Name = RIDE_ELEVATOR
	rideElevator.OnInvoke = function(player: any, prompt: any): boolean
		if not isPlayer(player) or typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") then
			warn(`[DevCheat] {RIDE_ELEVATOR}(player, prompt) 인자가 틀렸다`)
			return false
		end
		return PlotService.rideElevator(prompt, player)
	end
	rideElevator.Parent = folder

	folder.Parent = ServerScriptService
	print(
		`[DevCheat] {FOLDER_NAME}.{FAST_FORWARD} / {GIVE_COINS} / {GIVE_DECOR} / {GIVE_FLOORS} / {RIDE_ELEVATOR} 준비`
	)
end

return DevCheat
