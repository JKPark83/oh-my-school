--!nonstrict
--[[
	부지 12개 + 광장. 기획서 §7.1·§7.5·§11.4, 계획서 §3.2·§3.5.
	  - 부팅 때 Plaza 와 PlotShell 12개를 짓고 ReplicatedStorage.PlotState 폴더(어트리뷰트 7개)를 만든다.
	  - 접속 순서로 번호가 가장 작은 빈 부지를 준다. 나가면 즉시 비운다.
	  - 시설 모델은 buildFacility 가 Geometry/<id>.build 로 넣는다(어트리뷰트 Built/FacilityId/Skin/BuiltAt).
	  - 패드 상태·실루엣·스티커 스폰 수는 프로필의 facilities 에서 파생해 refresh 한다.
	  - 스티커·별 Touched 는 여기서 받아 BindableEvent 로 넘긴다(EconomyService 가 구독). 이 모듈은 Economy 를 모른다.
	  - 패드 판정은 Touched 대신 occupants() 가 주인 캐릭터의 HRP 위치로 직접 계산한다(1Hz, 활성 패드 1개뿐).
]]

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local SkinConfig = require(ReplicatedStorage.Shared.Config.SkinConfig)
local StudentConfig = require(ReplicatedStorage.Shared.Config.StudentConfig)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)

local GeometryFolder = script.Parent.Parent.Geometry
local BuildKit = require(script.Parent.Parent.BuildKit)
local PlotShell = require(GeometryFolder.PlotShell)
local Plaza = require(GeometryFolder.Plaza)

local PlotService = {}

-- 기획서 §7.1 표. 부지 로컬 +Z 가 교문이고, 교문은 전부 광장(원점)을 향한다.
local LAYOUT: { { x: number, z: number, yaw: number } } = {
	{ x = -72, z = 216, yaw = 180 },
	{ x = 72, z = 216, yaw = 180 },
	{ x = 216, z = 72, yaw = -90 },
	{ x = 216, z = -72, yaw = -90 },
	{ x = 72, z = -216, yaw = 0 },
	{ x = -72, z = -216, yaw = 0 },
	{ x = -216, z = -72, yaw = 90 },
	{ x = -216, z = 72, yaw = 90 },
	{ x = -216, z = 216, yaw = 180 },
	{ x = 216, z = 216, yaw = 180 },
	{ x = 216, z = -216, yaw = 0 },
	{ x = -216, z = -216, yaw = 0 },
}

local PAD_RADIUS = 3.2 -- 패드 4×4 의 중심에서 HRP 까지 수평 거리
local PAD_HEIGHT = 6
local SILHOUETTE_TRANSPARENCY = 0.7
local FALL_Y = -50
local GATE_NAME_MAX = 8

local cframes: { CFrame } = {}
local plotModels: { Model } = {}
local stateFolders: { Folder } = {}
local owners: { [number]: Player } = {}
local plotOf: { [Player]: number } = {}
local locked: { [Player]: boolean } = {}
local characterConns: { [Player]: RBXScriptConnection } = {}

local stickerTouched = Instance.new("BindableEvent")
local starTouched = Instance.new("BindableEvent")
PlotService.StickerTouched = stickerTouched.Event -- (player: Player, part: BasePart)
PlotService.StarTouched = starTouched.Event -- (player: Player, plotId: number, part: BasePart)

local function playerFromPart(part: BasePart): Player?
	local character = part.Parent
	if not character then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

local function plotIdOfPart(part: BasePart): number?
	local folder = part.Parent
	local model = folder and folder.Parent
	if model and model.Parent == Workspace:FindFirstChild(Keys.PLOTS_FOLDER) then
		return model:GetAttribute(Keys.ATTR_PLOT_ID)
	end
	return nil
end

local function facilityBuilder(facilityId: string)
	local module = GeometryFolder:FindFirstChild(facilityId)
	if not module then
		warn(`[PlotService] Geometry/{facilityId} 가 없다`)
		return nil
	end
	return require(module)
end

local function setCollisionGroup(character: Model)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = Keys.COLLISION_GROUP_PLAYERS
		end
	end
	character.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") then
			part.CollisionGroup = Keys.COLLISION_GROUP_PLAYERS
		end
	end)
