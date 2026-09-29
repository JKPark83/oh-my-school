--!strict
--[[
	광장. 기획서 §7.3, 계획서 §3.5.

	Plaza.build() 가 돌려주는 Model 하나가 Workspace.Plaza 가 된다. 파트 40개(≤60), 전부 BuildKit.part.
	  Ground        600×600 잔디. 부지 12곳이 전부 이 위에 얹힌다
	  Boundary ×4   ±300 에 투명 벽(높이 50, CanCollide) — 떨어지지 않게
	  Pavement      가운데 100×100 포장
	  Podium        (0,0) 12×12 높이 2 + 앞 계단
	  Signpost      (8,0) 팻말 + ProximityPrompt "HomePrompt" 「우리 학교로」
	  Leaderboard   (0,20) 16×10 판. SurfaceGui(제목·순위)는 LeaderboardService 가 만든다
	  NoticeBoard   (0,-20) 12×8 판 + 그림문자 4칸(SurfaceGui Frame)
	  Bench ×4      네 모서리, 중심을 보게 돌려 놓는다
	  Tree ×4       벤치 바깥

	★ 지면 윗면은 y=-0.05 다. 부지 바닥(윗면 y=0, 두께 1)이 이 위에 겹치므로 면이 같으면 떨린다.
	  광장 물건은 전부 GROUND_TOP 기준으로 얹는다.
]]

local BuildKit = require(script.Parent.Parent.BuildKit)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Keys = require(ReplicatedStorage.Shared.Config.Keys)

local Plaza = {}

local TEXT_HOME = "우리 학교로"
local BOUNDARY = "Boundary"
local NOTICE_BOARD = "NoticeBoard"
local PROMPT_DISTANCE = 8

local GROUND_HALF = 300
local GROUND_T = 1
local GROUND_TOP = -0.05
local BOUNDARY_H = 50
local PAVEMENT_HALF = 50
local PAVEMENT_T = 0.2

local PODIUM_SIZE = Vector3.new(12, 2, 12)
local SIGNPOST = Vector3.new(8, 0, 0)
local LEADERBOARD_POS = Vector3.new(0, 0, 20)
local LEADERBOARD_SIZE = Vector3.new(16, 10, 0.8)
local NOTICE_POS = Vector3.new(0, 0, -20)
local NOTICE_SIZE = Vector3.new(12, 8, 0.8)
local BOARD_LIFT = 2.2 -- 판 아랫면 높이(기둥 위)
local BENCH_R = 40 -- 벤치 네 개 (±R, ±R)
local TREE_R = 70

local C = {
	grass = Color3.fromRGB(98, 140, 64),
	pavement = Color3.fromRGB(170, 170, 168),
	podium = Color3.fromRGB(196, 190, 178),
	podiumStep = Color3.fromRGB(176, 170, 158),
	post = Color3.fromRGB(96, 70, 44),
	signBoard = Color3.fromRGB(236, 230, 214),
	signText = Color3.fromRGB(40, 40, 44),
	leaderboard = Color3.fromRGB(34, 48, 78),
	notice = Color3.fromRGB(150, 108, 66),
	noticeCell = Color3.fromRGB(236, 226, 200),
	steel = Color3.fromRGB(110, 112, 116),
	benchWood = Color3.fromRGB(140, 100, 62),
	benchLeg = Color3.fromRGB(60, 62, 66),
	trunk = Color3.fromRGB(110, 80, 50),
	leaves = Color3.fromRGB(64, 116, 52),
}

-- 월드 CFrame 하나로 파트를 놓는다. BuildKit.part 는 위치·회전을 따로 받으므로 여기서 나눈다
local function put(parent: Instance, name: string, size: Vector3, cf: CFrame, opts: BuildKit.Opts): Part
	opts.cframe = cf.Rotation
	return BuildKit.part(parent, name, size, cf.Position, opts)
end

-- 바닥에 놓는 물건. 아랫면이 GROUND_TOP + lift 에 온다
local function onGround(x: number, z: number, height: number, lift: number?): CFrame
	return CFrame.new(x, GROUND_TOP + (lift or 0) + height / 2, z)
end

