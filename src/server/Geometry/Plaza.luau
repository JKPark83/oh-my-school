--!strict
--[[
	광장. 기획서 §7.3, 계획서 §3.5.

	Plaza.build() 가 돌려주는 Model 하나가 Workspace.Plaza 가 된다. 파트 ≤89(나무 9그루 × ≤5·화단 2 × 4 포함) + 스토어 모델(≤3 × entry.parts), 광장 예산 ≤500.
	  Ground        750×750 잔디. 부지 12곳이 전부 이 위에 얹힌다
	  Boundary ×4   ±375 에 투명 벽(높이 50, CanCollide) — 떨어지지 않게
	  Pavement      가운데 125×125 포장
	  Podium        (0,0) 12×12 높이 2 + 앞 계단
	  Signpost      (8,0) 팻말 + ProximityPrompt "HomePrompt" 「우리 학교로」
	  Leaderboard   (0,20) 16×10 판. SurfaceGui(제목·순위)는 LeaderboardService 가 만든다
	  NoticeBoard   (0,-20) 12×8 판 + 그림문자 4칸(SurfaceGui Frame)
	  Bench ×4      네 모서리, 중심을 보게 돌려 놓는다
	  Tree ×9       잔디에 비대칭으로 흩어 놓은 시드 나무(PropLibrary.tree, 메시 없으면 Tree.luau)
	  Flowerbed ×2  알림판 양옆 포장 위 화단(PropLibrary.flowerbed)
	  Store ×≤3     PropAssets.STORE_MODELS 가 있을 때만 잔디 자리에 비동기로 얹는다(비면 없음)
	  ClockTower    포장 북서쪽 시계탑(파트 4). 멀리서 방향을 잡는 랜드마크

	★ 지면 윗면은 y=-0.05 다. 부지 바닥(윗면 y=0, 두께 1)이 이 위에 겹치므로 면이 같으면 떨린다.
	  광장 물건은 전부 GROUND_TOP 기준으로 얹는다.
]]

local BuildKit = require(script.Parent.Parent.BuildKit)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)
local PropLibrary = require(script.Parent.PropLibrary)

local Plaza = {}

local TEXT_HOME = "우리 학교로"
local BOUNDARY = "Boundary"
local NOTICE_BOARD = "NoticeBoard"
local PROMPT_DISTANCE = 8

local GROUND_HALF = 375
local GROUND_T = 1
local GROUND_TOP = -0.05
local BOUNDARY_H = 50
local PAVEMENT_HALF = 62.5
local PAVEMENT_T = 0.2

local PODIUM_SIZE = Vector3.new(12, 2, 12)
local SIGNPOST = Vector3.new(8, 0, 0)
local LEADERBOARD_POS = Vector3.new(0, 0, 20)
local LEADERBOARD_SIZE = Vector3.new(16, 10, 0.8)
local NOTICE_POS = Vector3.new(0, 0, -20)
local NOTICE_SIZE = Vector3.new(12, 8, 0.8)
local BOARD_LIFT = 2.2 -- 판 아랫면 높이(기둥 위)
local BENCH_R = 50 -- 벤치 네 개 (±R, ±R)

-- 나무 9그루. 광장 잔디(포장 밖, 부지 사이 |x|,|z| < 195)에 흩어 놓는다.
-- 거울 대칭·등간격을 피하고, 교문 8곳에서 연단으로 오는 직선(각도 ±24.8°·±65.2° 계열)은 비워 둔다
local TREE_SPOTS = {
	Vector2.new(110, 6),
	Vector2.new(100, 112),
	Vector2.new(3, 85),
	Vector2.new(-20, 159),
	Vector2.new(-89, 80),
	Vector2.new(-95, -5),
	Vector2.new(-123, -110),
	Vector2.new(5, -130),
	Vector2.new(74, -67),
}
local TREE_SEED = 900 -- 부지 나무(plotId×100+i, ≤1202)와 겹치지 않게 시드를 띄운다

-- 화단 2. 알림판(0,-20, 폭 12) 양옆 포장 위
local FLOWERBED_SPOTS = { Vector2.new(-10, -20), Vector2.new(10, -20) }
local FLOWERBED_SEED = 1300 -- 부지 화단(plotId×100+50+i, ≤1252)과도 겹치지 않게

-- Creator Store 모델 자리 ≤3. 잔디 바깥쪽, 나무·교문 직선과 떨어진 곳
local STORE_SPOTS = { Vector2.new(145, 138), Vector2.new(-140, 150), Vector2.new(-152, -140) }

