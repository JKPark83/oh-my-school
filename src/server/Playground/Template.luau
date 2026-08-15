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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local Upgrades = require(ReplicatedStorage.Shared.Config.Upgrades)

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

local LOBBY_Z_END = -124 -- 로비 안쪽 벽. 계단 한 층이 들어갈 만큼 깊어야 한다
local LOBBY_HALF_X = 32
local LOBBY_H = 15

--[[
	교실로 올라가는 계단. 이 게임에서 유일하게 "올라가는" 동작이다.

	★ 진입은 버튼이 아니라 계단이다.
	  전에는 신발장 앞에서 E 를 눌렀다. 누르는 순간과 교실에 서 있는 순간 사이에
	  아무 일도 없어서, 교실이 어디에 붙어 있는 곳인지 감이 안 잡혔다.
	  계단을 아홉 칸 밟아 올라가면 "2층으로 올라왔다"가 몸에 남는다.
	  신발장은 소품으로 남긴다 — 프롬프트가 둘이면 어느 쪽이 입구인지 헷갈린다.

	치수는 사람이 걸어 올라갈 수 있어야 한다는 것 하나로 정해진다.
	0.8 단높이는 Humanoid 가 멈칫하지 않고 올라가고, 1.5 단너비면 28도 —
	실제 학교 계단(약 30도)과 거의 같다.
]]
local STAIR_STEPS = 9
local STAIR_RISE = 0.8
local STAIR_RUN = 1.5
local STAIR_W = 20
local STAIR_TOP_Y = STAIR_STEPS * STAIR_RISE -- 7.2. 한 층 올라온 높이
local STAIR_FRONT_Z = -104 -- 첫 단의 앞 모서리
local STAIR_BACK_Z = STAIR_FRONT_Z - STAIR_STEPS * STAIR_RUN -- 마지막 단 뒷면

