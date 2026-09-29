--!nonstrict
--[[
	부지 12개 + 광장. 기획서 §7.1·§7.5·§11.4, 계획서 §3.2·§3.5.
	  - 부팅 때 Plaza 와 PlotShell 12개를 짓고 ReplicatedStorage.PlotState 폴더(어트리뷰트 8개)를 만든다.
	  - 접속 순서로 번호가 가장 작은 빈 부지를 준다. 나가면 즉시 비운다.
	  - 시설 모델은 buildPart 가 부품 단위로 넣는다(개선계획 §3.4). Geometry/<id>.build 로 전체를 임시로 짓고
	    PartIndex == k 인 파트만 실제 모델로 옮긴다. 어트리뷰트 FacilityId/Parts/BuiltAt, 마지막 부품이면 Built.
	  - 패드 상태·실루엣·스티커 스폰 수는 프로필의 facilities·buildParts 에서 파생해 refresh 한다.
	  - 스티커·별 Touched 는 여기서 받아 BindableEvent 로 넘긴다(EconomyService 가 구독). 이 모듈은 Economy 를 모른다.
	  - 서버 순간이동은 teleport 한 곳을 지나고 Teleported 를 쏜다(goHome 도 이것을 쓴다).
	  - 패드 판정은 Touched 대신 occupants() 가 주인 캐릭터의 HRP 위치로 직접 계산한다(1Hz, 활성 패드 1개뿐).
	    패드 Touched 는 W7 측정(Metrics 의 패드 체류)에만 쓴다. 주인이 자기 활성 패드에 닿으면 PadTouched 로 넘긴다.
	  - 탑(개선계획 §3.6): refreshWorld 가 Geometry/Tower 로 Tower 폴더를 강당이 있을 때만 짓는다. 층 구매 패드도
	    같은 HRP 계산(onTowerPad)이다. 엘리베이터는 PromptTriggered 에서 서버가 판정하고 teleport 한다(방문객도 탄다).
]]

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local StudentConfig = require(ReplicatedStorage.Shared.Config.StudentConfig)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local TowerConfig = require(ReplicatedStorage.Shared.Config.TowerConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlotLayout = require(ReplicatedStorage.Shared.PlotLayout)
local DecorCodec = require(ReplicatedStorage.Shared.DecorCodec)
local DataService = require(script.Parent.DataService)

local GeometryFolder = script.Parent.Parent.Geometry
local BuildKit = require(script.Parent.Parent.BuildKit)
local PlotShell = require(GeometryFolder.PlotShell)
local Plaza = require(GeometryFolder.Plaza)
local Tower = require(GeometryFolder.Tower)

local PlotService = {}

-- 기획서 §7.1 표. 부지 로컬 +Z 가 교문이고, 교문은 전부 광장(원점)을 향한다.
local LAYOUT: { { x: number, z: number, yaw: number } } = {
	{ x = -90, z = 270, yaw = 180 },
	{ x = 90, z = 270, yaw = 180 },
	{ x = 270, z = 90, yaw = -90 },
	{ x = 270, z = -90, yaw = -90 },
	{ x = 90, z = -270, yaw = 0 },
	{ x = -90, z = -270, yaw = 0 },
	{ x = -270, z = -90, yaw = 90 },
	{ x = -270, z = 90, yaw = 90 },
	{ x = -270, z = 270, yaw = 180 },
	{ x = 270, z = 270, yaw = 180 },
	{ x = 270, z = -270, yaw = 0 },
	{ x = -270, z = -270, yaw = 0 },
}

local PAD_RADIUS = 3.2 -- 패드 4×4 의 중심에서 HRP 까지 수평 거리
local PAD_HEIGHT = 6
local SILHOUETTE_TRANSPARENCY = 0.7
local FALL_Y = -50
local GATE_NAME_MAX = 8
-- 엘리베이터 판정(개선계획 §3.6 #7). 앵커 중심에서 루트까지
local ELEVATOR_REACH = 10 -- 수평
local ELEVATOR_DY = 6 -- 높이 차
local ELEVATOR_COOLDOWN = 1 -- 초, 플레이어별

local cframes: { CFrame } = {}
local plotModels: { Model } = {}
local stateFolders: { Folder } = {}
local owners: { [number]: Player } = {}
local plotOf: { [Player]: number } = {}
local locked: { [Player]: boolean } = {}
local characterConns: { [Player]: RBXScriptConnection } = {}
local stickerRngs: { [number]: Random } = {} -- 부지마다 스티커 자리 추첨용 하나
local lastRide: { [Player]: number } = {} -- 엘리베이터 쿨다운(방문객 포함)

local stickerTouched = Instance.new("BindableEvent")
local starTouched = Instance.new("BindableEvent")
local padTouched = Instance.new("BindableEvent")
local teleported = Instance.new("BindableEvent")
PlotService.StickerTouched = stickerTouched.Event -- (player: Player, part: BasePart)
PlotService.StarTouched = starTouched.Event -- (player: Player, plotId: number, part: BasePart)
PlotService.PadTouched = padTouched.Event -- (player: Player, pad: BasePart). 주인·활성 패드만
PlotService.Teleported = teleported.Event -- (player: Player). PivotTo 직후

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
	folder:SetAttribute(Keys.ATTR_STUDENTS, "")
	folder:SetAttribute(Keys.ATTR_INCOME, 0)
	folder:SetAttribute(Keys.ATTR_DECOR, "")
	folder:SetAttribute(Keys.ATTR_TOWER_FLOORS, 0)
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

--[[
	실루엣 슬롯(부지당 ≤1). 다음 시설의 아직 안 산 부품(PartIndex > buildParts)을 세운다. 같은 시설·같은 부품 수면 다시 짓지 않는다.
	14개가 다 서 있으면 같은 슬롯에 다음 층 유령(Tower.ghost)을 세운다. 층이 상한이면 비운다(§3.6 #6)
]]
local function refreshSilhouette(plotId: number, built: { [string]: boolean }, buildParts: number, towerFloors: number)
	local model = plotModels[plotId]
	local old = model:FindFirstChild(Keys.SILHOUETTE)
	local nextRow = FacilityConfig.nextOf(built)
	if not nextRow then
		local nextFloor = if built.auditorium then TowerConfig.nextFloor(towerFloors) else nil
		if old and nextFloor and old:GetAttribute(Keys.ATTR_FLOOR) == nextFloor then
			return
		end
		if old then
			old:Destroy()
		end
		if nextFloor then
			local ghost = Tower.ghost(cframes[plotId], nextFloor)
			ghost.Name = Keys.SILHOUETTE
			ghost.Parent = model
		end
		return
	end
	if old then
		local oldParts = old:GetAttribute(Keys.ATTR_PARTS)
		if nextRow and old:GetAttribute(Keys.ATTR_FACILITY_ID) == nextRow.id and type(oldParts) == "number" then
			if oldParts == buildParts then
				return
			end
			if oldParts < buildParts then
				-- 같은 시설의 부품이 늘었다. 통째로 다시 짓지 않고 산 부품만 뺀다(부품마다 전체 재복제를 피한다)
				for _, part in old:GetDescendants() do
					if part:IsA("BasePart") and (part:GetAttribute(Keys.ATTR_PART_INDEX) or 0) <= buildParts then
						part:Destroy()
					end
				end
				old:SetAttribute(Keys.ATTR_PARTS, buildParts)
				return
			end
		end
		old:Destroy()
	end
	local builder = facilityBuilder(nextRow.id)
	if not builder then
		return
	end
	local silhouette = builder.build(cframes[plotId])
	BuildKit.localizeAttachments(silhouette)
	silhouette.Name = Keys.SILHOUETTE
	silhouette:SetAttribute(Keys.ATTR_FACILITY_ID, nextRow.id)
	silhouette:SetAttribute(Keys.ATTR_PARTS, buildParts)
	-- 이미 산 부품은 실제 모델에 있다. 겹치지 않게 뺀다
	for _, part in silhouette:GetDescendants() do
		if part:IsA("BasePart") and (part:GetAttribute(Keys.ATTR_PART_INDEX) or 0) <= buildParts then
			part:Destroy()
		end
	end
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

--- 2층 「공사 중」 실루엣: 강당 부품이 하나라도 들어가면 숨긴다(부품 1 이 바닥+벽이라 공사판과 겹친다)
local function refreshConstruction(plotId: number, built: { [string]: boolean }, buildParts: number)
	local shell = plotModels[plotId]:FindFirstChild(Keys.SHELL)
	local construction = shell and shell:FindFirstChild(Keys.CONSTRUCTION)
	if not construction then
		return
	end
	local nextRow = FacilityConfig.nextOf(built)
	local hidden = built.auditorium == true or (nextRow ~= nil and nextRow.id == "auditorium" and buildParts >= 1)
	for _, part in construction:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = if hidden then 1 else SILHOUETTE_TRANSPARENCY
		elseif part:IsA("SurfaceGui") or part:IsA("BillboardGui") then
			part.Enabled = not hidden
		end
	end
end

--- 부지 로컬 수평 자리의 바닥 윗면 y. 시설(복도·운동장)의 부품이 하나라도 들어간 발자국 안이면 그 구역 floorY, 아니면 마당 0.
--- 바닥은 부품 1 에 있다(Geometry 규약). 구역 floorY 는 시설이 있을 때 값이라 안 지은 시설 자리는 0 이다.
--- 홈 자리(복도 2·운동장 3)도 같은 규칙
local function floorYAt(plotId: number, spot: Vector2): number
	local model = plotModels[plotId]
	for _, zone in PlotLayout.STICKER_ZONES do
		local facilityId = zone.facilityId
		local row = facilityId and FacilityConfig.BY_ID[facilityId]
		local facility = facilityId and model:FindFirstChild(facilityId)
		if row and facility and (facility:GetAttribute(Keys.ATTR_PARTS) or 0) >= 1 then
			local c, size = row.center, row.size
			if math.abs(spot.X - c.X) <= size.X / 2 and math.abs(spot.Y - c.Z) <= size.Z / 2 then
				return zone.floorY
			end
		end
	end
	return 0
end

--- 히트박스를 부지 로컬 자리 spot 의 바닥에 붙인다(아랫면 = 바닥 윗면). 같은 자리면 쓰지 않는다(복제 줄이기)
local function placeSticker(plotId: number, part: BasePart, spot: Vector2)
	local cf = cframes[plotId] * CFrame.new(spot.X, floorYAt(plotId, spot) + part.Size.Y / 2, spot.Y)
	if (part.Position - cf.Position).Magnitude > 1e-3 then
		part.CFrame = cf
	end
end

local function localXZ(plotId: number, world: Vector3): Vector2
	local p = cframes[plotId]:PointToObjectSpace(world)
	return Vector2.new(p.X, p.Z)
end

--[[
	스티커 히트박스를 옮긴다(개선계획 §3.2 #4·#5). Position 만 바꾸고 어트리뷰트는 건드리지 않는다.
	  toHome = true  → StickerId 의 홈 자리(PlotLayout.HOME_SPOTS)
	  toHome = false → PlotLayout.pickStickerSpot. prev = 지금 자리, ownerPos = 주인 HRP 수평 위치,
	                   occupied = 같은 부지의 다른 켜진·안 주운 스티커 자리(전부 부지 로컬)
	높이는 pickStickerSpot 이 돌려준 구역 floorY 대신 floorYAt 으로 정한다(안 지은 시설 자리는 0).
	리스폰 때 호출자는 이 함수 다음에 Collected=false 를 쓴다(자리와 등장이 같은 프레임에 복제되게).
]]
function PlotService.moveSticker(plotId: number, part: BasePart, toHome: boolean)
	if toHome then
		local id = part:GetAttribute(Keys.ATTR_STICKER_ID)
		local spot = if type(id) == "number" then PlotLayout.HOME_SPOTS[id] else nil
		if spot then
			placeSticker(plotId, part, spot)
		end
		return
	end
	local rng = stickerRngs[plotId]
	if not rng then
		rng = Random.new()
		stickerRngs[plotId] = rng
	end
	local owner = owners[plotId]
	local root = owner and owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
	local ownerPos = if root and root:IsA("BasePart") then localXZ(plotId, root.Position) else nil
	local occupied = {}
	for _, other in PlotService.activeStickers(plotId) do
		if other ~= part and not other:GetAttribute(Keys.ATTR_COLLECTED) then
			table.insert(occupied, localXZ(plotId, other.Position))
		end
	end
	local spot = PlotLayout.pickStickerSpot(rng, localXZ(plotId, part.Position), ownerPos, occupied)
	placeSticker(plotId, part, spot)
end

--- 스폰 수(3 → 5 → 8)만큼만 스티커를 켠다. 새로 열리는 스폰은 즉시 보인다.
--- 켜기·끄기 때는 홈 자리로 돌린다. 나머지는 수평 자리를 두고 높이만 바닥에 맞춘다(시설이 서거나 없어지면 바닥이 바뀐다)
local function refreshStickers(plotId: number, built: { [string]: boolean }, buildParts: number)
	local stickers = plotModels[plotId]:FindFirstChild(Keys.STICKERS_FOLDER)
	if not stickers then
		return
	end
	local count = EconomyConfig.spawnCount(built, buildParts)
	for _, part in stickers:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		local index = part:GetAttribute(Keys.ATTR_STICKER_ID) or 0
		local enabled = index <= count
		if part:GetAttribute("Enabled") ~= enabled then
			PlotService.moveSticker(plotId, part, true) -- 자리 먼저, 어트리뷰트는 그다음
			part:SetAttribute("Enabled", enabled)
			part:SetAttribute(Keys.ATTR_COLLECTED, not enabled)
			part:SetAttribute(Keys.ATTR_GOLD, false)
			part.CanTouch = enabled
		else
			placeSticker(plotId, part, localXZ(plotId, part.Position))
		end
	end
end

local function refreshWorld(plotId: number, built: { [string]: boolean }, buildParts: number, towerFloors: number)
	refreshPads(plotId, built)
	refreshSilhouette(plotId, built, buildParts, towerFloors)
	refreshConstruction(plotId, built, buildParts)
	refreshStickers(plotId, built, buildParts)
	Tower.refresh(plotModels[plotId], cframes[plotId], towerFloors, built.auditorium == true)
end

--[[
	시설 facilityId 의 부품 first..last 를 부지에 넣는다. 구매는 first == last == k, 복원은 1..n.
	Geometry 로 전체 모델을 임시로 짓고(Workspace 밖) PartIndex 가 범위 안인 BasePart 만 실제 모델로 옮긴 뒤 임시 모델은 버린다.
	Geometry 규약상 BasePart 는 전부 모델의 직계 자식이다.
	first == 1 이면 실제 모델을 새로 만든다(같은 이름 모델은 버린다): 피벗·Seats·Door·그 밖의 BasePart 아닌 자식·어트리뷰트를 옮긴다.
	Parts = last, 마지막 부품까지 들어가면 Built = true(클라 완공 연출 트리거).
]]
local function insertParts(plotId: number, facilityId: string, first: number, last: number, fresh: boolean): Model?
	local builder = facilityBuilder(facilityId)
	if not builder then
		return nil
	end
	local model = plotModels[plotId]
	local facility = model:FindFirstChild(facilityId)
	if first > 1 and not facility then
		first = 1 -- 앞 부품이 없으면(있을 수 없지만) 처음부터 다시 넣는다
	end
	local temp = builder.build(cframes[plotId])
	BuildKit.localizeAttachments(temp)

	local isNew = first == 1
	if isNew then
		if facility then
			facility:Destroy()
		end
		facility = Instance.new("Model")
		facility.Name = facilityId
	end
	for _, child in temp:GetChildren() do
		local index = child:GetAttribute(Keys.ATTR_PART_INDEX)
		if child:IsA("BasePart") and index and index >= first and index <= last then
			child.Parent = facility
		end
	end
	if isNew then
		-- 파트를 먼저 옮기고 피벗을 쓴다. 빈 모델에 첫 파트가 들어올 때 피벗이 다시 잡히지 않게.
		-- Attachment 는 localizeAttachments 가 이 피벗 기준 로컬로 바꿔 두었다
		facility.WorldPivot = temp.WorldPivot
		for _, child in temp:GetChildren() do
			if not child:IsA("BasePart") then
				child.Parent = facility
			end
		end
		for name, value in temp:GetAttributes() do
			facility:SetAttribute(name, value)
		end
		facility:SetAttribute(Keys.ATTR_FACILITY_ID, facilityId)
		if fresh then
			facility:SetAttribute("BuiltAt", Workspace:GetServerTimeNow())
		end
	end
	temp:Destroy()

	facility:SetAttribute(Keys.ATTR_PARTS, last)
	if last >= FacilityConfig.partCount(facilityId) then
		facility:SetAttribute(Keys.ATTR_BUILT, true)
	end
	facility.Parent = model
	return facility
end

local function removeFacilities(plotId: number)
	local model = plotModels[plotId]
	for _, child in model:GetChildren() do
		if child:IsA("Model") and FacilityConfig.BY_ID[child.Name] and child:GetAttribute(Keys.ATTR_FACILITY_ID) then
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
	elseif part:HasTag(Keys.PAD_TAG) then
		if owners[plotId] == player and part:GetAttribute(Keys.ATTR_PAD_STATE) == "active" then
			padTouched:Fire(player, part)
		end
	end
end

local function wireTouches(plotId: number)
	local model = plotModels[plotId]
	for _, folderName in { Keys.STICKERS_FOLDER, Keys.STARS_FOLDER, Keys.PADS_FOLDER } do
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
	local gate = cf:PointToWorldSpace(Vector3.new(0, 0, 75))
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

--[[
	엘리베이터(§3.6 #7). 프롬프트는 클라가 누르지만 판정은 서버가 한다. 실패는 조용히 무시한다(위반 아님).
	앵커(부지 Tower 폴더의 ElevatorNN) 근처(수평 ≤ ELEVATOR_REACH, |dy| ≤ ELEVATOR_DY)에 있어야 하고,
	목표 층은 앵커 층 ±1 이며 2 ≤ 목표 ≤ 2 + 그 부지 주인의 towerFloors. 방문객도 탄다. 플레이어별 1초 쿨다운.
	연출·소리는 탄 사람에게만 가는 ElevatorRide 로만(§7.5)
]]
local function rideElevator(prompt: ProximityPrompt, player: Player): boolean
	-- 졸업식 잠금 중(주인)이면 타지 않는다. 졸업식 카메라와 겹치고 finish 의 대피가 어차피 내린다
	if locked[player] then
		return false
	end
	-- 프롬프트는 앵커 안 Attachment 에 달려 있다(Tower makePrompt)
	local holder = prompt.Parent
	local anchor = if holder and holder:IsA("Attachment") then holder.Parent else holder
	if not anchor or not anchor:IsA("BasePart") then
		return false
	end
	local from = anchor:GetAttribute(Keys.ATTR_FLOOR)
	local folder = anchor.Parent
	if typeof(from) ~= "number" or not folder or folder.Name ~= Keys.TOWER_FOLDER then
		return false
	end
	local plotId = plotIdOfPart(anchor)
	local owner = plotId and owners[plotId]
	local profile = owner and DataService.get(owner)
	if not plotId or not profile then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local d = root.Position - anchor.Position
	if Vector3.new(d.X, 0, d.Z).Magnitude > ELEVATOR_REACH or math.abs(d.Y) > ELEVATOR_DY then
		return false
	end
	local target = if prompt.Name == Keys.ELEVATOR_UP then from + 1 else from - 1
	if target < 2 or target > 2 + profile.towerFloors then
		return false
	end
	if not folder:FindFirstChild(string.format("Elevator%02d", target)) then
		return false
	end
	local now = os.clock()
	if lastRide[player] and now - lastRide[player] < ELEVATOR_COOLDOWN then
		return false
	end
	lastRide[player] = now
	PlotService.teleport(player, Tower.arrival(cframes[plotId], target), false)
	Remotes.event(player, "ElevatorRide", { plot = plotId, floor = target })
	return true
end

--- 엘리베이터 판정. DevCheat.RideElevator 가 프롬프트 없이 부른다(Studio 게이트). 통과해 옮겼으면 true
PlotService.rideElevator = rideElevator

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
		refreshWorld(plotId, {}, 0, 0)
		wireTouches(plotId)
	end
	stateRoot.Parent = ReplicatedStorage

	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt.Name == Keys.HOME_PROMPT then
			PlotService.goHome(player)
		elseif prompt.Name == Keys.ELEVATOR_UP or prompt.Name == Keys.ELEVATOR_DOWN then
			rideElevator(prompt, player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRide[player] = nil
	end)

	-- 낙하 귀가
	task.spawn(function()
		while true do
			task.wait(1)
			for player, plotId in plotOf do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root.Position.Y < FALL_Y and plotModels[plotId] then
					task.spawn(PlotService.goHome, player) -- goHome 은 스트리밍을 기다린다. 이 루프를 멈추지 않게
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
		-- 완공 시설은 부품 전부, 짓다 만 다음 시설은 산 부품까지
		for _, id in FacilityConfig.ORDER do
			if profile.facilities[id] then
				insertParts(plotId, id, 1, FacilityConfig.partCount(id), false)
			end
		end
		local nextPart = FacilityConfig.nextPartOf(profile.facilities, profile.buildParts)
		if nextPart and profile.buildParts > 0 then
			insertParts(plotId, nextPart.facility.id, 1, profile.buildParts, false)
		end
		refreshWorld(plotId, profile.facilities, profile.buildParts, profile.towerFloors)
	end
	PlotService.syncAttributes(player)
	if player.Character then
		task.spawn(PlotService.goHome, player) -- 첫 ProfileSync 가 늦어지지 않게 기다리지 않는다
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
	-- 탑이 사라지기 전에 3층 이상에 있는 사람(방문객)을 스폰으로 내린다. 졸업(finish)과 같은 대피(§3.6 #11)
	PlotService.evacuate(plotId)
	owners[plotId] = nil
	removeFacilities(plotId)
	-- 이전 주인이 주운 스티커는 respawnSticker 가 주인이 바뀌어 다시 켜지 않는다. 전부 새로 켜게 Enabled 를 지운다
	local stickers = plotModels[plotId]:FindFirstChild(Keys.STICKERS_FOLDER)
	if stickers then
		for _, part in stickers:GetChildren() do
			part:SetAttribute("Enabled", nil)
		end
	end
	refreshWorld(plotId, {}, 0, 0)
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

--- 프로필 → PlotState 어트리뷰트 8개 + 교문 현판. 꾸미기(Decor)는 졸업과 상관없어 DecorService 가 잠금 중에도 따로 쓴다
function PlotService.syncAttributes(player: Player)
	local plotId = plotOf[player]
	local profile: Types.Profile? = DataService.get(player)
	if not plotId or not profile then
		return
	end
	-- 졸업 잠금 동안은 그대로 둔다. 클라 졸업식이 지금 학생으로 강당을 채우기 때문이다.
	-- 8.0초 철거(GraduationService.finish)가 잠금을 푼 뒤 한 번에 바꾼다(§6.1)
	if locked[player] then
		return
	end
	local folder = stateFolders[plotId]
	folder:SetAttribute(Keys.ATTR_OWNER_ID, player.UserId)
	folder:SetAttribute(Keys.ATTR_OWNER_NAME, player.DisplayName)
	folder:SetAttribute(Keys.ATTR_GRADUATIONS, profile.graduations)
	folder:SetAttribute(Keys.ATTR_FACILITIES, FacilityConfig.toCsv(profile.facilities))
	folder:SetAttribute(Keys.ATTR_STUDENTS, StudentConfig.toCsv(profile.students))
	folder:SetAttribute(Keys.ATTR_INCOME, math.floor(EconomyConfig.incomePerSecond(profile)))
	folder:SetAttribute(Keys.ATTR_DECOR, DecorCodec.encode(profile.decorPlaced))
	folder:SetAttribute(Keys.ATTR_TOWER_FLOORS, profile.towerFloors)
	setGateSign(plotId, player.DisplayName)
end

--- 부품 k 삽입 + 패드·실루엣·스티커 갱신. 프로필 facilities·buildParts 는 호출자가 먼저 바꾼다
function PlotService.buildPart(player: Player, facilityId: string, k: number): Model?
	local plotId = plotOf[player]
	local profile = DataService.get(player)
	if not plotId or not profile then
		return nil
	end
	local facility = insertParts(plotId, facilityId, k, k, true)
	refreshWorld(plotId, profile.facilities, profile.buildParts, profile.towerFloors)
	PlotService.syncAttributes(player)
	return facility
end

--- 프로필(facilities·buildParts·towerFloors) 그대로 패드·실루엣·스티커·탑을 다시 맞춘다. 층 구매·DevCheat 용
function PlotService.refreshWorld(player: Player)
	local plotId = plotOf[player]
	local profile = DataService.get(player)
	if not plotId or not profile then
		return
	end
	refreshWorld(plotId, profile.facilities, profile.buildParts, profile.towerFloors)
	PlotService.syncAttributes(player)
end

--- 졸업: 시설 모델 전부 제거, 스폰 0(책상 첫 부품을 다시 사면 3), 실루엣. 프로필(facilities·buildParts)은 이미 비워져 있다
function PlotService.teardown(player: Player)
	local plotId = plotOf[player]
	local profile = DataService.get(player)
	if not plotId then
		return
	end
	removeFacilities(plotId)
	-- 강당이 없어져 Tower 폴더도 비운다. towerFloors 는 남아 강당을 다시 지으면 층이 돌아온다(질문 13)
	if profile then
		refreshWorld(plotId, profile.facilities, profile.buildParts, profile.towerFloors)
	else
		refreshWorld(plotId, {}, 0, 0)
	end
	PlotService.syncAttributes(player)
end

--- 자기 부지 스폰으로 옮긴다. 도착지 스트리밍을 기다리므로 멈춘다(호출자가 멈추면 안 되면 task.spawn)
function PlotService.goHome(player: Player)
	local plotId = plotOf[player]
	local character = player.Character
	if not plotId or not character then
		return
	end
	local spawn = plotModels[plotId]:FindFirstChild(Keys.SPAWN)
	local cf = if spawn then spawn.CFrame else cframes[plotId] * CFrame.new(0, 0, 60)
	PlotService.teleport(player, cf)
end

--[[
	서버 순간이동 공통 경로(개선계획 §3.6 #1). cf 위 4스터드로 옮기고 Teleported 를 쏜다.
	waitStream 이 false 가 아니면 도착지 스트리밍을 기다리므로 멈춘다(호출자가 멈추면 안 되면 task.spawn).
	false 면 기다리지 않고 바로 옮긴다(졸업 대피처럼 즉시 옮겨야 할 때).
]]
function PlotService.teleport(player: Player, cf: CFrame, waitStream: boolean?)
	local character = player.Character
	if not character then
		return
	end
	if waitStream ~= false then
		-- 멀리서 순간이동하면 바닥이 아직 안 내려와 떨어질 수 있다. 도착지 주변을 먼저 받게 한다(실패해도 이동은 한다)
		pcall(player.RequestStreamAroundAsync, player, cf.Position)
		if player.Character ~= character or not character.Parent then
			return -- 기다리는 동안 리스폰·퇴장
		end
	end
	character:PivotTo(cf + Vector3.new(0, 4, 0))
	teleported:Fire(player)
end

function PlotService.lock(player: Player, isLocked: boolean)
	if plotOf[player] then
		locked[player] = isLocked
	end
end

function PlotService.isLocked(player: Player): boolean
	return locked[player] == true
end

--- HRP 가 패드 위에 있나(수평 PAD_RADIUS, 높이 -1 ~ PAD_HEIGHT)
local function isOver(root: BasePart, pad: BasePart): boolean
	local offset = root.Position - pad.Position
	local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
	return flat <= PAD_RADIUS and offset.Y >= -1 and offset.Y <= PAD_HEIGHT
end

--- 주인 캐릭터가 자기 부지 TOWER_PAD 위에 있나(occupants 와 같은 isOver 기준). 패드는 강당이 있을 때만 있다
function PlotService.onTowerPad(player: Player): boolean
	local plotId = plotOf[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not plotId or not root then
		return false
	end
	local tower = plotModels[plotId]:FindFirstChild(Keys.TOWER_FOLDER)
	local pad = tower and tower:FindFirstChild(Keys.TOWER_PAD)
	return pad ~= nil and pad:IsA("BasePart") and isOver(root, pad)
end

--[[
	졸업 대피(§3.6 #11). 이 부지 범위 안에서 루트 Y 가 TowerConfig.EVACUATE_Y 를 넘는 사람(주인·방문객)을
	이 부지 스폰으로 바로 옮긴다. 스트리밍을 기다리지 않아 멈추지 않는다(teardown 전에 동기로 부른다).
	teleport 를 지나므로 Teleported 가 스티커 과속 기준점을 지운다
]]
function PlotService.evacuate(plotId: number)
	local cf = cframes[plotId]
	local model = plotModels[plotId]
	if not cf or not model then
		return
	end
	local spawn = model:FindFirstChild(Keys.SPAWN)
	local target = if spawn and spawn:IsA("BasePart") then spawn.CFrame else cf * CFrame.new(PlotLayout.SPAWN)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local p = cf:PointToObjectSpace(root.Position)
			local half = PlotLayout.PLOT_HALF
			if math.abs(p.X) <= half and math.abs(p.Z) <= half and p.Y > TowerConfig.EVACUATE_Y then
				PlotService.teleport(player, target, false)
			end
		end
	end
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
		if pad:IsA("BasePart") and pad:GetAttribute(Keys.ATTR_PAD_STATE) == "active" and isOver(root, pad) then
			result[pad.Name] = true
		end
	end
	return result
end

--- 이 패드가 아직 활성이고 캐릭터가 그 위에 있나. occupants 와 같은 기준으로 패드 1개만 본다(Metrics 용)
function PlotService.standsOn(player: Player, pad: BasePart): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and pad:GetAttribute(Keys.ATTR_PAD_STATE) == "active" and isOver(root, pad)
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
