--!strict
--[[
	부지 껍데기. 기획서 §7.2, 계획서 §3.5.

	PlotShell.build(plotCFrame, plotId) 가 돌려주는 Model 하나가 Workspace.Plots.PlotNN 이 된다.
	  Shell (Model)          바닥·담장·교문·현판·팻말·접수대·현관·2층 계단·착지대·스티커판·교실1·「공사 중」 실루엣
	  Spawn (SpawnLocation)  (0,48). Neutral, Enabled=false — 서버가 RespawnLocation 으로 지정한다
	  Pads (Folder)          시설 14개 구매 패드. 이름 = facilityId, PadState="hidden" 이라 투명으로 시작
	  Stickers (Folder)      칭찬스티커 스폰 8개. Collected=true + 투명으로 시작(서버가 리스폰 때 켠다)
	  Stars (Folder)         방문객 별 2개

	좌표는 전부 부지 로컬(중심 0,0, +Z 가 교문 쪽)이고 마지막에 plotCFrame 으로 월드로 옮긴다.
	시설 자리(교실2·급식실·…)는 평평한 바닥 그대로 둔다. 바닥은 Shell 이 이미 깔았다.

	★ 바닥 윗면은 y=0 이다(시설 빌더들이 center.Y=0 을 바닥으로 본다). 광장 지면은 면이 겹치지 않게 Plaza 쪽이 0.05 내려가 있다.
	★ 담장은 두께 0.6 을 부지 경계 바깥으로 0.2 내밀었다(중심 ±59.9). 경계에 붙는 방 벽(교실1·도서관·체육관…)의
	  바깥 면 x=±60 이 담장 속에 묻혀서 면끼리 겹치지 않는다.
	★ 2층 계단: 기획서의 「x 4~10 · z -12~4」 그대로 두면 착지대(z -14~-6)와 위아래로 겹쳐 머리가 걸린다.
	  계단 7단(높이 1.5)을 z 5 → -5.5 로 두고 8단째를 착지대(y12)로 삼았다. 현관 지붕은 계단 위(x 4~12, z -6~6)를 뚫어 뒀다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)

local PlotShell = {}

local TEXT_HOME = "우리 학교로"
local TEXT_ADMISSION = "입학 접수"
local TEXT_ADMISSION_DESK = "입학 접수대"
local TEXT_CONSTRUCTION = "공사 중"
local PAD_STATE_HIDDEN = "hidden"
local PROMPT_DISTANCE = 8

-- ── 치수 (기획서 §7.2) ────────────────────────────────────────────
local PLOT_HALF = 60
local FLOOR_T = 1
local FENCE_H = 3
local FENCE_T = 0.6
local FENCE_X = PLOT_HALF - 0.1 -- 담장 중심. 바깥으로 0.2 내민다

local GATE_Z = 54
local GATE_W = 12 -- 기둥 안쪽 면 사이
local GATE_H = 8
local PILLAR = 1.5
local LEAF_W = 5.8
local LEAF_OPEN = math.rad(75) -- 문짝이 바깥(+Z)으로 열린 각도

local SPAWN = Vector3.new(0, 0, 48)
local SIGNPOST = Vector3.new(-10, 0, 50)
local ADMISSION = Vector3.new(12, 0, 46)

local WALL_T = 1
local WALL_H = 12
local ROOF_T = 1
local DOOR_W = 8
local DOOR_H = 8

-- 현관 (0,-4) 24×20. 남문 (0,6), 북문 (0,-14)
local ENTRANCE = Vector3.new(0, 0, -4)
local ENTRANCE_SIZE = Vector3.new(24, WALL_H, 20)
-- 교실1 (-48,-38) 24×24. 남문 (-48,-26)
local CLASS1 = Vector3.new(-48, 0, -38)
local CLASS1_SIZE = Vector3.new(24, WALL_H, 24)

-- 2층 계단·착지대
local STAIR_X0, STAIR_X1 = 4, 11 -- 현관 동쪽 벽 안쪽 면(x=11)까지
local STAIR_Z_BOTTOM = 5
local STAIR_STEPS = 7
local STAIR_RISE = 1.5
local STAIR_RUN = 1.5
local LANDING = Vector3.new(4, 12, -10)
local LANDING_SIZE = Vector3.new(16, 1, 8)
local STAIRWELL_Z0 = -6 -- 현관 지붕에 뚫는 구멍의 북쪽 끝(x 4~12, 남쪽 끝은 현관 남벽)

-- 강당 실루엣(2층). FacilityConfig.auditorium 의 center/size 를 쓴다
local CONSTRUCTION_T = 0.5
local CONSTRUCTION_ALPHA = 0.7

local STICKER_BOARD = Vector3.new(-10.85, 5, -4) -- 현관 서쪽 벽 안쪽 면(x=-11)에 붙인다
local STICKER_BOARD_SIZE = Vector3.new(0.3, 5, 8)

-- 스티커 스폰 8 (앞마당 3 · 복도 2 · 운동장 3) · 별 2
local STICKER_Y = 1
local STICKER_SPOTS = {
	Vector2.new(-6, 26),
	Vector2.new(0, 36),
	Vector2.new(20, 30),
	Vector2.new(-44, -20),
	Vector2.new(44, -20),
	Vector2.new(-48, 20),
	Vector2.new(-36, 30),
	Vector2.new(-24, 40),
}
local STAR_Y = 1.5
local STAR_SPOTS = { Vector2.new(-8, 42), Vector2.new(8, 42) }

local PAD_SIZE = Vector3.new(4, 0.4, 4)
local PAD_LIFT = 0.2

local TREES = { Vector2.new(30, 40), Vector2.new(-8, 10) }
local FLAGPOLE = Vector3.new(-10, 0, 46)

-- ── 색 (사실적 톤) ────────────────────────────────────────────────
local C = {
	floor = Color3.fromRGB(150, 150, 148),
	fence = Color3.fromRGB(152, 150, 146),
	pillar = Color3.fromRGB(122, 120, 116),
	gateBeam = Color3.fromRGB(88, 90, 96),
	gateSign = Color3.fromRGB(28, 58, 48),
	gateText = Color3.fromRGB(245, 245, 240),
	leaf = Color3.fromRGB(62, 72, 92),
	wall = Color3.fromRGB(228, 222, 208),
	roof = Color3.fromRGB(70, 72, 76),
	stair = Color3.fromRGB(160, 158, 152),
	landing = Color3.fromRGB(150, 150, 148),
	post = Color3.fromRGB(96, 70, 44),
	signBoard = Color3.fromRGB(236, 230, 214),
	signText = Color3.fromRGB(40, 40, 44),
	desk = Color3.fromRGB(58, 110, 190),
	deskDome = Color3.fromRGB(200, 230, 250),
	deskSlot = Color3.fromRGB(40, 40, 44),
	deskText = Color3.fromRGB(250, 250, 250),
	cork = Color3.fromRGB(198, 154, 104),
	ghost = Color3.fromRGB(190, 192, 196),
	ghostText = Color3.fromRGB(60, 60, 64),
	spawn = Color3.fromRGB(176, 176, 174),
	pad = Color3.fromRGB(52, 211, 153),
	sticker = Color3.fromRGB(250, 204, 21),
	star = Color3.fromRGB(135, 206, 250),
	trunk = Color3.fromRGB(110, 80, 50),
	leaves = Color3.fromRGB(70, 120, 55),
	pole = Color3.fromRGB(200, 200, 204),
	flag = Color3.fromRGB(70, 110, 180),
}

-- ── 헬퍼 ─────────────────────────────────────────────────────────
-- 월드 CFrame 하나로 파트를 놓는다. BuildKit.part 는 위치·회전을 따로 받으므로 여기서 나눈다.
local function put(parent: Instance, name: string, size: Vector3, cf: CFrame, opts: BuildKit.Opts): Part
	opts.cframe = cf.Rotation
	return BuildKit.part(parent, name, size, cf.Position, opts)
end

local function makePrompt(parent: BasePart, name: string, actionText: string, objectText: string): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	-- TODO(통합): 클라가 72px 커스텀 프롬프트를 그리면 Style = Custom 으로 바꾼다(기획서 §8.3)
	prompt.Parent = parent
	return prompt
end

-- 벽 한 면에 폭 DOOR_W 문을 뚫는다. 벽 두 토막 + 상인방 = 파트 3개.
-- axis = "X" 면 벽이 X 방향으로 길고(남·북 벽), "Z" 면 Z 방향으로 길다(동·서 벽).
local function wallWithDoor(
	parent: Instance,
	name: string,
	plotCFrame: CFrame,
	axis: "X" | "Z",
	from: number,
	to: number,
	doorAt: number,
	fixed: number
)
	local opts = { color = C.wall, material = Enum.Material.Concrete, fade = true }
	local d0, d1 = doorAt - DOOR_W / 2, doorAt + DOOR_W / 2
	local function seg(suffix: string, a: number, b: number, y: number, h: number)
		local len = b - a
		local mid = (a + b) / 2
		local size = if axis == "X" then Vector3.new(len, h, WALL_T) else Vector3.new(WALL_T, h, len)
		local pos = if axis == "X" then Vector3.new(mid, y, fixed) else Vector3.new(fixed, y, mid)
		put(parent, name .. suffix, size, plotCFrame * CFrame.new(pos), table.clone(opts))
	end
	seg("A", from, d0, WALL_H / 2, WALL_H)
	seg("B", d1, to, WALL_H / 2, WALL_H)
	seg("Lintel", d0, d1, (DOOR_H + WALL_H) / 2, WALL_H - DOOR_H)
end

local function solidWall(
	parent: Instance,
	name: string,
	plotCFrame: CFrame,
	axis: "X" | "Z",
	from: number,
	to: number,
	fixed: number
)
	local len = to - from
	local mid = (from + to) / 2
	local size = if axis == "X" then Vector3.new(len, WALL_H, WALL_T) else Vector3.new(WALL_T, WALL_H, len)
	local pos = if axis == "X" then Vector3.new(mid, WALL_H / 2, fixed) else Vector3.new(fixed, WALL_H / 2, mid)
	put(
		parent,
		name,
		size,
		plotCFrame * CFrame.new(pos),
		{ color = C.wall, material = Enum.Material.Concrete, fade = true }
	)
end

local function roof(parent: Instance, name: string, plotCFrame: CFrame, center: Vector3, size: Vector3)
	-- 지붕 윗면이 벽 높이(12)와 같다. 2층 바닥과 같은 높이라 강당이 그 위에 앉는다
	local pos = Vector3.new(center.X, WALL_H - ROOF_T / 2, center.Z)
	put(parent, name, Vector3.new(size.X, ROOF_T, size.Z), plotCFrame * CFrame.new(pos), {
		color = C.roof,
		material = Enum.Material.Concrete,
		fade = true,
		light = true,
	})
end

-- ── Shell 조각들 ──────────────────────────────────────────────────
local function buildGround(shell: Model, plotCFrame: CFrame)
	put(
		shell,
		"Floor",
		Vector3.new(PLOT_HALF * 2, FLOOR_T, PLOT_HALF * 2),
		plotCFrame * CFrame.new(0, -FLOOR_T / 2, 0),
		{
			color = C.floor,
			material = Enum.Material.Concrete,
		}
	)

	local fenceOpts = { color = C.fence, material = Enum.Material.Concrete }
	local sideLen = GATE_Z + PLOT_HALF -- z -60 ~ 54
	local sideMid = (GATE_Z - PLOT_HALF) / 2
	put(
		shell,
		"FenceN",
		Vector3.new(PLOT_HALF * 2 + FENCE_T, FENCE_H, FENCE_T),
		plotCFrame * CFrame.new(0, FENCE_H / 2, -FENCE_X),
		table.clone(fenceOpts)
	)
	put(
		shell,
		"FenceE",
		Vector3.new(FENCE_T, FENCE_H, sideLen),
		plotCFrame * CFrame.new(FENCE_X, FENCE_H / 2, sideMid),
		table.clone(fenceOpts)
	)
	put(
		shell,
		"FenceW",
		Vector3.new(FENCE_T, FENCE_H, sideLen),
		plotCFrame * CFrame.new(-FENCE_X, FENCE_H / 2, sideMid),
		table.clone(fenceOpts)
	)
	-- 남쪽 담장은 교문 줄(z=54)에 맞춘다. 기둥 바깥 면(x=±7.5)부터 부지 끝까지
	local southFrom = GATE_W / 2 + PILLAR
	local southLen = PLOT_HALF - southFrom
	local southMid = (southFrom + PLOT_HALF) / 2
	put(
		shell,
		"FenceSW",
		Vector3.new(southLen, FENCE_H, FENCE_T),
		plotCFrame * CFrame.new(-southMid, FENCE_H / 2, GATE_Z),
		table.clone(fenceOpts)
	)
	put(
		shell,
		"FenceSE",
		Vector3.new(southLen, FENCE_H, FENCE_T),
		plotCFrame * CFrame.new(southMid, FENCE_H / 2, GATE_Z),
		table.clone(fenceOpts)
	)
end

local function buildGate(shell: Model, plotCFrame: CFrame)
	local pillarH = GATE_H + 1.5
	local pillarX = GATE_W / 2 + PILLAR / 2
	local pillarOpts = { color = C.pillar, material = Enum.Material.Concrete }
	put(
		shell,
		"GatePillarW",
		Vector3.new(PILLAR, pillarH, PILLAR),
		plotCFrame * CFrame.new(-pillarX, pillarH / 2, GATE_Z),
		table.clone(pillarOpts)
	)
	put(
		shell,
		"GatePillarE",
		Vector3.new(PILLAR, pillarH, PILLAR),
		plotCFrame * CFrame.new(pillarX, pillarH / 2, GATE_Z),
		table.clone(pillarOpts)
	)

	-- 교문 = 기둥 위를 가로지르는 보. 아래 통로 폭 12 · 높이 8
	local beamH = 1.5
	put(
		shell,
		Keys.GATE,
		Vector3.new(GATE_W + PILLAR * 2, beamH, PILLAR),
		plotCFrame * CFrame.new(0, GATE_H + beamH / 2, GATE_Z),
		{
			color = C.gateBeam,
			material = Enum.Material.Metal,
		}
	)

	-- 현판. 글자는 PlotService 가 채운다(「{이름}의 학교」 + 졸업 횟수 + 재학생 수)
	local signH = 3
	local sign = put(
		shell,
		Keys.GATE_SIGN,
		Vector3.new(GATE_W, signH, 0.4),
		plotCFrame * CFrame.new(0, GATE_H + beamH + signH / 2, GATE_Z),
		{
			color = C.gateSign,
			material = Enum.Material.SmoothPlastic,
		}
	)
	-- 광장 쪽(+Z) 면. 글자는 PlotService 가 주인 이름으로 바꾼다
	local label = BuildKit.surfaceText(sign, Enum.NormalId.Back, "", C.gateText, 0.8)
	label.Name = "Label"

	-- 문짝 두 장. 바깥으로 75° 열린 채 고정. 장식이라 CanCollide=false
	local leafH = GATE_H - 0.5
	local function leaf(name: string, hingeX: number, yaw: number, along: number)
		local cf = plotCFrame
			* CFrame.new(hingeX, leafH / 2, GATE_Z)
			* CFrame.Angles(0, yaw, 0)
			* CFrame.new(along, 0, 0)
		put(
			shell,
			name,
			Vector3.new(LEAF_W, leafH, 0.3),
			cf,
			{ color = C.leaf, material = Enum.Material.Metal, collide = false }
		)
	end
	leaf("GateLeafW", -GATE_W / 2, -LEAF_OPEN, LEAF_W / 2)
	leaf("GateLeafE", GATE_W / 2, LEAF_OPEN, -LEAF_W / 2)
end

local function buildSignpost(shell: Model, plotCFrame: CFrame)
	local poleH = 4
	local boardSize = Vector3.new(3, 2, 0.3)
	put(
		shell,
		"SignpostPole",
		Vector3.new(0.4, poleH, 0.4),
		plotCFrame * CFrame.new(SIGNPOST + Vector3.new(0, poleH / 2, 0)),
		{
			color = C.post,
			material = Enum.Material.Wood,
		}
	)
	local board = put(
		shell,
		Keys.SIGNPOST,
		boardSize,
		plotCFrame * CFrame.new(SIGNPOST + Vector3.new(0, poleH + boardSize.Y / 2, 0)),
		{
			color = C.signBoard,
			material = Enum.Material.Wood,
		}
	)
	BuildKit.surfaceText(board, Enum.NormalId.Front, TEXT_HOME, C.signText, 0.45)
	BuildKit.surfaceText(board, Enum.NormalId.Back, TEXT_HOME, C.signText, 0.45)
	makePrompt(board, Keys.HOME_PROMPT, TEXT_HOME, "")
end

local function buildAdmissionDesk(shell: Model, plotCFrame: CFrame)
	local bodySize = Vector3.new(4, 6, 4)
	local body = put(
		shell,
		Keys.ADMISSION_DESK,
		bodySize,
		plotCFrame * CFrame.new(ADMISSION + Vector3.new(0, bodySize.Y / 2, 0)),
		{
			color = C.desk,
			material = Enum.Material.SmoothPlastic,
		}
	)
	BuildKit.surfaceText(body, Enum.NormalId.Back, TEXT_ADMISSION, C.deskText, 0.6)
	makePrompt(body, Keys.ADMISSION_PROMPT, TEXT_ADMISSION, TEXT_ADMISSION_DESK)

	-- 뽑기 기계 느낌: 위에 유리 돔, 앞에 배출구
	local domeD = 3.2
	put(
		shell,
		"AdmissionDome",
		Vector3.new(domeD, domeD, domeD),
		plotCFrame * CFrame.new(ADMISSION + Vector3.new(0, bodySize.Y + domeD / 2 - 0.4, 0)),
		{
			color = C.deskDome,
			material = Enum.Material.Glass,
			transparency = 0.35,
			shape = Enum.PartType.Ball,
			collide = false,
		}
	)
	put(
		shell,
		"AdmissionSlot",
		Vector3.new(2, 1, 0.2),
		plotCFrame * CFrame.new(ADMISSION + Vector3.new(0, 2.2, bodySize.Z / 2 + 0.1)),
		{
			color = C.deskSlot,
			material = Enum.Material.SmoothPlastic,
			collide = false,
		}
	)
end

local function buildEntrance(shell: Model, plotCFrame: CFrame)
	local hx, hz = ENTRANCE_SIZE.X / 2, ENTRANCE_SIZE.Z / 2
	local x0, x1 = ENTRANCE.X - hx, ENTRANCE.X + hx
	local z0, z1 = ENTRANCE.Z - hz, ENTRANCE.Z + hz
	local inner = WALL_T / 2

	solidWall(shell, "EntranceWallW", plotCFrame, "Z", z0 + WALL_T, z1 - WALL_T, x0 + inner)
	solidWall(shell, "EntranceWallE", plotCFrame, "Z", z0 + WALL_T, z1 - WALL_T, x1 - inner)
	wallWithDoor(shell, "EntranceWallS", plotCFrame, "X", x0, x1, ENTRANCE.X, z1 - inner)
	wallWithDoor(shell, "EntranceWallN", plotCFrame, "X", x0, x1, ENTRANCE.X, z0 + inner)

	-- 지붕. 계단 위(x 4~12, z -6~6)는 뚫고, 착지대가 z -14~-6 의 동쪽을 덮는다
	local landingX0 = LANDING.X - LANDING_SIZE.X / 2 -- -4
	roof(
		shell,
		"EntranceRoof",
		plotCFrame,
		Vector3.new((x0 + STAIR_X0) / 2, 0, (STAIRWELL_Z0 + z1) / 2),
		Vector3.new(STAIR_X0 - x0, 0, z1 - STAIRWELL_Z0)
	)
	roof(
		shell,
		"EntranceRoofNW",
		plotCFrame,
		Vector3.new((x0 + landingX0) / 2, 0, (z0 + STAIRWELL_Z0) / 2),
		Vector3.new(landingX0 - x0, 0, STAIRWELL_Z0 - z0)
	)

	-- 2층 계단 7단 + 착지대. 단은 바닥부터 꽉 찬 블록이라 옆에서 봐도 계단이다
	local stairW = STAIR_X1 - STAIR_X0
	for i = 1, STAIR_STEPS do
		local h = STAIR_RISE * i
		local zTop = STAIR_Z_BOTTOM - STAIR_RUN * (i - 1)
		local pos = Vector3.new((STAIR_X0 + STAIR_X1) / 2, h / 2, zTop - STAIR_RUN / 2)
		put(shell, string.format("Stair%02d", i), Vector3.new(stairW, h, STAIR_RUN), plotCFrame * CFrame.new(pos), {
			color = C.stair,
			material = Enum.Material.Concrete,
		})
	end
	put(shell, "Landing", LANDING_SIZE, plotCFrame * CFrame.new(LANDING.X, LANDING.Y - LANDING_SIZE.Y / 2, LANDING.Z), {
		color = C.landing,
		material = Enum.Material.Concrete,
	})
	-- TODO(통합): 강당(auditorium) 바닥은 착지대 윗면 y=12 와 같은 높이여야 하고, 계단 위 x 4~12 · z -6~6 은 비워 둬야 머리가 안 걸린다

	-- 칭찬스티커판. 서쪽 벽 안쪽 면. 60칸은 클라(PadController)가 이 SurfaceGui 에 그린다
	local board = put(shell, Keys.STICKER_BOARD, STICKER_BOARD_SIZE, plotCFrame * CFrame.new(STICKER_BOARD), {
		color = C.cork,
		material = Enum.Material.Fabric,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Right -- +X = 현관 안쪽
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1
	gui.Parent = board
end

local function buildClass1(shell: Model, plotCFrame: CFrame)
	local hx, hz = CLASS1_SIZE.X / 2, CLASS1_SIZE.Z / 2
	local x0, x1 = CLASS1.X - hx, CLASS1.X + hx
	local z0, z1 = CLASS1.Z - hz, CLASS1.Z + hz
	local inner = WALL_T / 2

	solidWall(shell, "Class1WallN", plotCFrame, "X", x0, x1, z0 + inner)
	solidWall(shell, "Class1WallW", plotCFrame, "Z", z0 + WALL_T, z1 - WALL_T, x0 + inner)
	solidWall(shell, "Class1WallE", plotCFrame, "Z", z0 + WALL_T, z1 - WALL_T, x1 - inner)
	wallWithDoor(shell, "Class1WallS", plotCFrame, "X", x0, x1, CLASS1.X, z1 - inner)
	roof(shell, "Class1Roof", plotCFrame, CLASS1, CLASS1_SIZE)
end

-- 「공사 중」 실루엣. 강당 자리(2층)에 벽 4 + 지붕 1, 30% 만 보인다. 강당을 지으면 PlotService 가 없앤다
local function buildConstruction(shell: Model, plotCFrame: CFrame)
	local aud = FacilityConfig.BY_ID.auditorium
	local model = Instance.new("Model")
	model.Name = Keys.CONSTRUCTION
	model:SetAttribute(Keys.ATTR_FACILITY_ID, aud.id)

	local opts = {
		color = C.ghost,
		material = Enum.Material.SmoothPlastic,
		transparency = CONSTRUCTION_ALPHA,
		collide = false,
		cast = false,
	}
	local hx, hz = aud.size.X / 2, aud.size.Z / 2
	local function slab(name: string, size: Vector3, offset: Vector3): Part
		local p = put(model, name, size, plotCFrame * CFrame.new(aud.center + offset), table.clone(opts))
		p.CanQuery = false
		return p
	end
	local south = slab(
		"GhostWallS",
		Vector3.new(aud.size.X, aud.size.Y, CONSTRUCTION_T),
		Vector3.new(0, aud.size.Y / 2, hz - CONSTRUCTION_T / 2)
	)
	slab(
		"GhostWallN",
		Vector3.new(aud.size.X, aud.size.Y, CONSTRUCTION_T),
		Vector3.new(0, aud.size.Y / 2, -hz + CONSTRUCTION_T / 2)
	)
	slab(
		"GhostWallE",
		Vector3.new(CONSTRUCTION_T, aud.size.Y, aud.size.Z),
		Vector3.new(hx - CONSTRUCTION_T / 2, aud.size.Y / 2, 0)
	)
	slab(
		"GhostWallW",
		Vector3.new(CONSTRUCTION_T, aud.size.Y, aud.size.Z),
		Vector3.new(-hx + CONSTRUCTION_T / 2, aud.size.Y / 2, 0)
	)
	slab(
		"GhostRoof",
		Vector3.new(aud.size.X, CONSTRUCTION_T, aud.size.Z),
		Vector3.new(0, aud.size.Y - CONSTRUCTION_T / 2, 0)
	)
	BuildKit.surfaceText(south, Enum.NormalId.Back, TEXT_CONSTRUCTION, C.ghostText, 2)

	model.Parent = shell
end

local function buildYard(shell: Model, plotCFrame: CFrame)
	for i, spot in TREES do
		local base = Vector3.new(spot.X, 0, spot.Y)
		local trunkH, canopyD = 5, 7
		put(
			shell,
			string.format("Tree%02dTrunk", i),
			Vector3.new(1.2, trunkH, 1.2),
			plotCFrame * CFrame.new(base + Vector3.new(0, trunkH / 2, 0)),
			{
				color = C.trunk,
				material = Enum.Material.Wood,
			}
		)
		put(
			shell,
			string.format("Tree%02dCanopy", i),
			Vector3.new(canopyD, canopyD, canopyD),
			plotCFrame * CFrame.new(base + Vector3.new(0, trunkH + canopyD / 2 - 1, 0)),
			{
				color = C.leaves,
				material = Enum.Material.Grass,
				shape = Enum.PartType.Ball,
				collide = false,
			}
		)
	end

	local poleH = 14
	put(
		shell,
		"Flagpole",
		Vector3.new(0.3, poleH, 0.3),
		plotCFrame * CFrame.new(FLAGPOLE + Vector3.new(0, poleH / 2, 0)),
		{
			color = C.pole,
			material = Enum.Material.Metal,
		}
	)
	put(shell, "Flag", Vector3.new(3, 2, 0.1), plotCFrame * CFrame.new(FLAGPOLE + Vector3.new(1.65, poleH - 1.2, 0)), {
		color = C.flag,
		material = Enum.Material.Fabric,
		collide = false,
	})
end

-- ── 플레이 요소 ───────────────────────────────────────────────────
local function buildSpawn(plot: Model, plotCFrame: CFrame)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = Keys.SPAWN
	spawn.Size = Vector3.new(8, 0.3, 8)
	spawn.CFrame = plotCFrame * CFrame.new(SPAWN + Vector3.new(0, spawn.Size.Y / 2, 0))
	spawn.Color = C.spawn
	spawn.Material = Enum.Material.Concrete
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Enabled = false -- 자동 스폰 금지. PlotService 가 RespawnLocation 으로 지정한다
	spawn.Duration = 0
	spawn.Parent = plot
end

local function buildPads(plot: Model, plotCFrame: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = Keys.PADS_FOLDER
	for _, row in FacilityConfig.LIST do
		local pad = put(folder, row.id, PAD_SIZE, plotCFrame * CFrame.new(row.pad + Vector3.new(0, PAD_LIFT, 0)), {
			color = C.pad,
			material = Enum.Material.SmoothPlastic,
			transparency = 1,
			collide = false,
			cast = false,
		})
		pad.CanTouch = true
		pad:SetAttribute(Keys.ATTR_FACILITY_ID, row.id)
		pad:SetAttribute(Keys.ATTR_PAD_STATE, PAD_STATE_HIDDEN)
		pad:AddTag(Keys.PAD_TAG)
	end
	folder.Parent = plot
end

local function buildStickers(plot: Model, plotCFrame: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = Keys.STICKERS_FOLDER
	-- 원반: Cylinder 의 축은 X 라 Z 축으로 90° 눕힌다
	local flat = CFrame.Angles(0, 0, math.pi / 2)
	for i, spot in STICKER_SPOTS do
		local sticker = put(
			folder,
			string.format("Sticker%02d", i),
			Vector3.new(0.4, 2, 2),
			plotCFrame * CFrame.new(spot.X, STICKER_Y, spot.Y) * flat,
			{
				color = C.sticker,
				material = Enum.Material.SmoothPlastic,
				transparency = 1,
				shape = Enum.PartType.Cylinder,
				collide = false,
				cast = false,
			}
		)
		sticker.CanTouch = true
		sticker:SetAttribute(Keys.ATTR_STICKER_ID, i)
		sticker:SetAttribute(Keys.ATTR_COLLECTED, true)
		sticker:AddTag(Keys.STICKER_TAG)
	end
	folder.Parent = plot
end

local function buildStars(plot: Model, plotCFrame: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = Keys.STARS_FOLDER
	for i, spot in STAR_SPOTS do
		local star = put(
			folder,
			string.format("Star%02d", i),
			Vector3.new(1.6, 1.6, 1.6),
			plotCFrame * CFrame.new(spot.X, STAR_Y, spot.Y),
			{
				color = C.star,
				material = Enum.Material.Neon,
				shape = Enum.PartType.Ball,
				collide = false,
				cast = false,
			}
		)
		star.CanTouch = true
		star:AddTag(Keys.STAR_TAG)
	end
	folder.Parent = plot
end

--- 부지 하나. 돌려준 Model 을 호출자가 Workspace.Plots 에 넣는다(여기서는 Parent 를 잡지 않는다)
function PlotShell.build(plotCFrame: CFrame, plotId: number): Model
	local plot = Instance.new("Model")
	plot.Name = Keys.plotName(plotId)
	plot:SetAttribute(Keys.ATTR_PLOT_ID, plotId)

	local shell = Instance.new("Model")
	shell.Name = Keys.SHELL
	buildGround(shell, plotCFrame)
	buildGate(shell, plotCFrame)
	buildSignpost(shell, plotCFrame)
	buildAdmissionDesk(shell, plotCFrame)
	buildEntrance(shell, plotCFrame)
	buildClass1(shell, plotCFrame)
	buildConstruction(shell, plotCFrame)
	buildYard(shell, plotCFrame)
	shell.Parent = plot

	buildSpawn(plot, plotCFrame)
	buildPads(plot, plotCFrame)
	buildStickers(plot, plotCFrame)
	buildStars(plot, plotCFrame)

	return plot
end

return PlotShell