end

local function gateSignLabel(plotId: number): TextLabel?
	local shell = plotModels[plotId]:FindFirstChild(Keys.SHELL)
	local sign = shell and shell:FindFirstChild(Keys.GATE_SIGN, true)
	if not sign then
		return nil
	end
	local label = sign:FindFirstChildWhichIsA("TextLabel", true)
	if label then
		return label
	end
	local gui = sign:FindFirstChildWhichIsA("SurfaceGui")
	if not gui then
		return nil
	end
	label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.92, 0.86)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(40, 40, 40)
	label.TextScaled = true
	label.Parent = gui
	return label
end

local function setGateSign(plotId: number, ownerName: string)
	local label = gateSignLabel(plotId)
	if not label then
		return
	end
	if ownerName == "" then
		label.Text = "빈 학교"
	else
		local short = ownerName
		local length = utf8.len(short) or 0
		if length > GATE_NAME_MAX then
			short = string.sub(short, 1, (utf8.offset(short, GATE_NAME_MAX + 1) or #short + 1) - 1)
		end
		label.Text = `{short}의 학교`
	end
end

local function resetState(plotId: number)
	local folder = stateFolders[plotId]
	folder:SetAttribute(Keys.ATTR_OWNER_ID, 0)
	folder:SetAttribute(Keys.ATTR_OWNER_NAME, "")
	folder:SetAttribute(Keys.ATTR_GRADUATIONS, 0)
	folder:SetAttribute(Keys.ATTR_FACILITIES, "")
	folder:SetAttribute(Keys.ATTR_SKINS, "")
	folder:SetAttribute(Keys.ATTR_STUDENTS, "")
	folder:SetAttribute(Keys.ATTR_INCOME, 0)
	setGateSign(plotId, "")
end

--- 패드 14개 상태를 facilities 에서 파생한다
local function refreshPads(plotId: number, built: { [string]: boolean })
	local pads = plotModels[plotId]:FindFirstChild(Keys.PADS_FOLDER)
	if not pads then
		return
	end
	local nextRow = FacilityConfig.nextOf(built)
	for _, pad in pads:GetChildren() do
		local id = pad.Name
		local state = "hidden"
		if built[id] then
			state = "built"
		elseif nextRow and nextRow.id == id then
			state = "active"
		end
		pad:SetAttribute(Keys.ATTR_PAD_STATE, state)
	end
end

--- 다음의 다음 시설 실루엣 하나
local function refreshSilhouette(plotId: number, built: { [string]: boolean })
	local model = plotModels[plotId]
	local old = model:FindFirstChild(Keys.SILHOUETTE)
	local afterRow = FacilityConfig.afterNextOf(built)
	if old then
		if afterRow and old:GetAttribute(Keys.ATTR_FACILITY_ID) == afterRow.id then
			return
		end
		old:Destroy()
	end
	if not afterRow then
		return
	end
	local builder = facilityBuilder(afterRow.id)
	if not builder then
		return
	end
	local silhouette = builder.build(cframes[plotId], 1)
	BuildKit.localizeAttachments(silhouette)
	silhouette.Name = Keys.SILHOUETTE
	silhouette:SetAttribute(Keys.ATTR_FACILITY_ID, afterRow.id)
	for _, part in silhouette:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = SILHOUETTE_TRANSPARENCY
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
		elseif part:IsA("Seat") then
			part.Disabled = true
		elseif part:IsA("SurfaceGui") or part:IsA("ProximityPrompt") or part:IsA("Light") then
			part:Destroy()
		end
	end
	silhouette.Parent = model
end

--- 2층 「공사 중」 실루엣: 강당이 서면 숨긴다
local function refreshConstruction(plotId: number, built: { [string]: boolean })
	local shell = plotModels[plotId]:FindFirstChild(Keys.SHELL)
	local construction = shell and shell:FindFirstChild(Keys.CONSTRUCTION)
	if not construction then
		return
	end
	local hidden = built.auditorium == true
	for _, part in construction:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = if hidden then 1 else SILHOUETTE_TRANSPARENCY
		elseif part:IsA("SurfaceGui") or part:IsA("BillboardGui") then
			part.Enabled = not hidden
		end
	end
end

--- 스폰 수(3 → 5 → 8)만큼만 스티커를 켠다. 새로 열리는 스폰은 즉시 보인다
local function refreshStickers(plotId: number, built: { [string]: boolean })
	local stickers = plotModels[plotId]:FindFirstChild(Keys.STICKERS_FOLDER)
	if not stickers then
		return
	end
	local count = EconomyConfig.spawnCount(built)
	for _, part in stickers:GetChildren() do
		local index = part:GetAttribute(Keys.ATTR_STICKER_ID) or 0
		local enabled = index <= count
		if part:GetAttribute("Enabled") ~= enabled then
			part:SetAttribute("Enabled", enabled)
			part:SetAttribute(Keys.ATTR_COLLECTED, not enabled)
			part:SetAttribute(Keys.ATTR_GOLD, false)
			part.CanTouch = enabled
		end
	end
end

local function refreshWorld(plotId: number, built: { [string]: boolean })
	refreshPads(plotId, built)
	refreshSilhouette(plotId, built)
	refreshConstruction(plotId, built)
	refreshStickers(plotId, built)
end

local function insertFacility(plotId: number, facilityId: string, skinIndex: number, fresh: boolean): Model?
	local builder = facilityBuilder(facilityId)
	if not builder then
		return nil
	end
	local model = plotModels[plotId]
	local old = model:FindFirstChild(facilityId)
	if old then
		old:Destroy()
	end
	local facility = builder.build(cframes[plotId], skinIndex)
	BuildKit.localizeAttachments(facility)
	facility.Name = facilityId
	facility:SetAttribute(Keys.ATTR_BUILT, true)
	facility:SetAttribute(Keys.ATTR_FACILITY_ID, facilityId)
	facility:SetAttribute(Keys.ATTR_SKIN, skinIndex)
	if fresh then
		facility:SetAttribute("BuiltAt", Workspace:GetServerTimeNow())
	end
	facility.Parent = model
	return facility
end

local function removeFacilities(plotId: number)
	local model = plotModels[plotId]
	for _, child in model:GetChildren() do
		if child:IsA("Model") and child:GetAttribute(Keys.ATTR_BUILT) then
			child:Destroy()
		end
	end
	local silhouette = model:FindFirstChild(Keys.SILHOUETTE)
	if silhouette then
		silhouette:Destroy()
	end
end

local function onPartTouched(part: BasePart, hit: BasePart)
	local player = playerFromPart(hit)
	if not player then
		return
	end
	local plotId = plotIdOfPart(part)
	if not plotId then
		return
	end
	if part:HasTag(Keys.STICKER_TAG) then
		stickerTouched:Fire(player, part)
	elseif part:HasTag(Keys.STAR_TAG) then
		starTouched:Fire(player, plotId, part)
	end
end

local function wireTouches(plotId: number)
	local model = plotModels[plotId]
	for _, folderName in { Keys.STICKERS_FOLDER, Keys.STARS_FOLDER } do
		local folder = model:FindFirstChild(folderName)
		if folder then
			for _, part in folder:GetChildren() do
				if part:IsA("BasePart") then
					part.Touched:Connect(function(hit)
						onPartTouched(part, hit)
					end)
				end
			end
		end
	end
end

local function buildPlot(plotId: number)
	local row = LAYOUT[plotId]
	local cf = CFrame.new(row.x, 0, row.z) * CFrame.Angles(0, math.rad(row.yaw), 0)
	cframes[plotId] = cf
	-- 교문(로컬 +Z 끝)이 부지 중심보다 원점에 가까워야 한다(교문은 광장을 향한다)
	local gate = cf:PointToWorldSpace(Vector3.new(0, 0, 60))
	assert(
		Vector3.new(gate.X, 0, gate.Z).Magnitude < Vector3.new(row.x, 0, row.z).Magnitude,
		`Plot{plotId} 의 교문이 광장을 향하지 않는다`
	)

	local model = PlotShell.build(cf, plotId)
	model.Name = Keys.plotName(plotId)
	model:SetAttribute(Keys.ATTR_PLOT_ID, plotId)
	plotModels[plotId] = model

	local state = Instance.new("Folder")
	state.Name = Keys.plotName(plotId)
	stateFolders[plotId] = state
end

function PlotService.Start()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(Keys.COLLISION_GROUP_PLAYERS)
	end)
	PhysicsService:CollisionGroupSetCollidable(Keys.COLLISION_GROUP_PLAYERS, Keys.COLLISION_GROUP_PLAYERS, false)

	local plaza = Plaza.build()
	plaza.Name = Keys.PLAZA
	plaza.Parent = Workspace

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = Keys.PLOTS_FOLDER
	local stateRoot = Instance.new("Folder")
	stateRoot.Name = Keys.PLOT_STATE_FOLDER

	for plotId = 1, Keys.PLOT_COUNT do
		buildPlot(plotId)
	end
	plotsFolder.Parent = Workspace
	for plotId = 1, Keys.PLOT_COUNT do
		plotModels[plotId].Parent = plotsFolder
		stateFolders[plotId].Parent = stateRoot
		resetState(plotId)
		refreshWorld(plotId, {})
		wireTouches(plotId)
	end
	stateRoot.Parent = ReplicatedStorage

	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt.Name == Keys.HOME_PROMPT then
			PlotService.goHome(player)
		end
	end)

	-- 낙하 귀가
	task.spawn(function()
		while true do
			task.wait(1)
			for player, plotId in plotOf do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root.Position.Y < FALL_Y and plotModels[plotId] then
					PlotService.goHome(player)
				end
			end
		end
	end)
