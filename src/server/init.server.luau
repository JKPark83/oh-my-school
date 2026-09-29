--!strict
--[[
	서버 부트스트랩. 순서를 아는 유일한 곳이다. 기획서 §11.2.

	모듈 최상위에서는 아무것도 하지 않는다. require 는 값만 반환하고 실제 작업은 Start() 에서 한다.

	순서:
	  Remotes.init       RemoteEvents 폴더 + 이벤트 7개. 가장 먼저
	  DataService        플레이어가 들어오기 전에 스토어가 있어야 한다
	  RemoteGuard        SetSetting 핸들러 + 위반 카운트 정리
	  CharacterBuilder   메시 원형 내려받기(task.spawn, 부팅을 막지 않는다)
	  PlotService        부지 12 + 광장 + PlotState. 뒤 서비스가 Workspace.Plots 를 읽는다
	  Economy → Student → Mission → Graduation → Leaderboard → Metrics → DevCheat(Studio)
	  PlayerAdded        이미 들어온 플레이어도 처리
]]

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DataService = require(script.Services.DataService)
local DevCheat = require(script.DevCheat)
local EconomyService = require(script.Services.EconomyService)
local GraduationService = require(script.Services.GraduationService)
local LeaderboardService = require(script.Services.LeaderboardService)
local Metrics = require(script.Metrics)
local MissionService = require(script.Services.MissionService)
local PlotService = require(script.Services.PlotService)
local RemoteGuard = require(script.RemoteGuard)
local StudentService = require(script.Services.StudentService)

Remotes.init()
DataService.Start()
RemoteGuard.Start()
task.spawn(CharacterBuilder.preload)
PlotService.Start()
EconomyService.Start()
StudentService.Start()
MissionService.Start()
GraduationService.Start()
LeaderboardService.Start()
Metrics.Start()
if RunService:IsStudio() then
	DevCheat.Start()
end

--- 어린이 안전(§12.2): 유료 무작위 아이템 제한 여부는 지금 로그만 한다
local function logPolicy(player: Player)
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	if ok then
		print(`[Policy] {player.UserId} ArePaidRandomItemsRestricted={info.ArePaidRandomItemsRestricted}`)
	else
		warn(`[Policy] {player.UserId} 조회 실패: {info}`)
	end
end

local function onPlayerAdded(player: Player)
	local profile = DataService.load(player)
	if not profile then
		return
	end
	MissionService.ensureDay(profile)
	if not PlotService.assign(player) then
		-- 12부지가 다 찼다(나간 사람의 release 보다 먼저 들어온 경우). 부지 없이는 할 게 없으니 다시 들어오게 한다
		player:Kick(Keys.KICK_RELOAD)
		return
	end
	Metrics.begin(player)
	DataService.syncNow(player)
	task.spawn(logPolicy, player)
end

local function onPlayerRemoving(player: Player)
	Metrics.finish(player)
	GraduationService.flush(player)
	PlotService.release(player)
	DataService.save(player)
	DataService.release(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

print(`[Boot] 교장이 되어보자! 부지 {Keys.PLOT_COUNT} + 광장 준비 완료`)
