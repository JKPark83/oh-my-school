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
	  · 주인공 소품은 메시(PropAssets.HERO, hero()). 메시가 없거나 못 불러오면 그 자리를 파트로 짓는다.
	시설이 새로 지어지면 등장 연출이 끝난 뒤(APPEAR_DELAY) 그린다.
	음악실 피아노 흰 건반(서버 파트 PianoKeys)을 밟으면 그 건반 소리를 낸다. 밟는 사람 화면에서만 울린다(§7.5).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local PlotLayout = require(ReplicatedStorage.Shared.PlotLayout)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)
local DecorConfig = require(ReplicatedStorage.Shared.Config.DecorConfig)

local MeshCache = require(script.Parent.Parent.MeshCache)

type SoundApi = { play: (key: string, pitch: number?) -> () }
local SoundController = (require(script.Parent.SoundController) :: any) :: SoundApi

local InteriorRenderController = {}

local LOD_INTERVAL = 1
local APPEAR_DELAY = 1.2 -- 시설 등장 연출(부품이 솟아오름)이 끝난 뒤 소품이 보이게
local MAX_PARTS_PER_ROOM = 16 -- 파트 소품 15 + 주인공 메시 1(음악실)
local ROOM_FLOOR_T = 0.2 -- 과학실 등 방 바닥 판 두께(Geometry FLOOR_T 와 같다)

-- 피아노 건반 밟기. 흰 건반 10개 = 도레미파솔라시도레미(왼쪽이 낮은 음). 검은 건반은 클라 소품이라 소리가 없다
local PIANO_KEYS = "PianoKeys" -- Geometry/music.luau 의 흰 건반 판 이름
local PIANO_WHITE_KEYS = 10
local PIANO_SEMITONES = { 0, 2, 4, 5, 7, 9, 11, 12, 14, 16 }
local PIANO_RAY = 4.5 -- 스터드. 루트 파트에서 발밑까지(R15 엉덩이 높이 + 여유)

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
	net = Color3.fromRGB(245, 245, 245),
	seam = Color3.fromRGB(40, 28, 22),
}

-- 소품 하나를 그리는 함수. pos = 부지 로컬 중심, rot = 부지 로컬 회전
type Put = (name: string, size: Vector3, pos: Vector3, color: Color3, opts: PutOpts?) -> BasePart
type PutOpts = {
	material: Enum.Material?,
	shape: Enum.PartType?,
	rot: CFrame?,
	transparency: number?,
	collide: boolean?, -- 바닥에 놓인 큰 가구만 true(메시도 충돌은 상자)
	mesh: PropAssets.MeshAsset?, -- 준비됐으면 그 메시(원래 텍스처). hero() 가 쓴다
}
type Recipe = (put: Put) -> ()

--[[
	주인공 소품(PropAssets.HERO 메시) 1 파트. 메시가 준비됐으면 놓고 true, 아니면 아무것도 안 하고 false.
	부르는 쪽은 false 일 때 같은 자리를 파트로 짓는다(Rooms/Kit.hero 와 같은 약속).
	base = 밑면 가운데(부지 로컬), h = 높이(메시 비율 그대로), yaw = 도(0 = 메시 앞이 +Z 남쪽, 180 = 북쪽).
]]
local function hero(
	put: Put,
	name: string,
	asset: PropAssets.MeshAsset,
	base: Vector3,
	h: number,
	yaw: number?,
	collide: boolean?
): boolean
	if not MeshCache.get(asset) then
		return false
	end
	put(name, asset.size * (h / asset.size.Y), base + Vector3.new(0, h / 2, 0), C.white, {
		mesh = asset,
		rot = CFrame.Angles(0, math.rad(yaw or 0), 0),
		collide = collide,
	})
	return true
end

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

