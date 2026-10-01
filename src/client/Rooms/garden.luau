--!strict
--[[
	옥상정원 레시피(옥상 방, 구역 x -18.9 ~ -2, z -13.9 ~ 13.9). 바닥 = 나무 데크.
	북쪽 = 텃밭(당근 줄·상추 줄), 학생 자리 1번은 그 앞 스툴(물뿌리개 옆). 서쪽 가장자리 = 화단 2, 남쪽 = 화단 1·연못(분수)·팻말,
	가운데 남쪽 = 등받이 벤치(좌석 2~4). 동쪽 입구(엘리베이터에서 오는 길) = 덩굴 아치, 동북 = 새집, 나무 2그루.
	파트: big 20 / props 13 / finish 9 = 42.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
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
		-- 덩굴 아치 뼈대: 기둥 2 + 위 들보
		for i, az in ARCH_Z do
			Kit.cylinder(put, `ArchPost{i}`, Vector3.new(ARCH_X, ARCH_H / 2, az), 0.6, ARCH_H, WorldPalette.trim)
		end
		put(
			"ArchBeam",
			Vector3.new(0.6, 0.6, ARCH_Z[2] - ARCH_Z[1] + 0.6),
			Vector3.new(ARCH_X, ARCH_H - 0.1, (ARCH_Z[1] + ARCH_Z[2]) / 2),
			WorldPalette.trim
		)
	end,

	props = function(put, ctx)
		local room = ctx.room
		local top = PATCH.h
		-- 당근 줄: 주황 어깨 + 초록 잎
		put("CarrotRow", Vector3.new(7, 0.15, 0.5), Vector3.new(PATCH.x, top + 0.075, -11.5), WorldPalette.sticker)
		put(
			"CarrotLeaves",
			Vector3.new(7, 0.5, 0.3),
			Vector3.new(PATCH.x, top + 0.4, -11.5),
			WorldPalette.leaf[3],
			{ material = Enum.Material.Grass }
		)
		-- 상추 줄
		for i, x in { -13, -11, -9 } do
			Kit.ball(put, `Lettuce{i}`, Vector3.new(x, top + 0.5, -9.5), 1, WorldPalette.leaf[1])
		end
		-- 화단 꽃(작은 색 구, 화단마다 2)
		local colors = { WorldPalette.blossom, WorldPalette.sticker, WorldPalette.star }
		for i, b in BEDS do
			local long = b.d > b.w
			for k, off in { -1, 1 } do
				local fx, fz = if long then b.x else b.x + off, if long then b.z + off else b.z
				Kit.ball(put, `Bed{i}Flower{k}`, Vector3.new(fx, BED_H + 0.1 + 0.35, fz), 0.7, colors[(i + k) % 3 + 1])
			end
		end
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
		-- 아치 위 덩굴 + 꽃 2
		local vineY = ARCH_H + 0.2 + 0.4
		local mid = (ARCH_Z[1] + ARCH_Z[2]) / 2
		put(
			"ArchVine",
			Vector3.new(1, 0.8, ARCH_Z[2] - ARCH_Z[1] + 1),
			Vector3.new(ARCH_X, vineY, mid),
			WorldPalette.hedge,
			{ material = Enum.Material.Grass }
		)
		for k, off in { -1.2, 1.4 } do
			Kit.ball(put, `ArchFlower{k}`, Vector3.new(ARCH_X, vineY + 0.6, mid + off), 0.6, WorldPalette.blossom)
		end
		-- 분수: 물 가운데 기둥 + 물보라
		Kit.cylinder(put, "FountainSpout", Vector3.new(POND.X, POND_H + 0.5, POND.Y), 0.4, 1, WorldPalette.stone)
		Kit.ball(
			put,
			"FountainSpray",
			Vector3.new(POND.X, POND_H + 1.2, POND.Y),
			0.9,
			WorldPalette.star,
			{ transparency = 0.3 }
		)
		-- 새집(기둥 + 집 + 지붕), 동북
		Kit.cylinder(put, "BirdPole", Vector3.new(-3.5, 2, -6), 0.25, 4, WorldPalette.wood)
		put("BirdHouse", Vector3.new(1, 1, 1), Vector3.new(-3.5, 4.5, -6), WorldPalette.trunk)
		put("BirdRoof", Vector3.new(1.4, 0.2, 1.4), Vector3.new(-3.5, 5.1, -6), room.accent)
		-- 이름 팻말(TowerRender 가 Back 면에 방 이름을 붙인다). 남쪽 난간에 붙어 있어 180° 돌려 글씨가 정원 안(북쪽)을 보게 한다
		put(
			"Sign",
			Vector3.new(5, 2.4, 0.3),
			Vector3.new(-11, 1.2, 13.65),
			room.accent,
			{ rot = CFrame.Angles(0, math.pi, 0) }
		)
	end,
}

return recipe
