--!strict
--[[
	옥상정원 레시피(옥상 방, 구역 x -18.9 ~ -2, z -13.9 ~ 13.9). 바닥 = 나무 데크(동쪽 끝 돌 테두리) + 가운데 잔디밭.
	북쪽 = 텃밭(당근 줄·상추 줄·허수아비), 학생 자리 1번은 그 앞 스툴(물뿌리개 옆). 서쪽 가장자리 = 화단 2,
	남쪽 = 화단 1(해바라기 2송이)·연못(분수), 가운데 남쪽 = 등받이 벤치(좌석 2~4). 동쪽 입구(엘리베이터에서 오는 길) =
	덩굴 아치·이름 팻말(동쪽을 본다), 나무 2그루.
	메시(PropAssets.HERO): 덩굴 아치 3 파트 → arch 1(문이 닫혀 있어 통로를 비켜 동쪽 가장자리, 앞이 서쪽 정원 안),
	연못·분수 3 파트 → fountain 1. 둘 다 메시면 남는 자리에 입구 → 벤치 디딤돌 3.
	파트: 폴백 big 21 / props 21 / finish 3 = 45, 메시 big 19 / props 21 / finish 4 = 44.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local BED_H = 0.9 -- 화단 상자 윗면(흙판은 그 위 0.1)
-- 화단 3(가운데 x·z, 가로 w, 깊이 d)
local BEDS = {
	{ x = -17.4, z = -9, w = 3, d = 5 },
	{ x = -17.4, z = 10.5, w = 3, d = 5 },
	{ x = -12.5, z = 11.5, w = 5, d = 3 },
}
local PATCH = { x = -11, z = -10.5, w = 8, d = 5, h = 0.4 } -- 텃밭 흙 상자(x -15 ~ -7, z -13 ~ -8)
local POND = Vector2.new(-6, 10.5) -- 연못 가운데
local POND_H = 0.6 -- 연못 테두리 높이
local ARCH_X = -3 -- 덩굴 아치(입구 통로 z 약 1.7 이 기둥 사이)
local ARCH_Z = { -0.5, 4.5 }
local ARCH_H = 6
local ARCH_MESH = Vector3.new(-3.5, 0, -4.3) -- 아치 메시 밑면 가운데(동쪽 가장자리, 통로 북쪽)
local CARROT = Color3.fromRGB(245, 145, 50) -- 당근 주황(팔레트에 주황이 없다. 빨강 아님 H 29°)
local FACE_Z = CFrame.Angles(0, math.pi / 2, 0) -- 원기둥 축(X)을 Z 로(북쪽을 보는 원판)

local recipe: Kit.Recipe = {
	big = function(put, ctx)
		local room = ctx.room
		local z = Kit.zone(room)
		put(
			"Deck",
			Vector3.new(z.x1 - z.x0, 0.1, z.z1 - z.z0),
			Vector3.new((z.x0 + z.x1) / 2, 0.05, (z.z0 + z.z1) / 2),
			WorldPalette.benchWood,
			{ material = Enum.Material.WoodPlanks }
		)
		-- 동쪽 끝 돌 테두리(옥상 바닥과 데크 경계)
		put("DeckEdge", Vector3.new(0.4, 0.2, z.z1 - z.z0), Vector3.new(z.x1 - 0.2, 0.1, 0), WorldPalette.stone)
		-- 잔디밭(나무 1·벤치 둘레, 텃밭·스툴·디딤돌은 비킨다)
		put(
			"Lawn",
			Vector3.new(10.5, 0.1, 13),
			Vector3.new(-13.65, 0.15, 2.5),
			WorldPalette.lawn,
			{ material = Enum.Material.Grass }
		)
		-- 학생 스툴(텃밭 앞) + 등받이 벤치(좌석 2~4, Chair* = 좌석 상자 안 허용)
		Kit.chair(put, 1, room.seats[1], WorldPalette.wood, room.seatYaw)
		local h = Kit.SIT_HIP - 0.15
		put("ChairBench", Vector3.new(9, h, 2), Vector3.new(-13, h / 2, 6.2), WorldPalette.wood)
		put("ChairBenchBack", Vector3.new(9, 1.6, 0.3), Vector3.new(-13, h + 0.8, 7.1), WorldPalette.wood)
		-- 화단 상자(충돌) + 흙판
		for i, b in BEDS do
			put(
				`Bed{i}`,
				Vector3.new(b.w, BED_H, b.d),
				Vector3.new(b.x, BED_H / 2, b.z),
				WorldPalette.trunk,
				{ collide = true }
			)
			put(
				`Bed{i}Soil`,
				Vector3.new(b.w - 0.4, 0.1, b.d - 0.4),
				Vector3.new(b.x, BED_H + 0.05, b.z),
				WorldPalette.soil
			)
		end
		-- 텃밭 흙 상자
		put(
			"Patch",
			Vector3.new(PATCH.w, PATCH.h, PATCH.d),
			Vector3.new(PATCH.x, PATCH.h / 2, PATCH.z),
			WorldPalette.soil,
			{ material = Enum.Material.Ground }
		)
		-- 나무 2(줄기 충돌 + 둥근 잎)
		for i, p in { Vector2.new(-16.9, -1), Vector2.new(-4.5, -11) } do
			Kit.cylinder(put, `Tree{i}Trunk`, Vector3.new(p.X, 2, p.Y), 0.8, 4, WorldPalette.trunk, { collide = true })
			Kit.ball(
				put,
				`Tree{i}Crown`,
				Vector3.new(p.X, 5.5, p.Y),
				4,
				WorldPalette.leaf[i],
				{ material = Enum.Material.Grass }
			)
		end
		-- 연못·분수: 메시(지름 5) 또는 돌 테두리 + 물(물기둥은 finish)
		if
			not Kit.hero(
				put,
				ctx.ready,
				"Fountain",
				PropAssets.HERO.fountain,
				Vector3.new(POND.X, 0, POND.Y),
				4.1,
				0,
				true
			)
		then
			-- 연못: 돌 테두리 + 물
			Kit.cylinder(put, "PondRim", Vector3.new(POND.X, POND_H / 2, POND.Y), 5, POND_H, WorldPalette.stone)
			Kit.cylinder(
				put,
				"PondWater",
				Vector3.new(POND.X, POND_H - 0.05, POND.Y),
				4.4,
				0.1,
				WorldPalette.star,
				{ transparency = 0.2 }
			)
		end
		-- 덩굴 아치: 메시(동쪽 가장자리, 앞 = 서쪽) 또는 기둥 2(위 덩굴은 finish)
		if not Kit.hero(put, ctx.ready, "Arch", PropAssets.HERO.arch, ARCH_MESH, 5.6, 270, true) then
			for i, az in ARCH_Z do
				Kit.cylinder(put, `ArchPost{i}`, Vector3.new(ARCH_X, ARCH_H / 2, az), 0.6, ARCH_H, WorldPalette.trim)
			end
		end
	end,

	props = function(put, ctx)
		local room = ctx.room
		local top = PATCH.h
		-- 당근 줄: 주황 어깨 + 초록 잎
		put("CarrotRow", Vector3.new(7, 0.3, 0.5), Vector3.new(PATCH.x, top + 0.15, -11.5), CARROT)
		put(
			"CarrotLeaves",
			Vector3.new(7, 0.5, 0.3),
			Vector3.new(PATCH.x, top + 0.55, -11.5),
			WorldPalette.leaf[3],
			{ material = Enum.Material.Grass }
		)
		-- 상추 줄
		for i, x in { -13, -11, -9 } do
			Kit.ball(put, `Lettuce{i}`, Vector3.new(x, top + 0.5, -9.5), 1, WorldPalette.leaf[1])
		end
		-- 화단 1·2 꽃(색 구, 화단마다 2). 화단 3 은 해바라기
		local colors = { WorldPalette.blossom, WorldPalette.sticker, WorldPalette.star }
		for i = 1, 2 do
			local b = BEDS[i]
			for k, off in { -1, 1 } do
				Kit.ball(
					put,
					`Bed{i}Flower{k}`,
					Vector3.new(b.x, BED_H + 0.1 + 0.45, b.z + off),
					0.9,
					colors[(i + k) % 3 + 1]
				)
			end
		end
		-- 해바라기 2송이(화단 3, 벤치 뒤 배경): 줄기 + 노란 꽃잎 원판 + 갈색 씨 원판, 얼굴은 북쪽(정원 안)
		local bed3 = BEDS[3]
		for i, f in { { x = -1.3, y = 4.6 }, { x = 1.3, y = 3.9 } } do
			local x, soil = bed3.x + f.x, BED_H + 0.1
			Kit.cylinder(
				put,
				`Sun{i}Stem`,
				Vector3.new(x, (soil + f.y) / 2, bed3.z),
				0.3,
				f.y - soil,
				WorldPalette.leaf[2]
			)
			put(
				`Sun{i}Head`,
				Vector3.new(0.3, 2, 2),
				Vector3.new(x, f.y, bed3.z - 0.2),
				WorldPalette.sticker,
				{ shape = Enum.PartType.Cylinder, rot = FACE_Z }
			)
			put(
				`Sun{i}Seed`,
				Vector3.new(0.35, 0.9, 0.9),
				Vector3.new(x, f.y, bed3.z - 0.4),
				WorldPalette.trunk,
				{ shape = Enum.PartType.Cylinder, rot = FACE_Z }
			)
		end
		-- 허수아비(텃밭 북서 모서리): 막대 + 팔 벌린 셔츠 + 머리 + 밀짚모자
		local crow = Vector3.new(-14.2, top, -12.5)
		Kit.cylinder(put, "ScarecrowPole", crow + Vector3.new(0, 1.8, 0), 0.3, 3.6, WorldPalette.wood)
		put("ScarecrowShirt", Vector3.new(2.6, 0.9, 0.4), crow + Vector3.new(0, 2.9, 0), WorldPalette.flag)
		Kit.ball(put, "ScarecrowHead", crow + Vector3.new(0, 3.8, 0), 1, WorldPalette.signBoard)
		Kit.cylinder(put, "ScarecrowHat", crow + Vector3.new(0, 4.35, 0), 1.5, 0.2, WorldPalette.cork)
		-- 물뿌리개(학생 스툴 동쪽): 몸통 + 기울인 주둥이
		local can = Vector3.new(-8.6, 0, room.seats[1].Z)
		Kit.cylinder(put, "CanBody", can + Vector3.new(0, 0.45, 0), 0.8, 0.9, room.accent)
		put(
			"CanSpout",
			Vector3.new(1, 0.15, 0.15),
			can + Vector3.new(0.7, 0.75, 0),
			room.accent,
			{ rot = CFrame.Angles(0, 0, math.rad(35)) }
		)
	end,

	finish = function(put, ctx)
		local room = ctx.room
		local archMesh, fountainMesh = ctx.ready(PropAssets.HERO.arch), ctx.ready(PropAssets.HERO.fountain)
		if not archMesh then
			-- 아치 위 덩굴(기둥 윗면에 바로 얹는다)
			put(
				"ArchVine",
				Vector3.new(1, 0.8, ARCH_Z[2] - ARCH_Z[1] + 1),
				Vector3.new(ARCH_X, ARCH_H + 0.4, (ARCH_Z[1] + ARCH_Z[2]) / 2),
				WorldPalette.hedge,
				{ material = Enum.Material.Grass }
			)
		end
		if not fountainMesh then
			-- 분수: 물에 반쯤 잠긴 물보라 돔
			Kit.ball(
				put,
				"FountainSpray",
				Vector3.new(POND.X, POND_H + 0.5, POND.Y),
				1.2,
				WorldPalette.star,
				{ transparency = 0.3 }
			)
		end
		if archMesh and fountainMesh then
			-- 메시로 남는 자리: 입구 → 벤치 디딤돌 3
			for i, p in { Vector2.new(-3.6, 1.7), Vector2.new(-5.4, 2.1), Vector2.new(-7.2, 2.5) } do
				Kit.cylinder(put, `Stone{i}`, Vector3.new(p.X, 0.16, p.Y), 1.4, 0.12, WorldPalette.stone)
			end
		end
		-- 이름 팻말(TowerRender 가 Back 면에 방 이름을 붙인다). 동쪽 입구 옆, 90° 돌려 글씨가 엘리베이터(동쪽)를 보게 한다
		put(
			"Sign",
			Vector3.new(5, 2.4, 0.3),
			Vector3.new(-2.7, 1.2, 9),
			room.accent,
			{ rot = CFrame.Angles(0, math.pi / 2, 0) }
		)
	end,
}

return recipe