--- 지구본 폴백(받침 원판 + 공). 파트 2. base = 밑면 가운데, h = 높이
local function globeParts(put: Put, name: string, base: Vector3, h: number)
	put(name .. "Stand", Vector3.new(0.12 * h, 0.5 * h, 0.5 * h), base + Vector3.new(0, 0.06 * h, 0), C.wood, {
		shape = Enum.PartType.Cylinder,
		rot = CFrame.Angles(0, 0, math.pi / 2),
		material = Enum.Material.Wood,
	})
	put(name .. "Ball", Vector3.one * 0.75 * h, base + Vector3.new(0, 0.5 * h, 0), C.bookA, {
		shape = Enum.PartType.Ball,
	})
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

	-- 낮은 책꽂이 윗면(x −54.5..−49.5, 높이 3) 서쪽 끝, 화분 반대편이 빈다. 지구본이 방(−Z)을 본다
	local globeBase = Vector3.new(cx + 7, 3, southIn - 0.6)
	if not hero(put, "Globe", PropAssets.HERO.globe, globeBase, 1.4, 180) then
		globeParts(put, "Globe", globeBase, 1.4)
	end
end

-- 사물함 위: 공·책가방(폴백 = 책 더미)·작은 화분. 몸통 윗면 = 높이 + 위 마감.
-- 위 마감 x −47.8..−45.8·z −53.7..−41.3·윗면 6.3. 가운데(z −47.5) 책 더미 자리에 책가방이 방(−X)을 본다
local function locker(put: Put)
	local row = FacilityConfig.BY_ID.locker
	local topY = row.center.Y + row.size.Y + 0.3
	local x = row.center.X - row.size.X / 2
	local z0 = row.center.Z
	put("Ball", Vector3.one * 1.3, Vector3.new(x, topY + 0.65, z0 - 4), C.ball, { shape = Enum.PartType.Ball })
	if not hero(put, "Backpack", PropAssets.HERO.backpack, Vector3.new(x, topY, z0), 1.5, 270) then
		put("BookA", Vector3.new(1.1, 0.25, 1.5), Vector3.new(x, topY + 0.125, z0), C.bookA)
		put("BookB", Vector3.new(1, 0.25, 1.4), Vector3.new(x, topY + 0.375, z0), C.bookB, {
			rot = CFrame.Angles(0, 0.2, 0),
		})
		put("BookC", Vector3.new(1.05, 0.25, 1.3), Vector3.new(x, topY + 0.625, z0), C.bookC, {
			rot = CFrame.Angles(0, -0.15, 0),
		})
	end
	plant(put, "Plant", x, topY, z0 + 4, 0.6)
end

-- 과학실: 안 x −44..−16·z −16.5..6.5, 바닥 윗면 0.2. 실험대 W x −40..−32·E x −28..−20, z −8.5..−5.5, 윗면 3.075.
-- 실험대 윗면에서 서버 플라스크(x −38)·비커(x −22) 반대쪽 끝이 빈다. 현미경(동)·플라스크 세트(서)가 남쪽 스툴(+Z)을 본다. 문 옆 소화기
local function science(put: Put)
	local row = FacilityConfig.BY_ID.science
	local cx, cz = row.center.X, row.center.Z
	local floorTop = row.center.Y + ROOM_FLOOR_T
	local topY = floorTop + CharacterBuilder.SIT_DESK
	local benchZ = cz - 2

	-- 현미경(동쪽 실험대, 비커 반대편). 폴백 = 받침·기둥·경통
	local mx, mz = cx + 4.5, benchZ - 0.4
	if not hero(put, "Microscope", PropAssets.HERO.microscope, Vector3.new(mx, topY, mz), 1.4, 0) then
		put("ScopeBase", Vector3.new(0.9, 0.2, 0.7), Vector3.new(mx, topY + 0.1, mz), C.dark)
		put("ScopeArm", Vector3.new(0.2, 1.2, 0.25), Vector3.new(mx, topY + 0.8, mz + 0.2), C.dark)
		put("ScopeTube", Vector3.new(0.9, 0.3, 0.3), Vector3.new(mx, topY + 1.1, mz - 0.05), C.white, {
			shape = Enum.PartType.Cylinder,
			rot = CFrame.Angles(0, 0, math.pi / 2 - 0.35),
		})
	end

	-- 시험관 꽂이(서쪽 실험대, 플라스크 반대편). 폴백 = 받침 + 색 물 시험관 셋
	local rx, rz = cx - 4.5, benchZ - 0.4
	if not hero(put, "Flasks", PropAssets.HERO.flasks, Vector3.new(rx, topY, rz), 1.2, 0) then
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
-- 뚜껑·양옆 볼·건반 뚜껑·악보대·악보·페달 2·검은 건반 7 = 파트 15 + 드럼 세트 1(메시, 폴백 큰북 1) = 16.
-- 안 x 16..44·z −16.5..6.5. 남벽 앞 동쪽(x 35.6..40.4·z 4.4..6.2)이 빈다: 서버 큰북(x 36.4..39.6·z −12.6..−9.4)·
-- 의자(35,−6)·보면대·스피커(x 20..22)·음표 판(높이 5.2 위)과 떨어져 있다. 드럼이 방(−Z)을 본다
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

	local drums = Vector3.new(row.center.X + 8, floorTop, row.center.Z + 10.3)
	if not hero(put, "Drums", PropAssets.HERO.drums, drums, 3.4, 180, true) then
		put("DrumKit", Vector3.new(1.8, 2.4, 2.4), drums + Vector3.new(0, 1.2, 0), C.bookA, {
			shape = Enum.PartType.Cylinder,
			rot = CFrame.Angles(0, math.pi / 2, 0),
			collide = true,
		})
	end
