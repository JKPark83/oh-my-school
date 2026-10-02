--!strict
--[[
	미술실 레시피. 북쪽 줄 = 이젤 3개(학생 자리 1번은 가운데 이젤), 서남쪽 = 큰 작업 탁자(남쪽에 스툴 2개).
	북쪽 벽 = 아이들 그림 액자 3(바탕 + 해·꽃·띠 조각) + 동쪽 끝 그림 말리는 줄(낙서 종이 3),
	동쪽 벽 = 앞치마 걸이, 서쪽 벽 = 물감 선반, 동북 = 석고상.
	이젤은 PropAssets.HERO.easel 메시(그림이 걸린 채, 정면이 좌석 쪽 +Z). 메시가 없으면 파트(마스트·받침·캔버스·그림).
	석고상은 HERO.bust 메시(받침 위, 얼굴이 남쪽). 메시가 없으면 원기둥 몸통 + 공 머리.
	이젤 메시가 있으면 아낀 그림 파트 자리에 동쪽 바닥 도자기 코너(탁자·물레·항아리·꽃병)와
	남쪽 빈 바닥 크레파스 코너(깔개·통·크레파스 3)를 놓는다.
	파트: 폴백 big 19 / props 16 / finish 24 = 59, 메시일 때 big 13 / props 22 / finish 24 = 59.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local EASEL_Z = -8.4 -- 이젤 캔버스 가운데 z(이젤 좌석 z -6 앞)
local EASEL_MESH_Z = -8.6 -- 이젤 메시 밑면 가운데 z(깊이 2.86 → 좌석 상자 z -7 앞에서 끝난다)
local LEDGE_TOP = 2.375 -- 캔버스 받침 윗면
local CANVAS_H = 2.4
local TABLE = { x = -10, z = 6, w = 10, d = 3, h = Kit.SIT_DESK } -- 작업 탁자(남쪽 좌석 4·5 앞)
local STATUE = Vector3.new(4, 0, -9) -- 석고상 받침 바닥 가운데
local CLAY = { x = 9, z = -6, w = 3.5, d = 2.6 } -- 도자기 탁자(석고상 동남쪽, 통로 북쪽)
local CRAYON = Vector3.new(6, 0, 10.5) -- 크레파스 통 바닥 가운데(남쪽 빈 바닥, 통로 남쪽)

local recipe: Kit.Recipe = {
	big = function(put, ctx)
		local room = ctx.room
		for i, s in room.seats do
			Kit.chair(put, i, s, room.accent, room.seatYaw) -- 스툴
		end
		-- 이젤 3개(좌석 1~3 앞): 가운데 마스트 + 받침 + 빈 캔버스
		for i = 1, 3 do
			local x = room.seats[i].X
			if
				not Kit.hero(put, ctx.ready, `Easel{i}`, PropAssets.HERO.easel, Vector3.new(x, 0, EASEL_MESH_Z), 5, 0)
			then
				put(`Easel{i}Post`, Vector3.new(0.25, 5.6, 0.25), Vector3.new(x, 2.8, EASEL_Z - 0.2), WorldPalette.wood)
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
		-- 캔버스 그림(앞면 +Z 에 색 조각 1개, 흰 캔버스가 둘레에 남는다)
		local paints = { WorldPalette.star, WorldPalette.sticker, room.accent }
		local front = EASEL_Z + 0.075 -- 캔버스 앞면
		if not ctx.ready(PropAssets.HERO.easel) then -- 메시는 그림이 이미 걸려 있다
			for i = 1, 3 do
				local x = room.seats[i].X
				local y = LEDGE_TOP + CANVAS_H / 2
				put(`Paint{i}`, Vector3.new(1.8, 1.2, 0.05), Vector3.new(x - 0.2, y + 0.2, front), paints[i])
			end
		else
			-- 이젤 메시가 아낀 파트로 동쪽 바닥 도자기 코너: 탁자 + 물레 + 빚는 항아리 + 다 만든 꽃병
			local h = TABLE.h
			Kit.lowTable(put, "ClayTable", CLAY.x, CLAY.z, CLAY.w, CLAY.d, h, WorldPalette.benchWood)
			Kit.cylinder(put, "ClayWheel", Vector3.new(CLAY.x - 0.6, h + 0.1, CLAY.z), 1.6, 0.2, WorldPalette.stone)
			Kit.cylinder(put, "ClayPot", Vector3.new(CLAY.x - 0.6, h + 0.6, CLAY.z), 0.9, 0.8, WorldPalette.cork)
			Kit.ball(put, "ClayVase", Vector3.new(CLAY.x + 1.0, h + 0.45, CLAY.z + 0.3), 0.9, WorldPalette.desk)
			-- 남쪽 빈 바닥: 깔개 + 큰 크레파스 통 + 크레파스 3(통로 남쪽, 금지 구역 서쪽)
			Kit.rug(put, "CrayonRug", CRAYON.X, CRAYON.Z, 7, 5, WorldPalette.star)
			Kit.cylinder(
				put,
				"CrayonPail",
				CRAYON + Vector3.new(0, 1, 0),
				2.4,
				2,
				WorldPalette.desk,
				{ collide = true }
			)
			local crayons = {
				{ dx = -0.5, dz = -0.3, h = 4.4, c = WorldPalette.sticker },
				{ dx = 0.5, dz = -0.2, h = 5.2, c = WorldPalette.blossom },
				{ dx = 0, dz = 0.5, h = 3.8, c = WorldPalette.pad },
			}
			for k, d in crayons do
				local pos = CRAYON + Vector3.new(d.dx, 0.1 + d.h / 2, d.dz)
				Kit.cylinder(put, `Crayon{k}`, pos, 0.6, d.h, d.c)
			end
		end
		-- 작업 탁자 위: 팔레트 + 물감 2 방울, 붓통 + 붓 2
		local top = TABLE.h
		put("Palette", Vector3.new(1.6, 0.1, 1.1), Vector3.new(-12, top + 0.05, 6), WorldPalette.signBoard)
		for k, c in { WorldPalette.sticker, WorldPalette.star } do
			put(`PaletteDot{k}`, Vector3.new(0.3, 0.08, 0.3), Vector3.new(-12.9 + k * 0.6, top + 0.14, 6 - 0.2), c)
		end
		Kit.cylinder(put, "BrushCup", Vector3.new(-8, top + 0.4, 6), 0.6, 0.8, WorldPalette.desk)
		for k, dx in { -0.12, 0.12 } do
			put(`Brush{k}`, Vector3.new(0.1, 1.2, 0.1), Vector3.new(-8 + dx, top + 0.9, 6), WorldPalette.wood)
		end
		-- 물감 선반 위 물감통 3
		for k, c in { WorldPalette.sticker, WorldPalette.blossom, WorldPalette.lawn } do
			Kit.cylinder(put, `PaintJar{k}`, Vector3.new(-18.8, 4.9, -3 + k * 1.5), 0.6, 0.8, c)
		end
		-- 작업 탁자 가운데: 스케치북 + 그리다 만 그림(살짝 비스듬히)
		local tilt = CFrame.Angles(0, math.rad(12), 0)
		put(
			"Sketchbook",
			Vector3.new(1.8, 0.08, 1.3),
			Vector3.new(-10, top + 0.04, 6),
			WorldPalette.trim,
			{ rot = tilt }
		)
		put(
			"SketchDoodle",
			Vector3.new(0.9, 0.02, 0.6),
			Vector3.new(-10, top + 0.09, 6),
			WorldPalette.blossom,
			{ rot = tilt }
		)
		-- 석고상(받침 윗면 y 3 에 얹는다, 얼굴이 남쪽 방 가운데를 본다. 이 메시는 앞이 −Z 라 yaw 180). 폴백 = 몸통 원기둥 + 머리 공
		if
			not Kit.hero(put, ctx.ready, "StatueBust", PropAssets.HERO.bust, STATUE + Vector3.new(0, 3, 0), 2.4, 180)
		then
			Kit.cylinder(put, "StatueBody", STATUE + Vector3.new(0, 3.6, 0), 1.0, 1.2, WorldPalette.trim)
			Kit.ball(put, "StatueHead", STATUE + Vector3.new(0, 4.6, 0), 1.1, WorldPalette.trim)
		end
	end,

	finish = function(put, ctx)
		local room = ctx.room
		-- 그림 위 조각: 원판(원기둥 축 X 를 벽 밖 +Z 로 돌린다) 또는 기울인 띠
		local disc: Kit.PutOpts = { shape = Enum.PartType.Cylinder, rot = CFrame.Angles(0, math.rad(90), 0) }
		local function tilt(deg: number): Kit.PutOpts
			return { rot = CFrame.Angles(0, 0, math.rad(deg)) }
		end
		-- 북쪽 벽 아이들 그림 액자 3(틀 + 바탕 + 그림 조각): 하늘과 해, 풀밭과 꽃, 노란 바탕에 파란 띠
		local pics = {
			{ x = -14, frame = room.accent, bg = WorldPalette.star, c = WorldPalette.sticker },
			{ x = -7, frame = WorldPalette.desk, bg = WorldPalette.lawn, c = WorldPalette.blossom },
			{ x = 0, frame = WorldPalette.pad, bg = WorldPalette.sticker, c = WorldPalette.desk },
		}
		local marks: { { size: Vector3, at: Vector2, opts: Kit.PutOpts } } = {
			{ size = Vector3.new(0.06, 1.1, 1.1), at = Vector2.new(1.0, 0.5), opts = disc },
			{ size = Vector3.new(0.06, 1.5, 1.5), at = Vector2.new(-0.3, 0), opts = disc },
			{ size = Vector3.new(3.4, 0.6, 0.06), at = Vector2.new(0, 0), opts = tilt(20) },
		}
		for k, p in pics do
			Kit.board(put, `Frame{k}`, "N", p.x, 9, 4.4, 3.2, p.frame)
			put(`Picture{k}`, Vector3.new(3.8, 2.6, 0.1), Vector3.new(p.x, 9, Kit.Z_N + 0.2), p.bg)
			local m = marks[k]
			put(`PictureMark{k}`, m.size, Vector3.new(p.x + m.at.X, 9 + m.at.Y, Kit.Z_N + 0.26), p.c, m.opts)
		end
		-- 북쪽 벽 동쪽 빈 구간: 그림 말리는 줄 + 그림 종이 3(윗변이 줄에 걸린다) + 종이마다 낙서 하나
		put("DryLine", Vector3.new(11.5, 0.08, 0.08), Vector3.new(11.75, 9.6, Kit.Z_N + 0.1), WorldPalette.wood)
		local papers = {
			{ x = 8, bg = WorldPalette.trim, c = room.accent, size = Vector3.new(0.05, 1.0, 1.0), opts = disc },
			{
				x = 11.75,
				bg = WorldPalette.blossom,
				c = WorldPalette.desk,
				size = Vector3.new(1.0, 1.0, 0.05),
				opts = tilt(45),
			},
			{
				x = 15.5,
				bg = WorldPalette.star,
				c = WorldPalette.lawn,
				size = Vector3.new(1.8, 0.6, 0.05),
				opts = tilt(-15),
			},
		}
		for k, p in papers do
			put(`DryPaper{k}`, Vector3.new(2.0, 2.4, 0.05), Vector3.new(p.x, 8.4, Kit.Z_N + 0.15), p.bg)
			put(`DryDoodle{k}`, p.size, Vector3.new(p.x, 8.3, Kit.Z_N + 0.19), p.c, p.opts)
		end
		-- 물감 얼룩 러그(흰 깔판이라 얼룩이 도드라진다)
		Kit.rug(put, "Rug", -9, 1.5, 12, 4, WorldPalette.trim)
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