local function buildGround(model: Model)
	put(
		model,
		"Ground",
		Vector3.new(GROUND_HALF * 2, GROUND_T, GROUND_HALF * 2),
		CFrame.new(0, GROUND_TOP - GROUND_T / 2, 0),
		{
			color = C.grass,
			material = Enum.Material.Grass,
		}
	)
	put(model, "Pavement", Vector3.new(PAVEMENT_HALF * 2, PAVEMENT_T, PAVEMENT_HALF * 2), onGround(0, 0, PAVEMENT_T), {
		color = C.pavement,
		material = Enum.Material.Concrete,
	})

	local wallOpts =
		{ color = C.grass, material = Enum.Material.SmoothPlastic, transparency = 1, collide = true, cast = false }
	local y = GROUND_TOP + BOUNDARY_H / 2
	local long = GROUND_HALF * 2
	put(model, BOUNDARY, Vector3.new(long, BOUNDARY_H, 1), CFrame.new(0, y, GROUND_HALF), table.clone(wallOpts))
	put(model, BOUNDARY, Vector3.new(long, BOUNDARY_H, 1), CFrame.new(0, y, -GROUND_HALF), table.clone(wallOpts))
	put(model, BOUNDARY, Vector3.new(1, BOUNDARY_H, long), CFrame.new(GROUND_HALF, y, 0), table.clone(wallOpts))
	put(model, BOUNDARY, Vector3.new(1, BOUNDARY_H, long), CFrame.new(-GROUND_HALF, y, 0), table.clone(wallOpts))
end

local function buildPodium(model: Model)
	put(model, "Podium", PODIUM_SIZE, onGround(0, 0, PODIUM_SIZE.Y, PAVEMENT_T), {
		color = C.podium,
		material = Enum.Material.Concrete,
	})
	-- 남쪽(+Z) 앞 계단 한 단. 높이 1 이라 Humanoid 가 그냥 올라간다
	put(model, "PodiumStep", Vector3.new(6, 1, 3), onGround(0, PODIUM_SIZE.Z / 2 + 1.5, 1, PAVEMENT_T), {
		color = C.podiumStep,
		material = Enum.Material.Concrete,
	})
end

local function buildSignpost(model: Model)
	local poleH = 4
	local boardSize = Vector3.new(3, 2, 0.3)
	put(model, "SignpostPole", Vector3.new(0.4, poleH, 0.4), onGround(SIGNPOST.X, SIGNPOST.Z, poleH, PAVEMENT_T), {
		color = C.post,
		material = Enum.Material.Wood,
	})
	local board =
		put(model, Keys.SIGNPOST, boardSize, onGround(SIGNPOST.X, SIGNPOST.Z, boardSize.Y, PAVEMENT_T + poleH), {
			color = C.signBoard,
			material = Enum.Material.Wood,
		})
	BuildKit.surfaceText(board, Enum.NormalId.Front, TEXT_HOME, C.signText, 0.45)
	BuildKit.surfaceText(board, Enum.NormalId.Back, TEXT_HOME, C.signText, 0.45)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = Keys.HOME_PROMPT
	prompt.ActionText = TEXT_HOME
	prompt.ObjectText = ""
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	-- TODO(통합): 클라가 72px 커스텀 프롬프트를 그리면 Style = Custom 으로 바꾼다(기획서 §8.3)
	prompt.Parent = board
end

-- 판 하나 + 기둥 둘. 판을 돌려준다
local function standingBoard(
	model: Model,
	name: string,
	pos: Vector3,
	size: Vector3,
	color: Color3,
	material: Enum.Material
): Part
	local postH = BOARD_LIFT + size.Y - 0.5
	local postOpts = { color = C.steel, material = Enum.Material.Metal }
	local dx = size.X / 2 - 0.6
	put(
		model,
		name .. "PostW",
		Vector3.new(0.5, postH, 0.5),
		onGround(pos.X - dx, pos.Z, postH, PAVEMENT_T),
		table.clone(postOpts)
	)
	put(
		model,
		name .. "PostE",
		Vector3.new(0.5, postH, 0.5),
		onGround(pos.X + dx, pos.Z, postH, PAVEMENT_T),
		table.clone(postOpts)
	)
	return put(
		model,
		name,
		size,
		onGround(pos.X, pos.Z, size.Y, PAVEMENT_T + BOARD_LIFT),
		{ color = color, material = material }
	)
end