end

-- 체육관: 농구 그물 둘 + 공 무늬. 서버는 기둥·백보드·림(지름 1.8, 높이 바닥 + 8)·공(지름 1.2)만 짓는다(Geometry/gym.luau).
-- 그물은 림 아래로 좁아지는 육각뿔대: 마름모 그물 텍스처를 깐 투명 판 6장. 막대로 줄을 그으면 막대로만 보인다.
-- 판은 윗변(림 쪽) 너비라 아래쪽에서 이웃 판과 겹치는데, 겹친 자리가 그물이 오므라든 것처럼 보인다.
-- 그물 6 × 2 + 공 이음매 3 = 파트 15 + 공 카트 1(메시, 폴백 상자 1) = 16. 뜀틀 메시는 서버 VaultBox 가 이미 있고 자리(파트 수)가 없어 뺐다.
-- 안 x 46..74·z 16..59. 동벽 앞 z 45(x 72.3..73.7·z 43.8..46.2)가 빈다: 뜀틀(z 36.5..38.5)·남쪽 매트(z 50.5..54.5)·
-- 골대(z 17.5·57.5)·서문 사이. 공 카트가 코트(−X)를 본다
local GYM_HOOP_H = 8
local GYM_NET_TOP_R, GYM_NET_BOTTOM_R, GYM_NET_H = 0.85, 0.5, 1.3 -- 육각 외접 반지름(림 반지름 0.9 안쪽)
local function gym(put: Put)
	local row = FacilityConfig.BY_ID.gym
	local floorTop = row.center.Y + ROOM_FLOOR_T
	local cx, cz, d = row.center.X, row.center.Z, row.size.Z
	local rimY = floorTop + GYM_HOOP_H
	local id = PropAssets.INTERIOR.HOOP_NET
	local apTop, apBottom = GYM_NET_TOP_R * math.cos(math.pi / 6), GYM_NET_BOTTOM_R * math.cos(math.pi / 6)
	for _, hoop in { { z = cz - d / 2 + 2.5, dir = 1 }, { z = cz + d / 2 - 2.5, dir = -1 } } do
		local rz = hoop.z + hoop.dir * 1.6 -- 림 중심(gym.luau buildHoop)
		for i = 0, 5 do
			local a = (i + 0.5) * math.pi / 3 -- 판 바깥 방향
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			local top = Vector3.new(cx, rimY - 0.05, rz) + out * apTop
			local bottom = Vector3.new(cx, rimY - 0.05 - GYM_NET_H, rz) + out * apBottom
			local up = top - bottom
			local tangent = Vector3.new(-out.Z, 0, out.X)
			local p = put(
				`Net{hoop.dir}_{i}`,
				Vector3.new(GYM_NET_TOP_R, up.Magnitude, 0.01), -- 앞뒤 텍스처가 벌어지면 줄이 겹쳐 보인다
				(top + bottom) / 2,
				C.net,
				{ transparency = if id ~= 0 then 1 else 0.6, rot = CFrame.fromMatrix(Vector3.zero, tangent, up.Unit) }
			)
			if id ~= 0 then
				for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
					local t = Instance.new("Texture")
					t.Face = face
					t.Texture = "rbxassetid://" .. id
					t.StudsPerTileU = 0.5 -- 한 장 2칸 = 판 너비에 마름모 약 3.4개
					t.StudsPerTileV = 0.5
					t.Parent = p
				end
			end
		end
	end
	-- 공 이음매: 공보다 살짝 큰 얇은 원판 셋을 서로 직각으로 끼운다(가장자리만 검은 줄로 보인다)
	local ball = Vector3.new(cx - 6, floorTop + 0.6, cz + 4)
	for i, rot in { CFrame.identity, CFrame.Angles(0, math.pi / 2, 0), CFrame.Angles(0, 0, math.pi / 2) } do
		put(`BallSeam{i}`, Vector3.new(0.05, 1.23, 1.23), ball, C.seam, { shape = Enum.PartType.Cylinder, rot = rot })
	end

	local cart = Vector3.new(cx + 13, floorTop, cz + 7.5)
	if not hero(put, "BallCart", PropAssets.HERO.ballcart, cart, 3.2, 270, true) then
		put("BallCartBox", Vector3.new(1.4, 3.2, 2.4), cart + Vector3.new(0, 1.6, 0), C.bin, { collide = true })
	end
