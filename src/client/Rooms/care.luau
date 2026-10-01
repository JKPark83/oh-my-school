--!strict
--[[
	돌봄교실 레시피. 북서 낮잠 매트, 서쪽 낮은 원탁, 남쪽 블록 러그·책 읽는 빈백, 북동 장난감 선반·사물함, 남동 간식 탁자.
	좌석: 1·2 원탁 방석, 3·4 빈백, 5 간식 탁자(RoomConfig care). 원탁은 좌석 상자에 걸쳐서 이름이 Desk* 다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Kit)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local ZN, XI = Kit.Z_N, Kit.X_IN
local FABRIC = Enum.Material.Fabric
local TABLE_X, TABLE_Z, TABLE_TOP = -10, -5.5, 2.6 -- 원탁 가운데·윗면 높이
local SNACK_X, SNACK_Z = 8, 9
local MAT_Z = -11.8
local WALL_DISK = CFrame.Angles(0, math.pi / 2, 0) -- 원기둥 축을 벽 쪽(Z)으로

local recipe: Kit.Recipe = {
	big = function(put, ctx) -- 19 파트
		local room = ctx.room
		local seats = room.seats
		-- 낮은 원탁 + 방석 2(앉는 높이 원기둥)
		Kit.cylinder(put, "DeskRound", Vector3.new(TABLE_X, TABLE_TOP - 0.15, TABLE_Z), 6, 0.3, WorldPalette.benchWood)
		Kit.cylinder(
			put,
			"DeskRoundLeg",
			Vector3.new(TABLE_X, (TABLE_TOP - 0.3) / 2, TABLE_Z),
			1.2,
			TABLE_TOP - 0.3,
			WorldPalette.wood,
			{
				collide = true,
			}
		)
		for i, c in { WorldPalette.sticker, WorldPalette.star } do
			Kit.cylinder(put, `Chair{i}`, seats[i] + Vector3.new(0, 0.7, 0), 2, 1.4, c, { material = FABRIC })
		end
		-- 빈백 2: 앉는 몸통 + 뒤 등받이 공
		for k, c in { WorldPalette.blossom, room.accent } do
			local s = seats[k + 2]
			put(`Chair{k + 2}`, Vector3.new(2.2, 1.4, 2.2), s + Vector3.new(0, 0.7, 0), c, { material = FABRIC })
			Kit.ball(put, `Chair{k + 2}Back`, s + Vector3.new(0, 1.4, 1.4), 2.2, c, { material = FABRIC })
		end
		-- 낮잠 매트 2
		for k, x in { -16, -10 } do
			put(
				`NapMat{k}`,
				Vector3.new(5, 0.3, 3),
				Vector3.new(x, 0.15, MAT_Z),
				if k == 1 then WorldPalette.star else room.wall,
				{
					material = FABRIC,
				}
			)
		end
		-- 장난감 선반(북쪽 벽) + 장난감 상자, 사물함(동쪽 벽)
		Kit.shelf(put, "ToyShelf", "N", 9, 6, 4, WorldPalette.trim, room.accent)
		put(
			"ToyBox",
			Vector3.new(2.4, 1.5, 1.6),
			Vector3.new(15, 0.75, -12.5),
			WorldPalette.sticker,
			{ collide = true }
		)
		Kit.shelf(put, "Cubby", "E", -8, 6, 3, WorldPalette.trim, room.wall)
		-- 간식 탁자 + 의자
		Kit.lowTable(put, "SnackTable", SNACK_X, SNACK_Z, 4, 2.4, 2.6, WorldPalette.benchWood)
		Kit.chair(put, 5, seats[5], WorldPalette.wood)
		-- 그림책 낮은 꽂이(남쪽 창 아래)
		put("BookRack", Vector3.new(6, 2.4, 1), Vector3.new(-2.5, 1.2, 13.8), WorldPalette.trim, { collide = true })
	end,

	props = function(put, ctx) -- 21 파트
		-- 원탁 위: 크레파스 상자 + 도화지
		put(
			"Crayons",
			Vector3.new(1.2, 0.3, 0.8),
			Vector3.new(TABLE_X, TABLE_TOP + 0.15, TABLE_Z + 0.5),
			WorldPalette.desk
		)
		-- 바깥 모서리가 원탁(반지름 3) 안: 가운데에서 약 2.55
		put(
			"Paper",
			Vector3.new(1.2, 0.05, 0.9),
			Vector3.new(TABLE_X - 1.5, TABLE_TOP + 0.025, TABLE_Z + 1),
			WorldPalette.trim
		)
		-- 매트 위 베개
		for k, x in { -17.8, -11.8 } do
			put(
				`Pillow{k}`,
				Vector3.new(1.2, 0.4, 2),
				Vector3.new(x, 0.5, MAT_Z),
				WorldPalette.trim,
				{ material = FABRIC }
			)
		end
		-- 선반 위 곰 인형(몸·머리·귀 2)과 블록 2
		local bearX, shelfZ = 7.5, ZN + 0.75
		Kit.ball(put, "BearBody", Vector3.new(bearX, 4.6, shelfZ), 1.4, WorldPalette.cork, { material = FABRIC })
		Kit.ball(put, "BearHead", Vector3.new(bearX, 5.7, shelfZ), 1, WorldPalette.cork, { material = FABRIC })
		for k, dx in { -0.35, 0.35 } do
			Kit.ball(
				put,
				`BearEar{k}`,
				Vector3.new(bearX + dx, 6.15, shelfZ),
				0.4,
				WorldPalette.cork,
				{ material = FABRIC }
			)
		end
		put("ShelfBlock1", Vector3.one * 0.9, Vector3.new(9.6, 4.45, shelfZ), WorldPalette.star)
		put("ShelfBlock2", Vector3.one * 0.9, Vector3.new(10.7, 4.45, shelfZ), WorldPalette.lawn)
		Kit.ball(put, "ToyBall", Vector3.new(12.8, 0.6, -10.8), 1.2, WorldPalette.lampGlow)
		-- 블록 러그 위: 블록 탑(세모 지붕) + 흩어진 블록
		local tower = { WorldPalette.lawn, WorldPalette.sticker, WorldPalette.desk }
		for k, c in tower do
			put(`Block{k}`, Vector3.one, Vector3.new(-14, k - 0.5, 8), c)
		end
		put("BlockRoof", Vector3.one, Vector3.new(-14, 3.5, 8), WorldPalette.blossom, { shape = Enum.PartType.Wedge })
		put("Block4", Vector3.one, Vector3.new(-12, 0.5, 9.5), ctx.room.accent)
		-- 간식: 접시 + 컵 2
		Kit.cylinder(put, "Plate", Vector3.new(SNACK_X, 2.65, SNACK_Z - 0.2), 1.4, 0.1, WorldPalette.trim)
		for k, dx in { -1.2, 1.2 } do
			Kit.cylinder(put, `Cup{k}`, Vector3.new(SNACK_X + dx, 2.85, SNACK_Z + 0.6), 0.4, 0.5, WorldPalette.star)
		end
		-- 꽂이 위 그림책 2
		put("Book1", Vector3.new(1.2, 0.2, 0.8), Vector3.new(-4, 2.5, 13.8), WorldPalette.sticker)
		put("Book2", Vector3.new(1.2, 0.2, 0.8), Vector3.new(-1.5, 2.5, 13.8), WorldPalette.desk)
	end,

	finish = function(put, ctx) -- 15 파트
		local room = ctx.room
		Kit.rug(put, "BlockRug", -13, 8.5, 8, 6, WorldPalette.star)
		Kit.rug(put, "ReadRug", -2.5, 10, 9, 5, room.wall)
		-- 매트 위 이불
		for k, x in { -15.2, -9.2 } do
			put(
				`Blanket{k}`,
				Vector3.new(2.8, 0.1, 2.8),
				Vector3.new(x, 0.35, MAT_Z),
				if k == 1 then WorldPalette.sticker else WorldPalette.blossom,
				{
					material = FABRIC,
				}
			)
		end
		-- 날씨판(해·구름)
		Kit.board(put, "WeatherBoard", "N", 0, 8, 6, 4, WorldPalette.cork)
		put("Sun", Vector3.new(0.3, 1.6, 1.6), Vector3.new(-1.5, 8.3, ZN + 0.15), WorldPalette.sticker, {
			shape = Enum.PartType.Cylinder,
			rot = WALL_DISK,
		})
		put("Cloud", Vector3.new(2, 1, 0.3), Vector3.new(1.4, 8.3, ZN + 0.15), WorldPalette.trim)
		-- 키 재기 자(서쪽 벽) + 눈금 3
		Kit.board(put, "HeightChart", "W", 1.5, 4, 1.4, 7, WorldPalette.trim)
		for k, c in { room.accent, WorldPalette.desk, WorldPalette.sticker } do
			put(`HeightMark{k}`, Vector3.new(0.3, 0.15, 1.6), Vector3.new(-XI + 0.15, k * 2, 1.5), c)
		end
		-- 사물함 위 그림 게시판 + 그림 2
		Kit.board(put, "ArtBoard", "E", -8, 6.5, 6, 3, WorldPalette.cork)
		for k, z in { -9.5, -6.5 } do
			put(
				`Drawing{k}`,
				Vector3.new(0.3, 1.6, 2),
				Vector3.new(XI - 0.15, 6.5, z),
				if k == 1 then WorldPalette.signBoard else WorldPalette.star
			)
		end
		put("Clock", Vector3.new(0.2, 2, 2), Vector3.new(-8, 11, ZN + 0.1), WorldPalette.clockFace, {
			shape = Enum.PartType.Cylinder,
			rot = WALL_DISK,
		})
	end,
}

return recipe
