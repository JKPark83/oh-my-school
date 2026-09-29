--!strict
--[[
	Studio 전용 치트. 계획서 §0 수치 검증용. Studio 가 아니면 아무것도 하지 않는다.
	ServerScriptService.DevCheat 폴더에 BindableFunction 2개를 둔다.
	  FastForward(player, seconds)  초당 수입 × seconds 만큼 용돈 지급. 지급액을 돌려준다
	  GiveTickets(player, n)        원서 n장. 지급 후 보유 수를 돌려준다
	MCP execute_luau 예:
	  game.ServerScriptService.DevCheat.FastForward:Invoke(game.Players:GetPlayers()[1], 600)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local DataService = require(script.Parent.Services.DataService)
local EconomyService = require(script.Parent.Services.EconomyService)

local DevCheat = {}

local FOLDER_NAME = "DevCheat"
local FAST_FORWARD = "FastForward"
local GIVE_TICKETS = "GiveTickets"

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

--- 원서 n장 지급. 보유 수 반환
function DevCheat.giveTickets(player: Player, n: number): number
	local profile = DataService.get(player)
	if not profile then
		return 0
	end
	profile.tickets += n
	DataService.markDirty(player)
	return profile.tickets
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

	local giveTickets = Instance.new("BindableFunction")
	giveTickets.Name = GIVE_TICKETS
	giveTickets.OnInvoke = function(player: any, n: any): number
		if not isPlayer(player) or typeof(n) ~= "number" then
			warn(`[DevCheat] {GIVE_TICKETS}(player, n) 인자가 틀렸다`)
			return 0
		end
		return DevCheat.giveTickets(player, n)
	end
	giveTickets.Parent = folder

	folder.Parent = ServerScriptService
	print(`[DevCheat] {FOLDER_NAME}.{FAST_FORWARD} / {GIVE_TICKETS} 준비`)
end

return DevCheat