end

-- 운동장: 축구 골대 그물. 서버는 기둥 둘(Z ±4)·크로스바(높이 4)만 짓는다(Geometry/field.luau).
-- 골대 뒤(바깥쪽)로 깊이 2.5 의 그물 상자: 뒤판·윗판·옆판 2 = 골대마다 4, 파트 8 + 시상대(메시, 폴백 3) = 11.
-- 땅 x −75..−15·z 15..60, 북쪽 트랙 z 15..18. 그 바로 안쪽 잔디(x −54.4..−49.6·z 18.2..20.4)가 빈다:
-- 하프라인(x −45)·골대(x −67.5·−22.5)·스티커 자리(−60,25)와 떨어져 있다. 시상대 별이 경기장(+Z)을 본다
local FIELD_GOAL_W, FIELD_GOAL_H, FIELD_GOAL_INSET, FIELD_NET_DEPTH = 8, 4, 22.5, 2.5
local function field(put: Put)
	local row = FacilityConfig.BY_ID.field
	local groundTop = row.center.Y + ROOM_FLOOR_T
	local cx, cz = row.center.X, row.center.Z
	local id = PropAssets.INTERIOR.NET
	local function panel(name: string, size: Vector3, pos: Vector3, faces: { Enum.NormalId })
		local p = put(name, size, pos, C.net, { transparency = if id ~= 0 then 1 else 0.7 })
		if id ~= 0 then
			for _, face in faces do
				local t = Instance.new("Texture")
				t.Face = face
				t.Texture = "rbxassetid://" .. id
				t.StudsPerTileU = 2 -- 한 장 4칸 = 칸 0.5 스터드
				t.StudsPerTileV = 2
				t.Parent = p
			end
		end
	end
	local X, Y, Z =
		{ Enum.NormalId.Right, Enum.NormalId.Left }, { Enum.NormalId.Top, Enum.NormalId.Bottom }, {
			Enum.NormalId.Front,
			Enum.NormalId.Back,
		}
	for _, side in { -1, 1 } do
		local gx = cx + side * FIELD_GOAL_INSET
		local bx = gx + side * FIELD_NET_DEPTH -- 뒤판 x
		local mx = gx + side * FIELD_NET_DEPTH / 2
		local midY = groundTop + FIELD_GOAL_H / 2
		panel(`NetBack{side}`, Vector3.new(0.05, FIELD_GOAL_H, FIELD_GOAL_W), Vector3.new(bx, midY, cz), X)
		panel(
			`NetTop{side}`,
			Vector3.new(FIELD_NET_DEPTH, 0.05, FIELD_GOAL_W),
			Vector3.new(mx, groundTop + FIELD_GOAL_H - 0.05, cz),
			Y
		)
		for _, s in { -1, 1 } do
			panel(
				`NetSide{side}_{s}`,
				Vector3.new(FIELD_NET_DEPTH, FIELD_GOAL_H, 0.05),
				Vector3.new(mx, midY, cz + s * FIELD_GOAL_W / 2),
				Z
			)
		end
	end

	local podium = Vector3.new(cx - 7, groundTop, cz - 18.2)
	if not hero(put, "Podium", PropAssets.HERO.podium, podium, 2, 0, true) then
		-- 2등(왼쪽 −X)·1등(가운데)·3등(오른쪽)
		for _, step in
			{
				{ dx = -1.6, h = 1.4, color = C.steel },
				{ dx = 0, h = 2, color = C.gold },
				{ dx = 1.6, h = 1, color = C.pot },
			}
		do
			put(
				"PodiumStep",
				Vector3.new(1.6, step.h, 2.2),
				podium + Vector3.new(step.dx, step.h / 2, 0),
				step.color,
				{ collide = true }
			)
		end
	end