end

--- 빈 번호 중 최소. 다 찼으면 nil(MaxPlayers 12 라 실제로는 없다)
function PlotService.assign(player: Player): number?
	if plotOf[player] then
		return plotOf[player]
	end
	local plotId: number? = nil
	for i = 1, Keys.PLOT_COUNT do
		if not owners[i] then
			plotId = i
			break
		end
	end
	if not plotId then
		warn(`[PlotService] 빈 부지가 없다: {player.Name}`)
		return nil
	end
	owners[plotId] = player
	plotOf[player] = plotId
	locked[player] = false
	player:SetAttribute(Keys.ATTR_PLOT, plotId)

	local spawn = plotModels[plotId]:FindFirstChild(Keys.SPAWN)
	if spawn and spawn:IsA("SpawnLocation") then
		player.RespawnLocation = spawn
	end
	characterConns[player] = player.CharacterAdded:Connect(function(character)
		setCollisionGroup(character)
		-- RespawnLocation 이 꺼진 SpawnLocation 을 무시해도 자기 학교에서 깨어나게
		task.defer(function()
			if character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5) then
				PlotService.goHome(player)
			end
		end)
	end)
	if player.Character then
		setCollisionGroup(player.Character)
	end

	local profile = DataService.get(player)
	if profile then
		for _, id in FacilityConfig.ORDER do
			if profile.facilities[id] then
				insertFacility(plotId, id, profile.skinsApplied[id] or 1, false)
			end
		end
		refreshWorld(plotId, profile.facilities)
	end
	PlotService.syncAttributes(player)
	if player.Character then
		PlotService.goHome(player)
	end
	return plotId
