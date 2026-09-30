--!strict
--[[
	InteriorRenderController — 방 안 작은 소품(클라이언트 전용). 기획서 §12.1 「방 안 소품」.

	서버 시설 파트는 예산(시설 ≤25) 때문에 더 늘릴 수 없다. 방이 비어 보이지 않게 화분·게시판·현미경 같은
	작은 소품을 클라가 로컬 파트로 그린다. 판정·충돌이 없는 장식이라 서버가 알 필요가 없다.
	  · Workspace.InteriorFx/PlotNN 아래에 그린다. 부지 로컬 → 월드는 Plots.PlotNN 피벗.
	  · 교실 1(Shell)은 늘, 시설 소품은 그 시설이 지어진 부지에서만(PlotState Facilities CSV).
	  · LOD: 내 부지 + 가까운 부지로 모두 DecorConfig.NEAR_COUNT 개(DecorController 와 같은 규칙).
	  · 방 하나에 MAX_PARTS_PER_ROOM 개 이하. 전부 Anchored·충돌·쿼리·그림자 없음.
	  · 그림 id(PropAssets.INTERIOR)가 0 이면 그림만 빠지고 파트는 그대로.
	시설이 새로 지어지면 등장 연출이 끝난 뒤(APPEAR_DELAY) 그린다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local PlotLayout = require(ReplicatedStorage.Shared.PlotLayout)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)
local DecorConfig = require(ReplicatedStorage.Shared.Config.DecorConfig)

local InteriorRenderController = {}

local LOD_INTERVAL = 1
local APPEAR_DELAY = 1.2 -- 시설 등장 연출(부품이 솟아오름)이 끝난 뒤 소품이 보이게
local MAX_PARTS_PER_ROOM = 15
local ROOM_FLOOR_T = 0.2 -- 과학실 등 방 바닥 판 두께(Geometry FLOOR_T 와 같다)

local C = {
	pot = Color3.fromRGB(196, 120, 84),
	leaf = Color3.fromRGB(96, 170, 96),
	bin = Color3.fromRGB(110, 150, 196),
	ball = Color3.fromRGB(232, 140, 60),
	bookA = Color3.fromRGB(90, 130, 200),
	bookB = Color3.fromRGB(240, 200, 90),
	bookC = Color3.fromRGB(120, 180, 120),
	wood = Color3.fromRGB(176, 130, 86),
	cork = Color3.fromRGB(198, 154, 104),
	white = Color3.fromRGB(240, 240, 236),
	steel = Color3.fromRGB(190, 192, 198),
	dark = Color3.fromRGB(60, 62, 68),
	glass = Color3.fromRGB(210, 230, 240),
	tubeA = Color3.fromRGB(120, 200, 240),
	tubeB = Color3.fromRGB(250, 210, 90),
	tubeC = Color3.fromRGB(150, 220, 130),
	extinguisher = Color3.fromRGB(214, 70, 60),
	pianoDark = Color3.fromRGB(60, 36, 20),
	pianoKey = Color3.fromRGB(28, 28, 32),
	gold = Color3.fromRGB(214, 176, 90),
}

-- 소품 하나를 그리는 함수. pos = 부지 로컬 중심, rot = 부지 로컬 회전
type Put = (name: string, size: Vector3, pos: Vector3, color: Color3, opts: PutOpts?) -> Part
type PutOpts = {
	material: Enum.Material?,
	shape: Enum.PartType?,
	rot: CFrame?,
	transparency: number?,
}
type Recipe = (put: Put) -> ()

-- ── 방별 소품 ─────────────────────────────────────────────────────

--- 화분(몸통 원기둥 + 잎 구 둘). 파트 3
local function plant(put: Put, name: string, x: number, y: number, z: number, scale: number)
	local potH = 1.2 * scale
	put(name .. "Pot", Vector3.new(potH, 1.1 * scale, 1.1 * scale), Vector3.new(x, y + potH / 2, z), C.pot, {
		shape = Enum.PartType.Cylinder,
		rot = CFrame.Angles(0, 0, math.pi / 2),
	})
	put(name .. "Leaf", Vector3.one * 1.6 * scale, Vector3.new(x, y + potH + 0.6 * scale, z), C.leaf, {
		shape = Enum.PartType.Ball,
		material = Enum.Material.Grass,
	})
	put(
		name .. "Leaf2",
		Vector3.one * 1.1 * scale,
		Vector3.new(x + 0.4 * scale, y + potH + 1.3 * scale, z - 0.2 * scale),
		C.leaf,
		{
			shape = Enum.PartType.Ball,
			material = Enum.Material.Grass,
		}
	)
end

-- 교실 1(Shell, 늘 있다). 방 x −75..−45, z −62.5..−32.5, 바닥 y 0. 벽 두께 1
local function class1(put: Put)
	local cx, cz = PlotLayout.CLASS1.X, PlotLayout.CLASS1.Z
	local hx, hz = PlotLayout.CLASS1_SIZE.X / 2, PlotLayout.CLASS1_SIZE.Z / 2
	local westIn, southIn = cx - hx + 1, cz + hz - 1

	-- 서쪽 벽 게시판(그림 한 장 = 코르크·테두리·그림). 방 쪽 면 = 로컬 +X(Right)
	local board = put("Bulletin", Vector3.new(0.15, 4.8, 8), Vector3.new(westIn + 0.075, 7, cz), C.cork)
	local id = PropAssets.INTERIOR.BULLETIN
	if id ~= 0 then
		local d = Instance.new("Decal")
		d.Face = Enum.NormalId.Right
		d.Texture = "rbxassetid://" .. id
		d.Parent = board
	end

	-- 뒤쪽(남) 구석 화분, 문 옆 휴지통, 동남 구석 낮은 책꽂이
	plant(put, "Plant", westIn + 1.5, 0, southIn - 1.5, 1)
	put("Bin", Vector3.new(1.4, 1.1, 1.1), Vector3.new(cx - 7, 0.7, southIn - 0.8), C.bin, {
		shape = Enum.PartType.Cylinder,
		rot = CFrame.Angles(0, 0, math.pi / 2),
	})
	local shelf = put("LowShelf", Vector3.new(5, 3, 1.2), Vector3.new(cx + 8, 1.5, southIn - 0.6), C.wood, {
		material = Enum.Material.Wood,
	})
	local books = PropAssets.BOOKSHELF_TEXTURE
	if books.id ~= 0 then
		local t = Instance.new("Texture")
		t.Face = Enum.NormalId.Front -- 로컬 −Z = 방 쪽
		t.Texture = "rbxassetid://" .. books.id
		t.StudsPerTileU = 5 / math.max(1, math.round(5 / (3 * 0.4))) -- 그림 비율 0.4 × 높이 3, 양 끝에서 책이 안 잘리게
		t.StudsPerTileV = 3
		t.Parent = shelf
	end
	plant(put, "ShelfPlant", cx + 9.5, 3, southIn - 0.6, 0.6)
end

-- 사물함 위: 공·책 더미·작은 화분. 몸통 윗면 = 높이 + 위 마감
local function locker(put: Put)
	local row = FacilityConfig.BY_ID.locker
	local topY = row.center.Y + row.size.Y + 0.3
	local x = row.center.X - row.size.X / 2
	local z0 = row.center.Z
	put("Ball", Vector3.one * 1.3, Vector3.new(x, topY + 0.65, z0 - 4), C.ball, { shape = Enum.PartType.Ball })
	put("BookA", Vector3.new(1.1, 0.25, 1.5), Vector3.new(x, topY + 0.125, z0), C.bookA)
	put("BookB", Vector3.new(1, 0.25, 1.4), Vector3.new(x, topY + 0.375, z0), C.bookB, {
		rot = CFrame.Angles(0, 0.2, 0),
	})
	put("BookC", Vector3.new(1.05, 0.25, 1.3), Vector3.new(x, topY + 0.625, z0), C.bookC, {
		rot = CFrame.Angles(0, -0.15, 0),
	})
	plant(put, "Plant", x, topY, z0 + 4, 0.6)
end

-- 과학실: 실험대 위 현미경·시험관 꽂이, 문 옆 소화기
local function science(put: Put)
	local row = FacilityConfig.BY_ID.science
	local cx, cz = row.center.X, row.center.Z
	local floorTop = row.center.Y + ROOM_FLOOR_T
	local topY = floorTop + CharacterBuilder.SIT_DESK
	local benchZ = cz - 2

	-- 현미경(동쪽 실험대, 비커 반대편). 받침·기둥·경통
	local mx, mz = cx + 4.5, benchZ - 0.4
	put("ScopeBase", Vector3.new(0.9, 0.2, 0.7), Vector3.new(mx, topY + 0.1, mz), C.dark)
	put("ScopeArm", Vector3.new(0.2, 1.2, 0.25), Vector3.new(mx, topY + 0.8, mz + 0.2), C.dark)
	put("ScopeTube", Vector3.new(0.9, 0.3, 0.3), Vector3.new(mx, topY + 1.1, mz - 0.05), C.white, {
		shape = Enum.PartType.Cylinder,
		rot = CFrame.Angles(0, 0, math.pi / 2 - 0.35),
	})

	-- 시험관 꽂이(서쪽 실험대, 플라스크 반대편). 받침 + 색 물 시험관 셋
	local rx, rz = cx - 4.5, benchZ - 0.4
	put(
		"Rack",
		Vector3.new(1.6, 0.35, 0.5),
		Vector3.new(rx, topY + 0.175, rz),
		C.wood,
		{ material = Enum.Material.Wood }
	)
	for i, color in { C.tubeA, C.tubeB, C.tubeC } do
		put("Tube" .. i, Vector3.new(0.9, 0.22, 0.22), Vector3.new(rx - 0.8 + i * 0.4, topY + 0.5, rz), color, {
			shape = Enum.PartType.Cylinder,
			rot = CFrame.Angles(0, 0, math.pi / 2),
			material = Enum.Material.Glass,
			transparency = 0.2,
		})
	end

	-- 소화기: 북문 동쪽 벽 옆. 몸통 + 손잡이
	local fx, fz = cx + 6, cz - row.size.Z / 2 + 1.6
	put("Extinguisher", Vector3.new(1.6, 0.7, 0.7), Vector3.new(fx, floorTop + 0.8, fz), C.extinguisher, {
		shape = Enum.PartType.Cylinder,
		rot = CFrame.Angles(0, 0, math.pi / 2),
	})
	put("ExtinguisherTop", Vector3.new(0.3, 0.35, 0.5), Vector3.new(fx, floorTop + 1.75, fz), C.dark)
end

-- 음악실: 업라이트 피아노 디테일. 서버는 몸통(6×4.6×2)·흰 건반 판(줄 SurfaceGui)만 짓는다(Geometry/music.luau).
-- 뚜껑·양옆 볼·건반 뚜껑·악보대·악보·페달 2·검은 건반 7 = 파트 15
local function music(put: Put)
	local row = FacilityConfig.BY_ID.music
	local floorTop = row.center.Y + ROOM_FLOOR_T
	local px, pz = row.center.X - 6, row.center.Z - 3.5 -- 몸통 중심. 앞면(건반 쪽) = pz + 1
	local front = pz + 1
	local keyTop = floorTop + 2.75

	put("PianoLid", Vector3.new(6.3, 0.25, 2.3), Vector3.new(px, floorTop + 4.72, pz + 0.05), C.pianoDark, {
		material = Enum.Material.Wood,
	})
	for i, side in { -1, 1 } do
		put(
			"PianoCheek" .. i,
			Vector3.new(0.3, 2.95, 1.25),
			Vector3.new(px + side * 2.95, floorTop + 1.475, front + 0.625),
			C.pianoDark,
			{ material = Enum.Material.Wood }
		)
	end
	put("PianoFallboard", Vector3.new(5.6, 0.45, 0.22), Vector3.new(px, keyTop + 0.225, front + 0.11), C.pianoDark, {
		material = Enum.Material.Wood,
	})
	-- 악보대: 건반 뚜껑 위, 몸통 쪽으로 살짝 기댄다
	local tilt = CFrame.Angles(-0.15, 0, 0)
	put("PianoMusicRest", Vector3.new(3.2, 0.9, 0.12), Vector3.new(px, keyTop + 1.0, front + 0.12), C.pianoDark, {
		material = Enum.Material.Wood,
		rot = tilt,
	})
	put("PianoSheet", Vector3.new(1.5, 0.8, 0.04), Vector3.new(px, keyTop + 1.02, front + 0.2), C.white, { rot = tilt })
	for i, side in { -1, 1 } do
		put(
			"PianoPedal" .. i,
			Vector3.new(0.22, 0.12, 0.6),
			Vector3.new(px + side * 0.35, floorTop + 0.3, front + 0.3),
			C.gold,
			{
				material = Enum.Material.Metal,
			}
		)
	end
	-- 검은 건반: 흰 건반 10개(도레미파솔라시도레미) 사이 도#·레#·파#·솔#·라#·도#·레#
	local white = 5.6 / 10
	for i, gap in { 1, 2, 4, 5, 6, 8, 9 } do
		put(
			"PianoBlackKey" .. i,
			Vector3.new(0.3, 0.16, 0.7),
			Vector3.new(px - 2.8 + gap * white, keyTop + 0.08, front + 0.57),
			C.pianoKey
		)
	end
end

-- 시설 id → 소품. SHELL 은 늘 그린다
local SHELL: { [string]: Recipe } = { class1 = class1 }
local RECIPES: { [string]: Recipe } = {
	locker = locker,
	science = science,
	music = music,
}

-- ── 렌더 ─────────────────────────────────────────────────────────

local player = Players.LocalPlayer
local started = false
local fxRoot: Folder? = nil
local plotsFolder: Instance? = nil
local stateRoot: Instance? = nil
local pivots: { [number]: CFrame } = {}
local near: { [number]: boolean } = {}
local rendered: { [number]: Folder } = {}
local watchedStates: { [Instance]: boolean } = {}

local function readMyPlot(): number?
	local value = player:GetAttribute(Keys.ATTR_PLOT)
	return if type(value) == "number" then value else nil
end

--- 부지 CFrame(PlotShell 이 WorldPivot 으로 둔다. 부지는 움직이지 않아 한 번만 읽는다)
local function plotPivot(plotId: number): CFrame?
	local known = pivots[plotId]
	if known then
		return known
	end
	local folder = plotsFolder
	local model = if folder then folder:FindFirstChild(Keys.plotName(plotId)) else nil
	if not (model and model:IsA("Model")) then
		return nil
	end
	local pivot = model:GetPivot()
	pivots[plotId] = pivot
	return pivot
end

local function builtOf(plotId: number): { [string]: boolean }
	local folder = stateRoot
	local state = if folder then folder:FindFirstChild(Keys.plotName(plotId)) else nil
	local csv = if state then state:GetAttribute(Keys.ATTR_FACILITIES) else nil
	return if type(csv) == "string" then FacilityConfig.fromCsv(csv) :: any else {}
end

local function drawRoom(parent: Folder, pivot: CFrame, id: string, recipe: Recipe)
	local room = Instance.new("Folder")
	room.Name = id
	local count = 0
	local function put(name: string, size: Vector3, pos: Vector3, color: Color3, opts: PutOpts?): Part
		count += 1
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = if opts and opts.shape then opts.shape else Enum.PartType.Block
		p.Size = size
		local rot = if opts and opts.rot then opts.rot else CFrame.identity
		p.CFrame = pivot * CFrame.new(pos) * rot
		p.Color = color
		p.Material = if opts and opts.material then opts.material else Enum.Material.SmoothPlastic
		p.Transparency = if opts and opts.transparency then opts.transparency else 0
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = room
		return p
	end
	recipe(put)
	assert(count <= MAX_PARTS_PER_ROOM, `InteriorRender {id}: 소품 {count}개 > {MAX_PARTS_PER_ROOM}`)
	room.Parent = parent
end

local function unrenderPlot(plotId: number)
	local folder = rendered[plotId]
	if folder then
		folder:Destroy()
		rendered[plotId] = nil
	end
end

local function renderPlot(plotId: number)
	unrenderPlot(plotId)
	local root = fxRoot
	local pivot = plotPivot(plotId)
	if not (root and pivot) then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = Keys.plotName(plotId)
	for id, recipe in SHELL do
		drawRoom(folder, pivot, id, recipe)
	end
	local built = builtOf(plotId)
	for id, recipe in RECIPES do
		if built[id] then
			drawRoom(folder, pivot, id, recipe)
		end
	end
	folder.Parent = root
	rendered[plotId] = folder
end

--- 내 부지 + 가까운 다른 부지로 채워 모두 DecorConfig.NEAR_COUNT 개(DecorController 와 같은 규칙)
local function updateNear()
	local myPlotId = readMyPlot()
	local character = player.Character
	local hrp = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local cam = Workspace.CurrentCamera
	local from: Vector3? = if hrp and hrp:IsA("BasePart") then hrp.Position elseif cam then cam.CFrame.Position else nil

	local order: { { id: number, score: number } } = {}
	for plotId = 1, Keys.PLOT_COUNT do
		local pivot = plotPivot(plotId)
		if pivot and from and plotId ~= myPlotId then
			local dist = (pivot.Position - from).Magnitude
			local score = if near[plotId] then dist - DecorConfig.NEAR_HYSTERESIS else dist
			table.insert(order, { id = plotId, score = score })
		end
	end
	table.sort(order, function(a, b)
		return a.score < b.score
	end)

	local want: { [number]: boolean } = {}
	local slots = DecorConfig.NEAR_COUNT
	if myPlotId then
		want[myPlotId] = true
		slots -= 1
	end
	for i = 1, math.min(slots, #order) do
		want[order[i].id] = true
	end

	for plotId in near do
		if not want[plotId] then
			near[plotId] = nil
			unrenderPlot(plotId)
		end
	end
	for plotId in want do
		if not near[plotId] then
			near[plotId] = true
			renderPlot(plotId)
		end
	end
end

local function watchState(state: Instance)
	if watchedStates[state] then
		return
	end
	local plotId = Keys.plotIdOf(state.Name)
	if not plotId then
		return
	end
	watchedStates[state] = true
	state:GetAttributeChangedSignal(Keys.ATTR_FACILITIES):Connect(function()
		task.delay(APPEAR_DELAY, function()
			if near[plotId] then
				renderPlot(plotId)
			end
		end)
	end)
end

function InteriorRenderController.Start()
	if started then
		return
	end
	started = true

	local fx = Instance.new("Folder")
	fx.Name = "InteriorFx"
	fx.Parent = Workspace
	fxRoot = fx

	-- Plots·PlotState 는 서버 부팅 뒤 온다. Start 를 막지 않게 따로 기다린다
	task.spawn(function()
		plotsFolder = Workspace:WaitForChild(Keys.PLOTS_FOLDER)
		local states = ReplicatedStorage:WaitForChild(Keys.PLOT_STATE_FOLDER)
		stateRoot = states
		for _, child in states:GetChildren() do
			watchState(child)
		end
		states.ChildAdded:Connect(watchState)

		while true do
			updateNear()
			task.wait(LOD_INTERVAL)
		end
	end)
end

return InteriorRenderController
