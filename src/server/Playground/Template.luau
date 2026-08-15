--!nonstrict
--[[
	운동장 허브. 잠입 구간이 아니라 안전한 로비다.

	좌표 규약은 교실과 같다:
	  -Z = 본관(학교 건물)   +Z = 운동장 뒤편
	  y = 0 이 땅 윗면

	★ 스폰에서 첫 시야에 본관 정면이 들어와야 한다.
	  SpawnLocation 의 LookVector 는 로컬 -Z 이므로, 회전 없는 CFrame 이면
	  그대로 -Z(본관)를 본다. 여기를 건드리면 "학교에 왔다"는 첫인상이 날아간다.

	★ 허브는 원점에 짓는다. 교실 슬롯은 x = 10000 부터라 절대 겹치지 않는다.
	  Phase 4 에서 슬롯 원점을 10000 으로 민 것이 바로 이 자리를 비워두기 위해서였다.

	교실 템플릿과 마찬가지로 아트 에셋을 쓰지 않는다. 전부 파트다.
]]

local BuildKit = require(script.Parent.Parent.BuildKit)

local part = BuildKit.part
local surfaceText = BuildKit.surfaceText

local Template = {}

-- ── 치수 ──────────────────────────────────────────────────────────
local GROUND_HALF_X = 120
local GROUND_Z_MIN, GROUND_Z_MAX = -80, 100

local FACADE_Z = -80 -- 본관 정면 벽면
local FACADE_HALF_X = 80
local FACADE_H = 44
local DOOR_HALF_W = 9
local DOOR_H = 13

local LOBBY_Z_END = -112 -- 로비 안쪽 벽
local LOBBY_HALF_X = 32
local LOBBY_H = 15

local SPAWN_Z = 40 -- 운동장 한가운데. 본관까지 120 스터드 — 건물이 한눈에 들어온다

-- ── 색 ────────────────────────────────────────────────────────────
local C = {
	dirt = Color3.fromRGB(196, 164, 118), -- 마사토 운동장
	line = Color3.fromRGB(238, 238, 232),
	grass = Color3.fromRGB(104, 148, 78),
	concrete = Color3.fromRGB(202, 198, 188),
	wall = Color3.fromRGB(226, 214, 190), -- 본관 외벽. 미색 타일
	trim = Color3.fromRGB(168, 146, 112),
	glass = Color3.fromRGB(178, 208, 224),
	metal = Color3.fromRGB(126, 130, 136),
	wood = Color3.fromRGB(186, 146, 96),
	locker = Color3.fromRGB(158, 160, 156),
	floor = Color3.fromRGB(210, 206, 196), -- 로비 타일
	dark = Color3.fromRGB(48, 48, 52),
	sign = Color3.fromRGB(28, 60, 108),
}

-- ── 운동장 ────────────────────────────────────────────────────────
local function buildGround(parent: Instance)
	local depth = GROUND_Z_MAX - GROUND_Z_MIN
	local centerZ = (GROUND_Z_MAX + GROUND_Z_MIN) / 2

	part(parent, "Ground", Vector3.new(GROUND_HALF_X * 2, 2, depth), Vector3.new(0, -1, centerZ), {
		color = C.dirt,
		material = Enum.Material.Sand,
	})

	-- 가장자리 잔디 화단. 흙바닥만 있으면 공터로 보인다
	for _, sign in { -1, 1 } do
		part(
			parent,
			`Hedge{sign}`,
			Vector3.new(6, 1.6, depth - 20),
			Vector3.new(sign * (GROUND_HALF_X - 3), 0.8, centerZ),
			{
				color = C.grass,
				material = Enum.Material.Grass,
			}
		)
	end

	--[[
		트랙 흰 선. 직선 네 개로 사각 트랙을 그린다.
		타원 트랙은 파트로 그리면 조각 수가 폭발하는데, 운동장이라는 인상은
		"흙바닥에 흰 선"만으로 충분히 선다.
	]]
	local TRACK_X, TRACK_Z1, TRACK_Z2 = 84, -20, 76
	for _, sign in { -1, 1 } do
		part(
			parent,
			`TrackSideX{sign}`,
			Vector3.new(0.8, 0.1, TRACK_Z2 - TRACK_Z1),
			Vector3.new(sign * TRACK_X, 0.05, (TRACK_Z1 + TRACK_Z2) / 2),
			{
				color = C.line,
				collide = false,
				cast = false,
			}
		)
		local z = if sign < 0 then TRACK_Z1 else TRACK_Z2
		part(parent, `TrackSideZ{sign}`, Vector3.new(TRACK_X * 2, 0.1, 0.8), Vector3.new(0, 0.05, z), {
			color = C.line,
			collide = false,
			cast = false,
		})
	end
