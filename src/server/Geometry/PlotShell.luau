--!strict
--[[
	부지 껍데기. 기획서 §7.2, 계획서 §3.5.

	PlotShell.build(plotCFrame, plotId) 가 돌려주는 Model 하나가 Workspace.Plots.PlotNN 이 된다.
	  Shell (Model)          바닥·담장·교문·화단 2·현판·팻말·접수대·현관(바깥 벽등 2)·2층 계단·착지대·스티커판·교실1·「공사 중」 실루엣
	  Spawn (SpawnLocation)  (0,60). Neutral, Enabled=false — 서버가 RespawnLocation 으로 지정한다
	  Pads (Folder)          시설 14개 구매 패드. 이름 = facilityId, PadState="hidden" 이라 투명으로 시작
	  Stickers (Folder)      칭찬스티커 스폰 8개. Collected=true + 투명으로 시작(서버가 리스폰 때 켠다)
	  Stars (Folder)         방문객 별 2개

	좌표는 전부 부지 로컬(중심 0,0, +Z 가 교문 쪽)이고 마지막에 plotCFrame 으로 월드로 옮긴다.
	시설 자리(교실2·급식실·…)는 평평한 바닥 그대로 둔다. 바닥은 Shell 이 이미 깔았다.

	★ 바닥 윗면은 y=0 이다(시설 빌더들이 center.Y=0 을 바닥으로 본다). 광장 지면은 면이 겹치지 않게 Plaza 쪽이 0.05 내려가 있다.
	★ 담장은 두께 0.6 을 부지 경계 바깥으로 0.2 내밀었다(중심 ±74.9). 경계에 붙는 방 벽(교실1·도서관·체육관…)의
	  바깥 면 x=±75 가 담장 속에 묻혀서 면끼리 겹치지 않는다.
	★ 2층 계단: 계단 17단(높이 1, 디딤 1.5)을 x 5~14 · z 15 → -10.5 로 두고 18단째를 착지대(y18)로 삼았다.
	  단마다 나무 디딤판(앞으로 0.15 내민 코), 서쪽에 옆판·난간 기둥·손잡이, 동쪽 벽에 벽 손잡이가 있다.
	  현관 지붕은 계단 위(x 5~14, z -10.5~0)를 뚫어 뒀고, 2층에서 그 구멍 서쪽 가장자리에 안전 난간을 둘렀다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local PlotLayout = require(ReplicatedStorage.Shared.PlotLayout)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)
local PropLibrary = require(script.Parent.PropLibrary)

local PlotShell = {}

local TEXT_HOME = "우리 학교로"
local TEXT_CONSTRUCTION = "공사 중"
local PAD_STATE_HIDDEN = "hidden"
local PROMPT_DISTANCE = 8

-- ── 치수 (기획서 §7.2) ────────────────────────────────────────────
local PLOT_HALF = PlotLayout.PLOT_HALF
local FLOOR_T = PlotLayout.FLOOR_T
local FENCE_H = 3
local FENCE_T = 0.6
local FENCE_X = PLOT_HALF - 0.1 -- 담장 중심. 바깥으로 0.2 내민다

local GATE_Z = PlotLayout.GATE_Z
local GATE_W = PlotLayout.GATE_W -- 기둥 안쪽 면 사이
local GATE_H = 8
local PILLAR = PlotLayout.GATE_PILLAR
local LEAF_W = 5.8
local LEAF_OPEN = math.rad(75) -- 문짝이 바깥(+Z)으로 열린 각도

local SPAWN = PlotLayout.SPAWN
local SIGNPOST = PlotLayout.SIGNPOST
local ADMISSION = PlotLayout.ADMISSION

local WALL_T = 1
local WALL_H = PlotLayout.WALL_H
local ROOF_T = 1
local DOOR_W = 8
local DOOR_H = 8

-- 현관 (0,6) 30×47. 남문 (0,29.5), 북문 (0,-17.5)
local ENTRANCE = PlotLayout.ENTRANCE
local ENTRANCE_SIZE = PlotLayout.ENTRANCE_SIZE
-- 교실1 (-60,-47.5) 30×30. 남문 (-60,-32.5)
local CLASS1 = PlotLayout.CLASS1
local CLASS1_SIZE = PlotLayout.CLASS1_SIZE

-- 2층 계단·착지대(값은 PlotLayout). 착지대는 동·북 벽 윗면(y=18)과 겹치지 않게 벽 안쪽 면(x=14, z=-16.5)까지만
local STAIR_X0, STAIR_X1 = PlotLayout.STAIR_X0, PlotLayout.STAIR_X1
local STAIR_Z_BOTTOM = PlotLayout.STAIR_Z_BOTTOM
local STAIR_STEPS = PlotLayout.STAIR_STEPS
local STAIR_RISE = PlotLayout.STAIR_RISE
local STAIR_RUN = PlotLayout.STAIR_RUN
local LANDING = PlotLayout.LANDING
local LANDING_SIZE = PlotLayout.LANDING_SIZE
local STAIRWELL_Z0 = PlotLayout.STAIRWELL_Z0 -- 현관 지붕 구멍의 북쪽 끝
local STAIRWELL_Z1 = PlotLayout.STAIRWELL_Z1 -- 남쪽 끝(강당 남벽 바깥 면)

-- 계단 디테일. 손잡이 높이는 디딤판 코 줄에서 잰다
local TREAD_T = 0.2 -- 디딤판 두께. 단 블록 윗면을 그만큼 낮춰 디딤판 윗면이 단 높이와 같다
local TREAD_NOSE = 0.15 -- 디딤판이 단 앞으로 나온 길이
local STRINGER_T = 0.4
local STRINGER_H = 1.8 -- 코 줄 아래 1.3(디딤판 옆 끝을 가린다) ~ 위 0.5
local RAIL_H = 3 -- 손잡이 높이
local RAIL_T = 0.35
local BALUSTER_T = 0.3
local BALUSTER_EVERY = 2 -- 난간 기둥을 몇 단마다
local NEWEL_T = 0.8 -- 첫 단 옆 굵은 기둥

-- 강당 실루엣(2층). FacilityConfig.auditorium 의 center/size 를 쓴다
local CONSTRUCTION_T = 0.5
local CONSTRUCTION_ALPHA = 0.7

-- 현관 남쪽 문 양옆 바깥 벽등. 문 가장자리에서 LAMP_GAP 떨어져, 등 밑변이 LAMP_Y
local LAMP_GAP = 2.5
local LAMP_Y = 5.5

local STICKER_BOARD = Vector3.new(-13.85, 5, -5) -- 현관 서쪽 벽 안쪽 면(x=-14)에 붙인다
local STICKER_BOARD_SIZE = Vector3.new(0.3, 5, 8)

-- 스티커 스폰 8(홈 자리: 앞마당 3 · 복도 2 · 운동장 3) · 별 2. 자리는 PlotLayout
-- 서버 파트는 보이지 않는 판정 상자다. 아랫면 = 바닥 윗면(중심 y = floorY + 높이/2). 표시 판은 클라가 그린다(개선계획 §3.2 #1)
local HITBOX_SIZE = Vector3.new(3.4, 3, 3.4)
local STICKER_SPOTS = PlotLayout.HOME_SPOTS
local STAR_SPOTS = PlotLayout.STAR_SPOTS

local PAD_SIZE = Vector3.new(4, 0.4, 4)
local PAD_LIFT = 0.2

local TREES = PlotLayout.TREES
local FLAGPOLE = PlotLayout.FLAGPOLE

-- ── 색 (WorldPalette 역할 색) ─────────────────────────────────────
local P = WorldPalette
local C = {
	lawn = P.lawn,
	path = P.path,
	hedge = P.hedge,
	pillar = P.stone,
	gateBeam = P.gateBeam,
	gateSign = P.gateSign,
	gateText = P.lightText,
	leaf = P.gateLeaf,
	wall = P.wall,
	roof = P.roof.classroom,
	stair = P.stone,
	tread = P.wood,
	rail = P.wood,
	landing = P.stone,
	post = P.wood,
	signBoard = P.signBoard,
	signText = P.darkText,
	desk = P.desk,
	deskDome = P.deskDome,
	deskSlot = P.darkText,
	cork = P.cork,
	wainscot = Color3.fromRGB(122, 170, 210), -- 교실 1 벽 아래 띠(하늘색)
	classFloor = Color3.fromRGB(232, 222, 196), -- 교실 1 바닥 타일(연한 베이지)
	ghost = P.ghost,
	ghostText = P.ghostText,
	spawn = P.spawn,
	pad = P.pad,
	sticker = P.sticker,
	star = P.star,
	pole = P.pole,
	flag = P.flag,
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
): (Part, Part)
	local opts = { color = C.wall, material = Enum.Material.Plaster, fade = true }
	local d0, d1 = doorAt - DOOR_W / 2, doorAt + DOOR_W / 2
	local function seg(suffix: string, a: number, b: number, y: number, h: number): Part
		local len = b - a
		local mid = (a + b) / 2
		local size = if axis == "X" then Vector3.new(len, h, WALL_T) else Vector3.new(WALL_T, h, len)
		local pos = if axis == "X" then Vector3.new(mid, y, fixed) else Vector3.new(fixed, y, mid)
		return put(parent, name .. suffix, size, plotCFrame * CFrame.new(pos), table.clone(opts))
	end
	local a = seg("A", from, d0, WALL_H / 2, WALL_H)
	local b = seg("B", d1, to, WALL_H / 2, WALL_H)
	seg("Lintel", d0, d1, (DOOR_H + WALL_H) / 2, WALL_H - DOOR_H)
	return a, b -- 문 양옆 두 토막(바닥까지 닿는 것)
end

local function solidWall(
	parent: Instance,
	name: string,
	plotCFrame: CFrame,
	axis: "X" | "Z",
	from: number,
	to: number,
	fixed: number
): Part
	local len = to - from
	local mid = (from + to) / 2
	local size = if axis == "X" then Vector3.new(len, WALL_H, WALL_T) else Vector3.new(WALL_T, WALL_H, len)
	local pos = if axis == "X" then Vector3.new(mid, WALL_H / 2, fixed) else Vector3.new(fixed, WALL_H / 2, mid)
	return put(
		parent,
		name,
		size,
		plotCFrame * CFrame.new(pos),
		{ color = C.wall, material = Enum.Material.Plaster, fade = true }
	)
end

-- x0~x1 · z0~z1 은 벽 안쪽 면까지다. 지붕이 벽 위까지 덮으면 벽 윗면·바깥면과 같은 평면에서 겹쳐
-- 카메라가 움직일 때마다 벽색·지붕색이 번갈아 깜빡인다(z-fighting)
--- noLight: 천장등을 달지 않는다(부지당 조명 수를 늘리지 않으려고 같은 방의 지붕 조각 하나는 끈다)
local function roof(
	parent: Instance,
	name: string,
	plotCFrame: CFrame,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	noLight: boolean?
)
	-- 지붕 윗면이 벽 높이(18)와 같다. 2층 바닥과 같은 높이라 강당이 그 위에 앉는다
	local pos = Vector3.new((x0 + x1) / 2, WALL_H - ROOF_T / 2, (z0 + z1) / 2)
	put(parent, name, Vector3.new(x1 - x0, ROOF_T, z1 - z0), plotCFrame * CFrame.new(pos), {
		color = C.roof,
		material = Enum.Material.Concrete,
		fade = true,
		light = not noLight,
	})
end

-- ── Shell 조각들 ──────────────────────────────────────────────────
-- 바닥 7타일. 건물 줄 뒤(z < 7.5)와 앞마당으로 튀어나온 현관 바닥은 흙마당(path), 앞마당은 잔디 둘 사이로
-- 교문 폭 길(path)이 현관 남문까지 간다. 타일끼리 옆면만 맞닿고 윗면(y=0)은 겹치지 않는다
local function buildGround(shell: Model, plotCFrame: CFrame)
	local rowZ = PlotLayout.ROW_FRONT_Z -- 7.5. 시설 앞줄의 남쪽 끝
	local frontZ = ENTRANCE.Z + ENTRANCE_SIZE.Z / 2 -- 29.5. 현관 남벽 바깥 면
	local ex0, ex1 = ENTRANCE.X - ENTRANCE_SIZE.X / 2, ENTRANCE.X + ENTRANCE_SIZE.X / 2
	local pathHalf = GATE_W / 2
	local function tile(name: string, x0: number, x1: number, z0: number, z1: number, color: Color3, mat: Enum.Material)
		put(
			shell,
			name,
			Vector3.new(x1 - x0, FLOOR_T, z1 - z0),
			plotCFrame * CFrame.new((x0 + x1) / 2, -FLOOR_T / 2, (z0 + z1) / 2),
			{ color = color, material = mat }
		)
	end
	tile("FloorBack", -PLOT_HALF, PLOT_HALF, -PLOT_HALF, rowZ, C.path, Enum.Material.Concrete)
	tile("FloorEntrance", ex0, ex1, rowZ, frontZ, C.path, Enum.Material.Concrete)
	tile("FloorYardW", -PLOT_HALF, ex0, rowZ, PLOT_HALF, C.lawn, Enum.Material.Grass)
	tile("FloorYardE", ex1, PLOT_HALF, rowZ, PLOT_HALF, C.lawn, Enum.Material.Grass)
	tile("FloorYardSW", ex0, -pathHalf, frontZ, PLOT_HALF, C.lawn, Enum.Material.Grass)
	tile("FloorPath", -pathHalf, pathHalf, frontZ, PLOT_HALF, C.path, Enum.Material.Concrete)
	tile("FloorYardSE", pathHalf, ex1, frontZ, PLOT_HALF, C.lawn, Enum.Material.Grass)

	-- 담장 자리의 생울타리. 치수는 담장 그대로
	local hedgeOpts = { color = C.hedge, material = Enum.Material.Grass }
	local sideLen = GATE_Z + PLOT_HALF -- z -75 ~ 67.5
	local sideMid = (GATE_Z - PLOT_HALF) / 2
	put(
		shell,
		"HedgeN",
		Vector3.new(PLOT_HALF * 2 + FENCE_T, FENCE_H, FENCE_T),
		plotCFrame * CFrame.new(0, FENCE_H / 2, -FENCE_X),
		table.clone(hedgeOpts)
	)
	put(
		shell,
		"HedgeE",
		Vector3.new(FENCE_T, FENCE_H, sideLen),
		plotCFrame * CFrame.new(FENCE_X, FENCE_H / 2, sideMid),
		table.clone(hedgeOpts)
	)
	put(
		shell,
		"HedgeW",
		Vector3.new(FENCE_T, FENCE_H, sideLen),
		plotCFrame * CFrame.new(-FENCE_X, FENCE_H / 2, sideMid),
		table.clone(hedgeOpts)
	)
	-- 남쪽 담장은 교문 줄(z=67.5)에 맞춘다. 기둥 바깥 면(x=±7.5)부터 부지 끝까지
	local southFrom = GATE_W / 2 + PILLAR
	local southLen = PLOT_HALF - southFrom
	local southMid = (southFrom + PLOT_HALF) / 2
	put(
		shell,
		"HedgeSW",
		Vector3.new(southLen, FENCE_H, FENCE_T),
		plotCFrame * CFrame.new(-southMid, FENCE_H / 2, GATE_Z),
		table.clone(hedgeOpts)
	)
	put(
		shell,
		"HedgeSE",
		Vector3.new(southLen, FENCE_H, FENCE_T),
		plotCFrame * CFrame.new(southMid, FENCE_H / 2, GATE_Z),
		table.clone(hedgeOpts)
	)
end

local function buildGate(shell: Model, plotCFrame: CFrame)
	-- 기둥 윗면 = 보 아랫면. 기둥이 보 높이까지 올라가면 두 면이 겹쳐 깜빡인다
	local pillarH = GATE_H
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

	-- 현판. 글자는 PlotService 가 채운다(「{이름}의 학교」)
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
	put(shell, Keys.ADMISSION_DESK, bodySize, plotCFrame * CFrame.new(ADMISSION + Vector3.new(0, bodySize.Y / 2, 0)), {
		color = C.desk,
		material = Enum.Material.SmoothPlastic,
	})
	-- 프롬프트·글자는 W4 에서 뺐다. 장식 건물만 남고, 용도는 W5·W6 에서 정한다

	-- 장식 기계 느낌: 위에 유리 돔, 앞에 배출구
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

-- 계단 코 줄(i 단 디딤판 앞 끝, 높이 i)을 지나는 직선 위의 점. z 에서의 높이
local function noseY(z: number): number
	return STAIR_RISE + (STAIR_Z_BOTTOM - z) * STAIR_RISE / STAIR_RUN
end

-- 코 줄과 나란한 비스듬한 막대. (x, zFrom) → (x, zTo) 를 잇고 코 줄보다 lift 위
local function slopedBar(
	shell: Model,
	plotCFrame: CFrame,
	name: string,
	x: number,
	zFrom: number,
	zTo: number,
	lift: number,
	size: Vector2,
	opts: BuildKit.Opts
)
	local p0 = Vector3.new(x, noseY(zFrom) + lift, zFrom)
	local p1 = Vector3.new(x, noseY(zTo) + lift, zTo)
	local cf = CFrame.lookAt((p0 + p1) / 2, p1)
	put(shell, name, Vector3.new(size.X, size.Y, (p1 - p0).Magnitude), plotCFrame * cf, opts)
end

--[[
	2층 계단. 단은 바닥부터 꽉 찬 블록(옆에서 봐도 계단)이고 위에 나무 디딤판을 얹는다.
	서쪽(현관 통로 쪽)에 옆판·난간 기둥·손잡이, 동쪽 벽에 벽 손잡이. 2층 구멍 서쪽 가장자리에 안전 난간.
	파트: 단 17 + 디딤판 17 + 옆판 1 + 첫 기둥 2 + 난간 기둥 8 + 손잡이 2 + 2층 난간 4 = 51
]]
local function buildStairs(shell: Model, plotCFrame: CFrame)
	local stairW = STAIR_X1 - STAIR_X0
	local midX = (STAIR_X0 + STAIR_X1) / 2
	local stone = { color = C.stair, material = Enum.Material.Concrete }
	local function wood(collide: boolean): BuildKit.Opts
		return { color = C.tread, material = Enum.Material.Wood, collide = collide }
	end

	for i = 1, STAIR_STEPS do
		local h = STAIR_RISE * i
		local zFront = STAIR_Z_BOTTOM - STAIR_RUN * (i - 1)
		local zMid = zFront - STAIR_RUN / 2
		put(
			shell,
			string.format("Stair%02d", i),
			Vector3.new(stairW, h - TREAD_T, STAIR_RUN),
			plotCFrame * CFrame.new(midX, (h - TREAD_T) / 2, zMid),
			table.clone(stone)
		)
		put(
			shell,
			string.format("Tread%02d", i),
			Vector3.new(stairW, TREAD_T, STAIR_RUN + TREAD_NOSE),
			plotCFrame * CFrame.new(midX, h - TREAD_T / 2, zMid + TREAD_NOSE / 2),
			wood(true)
		)
	end

	-- 서쪽 옆판. 바닥(코 줄이 y 0 인 곳)부터 착지대까지
	local zFloor = STAIR_Z_BOTTOM + STAIR_RUN
	local zTop = STAIRWELL_Z0
	slopedBar(
		shell,
		plotCFrame,
		"StairStringer",
		STAIR_X0 - STRINGER_T / 2,
		zFloor,
		zTop,
		0.5 - STRINGER_H / 2,
		Vector2.new(STRINGER_T, STRINGER_H),
		wood(false)
	)

	-- 난간. 기둥은 디딤판 서쪽 끝에 서고, 손잡이는 코 줄 + RAIL_H
	local railX = STAIR_X0 + BALUSTER_T / 2
	local newelZ = STAIR_Z_BOTTOM - NEWEL_T / 2
	local newelH = STAIR_RISE + RAIL_H + 0.3
	put(
		shell,
		"StairNewel",
		Vector3.new(NEWEL_T, newelH, NEWEL_T),
		plotCFrame * CFrame.new(STAIR_X0 + NEWEL_T / 2, newelH / 2, newelZ),
		wood(true)
	)
	put(
		shell,
		"StairNewelCap",
		Vector3.new(1, 1, 1),
		plotCFrame * CFrame.new(STAIR_X0 + NEWEL_T / 2, newelH + 0.35, newelZ),
		{ color = C.tread, material = Enum.Material.Wood, shape = Enum.PartType.Ball, collide = false }
	)
	for i = 1 + BALUSTER_EVERY, STAIR_STEPS, BALUSTER_EVERY do
		local zMid = STAIR_Z_BOTTOM - STAIR_RUN * (i - 1) - STAIR_RUN / 2
		local h = STAIR_RISE * i
		local postH = noseY(zMid) + RAIL_H - h
		put(
			shell,
			string.format("StairBaluster%02d", i),
			Vector3.new(BALUSTER_T, postH, BALUSTER_T),
			plotCFrame * CFrame.new(railX, h + postH / 2, zMid),
			wood(false)
		)
	end
	slopedBar(shell, plotCFrame, "StairHandrail", railX, newelZ, zTop, RAIL_H, Vector2.new(RAIL_T, RAIL_T), wood(false))
	-- 동쪽 벽 손잡이. 벽 안쪽 면(x 14)에서 0.3 떨어진다
	slopedBar(
		shell,
		plotCFrame,
		"StairWallRail",
		STAIR_X1 - 0.3 - RAIL_T / 2,
		STAIR_Z_BOTTOM,
		zTop,
		RAIL_H,
		Vector2.new(RAIL_T, RAIL_T),
		wood(false)
	)

	-- 2층 안전 난간: 구멍 서쪽 가장자리(x 5) z -10.5~-1(강당 남벽 앞까지). 지붕 위 y 18 에 선다
	local guardZ0, guardZ1 = zTop, STAIRWELL_Z1 - 1
	local guardTop = WALL_H + RAIL_H
	for k, z in { guardZ0 + BALUSTER_T / 2, (guardZ0 + guardZ1) / 2, guardZ1 - BALUSTER_T / 2 } do
		put(
			shell,
			"StairGuardPost" .. k,
			Vector3.new(BALUSTER_T, RAIL_H, BALUSTER_T),
			plotCFrame * CFrame.new(railX, WALL_H + RAIL_H / 2, z),
			wood(true)
		)
	end
	put(
		shell,
		"StairGuardRail",
		Vector3.new(RAIL_T, RAIL_T, guardZ1 - guardZ0),
		plotCFrame * CFrame.new(railX, guardTop, (guardZ0 + guardZ1) / 2),
		wood(true)
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

	-- 바깥 벽등 2(남쪽 문 = 앞마당 쪽). 등은 벽 바깥(+Z)을 본다
	for _, side in { -1, 1 } do
		local at = Vector3.new(ENTRANCE.X + side * (DOOR_W / 2 + LAMP_GAP), LAMP_Y, z1)
		PropLibrary.wallLamp(shell, plotCFrame * CFrame.lookAt(at, at + Vector3.zAxis))
	end

	-- 지붕. 계단 위(x 5~14, z -10.5~0)는 뚫고, 착지대가 z -16.5~-10.5 의 동쪽을 덮는다
	local landingX0 = LANDING.X - LANDING_SIZE.X / 2 -- -5
	roof(shell, "EntranceRoof", plotCFrame, x0 + WALL_T, STAIR_X0, STAIRWELL_Z0, z1 - WALL_T)
	roof(shell, "EntranceRoofNW", plotCFrame, x0 + WALL_T, landingX0, z0 + WALL_T, STAIRWELL_Z0)
	roof(shell, "EntranceRoofSE", plotCFrame, STAIR_X0, x1 - WALL_T, STAIRWELL_Z1, z1 - WALL_T, true)

	buildStairs(shell, plotCFrame)
	put(shell, "Landing", LANDING_SIZE, plotCFrame * CFrame.new(LANDING.X, LANDING.Y - LANDING_SIZE.Y / 2, LANDING.Z), {
		color = C.landing,
		material = Enum.Material.Concrete,
	})

	-- 칭찬스티커판. 서쪽 벽 안쪽 면. 40칸(BOARD_CELLS)은 클라(PadController)가 이 SurfaceGui 에 그린다
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

	local north = solidWall(shell, "Class1WallN", plotCFrame, "X", x0, x1, z0 + inner)
	local west = solidWall(shell, "Class1WallW", plotCFrame, "Z", z0 + WALL_T, z1 - WALL_T, x0 + inner)
	local east = solidWall(shell, "Class1WallE", plotCFrame, "Z", z0 + WALL_T, z1 - WALL_T, x1 - inner)
	local southA, southB = wallWithDoor(shell, "Class1WallS", plotCFrame, "X", x0, x1, CLASS1.X, z1 - inner)
	roof(shell, "Class1Roof", plotCFrame, x0 + WALL_T, x1 - WALL_T, z0 + WALL_T, z1 - WALL_T)

	-- 방 안 디테일(그림 id 0 이면 색 판만). 벽 안쪽 면 아래 띠: 북 +Z(Back)·서 +X(Right)·동 −X(Left)·남 −Z(Front)
	BuildKit.wainscot(north, Enum.NormalId.Back, C.wainscot)
	BuildKit.wainscot(west, Enum.NormalId.Right, C.wainscot)
	BuildKit.wainscot(east, Enum.NormalId.Left, C.wainscot)
	BuildKit.wainscot(southA, Enum.NormalId.Front, C.wainscot)
	BuildKit.wainscot(southB, Enum.NormalId.Front, C.wainscot)
	-- 교실 바닥: 흙마당(FloorBack) 위에 타일 판. 윗면을 0.02 올려 겹침 깜빡임을 피한다. 책상·의자 높이는 그대로
	local floor = put(
		shell,
		"Class1Floor",
		Vector3.new(CLASS1_SIZE.X - WALL_T * 2, FLOOR_T, CLASS1_SIZE.Z - WALL_T * 2),
		plotCFrame * CFrame.new(CLASS1.X, 0.02 - FLOOR_T / 2, CLASS1.Z),
		{ color = C.classFloor, material = Enum.Material.SmoothPlastic }
	)
	BuildKit.floorTile(floor)
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

local function buildYard(shell: Model, plotCFrame: CFrame, plotId: number)
	-- 시드 = 부지 번호 × 100 + 나무 번호. 부지마다 모양이 다르고, 같은 부지는 다시 지어도 같다
	for i, spot in TREES do
		local tree = PropLibrary.tree(shell, plotCFrame * CFrame.new(spot.X, 0, spot.Y), plotId * 100 + i)
		tree.Name = string.format("Tree%02d", i)
	end
	-- 교문 양옆 화단. 시드는 나무와 겹치지 않게 +50
	for i, spot in PlotLayout.FLOWERBEDS do
		local bed = PropLibrary.flowerbed(shell, plotCFrame * CFrame.new(spot.X, 0, spot.Y), plotId * 100 + 50 + i)
		bed.Name = string.format("Flowerbed%02d", i)
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

local function hitbox(folder: Folder, name: string, cf: CFrame, color: Color3): Part
	return put(folder, name, HITBOX_SIZE, cf, {
		color = color,
		material = Enum.Material.SmoothPlastic,
		transparency = 1,
		collide = false,
		cast = false,
	})
end

-- 처음엔 시설이 없어 홈 자리 바닥이 전부 마당(y0)이다. 시설이 서면 PlotService.refreshStickers 가 높이를 맞춘다
local function buildStickers(plot: Model, plotCFrame: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = Keys.STICKERS_FOLDER
	for i, spot in STICKER_SPOTS do
		local sticker = hitbox(
			folder,
			string.format("Sticker%02d", i),
			plotCFrame * CFrame.new(spot.X, HITBOX_SIZE.Y / 2, spot.Y),
			C.sticker
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
	local y = PlotLayout.STAR_FLOOR_Y + HITBOX_SIZE.Y / 2
	for i, spot in STAR_SPOTS do
		local star = hitbox(folder, string.format("Star%02d", i), plotCFrame * CFrame.new(spot.X, y, spot.Y), C.star)
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
	buildYard(shell, plotCFrame, plotId)
	shell.Parent = plot
	-- 클라는 스트리밍으로 파트 일부만 받아도 부지 중심을 알아야 한다(HudController.plotCenter). 피벗은 파트와 달리 늘 복제된다
	plot.WorldPivot = plotCFrame

	buildSpawn(plot, plotCFrame)
	buildPads(plot, plotCFrame)
	buildStickers(plot, plotCFrame)
	buildStars(plot, plotCFrame)

	return plot
end

return PlotShell