end

-- 교장실: 안 x 46..74·z −16.5..6.5, 바닥 윗면 0.2. 서버 책상 x 55.5..64.5·z −8..−4.4, 화분 x 49.7..52.3·z −13.3..−10.7,
-- 손님 의자 x 48.7..51.3·z −3.8..−1.2. 서벽 앞 화분과 손님 의자 사이(x 46.3..49·z −10..−4.5)가 빈다. 곁 책상이 방(+X)을 본다
local function principal(put: Put)
	local row = FacilityConfig.BY_ID.principal
	local floorTop = row.center.Y + ROOM_FLOOR_T
	local base = Vector3.new(row.center.X - 12.35, floorTop, row.center.Z - 2.25)
	-- 메시 책상 윗면 = 높이의 약 48% → 앉은 책상 높이에 맞춘다
	if not hero(put, "Desk", PropAssets.HERO.principaldesk, base, CharacterBuilder.SIT_DESK / 0.48, 90, true) then
		local top = CharacterBuilder.SIT_DESK
		put("DeskTop", Vector3.new(2.7, 0.4, 5.4), base + Vector3.new(0, top - 0.2, 0), C.wood, {
			material = Enum.Material.Wood,
			collide = true,
		})
		for _, dz in { -1.9, 1.9 } do
			put("DeskSide", Vector3.new(2.4, top - 0.4, 1.4), base + Vector3.new(0, (top - 0.4) / 2, dz), C.wood, {
				material = Enum.Material.Wood,
				collide = true,
			})
		end
	end
end

-- 강당(2층): 안 x −24..24·z −34..0, 바닥 윗면 18.2. 무대 x −15..15·z −34..−28·윗면 19.4, 종 x −1.5..1.5, 서버 연단 x 6..8.
-- 무대 앞 서쪽(서버 연단과 대칭, x −8.35..−5.65·z −30.7..−28.3)이 빈다. 연단 별이 객석(+Z)을 본다
local AUD_STAGE_H = 1.2 -- Geometry/auditorium.luau STAGE_H
local function auditorium(put: Put)
	local row = FacilityConfig.BY_ID.auditorium
	local stageTop = row.center.Y + PlotLayout.AUDITORIUM_FLOOR_T + AUD_STAGE_H
	local base = Vector3.new(row.center.X - 7, stageTop, row.center.Z - 12)
	if not hero(put, "Lectern", PropAssets.HERO.lectern, base, 3.4, 0, true) then
		put("LecternBody", Vector3.new(2.2, 3, 1.8), base + Vector3.new(0, 1.5, 0), C.bookA, { collide = true })
		put("LecternTop", Vector3.new(2.6, 0.2, 2.2), base + Vector3.new(0, 3.1, 0), C.wood, {
			material = Enum.Material.Wood,
			collide = true,
		})
	end
end

-- 복도: 안 x −74..74·z −31.5..−18.5, 바닥 윗면 0.2. 북벽 안쪽 면 x −32.5(교실1 문 −64..−56 과 교실2 문 −24..−16 사이 벽)에
-- 진열대 + 트로피. 스티커 자리(−42.5,−27.5)·줄무늬(z −25.8..−24.2)·교실2 패드(−20,−28.75)에서 떨어진 빈 벽이다
local function hall(put: Put)
	local row = FacilityConfig.BY_ID.hall
	local floorTop = row.center.Y + ROOM_FLOOR_T
	local stand = Vector3.new(1.8, 3, 1.4)
	local x, z = -32.5, row.center.Z - row.size.Z / 2 + 1 + stand.Z / 2
	put("TrophyStand", stand, Vector3.new(x, floorTop + stand.Y / 2, z), C.wood, {
		material = Enum.Material.Wood,
		collide = true,
	})
	local base = Vector3.new(x, floorTop + stand.Y, z)
	if not hero(put, "Trophy", PropAssets.HERO.trophy, base, 2, 0) then
		put("TrophyBase", Vector3.new(0.9, 0.35, 0.7), base + Vector3.new(0, 0.175, 0), C.wood, {
			material = Enum.Material.Wood,
		})
		put("TrophyCup", Vector3.new(1.3, 0.9, 0.9), base + Vector3.new(0, 1.0, 0), C.gold, {
			shape = Enum.PartType.Cylinder,
			rot = CFrame.Angles(0, 0, math.pi / 2),
			material = Enum.Material.Metal,
		})
	end