local function buildLeaderboard(model: Model)
	-- 판만 세운다. 연단 쪽(-Z) 면의 제목과 순위 줄은 LeaderboardService 가 한 SurfaceGui 에 모두 그린다
	standingBoard(
		model,
		Keys.LEADERBOARD,
		LEADERBOARD_POS,
		LEADERBOARD_SIZE,
		C.leaderboard,
		Enum.Material.SmoothPlastic
	)
end

local function buildNoticeBoard(model: Model)
	local board = standingBoard(model, NOTICE_BOARD, NOTICE_POS, NOTICE_SIZE, C.notice, Enum.Material.Wood)
	-- 연단 쪽(+Z) 면에 그림문자 자리 4칸. 글자는 없다(기획서 §7.3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1
	gui.Parent = board
	for i = 1, 4 do
		local cell = Instance.new("Frame")
		cell.Name = string.format("Cell%02d", i)
		cell.Size = UDim2.fromScale(0.2, 0.62)
		cell.Position = UDim2.fromScale(0.05 + (i - 1) * 0.235, 0.19)
		cell.BackgroundColor3 = C.noticeCell
		cell.BorderSizePixel = 0
		cell.Parent = gui
	end
	-- TODO(통합): 4칸 그림문자(구매·수집·졸업·스킨)는 클라가 ImageLabel 로 채우거나 파트로 그린다
end

local function buildBench(model: Model, index: number, x: number, z: number)
	-- 광장 중심을 보게 돌린다. 등받이가 바깥(-Z 가 중심 쪽)
	local base = Vector3.new(x, GROUND_TOP, z)
	local rot = CFrame.lookAt(base, Vector3.new(0, GROUND_TOP, 0)).Rotation
	local function place(offset: Vector3): CFrame
		return CFrame.new(base) * rot * CFrame.new(offset)
	end
	local prefix = string.format("Bench%02d", index)
	local seatH, legH = 0.3, 1.4
	put(model, prefix .. "Seat", Vector3.new(6, seatH, 1.8), place(Vector3.new(0, legH + seatH / 2, 0)), {
		color = C.benchWood,
		material = Enum.Material.Wood,
	})
	put(model, prefix .. "Back", Vector3.new(6, 1.6, 0.3), place(Vector3.new(0, legH + seatH + 0.8, 0.75)), {
		color = C.benchWood,
		material = Enum.Material.Wood,
	})
	local legOpts = { color = C.benchLeg, material = Enum.Material.Metal }
	put(
		model,
		prefix .. "LegW",
		Vector3.new(0.3, legH, 1.6),
		place(Vector3.new(-2.5, legH / 2, 0)),
		table.clone(legOpts)
	)
	put(
		model,
		prefix .. "LegE",
		Vector3.new(0.3, legH, 1.6),
		place(Vector3.new(2.5, legH / 2, 0)),
		table.clone(legOpts)
	)
end

local function buildTree(model: Model, index: number, x: number, z: number)
	local trunkH, canopyD = 6, 9
	put(model, string.format("Tree%02dTrunk", index), Vector3.new(1.4, trunkH, 1.4), onGround(x, z, trunkH), {
		color = C.trunk,
		material = Enum.Material.Wood,
	})
	put(
		model,
		string.format("Tree%02dCanopy", index),
		Vector3.new(canopyD, canopyD, canopyD),
		onGround(x, z, canopyD, trunkH - 1.5),
		{
			color = C.leaves,
			material = Enum.Material.Grass,
			shape = Enum.PartType.Ball,
			collide = false,
		}
	)
end

--- 광장 전체. 돌려준 Model 을 호출자가 Workspace 에 넣는다(여기서는 Parent 를 잡지 않는다)
function Plaza.build(): Model
	local model = Instance.new("Model")
	model.Name = Keys.PLAZA

	buildGround(model)
	buildPodium(model)
	buildSignpost(model)
	buildLeaderboard(model)
	buildNoticeBoard(model)

	local corners = { Vector2.new(1, 1), Vector2.new(-1, 1), Vector2.new(-1, -1), Vector2.new(1, -1) }
	for i, c in corners do
		buildBench(model, i, c.X * BENCH_R, c.Y * BENCH_R)
		buildTree(model, i, c.X * TREE_R, c.Y * TREE_R)
	end

	return model
end

return Plaza