end

-- ── 본관 ──────────────────────────────────────────────────────────
local function buildFacade(parent: Instance)
	local wall = { color = C.wall, material = Enum.Material.Brick }

	-- 정면 벽. 현관 구멍만 비운다
	local sideW = FACADE_HALF_X - DOOR_HALF_W
	for _, sign in { -1, 1 } do
		part(
			parent,
			`FacadeSide{sign}`,
			Vector3.new(sideW, FACADE_H, 2),
			Vector3.new(sign * (DOOR_HALF_W + sideW / 2), FACADE_H / 2, FACADE_Z),
			wall
		)
	end
	part(
		parent,
		"FacadeHeader",
		Vector3.new(DOOR_HALF_W * 2, FACADE_H - DOOR_H, 2),
		Vector3.new(0, DOOR_H + (FACADE_H - DOOR_H) / 2, FACADE_Z),
		wall
	)

	-- 층을 구분하는 띠. 이게 없으면 그냥 벽 한 장이다
	for floor = 1, 3 do
		part(
			parent,
			`FacadeBand{floor}`,
			Vector3.new(FACADE_HALF_X * 2, 1.2, 2.6),
			Vector3.new(0, floor * 13 - 1, FACADE_Z),
			{
				color = C.trim,
				material = Enum.Material.Concrete,
				collide = false,
			}
		)
	end

	-- 창문 격자. 3층 x 좌우 5칸씩
	for floor = 1, 3 do
		local y = floor * 13 + 4.5
		for i = -5, 5 do
			if i == 0 then
				continue -- 현관 위는 비워둔다
			end
			local x = i * 13
			part(parent, `Window{floor}_{i}`, Vector3.new(9, 6, 0.4), Vector3.new(x, y, FACADE_Z - 1.1), {
				color = C.glass,
				material = Enum.Material.Glass,
				transparency = 0.35,
				collide = false,
				cast = false,
			})
			part(parent, `WindowFrame{floor}_{i}`, Vector3.new(9.8, 6.8, 0.3), Vector3.new(x, y, FACADE_Z - 0.9), {
				color = C.line,
				material = Enum.Material.Metal,
				collide = false,
				cast = false,
			})
		end
	end

	-- 옥상 난간
	part(parent, "Parapet", Vector3.new(FACADE_HALF_X * 2, 3, 2.4), Vector3.new(0, FACADE_H + 1.5, FACADE_Z), {
		color = C.trim,
		material = Enum.Material.Concrete,
	})

	-- 현관 캐노피 + 계단
	part(parent, "Canopy", Vector3.new(28, 0.8, 10), Vector3.new(0, DOOR_H + 0.4, FACADE_Z + 5), {
		color = C.concrete,
		material = Enum.Material.Concrete,
	})
	for _, sign in { -1, 1 } do
		part(
			parent,
			`CanopyPost{sign}`,
			Vector3.new(0.9, DOOR_H, 0.9),
			Vector3.new(sign * 12, DOOR_H / 2, FACADE_Z + 9),
			{
				color = C.concrete,
				material = Enum.Material.Concrete,
			}
		)
	end
	for i = 1, 3 do
		part(parent, `EntranceStep{i}`, Vector3.new(26, 0.6, 2), Vector3.new(0, i * 0.6 - 0.3, FACADE_Z + 10 - i * 2), {
			color = C.concrete,
			material = Enum.Material.Concrete,
		})
	end

	-- 학교 간판. 첫 시야에서 읽혀야 하는 유일한 글자다
	local sign = part(parent, "SchoolSign", Vector3.new(34, 5, 0.5), Vector3.new(0, DOOR_H + 5.5, FACADE_Z - 1.2), {
		color = Color3.fromRGB(248, 246, 240),
		collide = false,
		cast = false,
	})
	surfaceText(sign, Enum.NormalId.Front, "<b>행복초등학교</b>", C.sign, 1.5)
end