end

-- 교실 2: 안 x −34..−6·z −61.5..−33.5, 바닥 = Shell 바닥 y 0. 뒷줄 책상 x −22.7..−17.3·z −44.6..−42.4, 서쪽 의자 x −22.3..−20.7.
-- 그 서쪽 통로 가장자리 바닥(x −23.8)에 책가방이 의자(+X)를 본다. 책상·의자·문(x −24..−16, z −32.5)과 겹치지 않는다
local function class2(put: Put)
	local row = FacilityConfig.BY_ID.class2
	local x, z = row.center.X - 3.8, row.center.Z + 5.6
	if not hero(put, "Backpack", PropAssets.HERO.backpack, Vector3.new(x, row.center.Y, z), 1.5, 90) then
		put("BackpackBody", Vector3.new(0.75, 1.3, 1.0), Vector3.new(x, row.center.Y + 0.65, z), C.cork)
		put("BackpackPocket", Vector3.new(0.2, 0.55, 0.8), Vector3.new(x + 0.47, row.center.Y + 0.4, z), C.bookA)
	end
end

-- 급식실: 안 x 6..34·z −61.5..−33.5, 바닥 윗면 0.2. 서버 배식대 x 12..28·z −61.5..−59.5, 식탁·의자 z −49.5..−43.5.
-- 북서 구석(배식대 서쪽 끝과 서벽 사이 x 6..12)이 빈다. 둘째 배식대를 동쪽(+X)으로 돌려 ㄱ자 배식 줄을 만든다
local function cafeteria(put: Put)
	local row = FacilityConfig.BY_ID.cafeteria
	local floorTop = row.center.Y + ROOM_FLOOR_T
	local x, z = 8.2, -57.9
	if not hero(put, "Counter", PropAssets.HERO.counter, Vector3.new(x, floorTop, z), 6, 90, true) then
		put("CounterBody", Vector3.new(3.6, 3, 6.4), Vector3.new(x, floorTop + 1.5, z), C.steel, {
			material = Enum.Material.Metal,
			collide = true,
		})
		put("CounterTop", Vector3.new(4, 0.2, 6.8), Vector3.new(x, floorTop + 3.1, z), C.steel, {
			material = Enum.Material.Metal,
			collide = true,
		})
		put("CounterPot", Vector3.new(0.8, 1.2, 1.2), Vector3.new(x, floorTop + 3.6, z + 1.5), C.dark, {
			shape = Enum.PartType.Cylinder,
			rot = CFrame.Angles(0, 0, math.pi / 2),
			material = Enum.Material.Metal,
		})
	end
end

-- 도서관: 안 x 46..74·z −61.5..−33.5, 바닥 윗면 0.2. 사서 카운터 x 49.5..54.5·z −40.5..−38.5·윗면 3.2.
-- 카운터 윗면 서쪽 끝이 빈다(「대출·반납」 글자는 앞면이라 안 가린다). 지구본이 방(−Z)을 본다
local function library(put: Put)
	local row = FacilityConfig.BY_ID.library
	local base = Vector3.new(row.center.X - 9.4, row.center.Y + ROOM_FLOOR_T + 3, row.center.Z + 8)
	if not hero(put, "Globe", PropAssets.HERO.globe, base, 1.5, 180) then
		globeParts(put, "Globe", base, 1.5)
	end
end

