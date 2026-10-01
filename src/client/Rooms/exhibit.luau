--!strict
--[[
	전시실(공룡·행성) 레시피. 서북 = 받침대 위 공룡 뼈대(목은 동쪽, 꼬리는 서쪽), 그 앞(남쪽) = 관람 벤치 두 줄.
	학생 자리 1번은 앞 벤치 가운데(공룡 바로 앞). 북쪽 벽 = 유리 진열장 2개(화석·운석)와 포스터 2장,
	가운데~동쪽 천장 = 행성 모빌(해 + 행성 6개). 벤치는 좌석 상자 안이라 이름을 Chair* 로 둔다.
	파트: big 20 / props 18 / finish 11 = 49.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
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

--- 천장에 매단 행성 1 개 = 줄 + 공 2 파트. 줄은 공 아랫면부터 천장까지(공을 꿰뚫는다)
local function hang(put: Kit.Put, name: string, pos: Vector3, dia: number, color: Color3)
	local y0 = pos.Y - dia / 2
	Kit.cylinder(put, name .. "String", Vector3.new(pos.X, (y0 + Kit.CEIL) / 2, pos.Z), 0.08, Kit.CEIL - y0, BONE)
	Kit.ball(put, name, pos, dia, color)
end

local recipe: Kit.Recipe = {
	big = function(put, ctx)
		local room = ctx.room
		-- 관람 벤치(앞줄 좌석 1~3, 뒷줄 4~5). 의자처럼 윗면 SIT_HIP - 0.15
		local h = Kit.SIT_HIP - 0.15
		put("ChairBenchFront", Vector3.new(11, h, 2), Vector3.new(-9, h / 2, 1.2), WorldPalette.benchWood)
		put("ChairBenchBack", Vector3.new(7, h, 2), Vector3.new(-9, h / 2, 8.2), WorldPalette.benchWood)

		-- 공룡 받침대(밟을 수 있는 낮은 단)
		put(
			"Stage",
			Vector3.new(14, STAGE_TOP, 6),
			Vector3.new(-10, STAGE_TOP / 2, DINO_Z),
			WorldPalette.stone,
			{ collide = true }
		)
		-- 다리 4(등뼈 아래로 조금 벌어진다)
		local legH = LEG_TOP - STAGE_TOP
		for i, p in { Vector2.new(-11, -0.3), Vector2.new(-11, 0.3), Vector2.new(-7, -0.3), Vector2.new(-7, 0.3) } do
			Kit.cylinder(put, `BoneLeg{i}`, Vector3.new(p.X, STAGE_TOP + legH / 2, DINO_Z + p.Y), 0.6, legH, BONE)
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
		-- 갈비 4(막대 위 2.3 ~ 등뼈 4.9)
		for i, x in { -10.2, -9.4, -8.6, -7.8 } do
			put(`BoneRib{i}`, Vector3.new(0.25, 2.6, 2.2), Vector3.new(x, ROD_Y + 1.3, DINO_Z), BONE)
		end
		-- 긴 목: 등뼈 동쪽 끝(-5.8, 5)에서 40° 위로 길이 5 → 끝 (-1.97, 8.21)
		put("BoneNeck", Vector3.new(5, 0.5, 0.5), Vector3.new(-3.885, 6.607, DINO_Z), BONE, { rot = rz(40) })
		put("BoneHead", Vector3.new(1.4, 0.8, 0.8), Vector3.new(-1.4, 8.3, DINO_Z), BONE)
		-- 꼬리: 등뼈 서쪽 끝(-12.2, 5)에서 25° 아래로 길이 6 → 끝 (-17.64, 2.46). 등뼈에 붙어 있고,
		-- 막대 서쪽 끝(x -16.5)에서는 막대 윗면보다 약 0.37 위라 막대에는 닿지 않는다
		put("BoneTail", Vector3.new(6, 0.4, 0.4), Vector3.new(-14.92, 3.73, DINO_Z), BONE, { rot = rz(25) })

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

	props = function(put, _ctx)
		-- 행성 모빌: 가운데~동쪽 천장(가구 금지 구역 x ≥ 12.5 를 비킨다)
		hang(put, "Sun", Vector3.new(4, 13.5, 2), 2.4, WorldPalette.sticker)
		hang(put, "Mercury", Vector3.new(6.5, 14.2, 2.5), 0.6, WorldPalette.stone)
		hang(put, "Venus", Vector3.new(5.5, 13, -1), 0.9, WorldPalette.lampGlow)
		hang(put, "Earth", Vector3.new(1, 13.6, 0.5), 1.1, WorldPalette.roof.classroom)
		hang(put, "Mars", Vector3.new(2.5, 14.4, 5), 0.8, WorldPalette.cork)
		hang(put, "Jupiter", Vector3.new(8.5, 12.8, 4.5), 1.8, WorldPalette.benchWood)
		local saturn = Vector3.new(-0.5, 12.8, 5.5)
		hang(put, "Saturn", saturn, 1.3, WorldPalette.signBoard)
		Kit.cylinder(put, "SaturnRing", saturn, 2.6, 0.08, WorldPalette.cork)

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
		Kit.ball(
			put,
			"Meteorite",
			Vector3.new(METEOR_X, CASE_TOP + 0.45, CASE_Z),
			0.9,
			WorldPalette.lampIron,
			{ material = Enum.Material.Slate }
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
		put(
			"InfoPanel",
			Vector3.new(1.8, 1.2, 0.15),
			Vector3.new(-17.2, 2.6, 1),
			WorldPalette.signBoard,
			{ rot = CFrame.Angles(math.rad(-30), 0, 0) }
		)
		-- 북쪽 벽 포스터(공룡 뒤 = 밝은 하늘색, 진열장 위 = 밤하늘), 서쪽 벽 띠
		Kit.board(put, "DinoPoster", "N", -10, 9, 12, 5, room.wall)
		Kit.board(put, "SpacePoster", "N", 5, 8, 10, 4, WorldPalette.boardDark)
		Kit.board(put, "Banner", "W", 4, 10, 12, 2.5, room.accent)
	end,
}

return recipe