end

function PlotService.release(player: Player)
	local plotId = plotOf[player]
	if characterConns[player] then
		characterConns[player]:Disconnect()
		characterConns[player] = nil
	end
	plotOf[player] = nil
	locked[player] = nil
	if not plotId then
		return
	end
	owners[plotId] = nil
	removeFacilities(plotId)
	refreshWorld(plotId, {})
	resetState(plotId)
end

function PlotService.plotOf(player: Player): number?
	return plotOf[player]
end

function PlotService.ownerOf(plotId: number): Player?
	return owners[plotId]
end

function PlotService.cframe(plotId: number): CFrame
	return cframes[plotId]
end

function PlotService.folder(plotId: number): Model
	return plotModels[plotId]
end

function PlotService.state(plotId: number): Folder
	return stateFolders[plotId]
end

--- 프로필 → PlotState 어트리뷰트 7개 + 교문 현판
function PlotService.syncAttributes(player: Player)
	local plotId = plotOf[player]
	local profile: Types.Profile? = DataService.get(player)
	if not plotId or not profile then
		return
	end
	local folder = stateFolders[plotId]
	folder:SetAttribute(Keys.ATTR_OWNER_ID, player.UserId)
	folder:SetAttribute(Keys.ATTR_OWNER_NAME, player.DisplayName)
	folder:SetAttribute(Keys.ATTR_GRADUATIONS, profile.graduations)
	folder:SetAttribute(Keys.ATTR_FACILITIES, FacilityConfig.toCsv(profile.facilities))
	folder:SetAttribute(Keys.ATTR_SKINS, SkinConfig.toCsv(profile.skinsApplied))
	folder:SetAttribute(Keys.ATTR_STUDENTS, StudentConfig.toCsv(profile.students))
	folder:SetAttribute(Keys.ATTR_INCOME, math.floor(EconomyConfig.incomePerSecond(profile)))
	setGateSign(plotId, player.DisplayName)