-- 시계탑. 포장 북서쪽에 하나만 둬서 어느 쪽이 북서인지 멀리서도 알 수 있다
local CLOCK_POS = Vector3.new(-38, 0, -42)
local CLOCK_BASE = Vector3.new(7, 3, 7) -- 기둥(받침)
local CLOCK_BODY = Vector3.new(5, 20, 5)
local CLOCK_FACE_D = 4
local CLOCK_ROOF = Vector3.new(6.5, 2.5, 6.5)

local P = WorldPalette
local C = {
	grass = P.plazaLawn,
	pavement = P.plazaPavement,
	podium = P.podium,
	podiumStep = P.podiumStep,
	post = P.wood,
	signBoard = P.signBoard,
	signText = P.darkText,
	leaderboard = P.boardDark,
	notice = P.notice,
	noticeCell = P.noticeCell,
	steel = P.boardPost,
	benchWood = P.benchWood,
	benchLeg = P.benchLeg,
	clockBase = P.stone,
	clockBody = P.wall,
	clockFace = P.clockFace,
	clockRoof = P.roof.clockTower,
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
	-- TODO(통합): 4칸 그림문자(구매·수집·층 쌓기·꾸미기)는 클라가 ImageLabel 로 채우거나 파트로 그린다
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

-- 시계탑 파트 4개: 받침 기둥·몸통·시계면·지붕. 시계면은 연단(원점) 쪽을 본다
local function buildClockTower(model: Model)
	local rot = CFrame.lookAt(Vector3.new(CLOCK_POS.X, 0, CLOCK_POS.Z), Vector3.new(0, 0, 0)).Rotation
	local function at(y: number, forward: number?): CFrame
		return CFrame.new(CLOCK_POS.X, GROUND_TOP + PAVEMENT_T + y, CLOCK_POS.Z)
			* rot
			* CFrame.new(0, 0, -(forward or 0))
	end
	put(model, "ClockTowerBase", CLOCK_BASE, at(CLOCK_BASE.Y / 2), {
		color = C.clockBase,
		material = Enum.Material.Concrete,
	})
	local bodyBottom = CLOCK_BASE.Y
	put(model, "ClockTowerBody", CLOCK_BODY, at(bodyBottom + CLOCK_BODY.Y / 2), {
		color = C.clockBody,
		material = Enum.Material.Concrete,
	})
	-- 원판: Cylinder 축(X)을 앞(-Z)으로 돌려 몸통 앞면에 0.1 내밀어 붙인다
	local faceT = 0.4
	local faceY = bodyBottom + CLOCK_BODY.Y - CLOCK_FACE_D / 2 - 1.5
	put(
		model,
		"ClockTowerFace",
		Vector3.new(faceT, CLOCK_FACE_D, CLOCK_FACE_D),
		at(faceY, CLOCK_BODY.Z / 2 + faceT / 2 - 0.1) * CFrame.Angles(0, math.pi / 2, 0),
		{
			color = C.clockFace,
			material = Enum.Material.SmoothPlastic,
			shape = Enum.PartType.Cylinder,
			collide = false,
		}
	)
	put(model, "ClockTowerRoof", CLOCK_ROOF, at(bodyBottom + CLOCK_BODY.Y + CLOCK_ROOF.Y / 2), {
		color = C.clockRoof,
		material = Enum.Material.SmoothPlastic,
	})
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

	buildClockTower(model)

	local corners = { Vector2.new(1, 1), Vector2.new(-1, 1), Vector2.new(-1, -1), Vector2.new(1, -1) }
	for i, c in corners do
		buildBench(model, i, c.X * BENCH_R, c.Y * BENCH_R)
	end
	for i, spot in TREE_SPOTS do
		local tree = PropLibrary.tree(model, CFrame.new(spot.X, GROUND_TOP, spot.Y), TREE_SEED + i)
		tree.Name = string.format("Tree%02d", i)
	end
	for i, spot in FLOWERBED_SPOTS do
		local bed =
			PropLibrary.flowerbed(model, CFrame.new(spot.X, GROUND_TOP + PAVEMENT_T, spot.Y), FLOWERBED_SEED + i)
		bed.Name = string.format("Flowerbed%02d", i)
	end
	-- 스토어 모델은 LoadAsset 이 기다리므로 광장 부팅을 막지 않게 따로 돈다. 목록이 비면 아무것도 안 한다
	if #PropAssets.STORE_MODELS > 0 then
		task.spawn(function()
			for i, entry in PropAssets.STORE_MODELS do
				if i > #STORE_SPOTS then
					break
				end
				local spot = STORE_SPOTS[i]
				local store = PropLibrary.storeModel(model, entry, CFrame.new(spot.X, GROUND_TOP, spot.Y))
				if store then
					store.Name = string.format("Store%02d", i)
				end
			end
		end)
	end

	return model
end

return Plaza
