--!nonstrict
--[[
	교실 하나를 통째로 만든다. Phase 1 의 Greybox 를 대체한다.

	좌표 규약 (전 Phase 공통):
	  -Z = 교실 앞(칠판)   +Z = 교실 뒤(뒷문)
	  -X = 창가             +X = 복도 쪽
	  y = 0 이 바닥 윗면

	★ 감지 판정에 영향을 주는 치수는 Phase 1 에서 튜닝된 값 그대로다.
	  교실 내부 46 x 38, 선생님 z = -15, 뒷문 x = 14, 책상 3분단 x 6열,
	  엄폐물 3개의 X/Z 발자국(footprint). 아트를 입히면서 이 값들을 건드리면
	  이미 검증된 난이도가 통째로 무효가 된다.
	  바뀐 것은 천장 높이(16 → 11 → 14)뿐이다. 감지는 전부 수평 판정이라 영향이 없다.

	  높이만 세 번 바뀐 이유: 16 은 사람 키(5.6)의 세 배라 "낮고 답답한 한국 교실"과
	  정반대였고, 그래서 11 로 낮췄더니 이번엔 진짜로 답답했다. 원인은 비율이 아니라
	  카메라다 — 3인칭 카메라가 11 스터드 뒤에서 비스듬히 내려다보는데 천장이 11 이면
	  카메라가 천장에 눌려 앞으로 밀린다. 로비(LOBBY_H = 15)와 나란히 놓았을 때
	  교실만 눌려 보인 것도 같은 이유다. 14 는 카메라가 천장을 안 건드리는 최저값이다.

	아트 리소스를 쓰지 않는다. 전부 파트와 로블록스 기본 머티리얼로 만든다.
	외부 에셋이 없으면 리뷰도 diff 도 파일 하나로 끝나고, Phase 4 의 슬롯 복제도
	Clone() 한 번이면 된다.
]]