-- 보건실: 안 x −74..−46·z −16.5..6.5, 바닥 윗면 0.2. 서버 침대 x −69.6..−66.4·z −6.8..−0.2(머리 북쪽), 북문 x −64..−56.
-- 서버 침대 북쪽 같은 줄(x −68, z −16.15..−10.45)이 빈 바닥이다. 둘째 침대도 머리가 북쪽(yaw 0, 메시 머리맡 = −Z)
local function nurse(put: Put)
	local row = FacilityConfig.BY_ID.nurse
	local floorTop = row.center.Y + ROOM_FLOOR_T
	local x, z = row.center.X - 8, -13.3
	if not hero(put, "Bed", PropAssets.HERO.bed, Vector3.new(x, floorTop, z), 3.2, 0, true) then
		put("BedFrame", Vector3.new(3.2, 0.8, 5.6), Vector3.new(x, floorTop + 0.4, z), C.steel, {
			material = Enum.Material.Metal,
			collide = true,
		})
		put("BedMattress", Vector3.new(3, 0.5, 5.2), Vector3.new(x, floorTop + 1.05, z), C.white, { collide = true })
		put("BedPillow", Vector3.new(2.4, 0.4, 1.1), Vector3.new(x, floorTop + 1.5, z - 2), C.white)
	end
end

-- 시설 id → 소품. SHELL 은 늘 그린다
local SHELL: { [string]: Recipe } = { class1 = class1 }
local RECIPES: { [string]: Recipe } = {
	locker = locker,
	hall = hall,
	class2 = class2,
	cafeteria = cafeteria,
	library = library,
	nurse = nurse,
	science = science,
	music = music,
	gym = gym,
	field = field,
	principal = principal,
	auditorium = auditorium,
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
	local function put(name: string, size: Vector3, pos: Vector3, color: Color3, opts: PutOpts?): BasePart
		count += 1
		local mesh = if opts and opts.mesh then MeshCache.get(opts.mesh) else nil
		local p: BasePart
		if mesh then
			p = mesh:Clone()
			color = Color3.new(1, 1, 1) -- 텍스처에 색이 곱해지지 않게
		else
			local part = Instance.new("Part")
			part.Shape = if opts and opts.shape then opts.shape else Enum.PartType.Block
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			p = part
		end
		p.Name = name
		p.Size = size
		local rot = if opts and opts.rot then opts.rot else CFrame.identity
		p.CFrame = pivot * CFrame.new(pos) * rot
		p.Color = color
		p.Material = if opts and opts.material then opts.material else Enum.Material.SmoothPlastic
		p.Transparency = if opts and opts.transparency then opts.transparency else 0
		p.Anchored = true
		p.CanCollide = opts ~= nil and opts.collide == true
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
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

-- ── 피아노 건반 밟기 ─────────────────────────────────────────────

local pianoParams = RaycastParams.new()
pianoParams.FilterType = Enum.RaycastFilterType.Exclude
local lastPianoKey: BasePart? = nil
local lastPianoIndex = 0

--- 발밑이 흰 건반 판이면 몇 번째 건반인지(1..10), 아니면 0
local function pianoKeyUnderFoot(): (BasePart?, number)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not (character and root and root:IsA("BasePart")) then
		return nil, 0
	end
	pianoParams.FilterDescendantsInstances = { character }
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -PIANO_RAY, 0), pianoParams)
	local keys = if hit then hit.Instance else nil
	if not (hit and keys and keys.Name == PIANO_KEYS) then
		return nil, 0
	end
	local x = keys.CFrame:PointToObjectSpace(hit.Position).X + keys.Size.X / 2
	return keys, math.clamp(math.floor(x / keys.Size.X * PIANO_WHITE_KEYS) + 1, 1, PIANO_WHITE_KEYS)
end

--- 다른 건반으로 옮겨 가거나 다시 올라설 때만 한 번 울린다(서 있는 동안 반복하지 않는다)
local function pianoTick()
	local keys, index = pianoKeyUnderFoot()
	if keys and (keys ~= lastPianoKey or index ~= lastPianoIndex) then
		SoundController.play("piano", 2 ^ (PIANO_SEMITONES[index] / 12))
	end
	lastPianoKey, lastPianoIndex = keys, index
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
	RunService.Heartbeat:Connect(pianoTick)
	MeshCache.onReady(function()
		for plotId in near do
			renderPlot(plotId)
		end
	end)

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
