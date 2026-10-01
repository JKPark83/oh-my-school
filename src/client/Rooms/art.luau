--!strict
--[[
	미술실 레시피. 북쪽 줄 = 이젤 3개(학생 자리 1번은 가운데 이젤), 서남쪽 = 큰 작업 탁자(남쪽에 스툴 2개).
	북쪽 벽 = 아이들 그림 액자, 동쪽 벽 = 앞치마 걸이, 서쪽 벽 = 물감 선반, 동북 = 석고상.
	파트: big 22 / props 18 / finish 16 = 56.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local EASEL_Z = -8.4 -- 이젤 캔버스 가운데 z(이젤 좌석 z -6 앞)
local LEDGE_TOP = 2.375 -- 캔버스 받침 윗면
local CANVAS_H = 2.4
local TABLE = { x = -10, z = 6, w = 10, d = 3, h = Kit.SIT_DESK } -- 작업 탁자(남쪽 좌석 4·5 앞)
local STATUE = Vector3.new(4, 0, -9) -- 석고상 받침 바닥 가운데

local recipe: Kit.Recipe = {
	big = function(put, ctx)
		local room = ctx.room
		for i, s in room.seats do
			Kit.chair(put, i, s, room.accent, room.seatYaw) -- 스툴
		end
		-- 이젤 3개(좌석 1~3 앞): 기둥 2 + 받침 + 빈 캔버스
		for i = 1, 3 do
			local x = room.seats[i].X
			for k, dx in { -1, 1 } do
				put(
					`Easel{i}Post{k}`,
					Vector3.new(0.2, 5, 0.2),
					Vector3.new(x + dx, 2.5, EASEL_Z - 0.2),
					WorldPalette.wood
				)
			end
			put(
				`Easel{i}Ledge`,
				Vector3.new(2.6, 0.15, 0.5),
				Vector3.new(x, LEDGE_TOP - 0.075, EASEL_Z),
				WorldPalette.wood
			)
			put(
				`Canvas{i}`,
				Vector3.new(3, CANVAS_H, 0.15),
				Vector3.new(x, LEDGE_TOP + CANVAS_H / 2, EASEL_Z),
				WorldPalette.trim
			)
		end
		Kit.lowTable(put, "WorkTable", TABLE.x, TABLE.z, TABLE.w, TABLE.d, TABLE.h, WorldPalette.benchWood)
		Kit.shelf(put, "PaintShelf", "W", 0, 6, 4.5, WorldPalette.wood, WorldPalette.star)
		put(
			"Pedestal",
			Vector3.new(1.8, 3, 1.8),
			STATUE + Vector3.new(0, 1.5, 0),
			WorldPalette.stone,
			{ collide = true }
		)
	end,

	props = function(put, ctx)
		local room = ctx.room
		-- 캔버스 그림(앞면 +Z 에 색 조각 2개)
		local paints = {
			{ WorldPalette.star, WorldPalette.lawn },
			{ WorldPalette.sticker, WorldPalette.blossom },
			{ room.accent, WorldPalette.pad },
		}
		local front = EASEL_Z + 0.075 -- 캔버스 앞면
		for i = 1, 3 do
			local x = room.seats[i].X
			local y = LEDGE_TOP + CANVAS_H / 2
			put(`Paint{i}a`, Vector3.new(1.8, 1.0, 0.05), Vector3.new(x - 0.3, y + 0.4, front), paints[i][1])
			put(`Paint{i}b`, Vector3.new(1.2, 0.8, 0.05), Vector3.new(x + 0.5, y - 0.5, front), paints[i][2])
		end
		-- 작업 탁자 위: 팔레트 + 물감 3 방울, 붓통 + 붓 2
		local top = TABLE.h
		put("Palette", Vector3.new(1.6, 0.1, 1.1), Vector3.new(-12, top + 0.05, 6), WorldPalette.signBoard)
		for k, c in { WorldPalette.sticker, WorldPalette.star, WorldPalette.lawn } do
			local dz = if k == 2 then 0.2 else -0.2
			put(`PaletteDot{k}`, Vector3.new(0.3, 0.08, 0.3), Vector3.new(-12.8 + k * 0.4, top + 0.14, 6 + dz), c)
		end
		Kit.cylinder(put, "BrushCup", Vector3.new(-8, top + 0.4, 6), 0.6, 0.8, WorldPalette.desk)
		for k, dx in { -0.12, 0.12 } do
			put(`Brush{k}`, Vector3.new(0.1, 1.2, 0.1), Vector3.new(-8 + dx, top + 0.9, 6), WorldPalette.wood)
		end
		-- 물감 선반 위 물감통 3
		for k, c in { WorldPalette.sticker, WorldPalette.blossom, WorldPalette.lawn } do
			Kit.cylinder(put, `PaintJar{k}`, Vector3.new(-18.8, 4.9, -3 + k * 1.5), 0.6, 0.8, c)
		end
		-- 석고상: 몸통 원기둥 + 머리 공
		Kit.cylinder(put, "StatueBody", STATUE + Vector3.new(0, 3.6, 0), 1.0, 1.2, WorldPalette.trim)
		Kit.ball(put, "StatueHead", STATUE + Vector3.new(0, 4.6, 0), 1.1, WorldPalette.trim)
	end,

	finish = function(put, ctx)
		local room = ctx.room
		-- 북쪽 벽 아이들 그림 액자 4(틀 + 그림)
		local pics = { WorldPalette.star, WorldPalette.lawn, WorldPalette.sticker, WorldPalette.blossom }
		for k, x in { -15, -9, -3, 3 } do
			Kit.board(put, `Frame{k}`, "N", x, 9, 3.4, 2.6, room.accent)
			put(`Picture{k}`, Vector3.new(2.6, 1.8, 0.1), Vector3.new(x, 9, Kit.Z_N + 0.2), pics[k])
		end
		-- 물감 얼룩 러그
		Kit.rug(put, "Rug", -9, 1.5, 12, 4, room.wall)
		local splashes = {
			{ x = -12, z = 1, c = WorldPalette.star },
			{ x = -8, z = 2.4, c = WorldPalette.sticker },
			{ x = -5, z = 0.6, c = WorldPalette.lawn },
		}
		for k, d in splashes do
			put(`Splash{k}`, Vector3.new(1.4, 0.04, 1.0), Vector3.new(d.x, 0.12, d.z), d.c)
		end
		-- 동쪽 벽 앞치마 걸이 + 앞치마 3
		Kit.board(put, "ApronRack", "E", -8, 5.6, 5, 0.3, WorldPalette.wood)
		for k, c in { WorldPalette.blossom, WorldPalette.star, WorldPalette.sticker } do
			put(`Apron{k}`, Vector3.new(0.2, 2.4, 1.2), Vector3.new(Kit.X_IN - 0.15, 4.3, -11 + k * 1.5), c)
		end
	end,
}
return recipe