local CollectionService = game:GetService("CollectionService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local GradeTheme = require(ReplicatedStorage.Shared.Config.GradeTheme)
local RoomKeys = require(ReplicatedStorage.Shared.Config.RoomKeys)
local BuildKit = require(script.Parent.Parent.BuildKit)

local Template = {}

-- ── 치수 ──────────────────────────────────────────────────────────
local HALF_W = 23
local HALF_D = 19
local HEIGHT = 14
local WALL = 1

local TEACHER_Z = -15
local DOOR_X = 14
local DOOR_WIDTH = 8

--[[
	뒷문 높이. 7 이었다.

	★ 폭 8 에 높이 7 이면 거의 정사각형이다. 그래서 이 자리가 "문"이 아니라
	  "벽에 뚫린 구멍"으로 읽혔다 — 사람 키(5.6)보다 높긴 했으니 못 지나갈 일은
	  없었는데, 지나갈 수 있다는 것과 문으로 보인다는 것은 다른 문제다.
	  9.5 는 사람 키의 1.7배다. 문설주와 상인방을 두르면 비율이 세로로 선다.

	★ 폭은 8 그대로다. 미닫이 두 짝이 각각 벽 뒤로 4.1 씩 물러나야 하는데,
	  왼쪽 벽은 x = 10 에서, 오른쪽 벽은 x = 18 에서 시작한다. 폭을 줄이면
	  열린 문짝이 문구멍을 도로 반쯤 막는다.
]]
local DOOR_HEIGHT = 9.5
local DOOR_LEAF_W = DOOR_WIDTH / 2 + 0.1 -- 두 짝이 가운데에서 살짝 겹친다

--[[
	문짝이 매달린 면. 벽(z = 18.5~19.5)보다 0.25 만큼 교실 안쪽이다.

	★ 문틀 안에 끼우지 않고 벽 앞면에 매다는 이유는 열릴 자리 때문이다.
	  문틀 안에서 미닫으면 두 짝이 서로 겹치는 만큼만 열려서 폭 8 이 4 가 된다.
	  벽 위로 빼면 8 이 통째로 열린다. 레일이 밖으로 나온 미닫이문은
	  실제 학교 복도에도 흔하다.

	  0.85 는 문설주(z = 18.4~19.6)와 안 겹치는 최소값에서 여유를 둔 값이다.
]]
local DOOR_Z = HALF_D - 0.85

-- 책상 격자. Phase 1 과 동일하다.
local DESK_X = { -14, 0, 14 }
local DESK_Z = { -8, -4, 0, 4, 8, 12 }

-- 의자는 책상 뒤(+Z). 학생은 -Z(칠판)를 본다.
-- 열 간격이 4 이므로, 등받이(좌석 +0.85)가 다음 줄 책상 앞면(z+2.9)에 닿지 않아야 한다.
local SEAT_DZ = 1.6
local DESK_DEPTH = 2.2

--[[
	가구 높이는 학생 체구에서 나온다. 이 두 식 덕분에 엉덩이가 의자에,
	팔뚝이 책상에 정확히 얹힌다.

	★ 예전에는 체구가 0.86 하나로 고정이라 상수 두 개였다. 학년마다 아이들 키가
	  달라지면서 식이 됐다 — 아이만 키우고 가구를 두면 6학년이 유치원 의자에 앉는다.
	  바뀌는 것은 y 뿐이다. 책상의 X/Z 발자국은 통로 폭을 정하는 값이라 손대지 않는다.
]]
local function chairTopY(scale: number): number
	return CharacterBuilder.SIT_HIP * scale
end

local function deskTopY(scale: number): number
	return CharacterBuilder.SIT_DESK * scale
end

-- 지을 때 쓰는 기준 학년. 실제 학년은 ClassroomService 가 반을 열 때 다시 입힌다.
local BUILD_GRADE = 1

-- 이름은 전부 RoomKeys 에서 온다. 클라이언트가 같은 문자열로 찾아야 하기 때문이다.
Template.SEAT_TAG = RoomKeys.SEAT_TAG
Template.COVER_TAG = RoomKeys.COVER_TAG
Template.SEATS_FOLDER = RoomKeys.SEATS_FOLDER
Template.OBSTACLES_FOLDER = RoomKeys.OBSTACLES_FOLDER
Template.OBSTACLES_ATTRIBUTE = RoomKeys.OBSTACLES_ATTRIBUTE
Template.SLIP_TAG = RoomKeys.SLIP_TAG

--[[
	방해물은 통로 한가운데에만 놓는다. 책상 폭이 4.6 이므로 분단은 x ± 2.3 을
	차지하고, 통로 중심은 x = ±7 이다. 여기를 피해 갈 수 없어야 방해물이다.

	삐걱거리는 마루는 "보이는" 함정이다. 색이 살짝 다른 널판이라 관찰하면 피할 수 있다.
	안 보이는 함정은 방해물이 아니라 그냥 억울함이다.
]]
local CREAK_TILES = { Vector3.new(-7, 0, -6), Vector3.new(7, 0, 0), Vector3.new(-7, 0, 8), Vector3.new(7, 0, 12) }
local CREAK_SIZE = Vector3.new(5, 0.08, 4)
local SLIP_SPOTS = { Vector3.new(7, 0, -6), Vector3.new(-7, 0, 4) }

-- ── 색 ────────────────────────────────────────────────────────────
local C = {
	wall = Color3.fromRGB(226, 220, 205), -- 미색 페인트
	wainscot = Color3.fromRGB(176, 166, 148), -- 허리 높이 굽도리
	ceiling = Color3.fromRGB(240, 238, 232),
	floor = Color3.fromRGB(186, 146, 96), -- 나무 마루
	board = Color3.fromRGB(28, 72, 52), -- 초록 칠판
	boardFrame = Color3.fromRGB(150, 116, 72),
	chalk = Color3.fromRGB(240, 240, 235),
	metal = Color3.fromRGB(118, 122, 128),
	locker = Color3.fromRGB(150, 152, 148),
	desk = Color3.fromRGB(212, 176, 126),
	chair = Color3.fromRGB(196, 158, 110),
	cork = Color3.fromRGB(198, 154, 104),
	curtain = Color3.fromRGB(238, 232, 214),
	pot = Color3.fromRGB(178, 96, 66),
	leaf = Color3.fromRGB(78, 138, 72),
	glass = Color3.fromRGB(196, 224, 238),
	dark = Color3.fromRGB(48, 48, 52),
}

--[[
	── 학년 스킨 ──

	교실을 지으면서 "학년이 바뀌면 손봐야 하는 것"만 따로 모아둔 목록이다.

	★ 학년마다 교실을 다시 짓지 않는다. 슬롯 12개는 서버가 뜰 때 한 번 지어지고
	  그 뒤로는 반이 바뀔 때마다 옷만 갈아입는다. 다시 지으면 좌석 참조가 끊기고,
	  그 참조를 들고 있는 것이 세션·감지·프롬프트 전부다.

	★ 나중에 이름으로 찾지 않고 지을 때 받아두는 이유는, 이름 검색이 조용히
	  실패하기 때문이다. 파트 이름 하나를 오타 내면 그 학년만 색이 안 바뀌는데
	  에러는 안 난다. 목록에 넣는 것을 빼먹으면 그건 diff 에 보인다.
]]
export type Skin = {
	accent: { BasePart },
	accentDark: { BasePart },
	deskTops: { BasePart },
	chairs: { BasePart },
	books: { BasePart },
	curtains: { BasePart },
	desks: { DeskUnit }, -- 체구를 따라 높이가 다시 잡히는 책상 한 벌
	labels: { [string]: any }, -- 칠판·급훈·시간표·게시판·문패의 TextLabel
}

type DeskUnit = {
	top: BasePart,
	legs: { BasePart },
	back: BasePart,
	leg: BasePart,
	seat: BasePart,
	book: BasePart,
}

local function newSkin(): Skin
	return {
		accent = {},
		accentDark = {},
		deskTops = {},
		chairs = {},
		books = {},
		curtains = {},
		desks = {},
		labels = {},
	}
end

-- ── 파트 생성 헬퍼 ─────────────────────────────────────────────────
-- Phase 5 에서 운동장 허브가 같은 헬퍼를 쓰게 되면서 BuildKit 으로 옮겼다.
-- 이름을 그대로 지역 변수에 받는 이유는, 아래 700줄이 전부 part(...) 로 쓰여 있어서다.
local part = BuildKit.part
local surfaceText = BuildKit.surfaceText

-- ── 구조 ──────────────────────────────────────────────────────────
local function buildStructure(parent: Instance)
	local w, d = HALF_W * 2, HALF_D * 2

	part(parent, "Floor", Vector3.new(w, WALL, d), Vector3.new(0, -WALL / 2, 0), {
		color = C.floor,
		material = Enum.Material.WoodPlanks,
	})
	part(parent, "Ceiling", Vector3.new(w, WALL, d), Vector3.new(0, HEIGHT + WALL / 2, 0), {
		color = C.ceiling,
		material = Enum.Material.Concrete,
		fade = true,
	})

	local y = HEIGHT / 2
	-- fade: 벽에 등을 붙이면 카메라가 벽 안으로 들어간다. 그때만 반투명해진다(RoomKeys.FADE_TAG)
	local opts = { color = C.wall, material = Enum.Material.Plaster, fade = true }

	part(parent, "WallFront", Vector3.new(w, HEIGHT, WALL), Vector3.new(0, y, -HALF_D), opts)
	part(parent, "WallLeft", Vector3.new(WALL, HEIGHT, d), Vector3.new(-HALF_W, y, 0), opts)
	part(parent, "WallRight", Vector3.new(WALL, HEIGHT, d), Vector3.new(HALF_W, y, 0), opts)

	-- 뒷벽은 뒷문 구멍만큼 비운다
	local doorLeft = DOOR_X - DOOR_WIDTH / 2
	local doorRight = DOOR_X + DOOR_WIDTH / 2
	local leftW = doorLeft + HALF_W
	local rightW = HALF_W - doorRight
	part(parent, "WallBackA", Vector3.new(leftW, HEIGHT, WALL), Vector3.new(-HALF_W + leftW / 2, y, HALF_D), opts)
	part(parent, "WallBackB", Vector3.new(rightW, HEIGHT, WALL), Vector3.new(doorRight + rightW / 2, y, HALF_D), opts)
	-- 문 위 인방
	part(
		parent,
		"DoorHeader",
		Vector3.new(DOOR_WIDTH, HEIGHT - DOOR_HEIGHT, WALL),
		Vector3.new(DOOR_X, DOOR_HEIGHT + (HEIGHT - DOOR_HEIGHT) / 2, HALF_D),
		opts
	)

	-- 굽도리(하단 나무 패널). 한국 교실 벽의 시각적 특징이다
	-- 벽과 같이 사라져야 한다. 벽만 지우고 굽도리가 남으면 허리 높이 띠가 공중에 뜬다
	local wainscot = { color = C.wainscot, material = Enum.Material.Wood, fade = true }
	part(parent, "WainscotFront", Vector3.new(w, 2.2, 0.2), Vector3.new(0, 1.1, -HALF_D + 0.6), wainscot)
	part(parent, "WainscotLeft", Vector3.new(0.2, 2.2, d), Vector3.new(-HALF_W + 0.6, 1.1, 0), wainscot)
	part(parent, "WainscotRight", Vector3.new(0.2, 2.2, d), Vector3.new(HALF_W - 0.6, 1.1, 0), wainscot)

	--[[
		형광등 4개. Neon 만으로는 실내가 어두워서 광원을 같이 단다.

		★ 창가(-X)가 밝고 복도(+X)가 어둡다. 이 비대칭이 게임플레이다.
		  복도 쪽 분단은 어두워서 몸을 숨기기 좋지만, 선생님과의 거리는 더 멀어
		  이동 시간이 길어진다. 창가 쪽은 밝아 잘 보이는 대신 빨리 도달한다.
		  형광등을 똑같이 켜면 이 선택 자체가 사라진다.

		★ Range 는 전부 방 대각선보다 크게 잡는다. PointLight.Range 는 부드러운
		  감쇠의 끝이 아니라 그 거리에서 딱 끊기는 경계선이다. 예전에는 Range 가
		  방보다 작아서, 통로를 걷다 경계를 넘는 순간 광원 여러 개가 한꺼번에
		  꺼졌다 — "갑자기 조명이 밝아진다"의 정체가 이거였다. 경계를 벽 밖으로
		  밀어내면 방 안에는 기울기만 남고 계단은 사라진다.
		  대신 밝기를 낮춘다. Range 를 늘리면 같은 거리에서 더 밝아지기 때문이다.

		★ 밝기를 한 번 더 반으로 깎았다(0.9/0.4 → 0.5/0.22, 창가 햇빛 1 → 0.55).
		  Range 가 전부 방보다 크다는 것은 방 안 어디에 서든 일곱 광원이 "동시에"
		  닿는다는 뜻이다. 개당 값만 보고 고르면 합산이 2.6 이 되어 화면이 하얗게 날아간다.
		  창가와 복도의 비(약 2.3배)는 그대로 두었다 — 그 비대칭이 게임플레이다.
	]]
	for _, x in { -11, 11 } do
		local windowSide = x < 0
		for _, z in { -8, 6 } do
			local lamp = part(parent, "Light", Vector3.new(10, 0.3, 1.2), Vector3.new(x, HEIGHT - 0.4, z), {
				color = Color3.fromRGB(255, 253, 240),
				material = Enum.Material.Neon,
				transparency = if windowSide then 0 else 0.25,
				collide = false,
				cast = false,
			})
			local light = Instance.new("PointLight")
			light.Brightness = if windowSide then 0.5 else 0.22
			light.Range = if windowSide then 50 else 48 -- 방 대각선(약 46)보다 크다
			light.Shadows = false -- 슬롯 12개 x 4등 = 48광원. 그림자까지 켜면 모바일이 죽는다
			light.Parent = lamp
		end
	end

	--[[
		창으로 들어오는 햇빛. 창가 벽을 따라 셋. 형광등보다 이쪽이 밝아야
		"창가가 밝다"가 조명이 아니라 시간대의 문제로 읽힌다.
		SpotLight 가 아니라 PointLight 인 것은 값 때문이다 — 그림자를 끈 이상
		방향을 줘봐야 연산만 늘고 그림 차이는 거의 없다.
	]]
	for _, z in { -10, 0, 10 } do
		local glow = part(parent, "SunGlow", Vector3.new(0.4, 6, 8), Vector3.new(-HALF_W + 2.4, 6, z), {
			color = Color3.fromRGB(255, 246, 220),
			transparency = 1,
			collide = false,
			cast = false,
		})
		local sun = Instance.new("PointLight")
		sun.Brightness = 0.55
		sun.Range = 58 -- 창가 광원에서 복도 쪽 먼 구석까지가 약 53이다
		sun.Color = Color3.fromRGB(255, 244, 214)
		sun.Shadows = false
		sun.Parent = glow
	end
end

--[[
	── 뒷문 ──

	★ 원래 여기는 문이 아니라 구멍이었다. 벽에 사각형을 비워두고 그걸 문이라고 불렀다.
	  플레이어가 "문을 여닫을 수 없다"고 말한 것은 기능 요청이 아니라 관찰이다 —
	  여닫을 수 없는 것은 문이 아니고, 문이 아닌 것 옆에서 부활하면
	  자기가 방금 어디로 들어왔는지 알 수 없다.

	한국 교실 뒷문은 미닫이 두 짝이다. 여닫이가 아니라 미닫이여야 하는 이유가
	이 게임에는 하나 더 있다 — 여닫이는 열릴 때 호를 그리며 사람을 밀어낸다.
	부활 지점이 문에서 3 스터드 앞이라, 열리는 문이 매번 플레이어를 걷어찬다.
	미닫이는 벽을 따라 옆으로 빠지므로 아무도 안 건드린다.

	@return 문짝 두 짝. 각 짝은 파트 묶음과 열릴 때 갈 방향이다.
	        닫힌 자세(CFrame)는 여기서 안 잰다 — 교실은 지어진 뒤 슬롯으로 옮겨지므로
	        지금 잰 좌표는 전부 원점 기준이고, 옮기고 나면 전부 틀린 값이 된다.
	        재는 것은 PivotTo 를 한 쪽(ClassroomService)의 몫이다.
]]
type Leaf = { parts: { BasePart }, slide: Vector3 }

local function buildBackDoor(parent: Instance, skin): { Leaf }
	-- 문설주와 상인방. 이 테두리가 있어야 구멍이 문이 된다
	local trim = { color = C.wall, material = Enum.Material.WoodPlanks, fade = true }
	for _, sign in { -1, 1 } do
		table.insert(
			skin.accent,
			part(
				parent,
				`DoorJamb{sign}`,
				Vector3.new(0.55, DOOR_HEIGHT + 0.7, 1.2),
				Vector3.new(DOOR_X + sign * (DOOR_WIDTH / 2 + 0.27), (DOOR_HEIGHT + 0.7) / 2, HALF_D),
				trim
			)
		)
	end
	table.insert(
		skin.accent,
		part(
			parent,
			"DoorLintel",
			Vector3.new(DOOR_WIDTH + 1.7, 0.7, 1.2),
			Vector3.new(DOOR_X, DOOR_HEIGHT + 0.35, HALF_D),
			trim
		)
	)
	part(parent, "DoorSill", Vector3.new(DOOR_WIDTH + 1.7, 0.12, 1.2), Vector3.new(DOOR_X, 0.06, HALF_D), {
		color = C.metal,
		material = Enum.Material.Metal,
		collide = false, -- 문턱에 걸려 넘어지는 것은 연출이 아니라 버그로 읽힌다
		cast = false,
	})

	--[[
		레일. 문짝이 열려서 벽 위에 가 있을 때도 매달려 있어야 하므로
		문구멍이 아니라 "이동 범위 전체"를 덮는 길이여야 한다.
		문구멍 폭만큼만 깔면 열린 문이 공중에 뜬 판때기가 된다.
	]]
	local travel = DOOR_LEAF_W
	part(
		parent,
		"DoorRail",
		Vector3.new(DOOR_WIDTH + travel * 2 + 0.6, 0.3, 0.55),
		Vector3.new(DOOR_X, DOOR_HEIGHT - 0.05, DOOR_Z),
		{ color = C.metal, material = Enum.Material.Metal, collide = false, fade = true }
	)

	--[[
		문짝. 아래는 나무 판, 위는 불투명 유리다.

		★ 유리를 넣는 것이 그림 문제만은 아니다. 문이 닫혀 있어도 복도 조명이
		  흐리게 비쳐야 "저 너머에 공간이 있다"가 남는다. 통판 나무로 막으면
		  교실이 상자가 되고, 상자에서는 나갈 생각이 안 든다.
	]]
	local leaves: { Leaf } = {}
	local half = DOOR_LEAF_W / 2
	local TOP, BOTTOM = 9.28, 0.08
	local PANEL_TOP, GLASS_TOP = 3.58, 8.92

	for _, sign in { -1, 1 } do
		local cx = DOOR_X + sign * half
		local parts: { BasePart } = {}

		local function piece(name: string, size: Vector3, dx: number, y: number, opts): BasePart
			local p = part(parent, name, size, Vector3.new(cx + dx, y, DOOR_Z), opts)
			table.insert(parts, p)
			return p
		end

		local wood = { color = C.desk, material = Enum.Material.WoodPlanks, fade = true }
		local rail = { color = C.wainscot, material = Enum.Material.Wood, fade = true }

		piece("DoorPanel", Vector3.new(DOOR_LEAF_W, PANEL_TOP - BOTTOM, 0.16), 0, (BOTTOM + PANEL_TOP) / 2, wood)
		table.insert(
			skin.accentDark,
			piece("DoorMidRail", Vector3.new(DOOR_LEAF_W, 0.34, 0.2), 0, PANEL_TOP + 0.17, rail)
		)
		table.insert(skin.accentDark, piece("DoorTopRail", Vector3.new(DOOR_LEAF_W, 0.36, 0.2), 0, TOP - 0.18, rail))
		for _, edge in { -1, 1 } do
			table.insert(
				skin.accentDark,
				piece("DoorStile", Vector3.new(0.26, TOP - BOTTOM, 0.2), edge * (half - 0.13), (BOTTOM + TOP) / 2, rail)
			)
		end

		local glassH = GLASS_TOP - (PANEL_TOP + 0.34)
		local glassY = (PANEL_TOP + 0.34 + GLASS_TOP) / 2
		piece("DoorGlass", Vector3.new(DOOR_LEAF_W - 0.5, glassH, 0.08), 0, glassY, {
			color = C.glass,
			material = Enum.Material.Glass,
			transparency = 0.5,
			collide = false,
			cast = false,
			fade = true,
		})
		piece("DoorMullion", Vector3.new(0.12, glassH, 0.14), 0, glassY, {
			color = C.wainscot,
			material = Enum.Material.Wood,
			collide = false,
			cast = false,
			fade = true,
		})

		-- 손잡이는 두 짝이 만나는 안쪽 모서리에 붙는다. 미닫이는 여기를 잡고 민다
		piece("DoorHandle", Vector3.new(0.16, 1.2, 0.3), -sign * (half - 0.45), 4.6, {
			color = C.metal,
			material = Enum.Material.Metal,
			collide = false,
			cast = false,
			fade = true,
		})

		-- 열리면 각자 바깥쪽 벽 위로 물러난다
		table.insert(leaves, { parts = parts, slide = Vector3.new(sign * travel, 0, 0) })
	end

	--[[
		문패. 교실 안쪽과 복도 쪽에 하나씩.

		★ 학년이 안 보인다는 말에 대한 가장 짧은 답이 이것이다. 부활 지점이 문 앞이고
		  플레이어는 매 판 여기서 시작하므로, 몸을 돌리면 언제나 "3-7"이 눈에 든다.
		  복도 쪽에도 다는 이유는 나갔다 들어올 때 같은 것이 보여야 하기 때문이다.
	]]
	local plates: { TextLabel } = {}
	for _, side in
		{ { z = HALF_D - 0.68, face = Enum.NormalId.Front }, { z = HALF_D + 0.68, face = Enum.NormalId.Back } }
	do
		local plate =
			part(parent, "DoorPlate", Vector3.new(4.2, 1.9, 0.14), Vector3.new(DOOR_X, DOOR_HEIGHT + 1.6, side.z), {
				color = Color3.fromRGB(250, 248, 242),
				collide = false,
				cast = false,
			})
		table.insert(plates, surfaceText(plate, side.face, "<b>1-1</b>", C.dark, 1.1))
		table.insert(
			skin.accent,
			part(
				parent,
				"DoorPlateFrame",
				Vector3.new(4.6, 2.3, 0.1),
				Vector3.new(
					DOOR_X,
					DOOR_HEIGHT + 1.6,
					side.z + (if side.face == Enum.NormalId.Front then 0.1 else -0.1)
				),
				{
					color = C.wainscot,
					material = Enum.Material.Wood,
					collide = false,
					cast = false,
				}
			)
		)
	end
	skin.labels.doorPlates = plates

	return leaves
end

--[[
	교실 밖 복도.

	★ 이건 장식이 아니라 바닥이다. 뒷벽에 문 구멍을 뚫어놓고 그 밖에 아무것도
	  안 두면 걸어 나가는 순간 낙하한다. "복도로 나가기" 프롬프트가 있다고 해서
	  플레이어가 프롬프트만 쓸 거라고 가정할 수 없다 — 문이 보이면 걸어 나간다.

	막다른 복도다. 실제로 지나다닐 곳이 아니라, 문 밖을 내다봤을 때 학교가
	계속 이어져 보이고 발을 헛디디지 않으면 된다. 그래서 양끝을 막는다.
]]
local CORRIDOR_DEPTH = 16 -- 뒷벽(z = HALF_D)에서 바깥쪽으로
local CORRIDOR_OVERHANG = 3 -- 교실 폭보다 좌우로 더 나가는 길이

local function buildCorridor(parent: Instance, skin)
	local zNear = HALF_D
	local zFar = HALF_D + CORRIDOR_DEPTH
	local zMid = (zNear + zFar) / 2
	local halfX = HALF_W + CORRIDOR_OVERHANG
	local w = halfX * 2
	local y = HEIGHT / 2

	part(parent, "CorridorFloor", Vector3.new(w, WALL, CORRIDOR_DEPTH), Vector3.new(0, -WALL / 2, zMid), {
		color = Color3.fromRGB(168, 132, 88), -- 교실 마루보다 조금 어둡다. 왁스 먹인 복도
		material = Enum.Material.WoodPlanks,
	})
	part(parent, "CorridorCeiling", Vector3.new(w, WALL, CORRIDOR_DEPTH), Vector3.new(0, HEIGHT + WALL / 2, zMid), {
		color = C.ceiling,
		material = Enum.Material.Concrete,
		fade = true,
	})

	local opts = { color = C.wall, material = Enum.Material.Plaster, fade = true }
	for _, sign in { -1, 1 } do
		part(
			parent,
			`CorridorEnd{sign}`,
			Vector3.new(WALL, HEIGHT, CORRIDOR_DEPTH),
			Vector3.new(sign * halfX, y, zMid),
			opts
		)
	end

	--[[
		바깥쪽 벽. 한국 학교 복도는 운동장 쪽이 통유리다.
		유리를 넣는 이유는 분위기가 아니라 방향 감각이다 — 복도가 막힌 상자로
		보이면 "여기서 더 갈 곳이 없다"가 아니라 "덜 만들었다"로 읽힌다.

		창틀 위아래를 상수로 둔다. 예전에는 "HEIGHT - 8.4 만큼, HEIGHT - 1.3 높이에"
		처럼 적혀 있었는데, 이 숫자는 HEIGHT 가 11 일 때만 맞는 값이었다.
		천장을 14 로 올리는 순간 위쪽 벽이 천장을 뚫고 나갔다.
	]]
	local WIN_LOW, WIN_HIGH = 3.2, 8.4
	local upperH = HEIGHT - WIN_HIGH

	part(parent, "CorridorOuterLow", Vector3.new(w, WIN_LOW, WALL), Vector3.new(0, WIN_LOW / 2, zFar), opts)
	part(parent, "CorridorOuterHigh", Vector3.new(w, upperH, WALL), Vector3.new(0, WIN_HIGH + upperH / 2, zFar), opts)

	local glassH = WIN_HIGH - WIN_LOW
	local glassY = (WIN_LOW + WIN_HIGH) / 2
	part(parent, "CorridorGlass", Vector3.new(w - 1, glassH, 0.2), Vector3.new(0, glassY, zFar), {
		color = C.glass,
		material = Enum.Material.Glass,
		transparency = 0.55,
		cast = false,
	})
	for i = -2, 2 do
		part(parent, `CorridorMullion{i}`, Vector3.new(0.25, glassH, 0.3), Vector3.new(i * 9, glassY, zFar), {
			color = C.metal,
			material = Enum.Material.Metal,
			collide = false,
			cast = false,
		})
	end

	-- 사물함. 문 반대쪽(-X)에 몰아둔다. 문 앞을 막으면 나가자마자 걸린다
	for i = 0, 4 do
		local x = -halfX + 3.2 + i * 5.2
		part(parent, `Locker{i}`, Vector3.new(5, 6, 1.6), Vector3.new(x, 3, zNear + 1.4), {
			color = C.locker,
			material = Enum.Material.Metal,
			fade = true, -- 키 높이라 복도에서 벽만큼 시야를 막는다
		})
		for row = 0, 1 do
			part(parent, `LockerLine{i}_{row}`, Vector3.new(5, 0.1, 0.1), Vector3.new(x, 1.5 + row * 3, zNear + 0.55), {
				color = C.dark,
				collide = false,
				cast = false,
			})
		end
	end

	--[[
		복도 게시판. 끝벽(-X)에 붙인다.

		문 바로 밖(+X 쪽)에는 아무것도 두지 않는다. 문에서 나오자마자 걸리는 물건이
		있으면 그건 장식이 아니라 함정이다. 뒷문은 x = 14 근처이므로 그쪽을 비워둔다.
	]]
	local board = part(parent, "CorridorBoard", Vector3.new(0.3, 5, 12), Vector3.new(-halfX + 0.7, 6.2, zMid), {
		color = C.cork,
		material = Enum.Material.Fabric,
	})
	skin.labels.corridor = surfaceText(
		board,
		Enum.NormalId.Right,
		"<b>이달의 독서왕</b>\n\n1학년 1반  김민준\n1학년 2반  이서연",
		C.dark,
		0.62
	)

	-- 복도 조명. 교실보다 확실히 어둡다 — 복도는 나가는 곳이지 머무는 곳이 아니다
	for _, z in { zNear + 4, zFar - 4 } do
		local lamp = part(parent, "CorridorLight", Vector3.new(8, 0.3, 1), Vector3.new(0, HEIGHT - 0.4, z), {
			color = Color3.fromRGB(255, 253, 240),
			material = Enum.Material.Neon,
			transparency = 0.35,
			collide = false,
			cast = false,
		})
		local light = Instance.new("PointLight")
		light.Brightness = 0.35
		light.Range = 36 -- 교실과 같은 이유로 복도 구석까지(약 32) 덮는다
		light.Shadows = false
		light.Parent = lamp
	end
end

-- ── 칠판 벽 ────────────────────────────────────────────────────────
--[[
	칠판 위 왼쪽에 태극기가 걸려 있었다. 파트로 태극 문양과 4괘까지 만들었는데,
	빼기로 했다. 국기는 "한국 교실"의 기호로는 강한 만큼 잘못 그리면 바로 티가 나고,
	여기 것은 S자 곡선을 못 내서 원판 두 장을 어긋나게 겹친 흉내였다.
	급훈 액자와 시계만으로도 벽은 이미 한국 교실로 읽힌다.
]]
local function buildFrontWall(parent: Instance, skin)
	local z = -HALF_D + 0.55 -- 굽도리보다 살짝 앞

	-- 칠판. 초록 판 + 나무 테두리 + 분필받이
	-- 테두리가 학년 색을 입는다. 교실에서 가장 오래 보는 물건이 칠판이라,
	-- 여기 한 줄이 벽 열 군데를 칠하는 것보다 학년을 잘 말한다
	table.insert(
		skin.accent,
		part(parent, "BlackboardFrame", Vector3.new(27, 5.8, 0.25), Vector3.new(0, 4.4, z), {
			color = C.boardFrame,
			material = Enum.Material.Wood,
			collide = false,
		})
	)
	local board = part(parent, "Blackboard", Vector3.new(26, 5, 0.3), Vector3.new(0, 4.4, z + 0.16), {
		color = C.board,
		material = Enum.Material.Slate,
		collide = false,
	})
	part(parent, "ChalkTray", Vector3.new(26.4, 0.28, 0.6), Vector3.new(0, 1.72, z + 0.35), {
		color = C.boardFrame,
		material = Enum.Material.Wood,
		collide = false,
	})
	part(parent, "ChalkStick", Vector3.new(0.7, 0.16, 0.16), Vector3.new(-9.5, 1.94, z + 0.4), {
		color = C.chalk,
		collide = false,
		cast = false,
	})

	-- 분필가루 자국. 지우다 만 흔적이 있어야 "쓰던 칠판"으로 보인다
	for _, spot in { Vector3.new(-6, 3.2, 0), Vector3.new(4, 5.6, 0), Vector3.new(9, 3.8, 0) } do
		part(parent, "ChalkDust", Vector3.new(6.5, 1.4, 0.04), Vector3.new(0, 4.4, z + 0.33) + spot, {
			color = C.chalk,
			transparency = 0.82,
			collide = false,
			cast = false,
		})
	end

	skin.labels.board = surfaceText(
		board,
		Enum.NormalId.Back,
		"1학년 1반  받아쓰기\n\n1. 학교종이 땡땡땡\n2. 우리 모두 다 같이",
		Color3.fromRGB(235, 235, 228),
		0.9
	)

	-- 급훈 액자 / 시계
	table.insert(
		skin.accentDark,
		part(parent, "MottoFrame", Vector3.new(6.4, 2.8, 0.2), Vector3.new(8, 8.4, z + 0.2), {
			color = C.boardFrame,
			material = Enum.Material.Wood,
			collide = false,
			cast = false,
		})
	)
	local motto = part(parent, "Motto", Vector3.new(5.8, 2.2, 0.1), Vector3.new(8, 8.4, z + 0.32), {
		color = Color3.fromRGB(250, 248, 240),
		collide = false,
		cast = false,
	})
	skin.labels.motto = surfaceText(
		motto,
		Enum.NormalId.Back,
		"급훈\n<b>바르고 슬기롭게</b>",
		Color3.fromRGB(40, 40, 45),
		0.85
	)

	part(parent, "Clock", Vector3.new(0.15, 2.2, 2.2), Vector3.new(0, 8.6, z + 0.2), {
		color = Color3.fromRGB(248, 248, 248),
		shape = Enum.PartType.Cylinder,
		cframe = CFrame.Angles(0, math.rad(90), 0),
		collide = false,
		cast = false,
	})
	part(parent, "ClockRim", Vector3.new(0.1, 2.5, 2.5), Vector3.new(0, 8.6, z + 0.15), {
		color = C.dark,
		shape = Enum.PartType.Cylinder,
		cframe = CFrame.Angles(0, math.rad(90), 0),
		collide = false,
		cast = false,
	})
	part(parent, "ClockHourHand", Vector3.new(0.12, 0.6, 0.06), Vector3.new(0, 8.9, z + 0.29), {
		color = C.dark,
		collide = false,
		cast = false,
	})
	part(parent, "ClockMinuteHand", Vector3.new(0.9, 0.08, 0.06), Vector3.new(0.4, 8.6, z + 0.29), {
		color = C.dark,
		collide = false,
		cast = false,
	})

	-- 교탁. 선생님(x=0) 을 가리지 않도록 옆으로 뺀다
	part(parent, "Podium", Vector3.new(5, 3, 2.2), Vector3.new(-8, 1.5, -13), {
		color = C.desk,
		material = Enum.Material.Wood,
	})

	-- 복도 쪽 벽걸이 TV
	part(parent, "TVFrame", Vector3.new(7, 4, 0.35), Vector3.new(15, 6.6, z + 0.1), {
		color = C.dark,
		collide = false,
	})
	part(parent, "TVScreen", Vector3.new(6.4, 3.5, 0.1), Vector3.new(15, 6.6, z + 0.3), {
		color = Color3.fromRGB(18, 22, 30),
		material = Enum.Material.Glass,
		collide = false,
		cast = false,
	})

	--[[
		학년 안내판. 창가 쪽 앞벽, TV 맞은편이다.

		★ "난이도 조절이 된 건지 모르겠다"에 대한 답이 여기 걸린다.
		  DifficultyTable 은 학년마다 항목을 하나씩만 새로 조이도록 짜여 있는데,
		  그 설계는 플레이어가 조여진 항목이 무엇인지 알 때만 설계로 작동한다.
		  모르면 그냥 "왜인지 어려워졌다"가 되고, 그건 연습으로 넘을 수 있는 벽이 아니다.
		  수치를 적지는 않는다 — "회전 속도 1.4배"가 아니라
		  "몸 도는 속도가 빨라졌다"여야 교실에 붙은 안내문으로 읽힌다.

		x = -17.6 인 것은 칠판 테두리(폭 27, ±13.5)를 피해야 해서다.
	]]
	table.insert(
		skin.accent,
		part(parent, "GradeSignFrame", Vector3.new(6.9, 4.4, 0.25), Vector3.new(-17.6, 6.6, z + 0.1), {
			color = C.boardFrame,
			material = Enum.Material.Wood,
			collide = false,
			cast = false,
		})
	)
	local sign = part(parent, "GradeSign", Vector3.new(6.3, 3.8, 0.12), Vector3.new(-17.6, 6.6, z + 0.28), {
		color = Color3.fromRGB(250, 248, 240),
		collide = false,
		cast = false,
	})
	skin.labels.hint = surfaceText(
		sign,
		Enum.NormalId.Back,
		"<b>1학년</b>\n\n선생님은\n돌아보기 전에 어깨가 먼저 움직인다",
		Color3.fromRGB(45, 45, 52),
		0.62
	)
end

-- ── 뒷벽 (게시판 + 사물함) ─────────────────────────────────────────
local function buildBackWall(parent: Instance, covers: { BasePart }, skin)
	local z = HALF_D - 0.6

	-- 게시판. 코르크 판 + 아이들 작품(색종이)
	table.insert(
		skin.accent,
		part(parent, "NoticeFrame", Vector3.new(19, 6.2, 0.2), Vector3.new(-8, 5.4, z), {
			color = C.boardFrame,
			material = Enum.Material.Wood,
			collide = false,
		})
	)
	local cork = part(parent, "NoticeBoard", Vector3.new(18, 5.4, 0.15), Vector3.new(-8, 5.4, z - 0.15), {
		color = C.cork,
		material = Enum.Material.Fabric,
		collide = false,
	})
	skin.labels.notice = surfaceText(cork, Enum.NormalId.Front, "우리들의 작품", Color3.fromRGB(70, 50, 30), 0.9)

	local paperColors = {
		Color3.fromRGB(255, 226, 140),
		Color3.fromRGB(168, 214, 255),
		Color3.fromRGB(255, 176, 176),
		Color3.fromRGB(186, 240, 186),
		Color3.fromRGB(232, 200, 255),
		Color3.fromRGB(255, 206, 160),
	}
	local rng = Random.new(20260815)
	for i, color in paperColors do
		local x = -15.2 + (i - 1) * 2.9
		part(parent, `Artwork{i}`, Vector3.new(2.1, 2.6, 0.06), Vector3.new(x, 4.6, z - 0.28), {
			color = color,
			collide = false,
			cast = false,
			cframe = CFrame.Angles(0, 0, math.rad(rng:NextNumber(-4, 4))),
		})
	end

	-- 뒤쪽 사물함. 엄폐물이다. X/Z 발자국은 Phase 1 과 동일하다
	local locker = part(parent, "Locker", Vector3.new(14, 6.5, 2), Vector3.new(-14, 3.25, HALF_D - 2), {
		color = C.locker,
		material = Enum.Material.Metal,
	})
	table.insert(covers, locker)
	for i = 0, 4 do
		part(
			parent,
			`LockerDivider{i}`,
			Vector3.new(0.12, 6.3, 0.1),
			Vector3.new(-20.5 + i * 2.8, 3.25, HALF_D - 3.05),
			{
				color = C.metal,
				material = Enum.Material.Metal,
				collide = false,
				cast = false,
			}
		)
	end

	-- 청소도구함. 엄폐물
	local cabinet = part(parent, "CleaningCabinet", Vector3.new(4, 6.8, 4), Vector3.new(-HALF_W + 3, 3.4, 16), {
		color = C.locker,
		material = Enum.Material.Metal,
	})
	table.insert(covers, cabinet)
	part(parent, "CabinetHandle", Vector3.new(0.18, 1, 0.18), Vector3.new(-HALF_W + 3, 3.4, 13.9), {
		color = C.metal,
		material = Enum.Material.Metal,
		collide = false,
		cast = false,
	})

	-- 복도 쪽 사물함. 엄폐물
	local side = part(parent, "SideLocker", Vector3.new(2, 6.5, 12), Vector3.new(HALF_W - 2, 3.25, 4), {
		color = C.locker,
		material = Enum.Material.Metal,
	})
	table.insert(covers, side)
end

-- ── 창가 ──────────────────────────────────────────────────────────
local function buildWindows(parent: Instance, skin)
	local x = -HALF_W + 0.6

	part(parent, "Windowsill", Vector3.new(1.1, 0.3, 30), Vector3.new(x + 0.3, 3.1, 0), {
		color = C.wainscot,
		material = Enum.Material.Wood,
		collide = false,
	})

	for i, z in { -10, 0, 10 } do
		part(parent, `WindowFrame{i}`, Vector3.new(0.2, 5.6, 9.4), Vector3.new(x, 6.1, z), {
			color = Color3.fromRGB(212, 212, 210),
			material = Enum.Material.Metal,
			collide = false,
			cast = false,
		})
		part(parent, `WindowGlass{i}`, Vector3.new(0.1, 5.2, 9), Vector3.new(x + 0.1, 6.1, z), {
			color = C.glass,
			material = Enum.Material.Glass,
			transparency = 0.62,
			collide = false,
			cast = false,
		})
		part(parent, `WindowMullion{i}`, Vector3.new(0.16, 5.4, 0.2), Vector3.new(x + 0.1, 6.1, z), {
			color = Color3.fromRGB(212, 212, 210),
			material = Enum.Material.Metal,
			collide = false,
			cast = false,
		})

		-- 커튼은 창 양옆에 묶여 있다
		for _, sign in { -1, 1 } do
			table.insert(
				skin.curtains,
				part(parent, `Curtain{i}{sign}`, Vector3.new(0.5, 6, 1.6), Vector3.new(x + 0.5, 6.1, z + sign * 4.4), {
					color = C.curtain,
					material = Enum.Material.Fabric,
					collide = false,
				})
			)
		end
	end

	-- 창가 화분
	for i, z in { -13, -3, 8 } do
		part(parent, `Pot{i}`, Vector3.new(1, 0.9, 1), Vector3.new(x + 0.35, 3.65, z), {
			color = C.pot,
			material = Enum.Material.Slate,
			shape = Enum.PartType.Cylinder,
			cframe = CFrame.Angles(0, 0, math.rad(90)),
			collide = false,
		})
		part(parent, `Plant{i}`, Vector3.new(1.3, 1.3, 1.3), Vector3.new(x + 0.35, 4.6, z), {
			color = C.leaf,
			material = Enum.Material.Grass,
			shape = Enum.PartType.Ball,
			collide = false,
		})
	end

	-- 시간표는 창가 쪽 앞 벽에 붙인다
	local timetable = part(parent, "Timetable", Vector3.new(0.1, 3.4, 4.6), Vector3.new(x + 0.05, 6.4, -15.5), {
		color = Color3.fromRGB(250, 250, 245),
		collide = false,
		cast = false,
	})
	skin.labels.timetable = surfaceText(
		timetable,
		Enum.NormalId.Right,
		"<b>시간표</b>\n1교시 국어\n2교시 수학\n3교시 통합\n4교시 체육",
		Color3.fromRGB(45, 45, 50),
		0.8
	)
end

-- ── 책상 / 의자 / 좌석 ────────────────────────────────────────────
--[[
	좌석 파트(의자 앉는 면)는 Seats 폴더에 따로 모은다.
	  - 서버: 여기서 빈자리를 뽑고 ProximityPrompt 를 붙인다
	  - 클라: 폴더 자식만 순회하면 학생 렌더 대상이 나온다

	태그도 같이 붙이지만, 클라이언트가 의존하는 것은 폴더다.
	태그 복제 시점을 기다리는 것보다 폴더 WaitForChild 가 확실하다.
]]
--[[
	책상 한 벌의 높이를 체구에 맞춘다. 짓는 순간에도, 학년이 바뀔 때도 여기를 통한다.
	식이 두 군데에 적혀 있으면 한쪽만 고치는 날이 반드시 온다.

	★ 바꾸는 것은 Size 와 y 뿐이다. X/Z 는 지금 값을 그대로 되쓴다 —
	  이 함수는 교실이 슬롯(x = 10000 + ...)으로 옮겨진 뒤에도 불리는데,
	  그때 로컬 좌표로 CFrame 을 새로 쓰면 책상 18개가 원점으로 순간이동한다.
	  슬롯 원점은 y 성분이 0 인 순수 평행이동이라 y 만은 로컬 = 월드다.
]]
local function fitDesk(unit: DeskUnit, scale: number)
	local deskTop = deskTopY(scale)
	local chairTop = chairTopY(scale)

	local function setY(p: BasePart, y: number)
		-- 회전을 지키기 위해 위치만 갈아끼운다. 교과서는 비스듬히 놓여 있다
		p.CFrame = p.CFrame + Vector3.new(0, y - p.Position.Y, 0)
	end

	unit.top.Size = Vector3.new(4.6, 0.2, DESK_DEPTH)
	setY(unit.top, deskTop - 0.1)
	for _, legPart in unit.legs do
		legPart.Size = Vector3.new(0.25, deskTop - 0.2, DESK_DEPTH - 0.4)
		setY(legPart, (deskTop - 0.2) / 2)
	end

	unit.back.Size = Vector3.new(1.9, 1.5, 0.2)
	setY(unit.back, chairTop + 0.75)
	unit.leg.Size = Vector3.new(1, chairTop - 0.2, 1)
	setY(unit.leg, (chairTop - 0.2) / 2)

	unit.seat.Size = Vector3.new(1.9, 0.2, 1.9)
	setY(unit.seat, chairTop - 0.1)

	setY(unit.book, deskTop + 0.11)
end

local function buildDesks(furniture: Instance, seats: Folder, skin)
	local index = 0
	local bookRng = Random.new(419)

	-- col 은 창가(-X)부터 1, row 는 칠판(-Z)부터 1이다. 둘 다 좌석에 박아두면
	-- 클라이언트가 "1분단 3번째"를 만들 때 DESK_X / DESK_Z 를 몰라도 된다.
	for col, x in DESK_X do
		for row, z in DESK_Z do
			index += 1
			local seatZ = z + SEAT_DZ

			-- 책상: 상판 + 다리 패널 2장. 높이는 아래 fitDesk 가 잡는다
			local top = part(furniture, `DeskTop{index}`, Vector3.new(4.6, 0.2, DESK_DEPTH), Vector3.new(x, 0, z), {
				color = C.desk,
				material = Enum.Material.Wood,
			})
			local legs: { BasePart } = {}
			for _, sign in { -1, 1 } do
				table.insert(
					legs,
					part(
						furniture,
						`DeskLeg{index}{sign}`,
						Vector3.new(0.25, 1, DESK_DEPTH - 0.4),
						Vector3.new(x + sign * 2, 0, z),
						{ color = C.metal, material = Enum.Material.Metal, collide = false }
					)
				)
			end

			-- 의자: 등받이 + 기둥. 앉는 면은 아래 좌석 파트가 겸한다
			local back = part(
				furniture,
				`ChairBack{index}`,
				Vector3.new(1.9, 1.5, 0.2),
				Vector3.new(x, 0, seatZ + 0.85),
				{ color = C.chair, material = Enum.Material.Wood, collide = false }
			)
			local leg = part(
				furniture,
				`ChairLeg{index}`,
				Vector3.new(1, 1, 1),
				Vector3.new(x, 0, seatZ),
				{ color = C.metal, material = Enum.Material.Metal, collide = false }
			)

			--[[
				펼쳐진 교과서. 학년마다 색이 다르다.

				★ 책상 위가 텅 비어 있으면 아무리 색을 칠해도 "쓰는 교실"로 안 읽힌다.
				  그리고 18개가 한 방향으로 정렬돼 있으면 그건 교실이 아니라 진열대다.
				  각도만 조금씩 흩어놓는다. 발자국(X/Z)은 책상 위라 통로와 무관하다.
			]]
			local book = part(furniture, `Textbook{index}`, Vector3.new(1.7, 0.22, 1.2), Vector3.new(x - 1, 0, z), {
				color = C.desk,
				material = Enum.Material.SmoothPlastic,
				collide = false,
				cast = false,
				cframe = CFrame.Angles(0, math.rad(bookRng:NextNumber(-18, 18)), 0),
			})
			table.insert(skin.books, book)
			table.insert(skin.deskTops, top)
			table.insert(skin.chairs, back)

			local seat = part(
				seats,
				string.format("Seat%02d", index),
				Vector3.new(1.9, 0.2, 1.9),
				Vector3.new(x, 0, seatZ),
				{ color = C.chair, material = Enum.Material.Wood, collide = false }
			)
			table.insert(skin.chairs, seat)

			local unit: DeskUnit = { top = top, legs = legs, back = back, leg = leg, seat = seat, book = book }
			fitDesk(unit, GradeTheme.get(BUILD_GRADE).bodyScale)
			table.insert(skin.desks, unit)

			seat:SetAttribute("Index", index)
			seat:SetAttribute("IsEmpty", false)
			seat:SetAttribute(RoomKeys.COLUMN_ATTRIBUTE, col)
			seat:SetAttribute(RoomKeys.ROW_ATTRIBUTE, row)
			-- 기본은 전원 칠판을 보고 손은 내리고 있다. 반마다 진행 쪽이 다시 정한다.
			seat:SetAttribute(RoomKeys.FACING_ATTRIBUTE, 0)
			seat:SetAttribute(RoomKeys.RAISED_ATTRIBUTE, false)
			CollectionService:AddTag(seat, Template.SEAT_TAG)
		end
	end
end

--[[
	방해물 2종. 6반부터 켠다 — 1~5반은 순수하게 규칙만 배우는 구간이다.

	켜고 끄는 주인은 ClassroomService 다. 여기서는 만들어 놓기만 하고,
	꺼진 상태(투명)로 시작한다.
]]
local function buildObstacles(parent: Instance): ({ BasePart }, { BasePart })
	local creaks: { BasePart } = {}
	local slips: { BasePart } = {}

	for i, spot in CREAK_TILES do
		local tile = part(parent, `CreakTile{i}`, CREAK_SIZE, Vector3.new(spot.X, 0.04, spot.Z), {
			color = Color3.fromRGB(150, 112, 68), -- 마루보다 한 톤 어둡다
			material = Enum.Material.WoodPlanks,
			transparency = 1,
			collide = false,
			cast = false,
		})
		table.insert(creaks, tile)
	end

	-- 굴러다니는 지우개·필통. 밟으면 미끄러져 정지 거리가 늘어난다.
	-- CanCollide 를 끈다 — 물리로 걸려 넘어지면 클라이언트마다 결과가 달라진다.
	for i, spot in SLIP_SPOTS do
		local isEraser = i % 2 == 1
		local item = part(
			parent,
			if isEraser then `Eraser{i}` else `PencilCase{i}`,
			if isEraser then Vector3.new(1.2, 0.5, 0.7) else Vector3.new(2.2, 0.6, 0.9),
			Vector3.new(spot.X, 0.3, spot.Z),
			{
				color = if isEraser then Color3.fromRGB(236, 232, 224) else Color3.fromRGB(72, 108, 176),
				material = Enum.Material.Plastic,
				transparency = 1,
				collide = false,
				cast = false,
				cframe = CFrame.Angles(0, math.rad(if isEraser then 25 else -40), 0),
			}
		)
		CollectionService:AddTag(item, Template.SLIP_TAG)
		table.insert(slips, item)
	end

	return creaks, slips
end

--[[
	교실에 학년을 입힌다. 반이 열릴 때마다 ClassroomService 가 부른다.

	★ 지오메트리는 한 칸도 안 움직인다. 바뀌는 것은 Color, TextLabel.Text,
	  그리고 가구의 "높이"뿐이다. 교실 치수(46 x 38), 책상 격자, 엄폐물 발자국,
	  선생님 z = -15 위에서 난이도가 튜닝됐고, 학년마다 방이 달라지면
	  그 튜닝이 학년마다 다시 필요해진다. 그건 여섯 배의 일이 아니라
	  "어느 학년에서 검증한 값인지 아무도 모르는 상태"다.

	★ 가구 높이만 예외인 것은 체구 때문이다. 6학년 아이를 1학년 의자에 앉히면
	  다리가 책상을 뚫는다. 높이는 감지에 안 쓰인다 — 시야 판정이 전부 X/Z 다.
]]
function Template.applyGrade(skin: Skin, grade: number, class: number)
	local theme = GradeTheme.get(grade)

	for _, p in skin.accent do
		p.Color = theme.accent
	end
	for _, p in skin.accentDark do
		p.Color = theme.accentDark
	end
	for _, p in skin.deskTops do
		p.Color = theme.deskTop
	end
	for _, p in skin.chairs do
		p.Color = theme.chair
	end
	for _, p in skin.books do
		p.Color = theme.book
	end
	for _, p in skin.curtains do
		p.Color = theme.curtain
	end

	for _, unit in skin.desks do
		fitDesk(unit, theme.bodyScale)
	end

	local L = skin.labels
	for _, plate in L.doorPlates do
		plate.Text = `<b>{grade}-{class}</b>`
	end
	L.board.Text = `{theme.label} {class}반  {theme.board}`
	L.motto.Text = `급훈\n<b>{theme.motto}</b>`
	L.timetable.Text = `<b>시간표</b>\n{theme.timetable}`
	L.notice.Text = theme.notice
	L.hint.Text = `<b>{theme.label}</b>\n\n선생님은\n{theme.hint}`
	L.corridor.Text = `<b>이달의 독서왕</b>\n\n{theme.label} 1반  김민준\n{theme.label} 2반  이서연`
end

-- ── 조립 ──────────────────────────────────────────────────────────
--[[
	@return 부모가 붙지 않은 교실 모델과, 서비스들이 필요로 하는 참조들.
	        Parent 도 슬롯 위치도 호출자(ClassroomService)가 정한다.

	★ 모델은 항상 원점 기준으로 만들고, WorldPivot 을 원점으로 못박아 돌려준다.
	  그래야 호출자가 room:PivotTo(슬롯원점) 한 번으로 순수한 평행이동을 얻는다.
	  이걸 안 해두면 PivotTo 가 바운딩박스 중심을 기준으로 움직여서
	  슬롯마다 교실이 미묘하게 다른 곳에 놓인다.
	  doorCFrame 도 로컬 좌표다. 호출자가 슬롯원점을 곱해서 쓴다.
]]
function Template.build(slotIndex: number?)
	local room = Instance.new("Model")
	room.Name = "Classroom"

	local structure = Instance.new("Folder")
	structure.Name = "Structure"
	structure.Parent = room

	local furniture = Instance.new("Folder")
	furniture.Name = "Furniture"
	furniture.Parent = room

	local seats = Instance.new("Folder")
	seats.Name = Template.SEATS_FOLDER
	seats.Parent = room

	local obstacles = Instance.new("Folder")
	obstacles.Name = Template.OBSTACLES_FOLDER
	obstacles.Parent = room

	local covers: { BasePart } = {}
	local skin = newSkin()

	buildStructure(structure)
	local doorLeaves = buildBackDoor(structure, skin)
	buildCorridor(structure, skin)
	buildFrontWall(furniture, skin)
	buildBackWall(furniture, covers, skin)
	buildWindows(furniture, skin)
	buildDesks(furniture, seats, skin)
	local creakTiles, slipItems = buildObstacles(obstacles)

	room:SetAttribute(Template.OBSTACLES_ATTRIBUTE, false)
	-- 클라이언트(StudentRenderController)가 학생 체구를 정하는 데 읽는다.
	-- 반이 열리기 전에 복제될 수 있으므로 nil 로 두지 않는다.
	room:SetAttribute(RoomKeys.GRADE_ATTRIBUTE, BUILD_GRADE)

	for _, cover in covers do
		CollectionService:AddTag(cover, Template.COVER_TAG)
	end

	-- 선생님. 칠판(-Z)을 보고 선다. WATCHING 에서 180도 돌면 학생(+Z)을 본다.
	local teacherBase = CFrame.new(0, 0, TEACHER_Z)
	local teacher = CharacterBuilder.build("Teacher", teacherBase, CharacterBuilder.teacherConfig(slotIndex))
	teacher.Parent = room

	-- 뒷문 앞 스폰. 여기는 MAX_SIGHT 밖이라 패턴을 관찰하고 출발할 수 있다.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "DoorSpawn"
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = CFrame.new(DOOR_X, 0.5, HALF_D - 3)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = room

	-- ★ 여기가 슬롯 배치의 전제다. 못박아두지 않으면 PivotTo 가 바운딩박스 중심을 쓴다.
	room.WorldPivot = CFrame.new()

	return {
		model = room,
		teacherModel = teacher,
		seatsFolder = seats,
		obstaclesFolder = obstacles,
		creakTiles = creakTiles,
		slipItems = slipItems,
		spawn = spawn,
		doorCFrame = CFrame.new(DOOR_X, 3, HALF_D - 3),
		doorLeaves = doorLeaves,
		skin = skin,
	}
end

return Template
