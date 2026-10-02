--!strict
--[[
	영어체험실 레시피. 역할놀이 코너 두 곳(서쪽 가게·동쪽 공항 체크인)과 북쪽 세계 지도, 남쪽 책상 3개,
	방 가운데 활주로 깔개와 그 위 천장에 매단 비행기.
	좌석: 1 가게 계산대 뒤, 2 체크인 데스크 뒤, 3~5 남쪽 책상(RoomConfig english).
	가게는 메시(PropAssets.HERO.stall, 앞이 남쪽 좌석·방 가운데 쪽)가 준비되면 계산대·기둥·차양·금전등록기·과일 대신 1 파트.
	그 남는 자리로 서쪽 벽 여행 엽서 3장과 체크인 줄 서기 띠(기둥 2 + 띠)를 단다.
	비행기(HERO.airplane)·지구본(HERO.globe)도 메시가 준비되면 1 파트.
	파트 수: 폴백 59 / 메시 55.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Kit)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local H = Kit.SIT_DESK -- 계산대·데스크 윗면 높이
local ZN = Kit.Z_N

local recipe: Kit.Recipe = {
	big = function(put, ctx) -- 23 파트(메시 19)
		local room = ctx.room
		local s1, s2 = room.seats[1], room.seats[2]
		-- 가게: 계산대 + 기둥 2 + 노란 차양(남쪽 좌석 쪽이 낮다) + 차양 끝 띠. 메시는 계산대 높이가 H 쯤 되게 h 6, 좌석 상자 북쪽에 붙인다
		local shopZ = s1.Z - 1.9
		local stallBase = Vector3.new(s1.X, 0, s1.Z - 2.9)
		if not Kit.hero(put, ctx.ready, "ShopStall", PropAssets.HERO.stall, stallBase, 6, 0, true) then
			put("ShopCounter", Vector3.new(5, H, 1.6), Vector3.new(s1.X, H / 2, shopZ), WorldPalette.benchWood, {
				collide = true,
			})
			for k, dx in { -2.3, 2.3 } do
				put(
					`ShopPost{k}`,
					Vector3.new(0.3, 3.6, 0.3),
					Vector3.new(s1.X + dx, H + 1.8, shopZ),
					WorldPalette.pole
				)
			end
			put(
				"ShopAwning",
				Vector3.new(5.6, 0.8, 2.4),
				Vector3.new(s1.X, H + 3.9, shopZ + 0.4),
				WorldPalette.sticker,
				{
					shape = Enum.PartType.Wedge,
					rot = CFrame.Angles(0, math.pi, 0), -- 높은 쪽을 북쪽으로: 기둥 꼭대기(H + 3.6)에 얹혀 남쪽으로 기운다
				}
			)
			put("ShopAwningEdge", Vector3.new(5.6, 0.4, 0.2), Vector3.new(s1.X, H + 3.7, shopZ + 1.5), room.accent)
		end
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

	props = function(put, ctx) -- 14 파트(메시 10)
		local room = ctx.room
		local s1, s2 = room.seats[1], room.seats[2]
		local shopZ, inZ = s1.Z - 1.9, s2.Z - 1.9
		-- 계산대: 금전등록기 + 과일 2(메시 가게엔 과일이 이미 있다)
		if not ctx.ready(PropAssets.HERO.stall) then
			put("Register", Vector3.new(1.2, 0.7, 0.9), Vector3.new(s1.X + 1.2, H + 0.35, shopZ), WorldPalette.ghost)
			Kit.ball(put, "Fruit1", Vector3.new(s1.X - 1.4, H + 0.3, shopZ), 0.6, WorldPalette.sticker)
			Kit.ball(put, "Fruit2", Vector3.new(s1.X - 0.7, H + 0.3, shopZ), 0.6, WorldPalette.lawn)
		end
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
		-- 지구본: 탁자(윗면 2.4) 위. 폴백은 받침 + 공
		if not Kit.hero(put, ctx.ready, "Globe", PropAssets.HERO.globe, Vector3.new(-4, 2.4, -11.5), 2.6, 0) then
			Kit.cylinder(put, "GlobeStand", Vector3.new(-4, 2.65, -11.5), 0.6, 0.5, WorldPalette.wood)
			Kit.ball(put, "Globe", Vector3.new(-4, 3.8, -11.5), 2, WorldPalette.desk)
		end
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

	finish = function(put, ctx) -- 22 파트(메시 26: 가게 준비 시 +6, 비행기 준비 시 −2)
		local room = ctx.room
		local s2 = room.seats[2]
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
		put("DeparturesLine2", Vector3.new(5, 0.3, 0.3), Vector3.new(s2.X, 7.8, ZN + 0.15), WorldPalette.lampGlow, {
			material = Enum.Material.Neon,
		})
		-- 데스크 포인트 띠
		put("CheckInStripe", Vector3.new(6, 0.6, 0.2), Vector3.new(s2.X, 2, s2.Z - 2.7), room.accent)
		-- 활주로 깔개 + 가운데 흰 선(깔개 윗면에 얹힌다)
		Kit.rug(put, "Runway", 0, 1.5, 18, 3.2, WorldPalette.boardDark)
		put("RunwayLine", Vector3.new(14, 0.04, 0.3), Vector3.new(0, 0.12, 1.5), WorldPalette.trim)
		-- 활주로 위 천장 비행기(코가 서쪽 세계 지도 쪽). 줄이 몸통 밑면부터 천장까지 꿰뚫는다
		Kit.cylinder(
			put,
			"PlaneString",
			Vector3.new(2, (11.8 + Kit.CEIL) / 2, 1.5),
			0.08,
			Kit.CEIL - 11.8,
			WorldPalette.pole
		)
		if not Kit.hero(put, ctx.ready, "Airplane", PropAssets.HERO.airplane, Vector3.new(2, 11.8, 1.5), 2.2, 90) then
			put("PlaneBody", Vector3.new(6, 1.4, 1.4), Vector3.new(2, 12.5, 1.5), WorldPalette.trim, {
				shape = Enum.PartType.Cylinder, -- 축 X 그대로 눕는다
			})
			put("PlaneWing", Vector3.new(1.6, 0.2, 6.4), Vector3.new(2.2, 12.4, 1.5), room.accent)
			put("PlaneTail", Vector3.new(1, 1.4, 0.2), Vector3.new(4.6, 13.3, 1.5), WorldPalette.sticker)
		end
		-- 메시 가게가 계산대 묶음을 1 파트로 줄인 자리: 서쪽 벽 여행 엽서 3 + 체크인 줄 서기 띠(기둥 2 + 띠)
		if ctx.ready(PropAssets.HERO.stall) then
			for k, p in
				{
					{ z = 3, c = WorldPalette.star },
					{ z = 7, c = WorldPalette.blossom },
					{ z = 11, c = WorldPalette.lawn },
				}
			do
				Kit.board(put, `Postcard{k}`, "W", p.z, 7, 3, 2.2, p.c)
			end
			for k, x in { 6.5, 13.5 } do
				Kit.cylinder(put, `QueuePost{k}`, Vector3.new(x, 1.5, -10), 0.3, 3, WorldPalette.pole)
			end
			put("QueueBand", Vector3.new(7, 0.3, 0.1), Vector3.new(10, 2.8, -10), room.accent)
		end
	end,
}

return recipe
