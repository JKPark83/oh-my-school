--!strict
--[[
	전시실(공룡·행성) 레시피. 서북 = 받침대 위 공룡 뼈대(머리는 동쪽, 꼬리는 서쪽), 그 앞(남쪽) = 관람 벤치 두 줄.
	학생 자리 1번은 앞 벤치 가운데(공룡 바로 앞). 북쪽 벽 = 유리 진열장 2개(화석·운석)와 포스터 2장,
	가운데~동쪽 천장 = 행성 모빌(해 + 행성 6개). 벤치는 좌석 상자 안이라 이름을 Chair* 로 둔다.
	서쪽 벽 아래 = 공룡 알 둥지, 바닥 = 엘리베이터 쪽에서 공룡 쪽으로 걷는 초록 발자국 3개,
	남동쪽 = 화석 발굴 모래판(반쯤 묻힌 뼈). 안내판 = 머리 띠 + 발자국 그림.
	메시(PropAssets.HERO): 뼈대 10 파트 → dinosaur 1(머리 동쪽).
	파트: 폴백 big 17 / props 25 / finish 18 = 60, 메시 big 8 / props 25 / finish 18 = 51.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local DINO_Z = -5 -- 공룡 뼈대 줄(받침대 가운데 z)
local STAGE_TOP = 0.6 -- 받침대 윗면
local LEG_TOP = 4.8 -- 다리 윗면(등뼈 아랫면 4.7 이 다리 안에 묻힌다)
local ROD_Y = 2.3 -- 갈비·꼬리를 받치는 쇠 막대 가운데 높이
local CASE_TOP = 2.6 -- 진열장 받침 윗면
local CASE_Z = Kit.Z_N + 1 -- 진열장 가운데 z(북쪽 벽에 붙는다, 깊이 2)
local FOSSIL_X, METEOR_X = 2, 8 -- 진열장 가운데 x

local BONE = WorldPalette.trim

local function rz(deg: number): CFrame
	return CFrame.Angles(0, 0, math.rad(deg))
end

--- 천장에 매단 행성 1 개 = 줄 + 공 2 파트. 줄은 공 아랫면부터 천장까지(공을 꿰뚫는다). 머리 위라 충돌 없음
local function hang(put: Kit.Put, name: string, pos: Vector3, dia: number, color: Color3)
	local y0 = pos.Y - dia / 2
	local air: Kit.PutOpts = { collide = false }
	Kit.cylinder(put, name .. "String", Vector3.new(pos.X, (y0 + Kit.CEIL) / 2, pos.Z), 0.08, Kit.CEIL - y0, BONE, air)
	Kit.ball(put, name, pos, dia, color, air)
end

local recipe: Kit.Recipe = {
	big = function(put, ctx)
		local room = ctx.room
		-- 관람 벤치(앞줄 좌석 1~3, 뒷줄 4~5). 의자처럼 윗면 SIT_HIP - 0.15
		local h = Kit.SIT_HIP - 0.15
		put(
			"ChairBenchFront",
			Vector3.new(11, h, 2),
			Vector3.new(-9, h / 2, 1.2),
			WorldPalette.benchWood,
			{ seat = true }
		)
		put(
			"ChairBenchBack",
			Vector3.new(7, h, 2),
			Vector3.new(-9, h / 2, 8.2),
			WorldPalette.benchWood,
			{ seat = true }
		)

		-- 공룡 받침대(밟을 수 있는 낮은 단)
		put(
			"Stage",
			Vector3.new(14, STAGE_TOP, 6),
			Vector3.new(-10, STAGE_TOP / 2, DINO_Z),
			WorldPalette.stone,
			{ collide = true }
		)
		-- 공룡 뼈대: 메시(높이 8 → 몸 길이 10 x -15 ~ -5, 폭 4.3 z -7.1 ~ -2.9) 또는 파트 묶음.
		-- 메시 머리가 -Z 라 머리 동쪽 = yaw 270
		if
			not Kit.hero(
				put,
				ctx.ready,
				"Dinosaur",
				PropAssets.HERO.dinosaur,
				Vector3.new(-10, STAGE_TOP, DINO_Z),
				8,
				270
			)
		then
			-- 다리 2(뒷다리·앞다리, 굵은 기둥)
			local legH = LEG_TOP - STAGE_TOP
			for i, x in { -11, -7 } do
				Kit.cylinder(put, `BoneLeg{i}`, Vector3.new(x, STAGE_TOP + legH / 2, DINO_Z), 0.9, legH, BONE)
			end
			-- 등뼈(x -12.5 ~ -5.5, y 4.7 ~ 5.3)
			put("BoneSpine", Vector3.new(7, 0.6, 0.6), Vector3.new(-9, 5, DINO_Z), BONE)
			-- 박물관식 쇠 받침 막대(다리를 꿰뚫고 갈비를 받친다)
			put(
				"Armature",
				Vector3.new(10, 0.2, 0.2),
				Vector3.new(-11.5, ROD_Y, DINO_Z),
				WorldPalette.lampIron,
				{ shape = Enum.PartType.Cylinder }
			)
			-- 갈비 3(막대 위 2.3 ~ 등뼈 4.9)
			for i, x in { -10, -9, -8 } do
				put(`BoneRib{i}`, Vector3.new(0.25, 2.6, 2.2), Vector3.new(x, ROD_Y + 1.3, DINO_Z), BONE)
			end
			-- 긴 목: 등뼈 동쪽 끝(-5.8, 5)에서 40° 위로 길이 5 → 끝 (-1.97, 8.21)
			put("BoneNeck", Vector3.new(5, 0.5, 0.5), Vector3.new(-3.885, 6.607, DINO_Z), BONE, { rot = rz(40) })
			put("BoneHead", Vector3.new(1.4, 0.8, 0.8), Vector3.new(-1.4, 8.3, DINO_Z), BONE)
			-- 꼬리: 등뼈 서쪽 끝(-12.2, 5)에서 25° 아래로 길이 6 → 끝 (-17.64, 2.46). 등뼈에 붙어 있고,
			-- 막대 서쪽 끝(x -16.5)에서는 막대 윗면보다 약 0.37 위라 막대에는 닿지 않는다
			put("BoneTail", Vector3.new(6, 0.4, 0.4), Vector3.new(-14.92, 3.73, DINO_Z), BONE, { rot = rz(25) })
		end

		-- 유리 진열장 2(받침 충돌 + 유리)
		for _, c in { { name = "Fossil", x = FOSSIL_X }, { name = "Meteor", x = METEOR_X } } do
			local name, x = c.name, c.x
			put(
				`Case{name}`,
				Vector3.new(4, CASE_TOP, 2),
				Vector3.new(x, CASE_TOP / 2, CASE_Z),
				room.accent,
				{ collide = true }
			)
			put(
				`Case{name}Glass`,
				Vector3.new(4, 1.8, 2),
				Vector3.new(x, CASE_TOP + 0.9, CASE_Z),
				WorldPalette.deskDome,
				{ material = Enum.Material.Glass, transparency = 0.6 }
			)
		end
	end,

	props = function(put)
		-- 행성 모빌: 가운데~동쪽 천장 가까이(전경을 가리지 않게 높이 단다. 가구 금지 구역 x ≥ 12.5 를 비킨다)
		hang(put, "Sun", Vector3.new(4, 16, 2), 2.4, WorldPalette.sticker)
		hang(put, "Mercury", Vector3.new(6.5, 16.7, 2.5), 0.6, WorldPalette.stone)
		hang(put, "Venus", Vector3.new(5.5, 15.5, -1), 0.9, WorldPalette.lampGlow)
		hang(put, "Earth", Vector3.new(1, 16.1, 0.5), 1.1, WorldPalette.roof.classroom)
		hang(put, "Mars", Vector3.new(2.5, 16.9, 5), 0.8, WorldPalette.cork)
		hang(put, "Jupiter", Vector3.new(8.5, 15.3, 4.5), 1.8, WorldPalette.benchWood)
		local saturn = Vector3.new(-0.5, 15.3, 5.5)
		hang(put, "Saturn", saturn, 1.3, WorldPalette.signBoard)
		Kit.cylinder(put, "SaturnRing", saturn, 2.6, 0.08, WorldPalette.cork, { collide = false })

		-- 진열장 속: 암모나이트(세운 원판)·뼈 화석, 운석
		local fx = FOSSIL_X
		put(
			"Ammonite",
			Vector3.new(0.3, 1.2, 1.2),
			Vector3.new(fx - 0.8, CASE_TOP + 0.6, CASE_Z),
			WorldPalette.cork,
			{ shape = Enum.PartType.Cylinder, rot = CFrame.Angles(0, math.pi / 2, 0) }
		)
		put("FossilBone", Vector3.new(1.4, 0.3, 0.3), Vector3.new(fx + 0.8, CASE_TOP + 0.15, CASE_Z), BONE)
		-- 동쪽 진열장: 운석 + 옆에 하늘색 수정 결정
		Kit.ball(
			put,
			"Meteorite",
			Vector3.new(METEOR_X, CASE_TOP + 0.45, CASE_Z),
			0.9,
			WorldPalette.lampIron,
			{ material = Enum.Material.Slate }
		)
		Kit.ball(
			put,
			"Crystal",
			Vector3.new(METEOR_X + 0.9, CASE_TOP + 0.35, CASE_Z),
			0.7,
			WorldPalette.star,
			{ material = Enum.Material.Glass }
		)

		-- 공룡 알 둥지: 서쪽 벽 아래(뒷줄 벤치 서쪽, 안내판 남쪽). 파스텔 알 3
		Kit.cylinder(put, "Nest", Vector3.new(-17, 0.25, 7), 2.6, 0.5, WorldPalette.trunk)
		for i, e in
			{
				{ x = -17.5, z = 6.7, color = WorldPalette.signBoard },
				{ x = -16.6, z = 7.2, color = WorldPalette.star },
				{ x = -17.1, z = 7.7, color = WorldPalette.blossom },
			}
		do
			Kit.ball(put, `Egg{i}`, Vector3.new(e.x, 0.85, e.z), 1, e.color)
		end

		-- 화석 발굴 모래판: 남동쪽 바닥(가구 금지 구역 x ≥ 12.5 서쪽). 낮은 모래 상자 + 반쯤 묻힌 뼈
		put("DigPit", Vector3.new(5, 0.4, 3.5), Vector3.new(7, 0.2, 11.5), WorldPalette.stone, {
			material = Enum.Material.Sand,
		})
		put(
			"DigBone",
			Vector3.new(1.8, 0.35, 0.35),
			Vector3.new(6.5, 0.4, 11.3),
			BONE,
			{ rot = CFrame.Angles(0, math.rad(20), 0) }
		)
	end,

	finish = function(put, ctx)
		local room = ctx.room
		Kit.rug(put, "Rug", -9, 4.7, 14, 9, room.wall)
		-- 관람 로프: 받침대 앞(z -1.2) 기둥 4 + 줄 1(충돌 없음)
		local ropeZ = -1.2
		for i, x in { -16, -12, -8, -4 } do
			Kit.cylinder(put, `RopePost{i}`, Vector3.new(x, 1.3, ropeZ), 0.3, 2.6, WorldPalette.sticker)
		end
		put(
			"Rope",
			Vector3.new(12, 0.15, 0.15),
			Vector3.new(-10, 2.4, ropeZ),
			room.accent,
			{ shape = Enum.PartType.Cylinder }
		)
		-- 안내판(기울인 판 + 기둥), 앞 벤치 서쪽
		Kit.cylinder(put, "InfoPost", Vector3.new(-17.2, 1.1, 1), 0.3, 2.2, WorldPalette.wood)
		local tilt = CFrame.Angles(math.rad(-30), 0, 0) -- 앞면(+Z)이 남쪽 위를 본다
		local panel = CFrame.new(-17.2, 2.6, 1) * tilt
		put("InfoPanel", Vector3.new(1.8, 1.2, 0.15), panel.Position, WorldPalette.signBoard, { rot = tilt })
		-- 안내판 앞면: 머리 띠 + 초록 발자국 그림(판에 0.02 묻힌다)
		put("InfoTitle", Vector3.new(1.6, 0.25, 0.06), (panel * CFrame.new(0, 0.4, 0.085)).Position, room.accent, {
			rot = tilt,
		})
		put(
			"InfoPrint",
			Vector3.new(0.06, 0.6, 0.6),
			(panel * CFrame.new(0, -0.1, 0.085)).Position,
			WorldPalette.lawn,
			{ shape = Enum.PartType.Cylinder, rot = tilt * CFrame.Angles(0, math.pi / 2, 0) }
		)
		-- 북쪽 벽 포스터(공룡 뒤 = 정글 초록, 진열장 위 = 밤하늘 + 달·별), 서쪽 벽 띠
		Kit.board(put, "DinoPoster", "N", -10, 9, 12, 5, WorldPalette.lawn)
		Kit.board(put, "SpacePoster", "N", 5, 8, 10, 4, WorldPalette.boardDark)
		-- 달(세운 원판)·별: 판 앞면(z -14.2)에 0.03 묻힌다
		put(
			"Moon",
			Vector3.new(0.1, 1.4, 1.4),
			Vector3.new(8, 9, Kit.Z_N + 0.22),
			WorldPalette.signBoard,
			{ shape = Enum.PartType.Cylinder, rot = CFrame.Angles(0, math.pi / 2, 0) }
		)
		put(
			"PosterStar",
			Vector3.new(0.6, 0.6, 0.1),
			Vector3.new(2, 8.8, Kit.Z_N + 0.22),
			WorldPalette.sticker,
			{ rot = rz(45) }
		)
		-- 공룡 발자국 3(나무 바닥과 대비되는 초록): 엘리베이터 도착 쪽에서 공룡 쪽으로 걷는 납작판(통로를 막지 않는다)
		for i, p in { Vector2.new(9, 6.5), Vector2.new(5, 7.8), Vector2.new(1, 6.5) } do
			Kit.cylinder(
				put,
				`Footprint{i}`,
				Vector3.new(p.X, 0.06, p.Y),
				1.6,
				0.12,
				WorldPalette.lawn,
				{ collide = false }
			)
		end
		Kit.board(put, "Banner", "W", 4, 10, 12, 2.5, room.accent)
	end,
}

return recipe