--[[
	현관 로비. 신발장과 문구점(상점)이 있는 곳이고, 교실로 들어가는 입구다.

	@return 신발장 파트, 상점 매대 3개(업그레이드 키 순서대로)
]]
local function buildLobby(parent: Instance): (BasePart, { BasePart })
	local depth = FACADE_Z - LOBBY_Z_END
	local centerZ = (FACADE_Z + LOBBY_Z_END) / 2
	-- 로비는 운동장에서 유일하게 닫힌 공간이라, 여기서만 벽이 카메라를 가린다
	local wall = { color = C.wall, material = Enum.Material.Plaster, fade = true }

	part(parent, "LobbyFloor", Vector3.new(LOBBY_HALF_X * 2, 1, depth), Vector3.new(0, -0.5, centerZ), {
		color = C.floor,
		material = Enum.Material.Pebble,
	})
	part(parent, "LobbyCeiling", Vector3.new(LOBBY_HALF_X * 2, 1, depth), Vector3.new(0, LOBBY_H, centerZ), {
		color = C.wall,
		material = Enum.Material.Concrete,
		fade = true,
	})
	part(
		parent,
		"LobbyBack",
		Vector3.new(LOBBY_HALF_X * 2, LOBBY_H, 1.5),
		Vector3.new(0, LOBBY_H / 2, LOBBY_Z_END),
		wall
	)
	for _, sign in { -1, 1 } do
		part(
			parent,
			`LobbySide{sign}`,
			Vector3.new(1.5, LOBBY_H, depth),
			Vector3.new(sign * LOBBY_HALF_X, LOBBY_H / 2, centerZ),
			wall
		)
	end

	-- 로비 조명
	for _, z in { FACADE_Z - 8, LOBBY_Z_END + 8 } do
		local lamp = part(parent, "LobbyLight", Vector3.new(12, 0.3, 1.2), Vector3.new(0, LOBBY_H - 0.5, z), {
			color = Color3.fromRGB(255, 252, 238),
			material = Enum.Material.Neon,
			collide = false,
			cast = false,
		})
		local light = Instance.new("PointLight")
		light.Brightness = 1.0
		-- Range 는 도달 거리가 아니라 딱 끊기는 경계선이다. 40 이면 로비 안쪽
		-- 두 구석(약 43)이 잘려 어두운 쐐기가 생긴다. 교실과 같은 문제였다.
		light.Range = 48
		--[[
			★ Shadows = false 로 두면 벽을 그냥 통과한다.
			  이 등은 로비 안(z=-88, -104)에 있는데 Range 가 48 이라, 그림자를
			  끈 상태에서는 본관 벽을 뚫고 운동장 z=-40 근처까지 빛을 뿌렸다.
			  현관 앞이 이유 없이 밝던 것이 이것이다.

			  그림자를 켜면 벽이 빛을 막고, 현관 구멍으로만 빛이 새어 나온다 —
			  그게 원래 의도한 그림이다. 게다가 신발장 칸마다 그늘이 져야
			  칸이 "구멍"으로 읽힌다. 그림자 없이는 평평한 판때기로 보인다.
			  그림자 지는 광원은 이 둘뿐이라 비용도 문제되지 않는다.
		]]
		light.Shadows = true
		light.Parent = lamp
	end

	-- 안쪽 벽 계단(교실로 올라가는 길). 실제로 올라가지는 않는다 — 전환은 신발장이 한다
	for i = 1, 5 do
		part(
			parent,
			`LobbyStair{i}`,
			Vector3.new(20, 0.8, 1.8),
			Vector3.new(0, i * 0.8 - 0.4, LOBBY_Z_END + 1 + (6 - i) * 1.8),
			{
				color = C.concrete,
				material = Enum.Material.Concrete,
			}
		)
	end

	--[[
		── 신발장 (왼쪽 벽) ──

		★ 원래 칸막이와 선반이 x = -LOBBY_HALF_X + 1 에 있었다. 그런데 몸통은
		  x = -31 ~ -28 을 차지하는 꽉 찬 덩어리였고, 앞면은 -28 이다.
		  즉 칸막이가 전부 몸통 "안쪽"에 파묻혀 있었다 — 그래서 밖에서 보면
		  회색 판때기 한 장이었다.

		  이번에는 순서를 뒤집었다. 뒤판을 어둡게 한 장 세우고, 칸막이와 선반을
		  그 앞으로 튀어나오게 짠다. 신발장이 신발장처럼 보이는 이유는
		  칸이 아니라 "칸 안의 그늘"이다. 어두운 뒤판 + 광원 그림자, 이 둘이 있어야
		  칸이 구멍으로 읽힌다.
	]]
	local RACK_BACK_X = -LOBBY_HALF_X + 1 -- 뒤판. 벽에 붙는다
	local RACK_FRONT_X = -LOBBY_HALF_X + 4 -- 앞면. 로비 쪽
	local RACK_DEPTH = RACK_FRONT_X - RACK_BACK_X
	local RACK_MID_X = (RACK_BACK_X + RACK_FRONT_X) / 2
	local RACK_LEN, RACK_TOP = 26, 9
	local COLS, ROWS = 13, 4

	-- 칸 내부 높이. 밑에 걸레받이, 위에 천판이 각각 한 겹씩 먹는다
	local INNER_BOTTOM, INNER_TOP = 0.5, RACK_TOP - 0.4
	local ROW_H = (INNER_TOP - INNER_BOTTOM) / ROWS
	local COL_W = RACK_LEN / COLS
	local RACK_Z0 = centerZ - RACK_LEN / 2

	local frame = { color = C.locker, material = Enum.Material.SmoothPlastic }

	-- 뒤판. 어두워야 칸이 깊어 보인다
	part(
		parent,
		"ShoeRackBack",
		Vector3.new(0.5, RACK_TOP, RACK_LEN),
		Vector3.new(RACK_BACK_X, RACK_TOP / 2, centerZ),
		{
			color = C.dark,
			material = Enum.Material.SmoothPlastic,
		}
	)
	part(
		parent,
		"ShoeRackKick",
		Vector3.new(RACK_DEPTH, INNER_BOTTOM, RACK_LEN),
		Vector3.new(RACK_MID_X, INNER_BOTTOM / 2, centerZ),
		frame
	)
	part(
		parent,
		"ShoeRackTop",
		Vector3.new(RACK_DEPTH + 0.3, RACK_TOP - INNER_TOP, RACK_LEN + 0.3),
		Vector3.new(RACK_MID_X, (RACK_TOP + INNER_TOP) / 2, centerZ),
		frame
	)

	for row = 1, ROWS - 1 do
		part(
			parent,
			`ShoeRackShelf{row}`,
			Vector3.new(RACK_DEPTH, 0.2, RACK_LEN),
			Vector3.new(RACK_MID_X, INNER_BOTTOM + row * ROW_H, centerZ),
			{ color = C.locker, material = Enum.Material.SmoothPlastic, collide = false }
		)
	end
	for col = 0, COLS do
		part(
			parent,
			`ShoeRackDivider{col}`,
			Vector3.new(RACK_DEPTH, INNER_TOP - INNER_BOTTOM, 0.2),
			Vector3.new(RACK_MID_X, (INNER_BOTTOM + INNER_TOP) / 2, RACK_Z0 + col * COL_W),
			{ color = C.locker, material = Enum.Material.SmoothPlastic, collide = false }
		)
	end

	--[[
		실내화. 칸을 다 채우면 창고가 되고, 다 비우면 폐교가 된다.
		띄엄띄엄 빈 칸이 있어야 "지금 애들이 교실에 있는 학교"로 보인다.
		난수 대신 규칙식을 쓴다 — 서버가 재시작해도 같은 그림이어야 하고,
		운동장은 세션마다 다시 지어질 이유가 없는 곳이다.
	]]
	local SHOE_COLORS = {
		Color3.fromRGB(238, 238, 232), -- 흰 실내화
		Color3.fromRGB(212, 224, 236),
		Color3.fromRGB(236, 212, 216),
		Color3.fromRGB(224, 226, 210),
	}
	for row = 0, ROWS - 1 do
		for col = 0, COLS - 1 do
			if (col * 7 + row * 3) % 5 >= 3 then
				continue -- 빈 칸
			end
			part(
				parent,
				`ShoeRackShoes{row}_{col}`,
				Vector3.new(RACK_DEPTH - 0.9, ROW_H * 0.32, COL_W * 0.6),
				Vector3.new(RACK_MID_X - 0.2, INNER_BOTTOM + row * ROW_H + ROW_H * 0.26, RACK_Z0 + (col + 0.5) * COL_W),
				{
					color = SHOE_COLORS[(col + row) % #SHOE_COLORS + 1],
					material = Enum.Material.Fabric,
					collide = false,
					cast = false,
				}
			)
		end
	end

	--[[
		ProximityPrompt 를 달 자리. 프롬프트는 붙은 파트의 중심에 뜨는데,
		몸통 파트에 달면 신발장 속에서 뜬다. 앞면 바로 앞 가슴 높이에
		보이지 않는 파트를 하나 두고 거기에 단다.
	]]
	local rack = part(parent, "ShoeRack", Vector3.new(1, 1, 1), Vector3.new(RACK_FRONT_X + 1, 4.5, centerZ), {
		color = C.locker,
		transparency = 1,
		collide = false,
		cast = false,
	})

	local rackSign =
		part(parent, "ShoeRackSign", Vector3.new(0.1, 2, 8), Vector3.new(-LOBBY_HALF_X + 0.9, 11, centerZ), {
			color = Color3.fromRGB(250, 248, 240),
			collide = false,
			cast = false,
		})
	surfaceText(rackSign, Enum.NormalId.Right, "<b>1학년 신발장</b>", Color3.fromRGB(45, 45, 50), 0.9)

	-- ── 문구점 매대 (오른쪽 벽) ──
	-- 순서는 Upgrades 표의 순서와 맞춰 호출자가 키를 붙인다
	local stands: { BasePart } = {}
	for i = 1, 3 do
		local z = centerZ - 9 + (i - 1) * 9
		part(parent, `ShopCounter{i}`, Vector3.new(5, 3.4, 6), Vector3.new(LOBBY_HALF_X - 4, 1.7, z), {
			color = C.wood,
			material = Enum.Material.Wood,
		})
		local top = part(parent, `ShopStand{i}`, Vector3.new(4.6, 0.4, 5.6), Vector3.new(LOBBY_HALF_X - 4, 3.6, z), {
			color = C.trim,
			material = Enum.Material.Wood,
		})
		table.insert(stands, top)
	end
	local shopSign = part(parent, "ShopSign", Vector3.new(0.1, 2.4, 28), Vector3.new(LOBBY_HALF_X - 0.9, 11, centerZ), {
		color = Color3.fromRGB(250, 244, 228),
		collide = false,
		cast = false,
	})
	surfaceText(
		shopSign,
		Enum.NormalId.Left,
		"<b>학교 앞 문구점</b>  ★로 살 수 있다",
		Color3.fromRGB(120, 60, 40),
		0.85
	)

	return rack, stands
end

-- ── 조립 ──────────────────────────────────────────────────────────
--[[
	@return 부모가 붙지 않은 허브 모델과 서비스가 필요로 하는 참조들.
	        교실 템플릿과 달리 슬롯 복제가 없으므로 WorldPivot 을 못박을 이유도 없다.
]]
function Template.build()
	local hub = Instance.new("Model")
	hub.Name = "Playground"

	local yard = Instance.new("Folder")
	yard.Name = "Yard"
	yard.Parent = hub

	local building = Instance.new("Folder")
	building.Name = "Building"
	building.Parent = hub

	--[[
		운동장에는 흙바닥·화단·트랙 선만 남긴다.
		골대·조회대·철봉·정글짐·동상·게양대는 전부 걷어냈다. 스폰에서 현관까지
		120 스터드를 걸어가는 것이 이 허브의 유일한 동선인데, 그 위에 놓인
		물건은 전부 장애물로만 작동했다. 빈 운동장이 오히려 학교처럼 보인다.
	]]
	buildGround(yard)

	buildFacade(building)
	local shoeRack, shopStands = buildLobby(building)

	--[[
		스폰. 회전 없는 CFrame 이므로 LookVector 가 -Z, 즉 본관 정면을 본다.
		Neutral 과 Transparency 는 교실 스폰과 같은 이유다 — 팀 없음, 안 보임.
	]]
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "YardSpawn"
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(0, 0.5, SPAWN_Z)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = hub

	return {
		model = hub,
		spawn = spawn,
		-- 교실에서 돌아올 때 쓴다. 신발장 쪽을 보게 두면 다음 판으로 가는 길이 자연스럽다
		returnCFrame = CFrame.new(Vector3.new(0, 3, FACADE_Z + 16), Vector3.new(0, 3, FACADE_Z - 20)),
		shoeRack = shoeRack,
		shopStands = shopStands,
	}
end

return Template