end

--- 시설 모델 삽입 + 패드·실루엣·스티커 갱신. 프로필 facilities 는 호출자가 먼저 바꾼다
function PlotService.buildFacility(player: Player, facilityId: string): Model?
	local plotId = plotOf[player]
	local profile = DataService.get(player)
	if not plotId or not profile then
		return nil
	end
	local facility = insertFacility(plotId, facilityId, profile.skinsApplied[facilityId] or 1, true)
	refreshWorld(plotId, profile.facilities)
	PlotService.syncAttributes(player)
	return facility
end

--- 졸업: 시설 모델 전부 제거, 스폰 3, 실루엣. 프로필은 이미 비워져 있다
function PlotService.teardown(player: Player)
	local plotId = plotOf[player]
	local profile = DataService.get(player)
	if not plotId then
		return
	end
	removeFacilities(plotId)
	refreshWorld(plotId, if profile then profile.facilities else {})
	PlotService.syncAttributes(player)
end

--- 스킨 적용: 모델 어트리뷰트 + PlotState. 색은 클라가 칠한다
function PlotService.applySkin(player: Player, facilityId: string, skinIndex: number)
	local plotId = plotOf[player]
	if not plotId then
		return
	end
	local facility = plotModels[plotId]:FindFirstChild(facilityId)
	if facility then
		facility:SetAttribute(Keys.ATTR_SKIN, skinIndex)
	end
	PlotService.syncAttributes(player)
end

function PlotService.goHome(player: Player)
	local plotId = plotOf[player]
	local character = player.Character
	if not plotId or not character then
		return
	end
	local spawn = plotModels[plotId]:FindFirstChild(Keys.SPAWN)
	local cf = if spawn then spawn.CFrame else cframes[plotId] * CFrame.new(0, 0, 48)
	character:PivotTo(cf + Vector3.new(0, 4, 0))
end

function PlotService.lock(player: Player, isLocked: boolean)
	if plotOf[player] then
		locked[player] = isLocked
	end
end

function PlotService.isLocked(player: Player): boolean
	return locked[player] == true
end

--- 주인 캐릭터가 지금 밟고 있는 패드. 활성 패드만 센다
function PlotService.occupants(player: Player): { [string]: boolean }
	local result = {}
	local plotId = plotOf[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not plotId or not root then
		return result
	end
	local pads = plotModels[plotId]:FindFirstChild(Keys.PADS_FOLDER)
	if not pads then
		return result
	end
	for _, pad in pads:GetChildren() do
		if pad:IsA("BasePart") and pad:GetAttribute(Keys.ATTR_PAD_STATE) == "active" then
			local offset = root.Position - pad.Position
			local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if flat <= PAD_RADIUS and offset.Y >= -1 and offset.Y <= PAD_HEIGHT then
				result[pad.Name] = true
			end
		end
	end
	return result
end

--- 켜져 있는 스티커 파트 목록(스폰 수만큼). EconomyService 리스폰용
function PlotService.activeStickers(plotId: number): { BasePart }
	local list = {}
	local stickers = plotModels[plotId] and plotModels[plotId]:FindFirstChild(Keys.STICKERS_FOLDER)
	if not stickers then
		return list
	end
	for _, part in stickers:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("Enabled") then
			table.insert(list, part)
		end
	end
	return list
end

return PlotService
