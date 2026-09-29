--!strict
--[[
	일일 미션 3개. 기획서 §6.3.
	  ensureDay(profile)   KST 일 번호가 바뀌었으면 진행도·done 초기화. 모든 진행 갱신 직전과 60초 틱에서 부른다
	  onSticker/onBuilt/onChair  진행도 갱신 → 목표 달성 즉시 원서 +1, 즉시 저장, MissionDone 발송
	  교장 의자: Workspace.Plots.PlotNN 안 "principal" 모델의 Seat "PrincipalChair" Occupant 를 감시한다.
	    주인이 아니면 Sit=false + Seat.Disabled 1초. 주인이면 onChair.
	3/3 완료 배너는 클라이언트가 프로필로 판단한다(추가 보상 없음).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local MissionConfig = require(ReplicatedStorage.Shared.Config.MissionConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)

local MissionService = {}

-- TODO(통합): 시설 id "principal" 은 FacilityConfig 의 id 문자열이다. Keys 에 상수가 없어 여기 둔다.
local PRINCIPAL_FACILITY_ID: Types.FacilityId = "principal"
-- TODO(통합): 기획서 §6.3 "Seat.Disabled 1초". 전용 Config 가 생기면 옮긴다.
local CHAIR_BLOCK_SECONDS = 1
local PLOTS_WAIT = 10

local function indexOf(id: string): number
	for i, row in MissionConfig.LIST do
		if row.id == id then
			return i
		end
	end
	return 0
end

local STICKERS_INDEX = indexOf("stickers")
local BUILT_INDEX = indexOf("built")
local CHAIR_INDEX = indexOf("chair")

local seatConnections: { [Seat]: RBXScriptConnection } = {}
local blockGeneration: { [Seat]: number } = {}

--- 날짜가 바뀌었으면 초기화. 초기화했으면 true
function MissionService.ensureDay(profile: Types.Profile): boolean
	local today = MissionConfig.dayOf(os.time())
	local missions = profile.missions
	if missions.day == today then
		return false
	end
	missions.day = today
	missions.stickers = 0
	missions.built = 0
	missions.chair = false
	missions.done = { false, false, false }
	return true
end

local function complete(player: Player, profile: Types.Profile, index: number)
	profile.missions.done[index] = true
	profile.tickets += MissionConfig.REWARD_TICKETS
	DataService.save(player)
	Remotes.event(player, "MissionDone", { index = index })
	DataService.markDirty(player)
end

local function check(player: Player, profile: Types.Profile, index: number)
	if index == 0 or profile.missions.done[index] then
		return
	end
	if MissionConfig.progressOf(profile.missions, index) >= MissionConfig.LIST[index].target then
		complete(player, profile, index)
	end
end

--- 스티커·별 count 개 주움
function MissionService.onSticker(player: Player, count: number)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	MissionService.ensureDay(profile)
	profile.missions.stickers += count
	check(player, profile, STICKERS_INDEX)
	DataService.markDirty(player)
end

--- 시설 1개 구매
function MissionService.onBuilt(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	MissionService.ensureDay(profile)
	profile.missions.built += 1
	check(player, profile, BUILT_INDEX)
	DataService.markDirty(player)
end

--- 교장 의자에 주인이 앉음
function MissionService.onChair(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	MissionService.ensureDay(profile)
	if profile.missions.chair then
		return
	end
	profile.missions.chair = true
	check(player, profile, CHAIR_INDEX)
	DataService.markDirty(player)
end

local function blockSeat(seat: Seat, occupant: Humanoid)
	occupant.Sit = false
	local generation = (blockGeneration[seat] or 0) + 1
	blockGeneration[seat] = generation
	seat.Disabled = true
	task.delay(CHAIR_BLOCK_SECONDS, function()
		if blockGeneration[seat] == generation and seat.Parent then
			seat.Disabled = false
		end
	end)
end

local function watchSeat(plotId: number, seat: Seat)
	if seatConnections[seat] then
		return
	end
	local connection = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		if not occupant then
			return
		end
		local character = occupant.Parent
		local sitter = if character and character:IsA("Model") then Players:GetPlayerFromCharacter(character) else nil
		local owner = PlotService.ownerOf(plotId)
		if sitter == nil or owner == nil or sitter ~= owner then
			blockSeat(seat, occupant)
			return
		end
		MissionService.onChair(sitter)
	end)
	seatConnections[seat] = connection
	seat.Destroying:Connect(function()
		connection:Disconnect()
		seatConnections[seat] = nil
		blockGeneration[seat] = nil
	end)
end

local function watchPlot(plotModel: Instance)
	local plotId = Keys.plotIdOf(plotModel.Name)
	if not plotId then
		return
	end
	local function onChild(child: Instance)
		if child.Name ~= PRINCIPAL_FACILITY_ID then
			return
		end
		task.spawn(function()
			local seat = child:FindFirstChild(Keys.PRINCIPAL_CHAIR, true) or child:WaitForChild(Keys.PRINCIPAL_CHAIR, 5)
			if seat and seat:IsA("Seat") then
				watchSeat(plotId, seat)
			else
				warn(`[MissionService] {plotModel.Name}.principal 에 Seat {Keys.PRINCIPAL_CHAIR} 가 없다`)
			end
		end)
	end
	for _, child in plotModel:GetChildren() do
		onChild(child)
	end
	plotModel.ChildAdded:Connect(onChild)
end

--- 60초 날짜 틱 + 교장 의자 감시
function MissionService.Start()
	local plots = Workspace:WaitForChild(Keys.PLOTS_FOLDER, PLOTS_WAIT)
	if plots then
		for _, plotModel in plots:GetChildren() do
			watchPlot(plotModel)
		end
		plots.ChildAdded:Connect(watchPlot)
	else
		warn(`[MissionService] Workspace.{Keys.PLOTS_FOLDER} 가 없어 교장 의자를 감시하지 않는다`)
	end

	task.spawn(function()
		while true do
			task.wait(MissionConfig.CHECK_INTERVAL)
			for _, player in Players:GetPlayers() do
				local profile = DataService.get(player)
				if profile and MissionService.ensureDay(profile) then
					DataService.markDirty(player)
				end
			end
		end
	end)
end

return MissionService
