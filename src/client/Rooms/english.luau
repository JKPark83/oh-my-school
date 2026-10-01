--!strict
--[[
	영어체험실 레시피. 역할놀이 코너 두 곳(서쪽 가게·동쪽 공항 체크인)과 북쪽 세계 지도, 남쪽 책상 3개.
	좌석: 1 가게 계산대 뒤, 2 체크인 데스크 뒤, 3~5 남쪽 책상(RoomConfig english).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Kit)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local H = Kit.SIT_DESK -- 계산대·데스크 윗면 높이
local ZN = Kit.Z_N

local recipe: Kit.Recipe = {
	big = function(put, ctx) -- 22 파트
		local room = ctx.room
		local s1, s2 = room.seats[1], room.seats[2]
		-- 가게: 계산대 + 기둥 2 + 간판(글자 없는 색 띠)
		local shopZ = s1.Z - 1.9
		put("ShopCounter", Vector3.new(5, H, 1.6), Vector3.new(s1.X, H / 2, shopZ), WorldPalette.benchWood, {
			collide = true,
		})
		for k, dx in { -2.3, 2.3 } do
			put(`ShopPost{k}`, Vector3.new(0.3, 3.6, 0.3), Vector3.new(s1.X + dx, H + 1.8, shopZ), WorldPalette.pole)
		end
		put("ShopSign", Vector3.new(5.4, 1.2, 0.4), Vector3.new(s1.X, H + 4.2, shopZ), WorldPalette.sticker)
		Kit.chair(put, 1, s1, WorldPalette.wood)
		Kit.shelf(put, "ShopShelf", "W", -6, 6, 6, WorldPalette.benchWood, WorldPalette.leaf[1])
		-- 공항: 체크인 데스크 + 가방 저울
		put("CheckIn", Vector3.new(6, H, 1.6), Vector3.new(s2.X, H / 2, s2.Z - 1.9), WorldPalette.trim, {
			collide = true,
		})
		Kit.chair(put, 2, s2, WorldPalette.boardDark)
		put("BagScale", Vector3.new(2.2, 0.8, 1.6), Vector3.new(s2.X + 4.3, 0.4, s2.Z - 1.9), WorldPalette.ghost)
		-- 남쪽 책상 3개
		for i = 3, #room.seats do
			Kit.seat(put, i, room.seats[i], WorldPalette.wood, room.accent)
		end
		-- 세계 지도(바다) + 지구본 탁자
		Kit.board(put, "WorldMap", "N", -4, 9, 12, 7, WorldPalette.star)
		Kit.lowTable(put, "GlobeTable", -4, -11.5, 2.4, 2.4, 2.4, WorldPalette.benchWood)
	end,

	props = function(put, ctx) -- 19 파트
		local room = ctx.room
		local s1, s2 = room.seats[1], room.seats[2]
		local shopZ, inZ = s1.Z - 1.9, s2.Z - 1.9
		-- 계산대: 금전등록기 + 과일 2
		put("Register", Vector3.new(1.2, 0.7, 0.9), Vector3.new(s1.X + 1.2, H + 0.35, shopZ), WorldPalette.ghost)
		Kit.ball(put, "Fruit1", Vector3.new(s1.X - 1.4, H + 0.3, shopZ), 0.6, WorldPalette.sticker)
		Kit.ball(put, "Fruit2", Vector3.new(s1.X - 0.7, H + 0.3, shopZ), 0.6, WorldPalette.lawn)
		-- 체크인: 화면 + 저울 위 가방 + 줄 선 여행 가방 2(손잡이)
		put(
			"CheckInScreen",
			Vector3.new(1.4, 1, 0.15),
			Vector3.new(s2.X + 1, H + 0.5, inZ + 0.5),
			WorldPalette.boardDark
		)
		put("ScaleBag", Vector3.new(1.4, 2, 0.8), Vector3.new(s2.X + 4.3, 1.8, inZ), room.accent)
		for k, b in
			{
				{ x = 8, w = 1.4, h = 2.2, c = WorldPalette.blossom },
				{ x = 10.5, w = 1.6, h = 1.8, c = WorldPalette.desk },
			}
		do
			put(`Suitcase{k}`, Vector3.new(b.w, b.h, 0.8), Vector3.new(b.x, b.h / 2, -11.5), b.c)
			put(
				`Suitcase{k}Handle`,
				Vector3.new(0.8, 0.5, 0.15),
				Vector3.new(b.x, b.h + 0.25, -11.5),
				WorldPalette.benchLeg
			)
		end
		-- 지구본(받침 + 공)
		Kit.cylinder(put, "GlobeStand", Vector3.new(-4, 2.65, -11.5), 0.6, 0.5, WorldPalette.wood)
		Kit.ball(put, "Globe", Vector3.new(-4, 3.8, -11.5), 2, WorldPalette.desk)
		-- 알파벳 블록 더미(2단)
		local blockColors = { WorldPalette.sticker, WorldPalette.star, WorldPalette.lawn, WorldPalette.blossom }
		for k, p in { Vector3.new(-7, 0.5, -2), Vector3.new(-5.8, 0.5, -2), Vector3.new(-6.4, 0.5, -0.8) } do
			put(`ABCBlock{k}`, Vector3.one, p, blockColors[k])
		end
		put("ABCBlock4", Vector3.one, Vector3.new(-6.4, 1.5, -2), blockColors[4], {
			rot = CFrame.Angles(0, math.rad(20), 0),
		})
		put("ABCBlock5", Vector3.one, Vector3.new(-4.6, 0.5, -1.2), WorldPalette.lampGlow)
		-- 책상마다 그림 낱말 카드
		for i = 3, #room.seats do
			put(
				`Card{i}`,
				Vector3.new(1, 0.1, 0.7),
				Kit.deskTop(room.seats[i]) + Vector3.new(0, 0.05, 0),
				WorldPalette.signBoard
			)
		end
	end,

	finish = function(put, ctx) -- 17 파트
		local room = ctx.room
		local s1, s2 = room.seats[1], room.seats[2]
		-- 대륙(지도 판 앞으로 0.1 나온다)
		local continents = {
			{ x = -7.5, y = 10.6, w = 3, h = 2.4, c = WorldPalette.lawn },
			{ x = -6.3, y = 7.4, w = 1.4, h = 2.6, c = WorldPalette.hedge },
			{ x = -3, y = 11.2, w = 1.6, h = 1.2, c = WorldPalette.blossom },
			{ x = -2.8, y = 8.4, w = 2, h = 2.6, c = WorldPalette.sticker },
			{ x = 0, y = 10.6, w = 3, h = 2.4, c = WorldPalette.leaf[3] },
			{ x = 0.6, y = 7, w = 1.4, h = 1, c = WorldPalette.lampGlow },
		}
		for k, c in continents do
			put(`Continent{k}`, Vector3.new(c.w, c.h, 0.3), Vector3.new(c.x, c.y, ZN + 0.15), c.c)
		end
		-- 국기 줄: 줄 + 삼각 깃발 5(빨강 없는 색)
		put("FlagLine", Vector3.new(23, 0.1, 0.1), Vector3.new(-3, 14.6, ZN + 0.05), WorldPalette.pole)
		local flagColors =
			{ WorldPalette.desk, WorldPalette.sticker, WorldPalette.lawn, WorldPalette.trim, WorldPalette.flag }
		for k, c in flagColors do
			put(`Flag{k}`, Vector3.new(0.2, 1.2, 1), Vector3.new(-13 + (k - 1) * 5, 14, ZN + 0.1), c, {
				shape = Enum.PartType.Wedge,
				rot = CFrame.Angles(0, math.pi / 2, math.pi), -- 판을 벽에 붙이고 뾰족한 끝을 아래로
			})
		end
		-- 출발 안내판 + 빛나는 줄
		Kit.board(put, "Departures", "N", s2.X, 8.5, 8, 3.5, WorldPalette.boardDark)
		put("DeparturesLine", Vector3.new(6, 0.3, 0.3), Vector3.new(s2.X, 9.3, ZN + 0.15), WorldPalette.pad, {
			material = Enum.Material.Neon,
		})
		-- 데스크·간판 포인트 띠, 블록 깔개
		put("CheckInStripe", Vector3.new(6, 0.6, 0.2), Vector3.new(s2.X, 2, s2.Z - 2.7), room.accent)
		put("ShopStripe", Vector3.new(5.4, 0.4, 0.5), Vector3.new(s1.X, H + 4.2, s1.Z - 1.9), room.accent)
		Kit.rug(put, "BlockRug", -5.8, -1.5, 5, 4, room.wall)
	end,
}

return recipe