local DOOR2F_HALF_W = 5 -- 2층 복도로 나가는 문
local DOOR2F_TOP_Y = STAIR_TOP_Y + 5

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
			--[[
				★ 창문·창틀·간판은 벽의 +Z 쪽에 붙는다. 운동장이 +Z 이기 때문이다.
				  벽은 두께 2 로 FACADE_Z 에 중심이 있으니 앞면이 FACADE_Z + 1 이고,
				  거기서 조금 더 나와야 벽에 파묻히지 않는다.
				  전에는 셋 다 -Z 였다 — 즉 건물 뒤통수에 붙어 있어서 운동장에서는
				  민무늬 콘크리트 벽 한 장만 보였다.
			]]
			local x = i * 13
			part(parent, `Window{floor}_{i}`, Vector3.new(9, 6, 0.4), Vector3.new(x, y, FACADE_Z + 1.1), {
				color = C.glass,
				material = Enum.Material.Glass,
				transparency = 0.35,
				collide = false,
				cast = false,
			})
			part(parent, `WindowFrame{floor}_{i}`, Vector3.new(9.8, 6.8, 0.3), Vector3.new(x, y, FACADE_Z + 0.9), {
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
	local sign = part(parent, "SchoolSign", Vector3.new(34, 5, 0.5), Vector3.new(0, DOOR_H + 5.5, FACADE_Z + 1.3), {
		color = Color3.fromRGB(248, 246, 240),
		collide = false,
		cast = false,
	})
	surfaceText(sign, Enum.NormalId.Back, "<b>행복초등학교</b>", C.sign, 1.5)
end

--[[
	매대 위에 올라가는 견본. 업그레이드 키마다 모양이 다르다.

	세 개 전부 -X 를 정면으로 본다(매대가 오른쪽 벽에 붙어 있으므로 손님은 -X 쪽에 선다).
	그래서 "앞으로 튀어나오는" 부속은 전부 x 를 빼는 방향으로 붙인다.

	@param origin 매대 상판 윗면 한가운데
]]
local function buildShopIcon(parent: Instance, key: string, origin: Vector3)
	local function at(dx: number, dy: number, dz: number): Vector3
		return origin + Vector3.new(dx, dy, dz)
	end

	if key == "quietShoes" then
		-- 실내화 한 켤레. 흰 바탕에 파란 코 — 이 조합이면 설명 없이 실내화로 읽힌다
		for _, side in { -1, 1 } do
			local z = side * 1.1
			part(parent, `Icon_shoe_sole{side}`, Vector3.new(2.4, 0.4, 1.3), at(0, 0.2, z), {
				color = Color3.fromRGB(244, 244, 240),
				material = Enum.Material.SmoothPlastic,
				collide = false,
			})
			part(parent, `Icon_shoe_heel{side}`, Vector3.new(1.3, 1.1, 1.2), at(0.5, 0.95, z), {
				color = Color3.fromRGB(248, 248, 244),
				material = Enum.Material.Fabric,
				collide = false,
			})
			part(parent, `Icon_shoe_toe{side}`, Vector3.new(0.5, 0.7, 1.25), at(-1.05, 0.75, z), {
				color = Color3.fromRGB(92, 130, 200),
				material = Enum.Material.Fabric,
				collide = false,
			})
		end
	elseif key == "balance" then
		--[[
			시소. 기울어진 판 하나가 "균형"이라는 말을 가장 짧게 한다.
			판을 수평으로 두면 그냥 탁자가 된다 — 기울기가 곧 의미다.
		]]
		part(parent, "Icon_balance_post", Vector3.new(0.8, 1.6, 0.8), at(0, 0.8, 0), {
			color = C.metal,
			material = Enum.Material.Metal,
			collide = false,
		})
		part(parent, "Icon_balance_beam", Vector3.new(0.35, 0.35, 4.6), at(0, 1.75, 0), {
			color = Color3.fromRGB(214, 168, 96),
			material = Enum.Material.Wood,
			collide = false,
			cframe = CFrame.Angles(math.rad(14), 0, 0),
		})
		for _, side in { -1, 1 } do
			part(parent, `Icon_balance_pan{side}`, Vector3.new(1.4, 0.25, 1.4), at(0, 1.75 - side * 0.55, side * 2.2), {
				color = Color3.fromRGB(214, 168, 96),
				material = Enum.Material.Wood,
				collide = false,
			})
		end
	elseif key == "instinct" then
		-- 눈. 흰자 위에 검은 동공 하나. 손님 쪽(-X)을 본다
		part(parent, "Icon_eye_ball", Vector3.new(2.4, 2.4, 2.4), at(0, 1.4, 0), {
			color = Color3.fromRGB(248, 248, 246),
			material = Enum.Material.SmoothPlastic,
			shape = Enum.PartType.Ball,
			collide = false,
		})
		part(parent, "Icon_eye_iris", Vector3.new(1.1, 1.1, 1.1), at(-0.85, 1.4, 0), {
			color = Color3.fromRGB(38, 62, 92),
			material = Enum.Material.SmoothPlastic,
			shape = Enum.PartType.Ball,
			collide = false,
		})
		part(parent, "Icon_eye_brow", Vector3.new(0.3, 0.3, 2.8), at(-0.5, 2.9, 0), {
			color = Color3.fromRGB(52, 46, 44),
			material = Enum.Material.SmoothPlastic,
			collide = false,
		})
	end
end

--[[
	현관 로비. 신발장과 문구점(상점)이 있는 곳이고, 교실로 들어가는 입구다.

	@return 상점 매대 3개(업그레이드 키 순서대로), 교실 입장 판정 파트
]]
local function buildLobby(parent: Instance): ({ BasePart }, BasePart)
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
	--[[
		안쪽 벽. 계단 위에 문 구멍 하나를 비운다.
		본관 정면 벽과 같은 방식이다 — 좌우 두 장 + 문 아래 + 문 위.
		구멍을 남기지 않고 통짜로 세우면 계단이 벽에 처박히는 그림이 된다.
	]]
	local sideW = LOBBY_HALF_X - DOOR2F_HALF_W
	for _, sign in { -1, 1 } do
		part(
			parent,
			`LobbyBack{sign}`,
			Vector3.new(sideW, LOBBY_H, 1.5),
			Vector3.new(sign * (DOOR2F_HALF_W + sideW / 2), LOBBY_H / 2, LOBBY_Z_END),
			wall
		)
	end
	part(
		parent,
		"LobbyBackSill",
		Vector3.new(DOOR2F_HALF_W * 2, STAIR_TOP_Y, 1.5),
		Vector3.new(0, STAIR_TOP_Y / 2, LOBBY_Z_END),
		wall
	)
	part(
		parent,
		"LobbyBackHeader",
		Vector3.new(DOOR2F_HALF_W * 2, LOBBY_H - DOOR2F_TOP_Y, 1.5),
		Vector3.new(0, (LOBBY_H + DOOR2F_TOP_Y) / 2, LOBBY_Z_END),
		wall
	)

	--[[
		문 위 안내판. 현관에 들어서서 처음 보이는 글자여야 한다.

		프롬프트가 사라진 자리를 이것이 메운다. 프롬프트는 가까이 가야 뜨지만
		안내판은 문을 들어서는 순간 이미 보이므로, "저기로 가면 되는구나"가
		걸음을 떼기 전에 정해진다. 계단을 쓰기로 한 이상 길 안내는 벽이 해야 한다.
	]]
	local wayfind = part(
		parent,
		"ClassWayfind",
		Vector3.new(DOOR2F_HALF_W * 2 - 0.5, 1.8, 0.12),
		Vector3.new(0, DOOR2F_TOP_Y + 1.4, LOBBY_Z_END + 0.82),
		{ color = Color3.fromRGB(58, 92, 66), collide = false, cast = false }
	)
	-- Back(+Z)이 로비 쪽이다. 안쪽 벽이라 현관에서 들어온 사람은 +Z 에 서 있다
	surfaceText(wayfind, Enum.NormalId.Back, "<b>↑ 2층 1학년 교실</b>", Color3.fromRGB(238, 244, 238), 0.8)
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

	--[[
		── 교실로 올라가는 계단 ──

		단을 얇은 판이 아니라 바닥까지 꽉 찬 덩어리로 짠다. 판만 띄워두면
		옆에서 봤을 때 공중에 뜬 발판이 되는데, 이 계단은 옆이 트여 있어서 다 보인다.
	]]
	local stone = { color = C.concrete, material = Enum.Material.Concrete }
	for i = 1, STAIR_STEPS do
		local top = i * STAIR_RISE
		part(
			parent,
			`LobbyStair{i}`,
			Vector3.new(STAIR_W, top, STAIR_RUN),
			Vector3.new(0, top / 2, STAIR_FRONT_Z - (i - 0.5) * STAIR_RUN),
			stone
		)
	end

	-- 계단참. 마지막 단에서 안쪽 벽까지 평평하게 메운다
	local landingDepth = STAIR_BACK_Z - (LOBBY_Z_END + 0.75)
	part(
		parent,
		"LobbyLanding",
		Vector3.new(STAIR_W, STAIR_TOP_Y, landingDepth),
		Vector3.new(0, STAIR_TOP_Y / 2, STAIR_BACK_Z - landingDepth / 2),
		stone
	)

	--[[
		난간. 경사면을 따라 비스듬히 눕힌 봉 하나씩.

		+Z 를 (0, 7.2, -13.5) 방향으로 돌려야 하므로 X 축 회전각은 atan(rise/run) 이다.
		부호를 반대로 주면 난간이 계단과 X 자로 교차한다 — 각도만 맞추고 넘어가면 안 되는 자리.
	]]
	local runZ = STAIR_STEPS * STAIR_RUN
	local slope = math.atan2(STAIR_TOP_Y, runZ)
	for _, sign in { -1, 1 } do
		part(
			parent,
			`StairRail{sign}`,
			Vector3.new(0.35, 0.35, math.sqrt(runZ * runZ + STAIR_TOP_Y * STAIR_TOP_Y)),
			Vector3.new(sign * (STAIR_W / 2 - 0.3), STAIR_TOP_Y / 2 + 3, STAIR_FRONT_Z - runZ / 2),
			{
				color = C.metal,
				material = Enum.Material.Metal,
				collide = false,
				cast = false,
				cframe = CFrame.Angles(slope, 0, 0),
			}
		)
	end

	--[[
		── 2층 복도 초입 ──

		문 너머가 검은 공백이면 "여기가 끝"으로 읽힌다. 실제로는 문턱을 넘는
		순간 화면이 덮이므로 이 복도는 한두 프레임밖에 안 보이지만,
		그 한두 프레임이 "교실은 저 안에 있다"를 만든다. 그래서 깊게 짓지 않는다.
	]]
	local hallDepth = 14
	local hallZ = LOBBY_Z_END - hallDepth / 2
	local hallH = DOOR2F_TOP_Y - STAIR_TOP_Y

	part(
		parent,
		"HallFloor",
		Vector3.new(DOOR2F_HALF_W * 2 + 4, 1, hallDepth),
		Vector3.new(0, STAIR_TOP_Y - 0.5, hallZ),
		{ color = C.floor, material = Enum.Material.Pebble }
	)
	part(
		parent,
		"HallCeiling",
		Vector3.new(DOOR2F_HALF_W * 2 + 4, 1, hallDepth),
		Vector3.new(0, DOOR2F_TOP_Y + 0.5, hallZ),
		{ color = C.wall, material = Enum.Material.Concrete }
	)
	for _, sign in { -1, 1 } do
		part(
			parent,
			`HallSide{sign}`,
			Vector3.new(1, hallH, hallDepth),
			Vector3.new(sign * (DOOR2F_HALF_W + 2), STAIR_TOP_Y + hallH / 2, hallZ),
			{ color = C.wall, material = Enum.Material.Plaster }
		)
	end
	part(
		parent,
		"HallEnd",
		Vector3.new(DOOR2F_HALF_W * 2 + 4, hallH, 1),
		Vector3.new(0, STAIR_TOP_Y + hallH / 2, hallZ - hallDepth / 2),
		{ color = C.wall, material = Enum.Material.Plaster }
	)

	-- 복도 끝 교실 문 하나. 이것 때문에 복도가 복도로 읽힌다
	local classDoor = part(
		parent,
		"HallClassDoor",
		Vector3.new(0.2, 4.4, 3.6),
		Vector3.new(-DOOR2F_HALF_W - 1.4, STAIR_TOP_Y + 2.2, hallZ - 2),
		{ color = C.wood, material = Enum.Material.WoodPlanks, collide = false, cast = false }
	)
	surfaceText(classDoor, Enum.NormalId.Right, "<b>1-1</b>", Color3.fromRGB(60, 50, 40), 1.2)

	local hallLamp = part(
		parent,
		"HallLight",
		Vector3.new(6, 0.3, 1),
		Vector3.new(0, DOOR2F_TOP_Y - 0.4, hallZ),
		{ color = Color3.fromRGB(255, 252, 238), material = Enum.Material.Neon, collide = false, cast = false }
	)
	local hallLight = Instance.new("PointLight")
	hallLight.Brightness = 0.9
	hallLight.Range = 26
	hallLight.Shadows = true
	hallLight.Parent = hallLamp

	--[[
		입장 판정. 문턱을 채우는 보이지 않는 판이다.

		★ ProximityPrompt 를 안 쓰는 이유가 여기 있다. 프롬프트는 "누를 수 있음"을
		  띄워주지만, 계단은 그런 안내 없이도 올라가는 곳이다. 문턱을 넘으면
		  들어가는 것이 계단의 약속이고, 그 약속을 지키는 것이 이 판이다.
		  실제 발화 처리와 중복 방지는 PlaygroundService 가 한다.
	]]
	local entrance = part(
		parent,
		"ClassEntrance",
		Vector3.new(DOOR2F_HALF_W * 2, hallH, 2),
		Vector3.new(0, STAIR_TOP_Y + hallH / 2, LOBBY_Z_END),
		{ color = C.line, transparency = 1, collide = false, cast = false }
	)

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
		★ 신발장에는 이제 프롬프트가 없다. 입장은 계단이 한다.
		  그래도 신발장은 남긴다 — 여기가 초등학교 현관이라는 말을 하는 것은
		  간판이 아니라 이 신발장이고, 그건 누를 수 없어도 제 몫을 한다.
	]]
	local rackSign =
		part(parent, "ShoeRackSign", Vector3.new(0.1, 2, 8), Vector3.new(-LOBBY_HALF_X + 0.9, 11, centerZ), {
			color = Color3.fromRGB(250, 248, 240),
			collide = false,
			cast = false,
		})
	surfaceText(rackSign, Enum.NormalId.Right, "<b>1학년 신발장</b>", Color3.fromRGB(45, 45, 50), 0.9)

	--[[
		── 문구점 매대 (오른쪽 벽) ──

		순서는 Upgrades 표의 순서와 맞춰 호출자가 키를 붙인다.

		★ 매대마다 물건이 놓여 있어야 한다. 전에는 빈 나무판 세 개였는데,
		  프롬프트를 띄우기 전까지는 무엇을 파는지 알 방법이 없었다. 상점은
		  "가까이 가서 눌러봐야 아는 곳"이 아니라 "멀리서 보고 고르는 곳"이다.
		  아트 에셋을 안 쓰므로 파트로 짠다 — 신발 한 켤레, 시소, 눈 하나.
		  벽에는 이름·값·설명을 적은 패를 걸어 값을 읽고 걸어오게 만든다.
	]]
	local stands: { BasePart } = {}
	for i, key in Upgrades.ORDER do
		local def = Upgrades.DEFS[key]
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

		buildShopIcon(parent, key, Vector3.new(LOBBY_HALF_X - 4, 3.8, z))

		-- 값패. 매대 바로 위 눈높이에 건다
		local card = part(parent, `ShopCard{i}`, Vector3.new(0.12, 4.2, 7), Vector3.new(LOBBY_HALF_X - 0.95, 7.2, z), {
			color = Color3.fromRGB(252, 250, 242),
			collide = false,
			cast = false,
		})
		surfaceText(
			card,
			Enum.NormalId.Left,
			`<b>{def.name}</b>\n<font color="#c05000">★{def.cost}</font>\n{def.desc}`,
			Color3.fromRGB(60, 52, 46),
			0.62
		)
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

	return stands, entrance
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
	local shopStands, entrance = buildLobby(building)

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
		--[[
			교실에서 돌아올 때 쓴다. 계단 발치에 계단을 보고 서게 둔다.
			로비 한가운데로 뱉으면 매번 "어디로 가야 하지"가 한 번 끼는데,
			다음 판까지 그 한 번이 매 라운드 쌓인다.
		]]
		returnCFrame = CFrame.new(Vector3.new(0, 3, STAIR_FRONT_Z + 14), Vector3.new(0, 3, STAIR_FRONT_Z)),
		shopStands = shopStands,
		entrance = entrance,
	}
end

return Template
