--!strict
--[[
	요리실 레시피. 조리대 4개(서쪽 2×2)·냉장고·가스레인지 오븐과 후드(북쪽 벽)·그릇 선반·앞치마 걸이(서쪽 벽)·시식 탁자와 케이크(가운데 북편)·채소 상자(남쪽 창가).
	가스레인지 오븐은 메시(PropAssets.HERO.stove)가 준비되면 메시 1, 아니면 파트 2(몸통·창).
	조리대는 메시(PropAssets.HERO.cookcounter)가 준비되면 조리대마다 메시 1, 아니면 파트 4(몸통·윗판·버너·싱크).
	좌석: [1]~[4] 조리대 남쪽 스툴(북쪽을 본다), [5]·[6] 시식 탁자.
	파트 big 23 · props 25 · finish 12 = 60(폴백) / 오븐 메시 59 / 오븐·조리대 메시 47.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local DARK = WorldPalette.lampIron -- 버너·싱크
local STEEL = WorldPalette.ghost
local APPLIANCE = WorldPalette.trim
local PINK = WorldPalette.blossom

-- 조리대 가운데(x, z). 좌석[1]~[4] 의 북쪽 2.6
local COUNTERS = { Vector2.new(-13, -8.6), Vector2.new(-5, -8.6), Vector2.new(-13, 3.4), Vector2.new(-5, 3.4) }
local COUNTER_TOP = Kit.SIT_DESK
local TABLE = Vector2.new(5, -5.5) -- 시식 탁자

local recipe: Kit.Recipe = {
	big = function(put, ctx)
		local room = ctx.room
		-- 조리대(문짝이 남쪽 스툴 쪽). 메시는 문짝·손잡이·화구·싱크가 붙어 있다.
		-- 메시 문짝 면이 −Z 라 yaw 180 으로 돌려야 남쪽을 본다(Studio 화면 확인)
		for i, c in COUNTERS do
			if
				not Kit.hero(
					put,
					ctx.ready,
					`Counter{i}`,
					PropAssets.HERO.cookcounter,
					Vector3.new(c.X, 0, c.Y),
					COUNTER_TOP,
					180,
					true
				)
			then
				put(
					`Counter{i}`,
					Vector3.new(5, COUNTER_TOP - 0.3, 3),
					Vector3.new(c.X, (COUNTER_TOP - 0.3) / 2, c.Y),
					WorldPalette.deskDome,
					{
						collide = true,
					}
				)
				put(`CounterTop{i}`, Vector3.new(5.2, 0.3, 3.2), Vector3.new(c.X, COUNTER_TOP - 0.15, c.Y), room.accent)
			end
		end
		-- 스툴은 파랑: 나무 시식 탁자·겨자 윗판과 섞이지 않는다
		for i, s in room.seats do
			Kit.chair(put, i, s, WorldPalette.desk, room.seatYaw)
		end
		-- 냉장고(북쪽 벽 동편)
		put("Fridge", Vector3.new(4, 9, 2.5), Vector3.new(14, 4.5, Kit.Z_N + 1.25), APPLIANCE, { collide = true })
		put("FridgeHandle", Vector3.new(0.2, 3, 0.2), Vector3.new(15.4, 4.5, Kit.Z_N + 2.55), WorldPalette.lampIron)
		-- 가스레인지 오븐(높이 4.5 → 발자국 4.06×3.03, 벽에 붙어 남쪽을 본다)
		if
			not Kit.hero(
				put,
				ctx.ready,
				"Oven",
				PropAssets.HERO.stove,
				Vector3.new(9.5, 0, Kit.Z_N + 1.6),
				4.5,
				0,
				true
			)
		then
			put("Oven", Vector3.new(3.5, 3, 2.5), Vector3.new(9.5, 1.5, Kit.Z_N + 1.25), APPLIANCE, { collide = true })
			put("OvenWindow", Vector3.new(2.4, 1.2, 0.1), Vector3.new(9.5, 1.4, Kit.Z_N + 2.5), DARK, {
				material = Enum.Material.Glass,
			})
		end
		-- 레인지 후드(북쪽 벽에 붙는다. 오븐 위 y 7.3~8.7)
		put("RangeHood", Vector3.new(4.2, 1.4, 2.4), Vector3.new(9.5, 8, Kit.Z_N + 1.2), STEEL, {
			material = Enum.Material.Metal,
		})
		Kit.lowTable(put, "TasteTable", TABLE.X, TABLE.Y, 6, 3, Kit.SIT_DESK, WorldPalette.wood)
		Kit.shelf(put, "Shelf", "W", -1, 6, 5, WorldPalette.wood, WorldPalette.trim)
	end,
	props = function(put, ctx)
		local top = COUNTER_TOP
		local counterMesh = ctx.ready(PropAssets.HERO.cookcounter) -- 메시는 버너·싱크가 붙어 있다
		for i, c in COUNTERS do
			local bx, z = c.X - 1.4, c.Y - 0.3
			if not counterMesh then
				Kit.cylinder(put, `Burner{i}`, Vector3.new(bx, top + 0.05, z), 1.2, 0.1, DARK)
				Kit.cylinder(put, `Sink{i}`, Vector3.new(c.X + 1.4, top + 0.04, z), 1.3, 0.08, DARK, {
					material = Enum.Material.Metal,
				})
			end
			if i == 1 or i == 4 then
				Kit.cylinder(
					put,
					`Pot{i}`,
					Vector3.new(bx, top + 0.5, z),
					1,
					0.8,
					STEEL,
					{ material = Enum.Material.Metal }
				)
			else
				Kit.cylinder(put, `Pan{i}`, Vector3.new(bx, top + 0.2, z), 1.1, 0.2, WorldPalette.lampIron)
				put(`PanHandle{i}`, Vector3.new(1, 0.1, 0.2), Vector3.new(bx - 0.95, top + 0.2, z), WorldPalette.wood)
			end
		end
		-- 조리대 가운데 재료: 브로콜리·레몬(버너와 싱크 사이)
		Kit.ball(put, "Broccoli", Vector3.new(COUNTERS[2].X, top + 0.45, COUNTERS[2].Y), 0.9, WorldPalette.hedge, {
			material = Enum.Material.Grass,
		})
		Kit.ball(put, "Lemon", Vector3.new(COUNTERS[3].X, top + 0.35, COUNTERS[3].Y), 0.7, WorldPalette.sticker)
		-- 선반 위 그릇 1·양념통 2(선반 윗면 y 5, x -19.4~-18.2)
		Kit.cylinder(put, "Bowl", Vector3.new(-18.8, 5.2, -2), 1, 0.4, WorldPalette.star)
		local jars = { WorldPalette.sticker, WorldPalette.trunk }
		for i, color in jars do
			Kit.cylinder(put, `Spice{i}`, Vector3.new(-18.8, 5.35, -0.8 + (i - 1) * 0.7), 0.4, 0.7, color)
		end
		-- 케이크(시식 탁자 가운데)
		local cake = Vector3.new(TABLE.X, Kit.SIT_DESK, TABLE.Y - 0.3)
		Kit.cylinder(put, "Cake", cake + Vector3.new(0, 0.4, 0), 1.6, 0.8, PINK)
		Kit.cylinder(put, "CakeCream", cake + Vector3.new(0, 0.875, 0), 1.7, 0.15, WorldPalette.trim)
		Kit.cylinder(put, "Candle", cake + Vector3.new(0, 1.2, 0), 0.15, 0.5, WorldPalette.sticker, {
			material = Enum.Material.Neon,
		})
		-- 남쪽 창가 채소 상자: 나무 상자 + 양배추·호박(빈 남쪽 바닥을 채운다. 통로 z 0~6.5 밖)
		put("VeggieCrate", Vector3.new(3.6, 1.6, 2.2), Vector3.new(6, 0.8, 11.5), WorldPalette.benchWood, {
			material = Enum.Material.Wood,
			collide = true,
		})
		Kit.ball(put, "Cabbage", Vector3.new(5.2, 2.05, 11.5), 1.2, WorldPalette.leaf[3], {
			material = Enum.Material.Grass,
		})
		Kit.ball(put, "Squash", Vector3.new(6.9, 1.95, 11.5), 1, WorldPalette.sticker)
	end,
	finish = function(put, ctx)
		local room = ctx.room
		-- 앞치마 걸이(서쪽 벽): 걸이 막대 + 앞치마 3
		Kit.board(put, "ApronRack", "W", -10, 7, 5, 0.4, WorldPalette.wood)
		local aprons = { room.accent, PINK, WorldPalette.star }
		for i, color in aprons do
			put(
				`Apron{i}`,
				Vector3.new(0.1, 2.4, 1.3),
				Vector3.new(-Kit.X_IN + 0.1, 5.8, -11.5 + (i - 1) * 1.5),
				color,
				{
					material = Enum.Material.Fabric,
				}
			)
		end
		-- 냉장고 문에 붙인 아이 그림(FridgeLine 위)
		put("FridgeDrawing", Vector3.new(1.4, 1.6, 0.1), Vector3.new(13.4, 7.4, Kit.Z_N + 2.53), PINK)
		-- 오늘의 요리 판 + 요리 카드 2
		Kit.board(put, "MenuBoard", "N", -8, 8, 10, 5, WorldPalette.boardDark)
		put("RecipeCard1", Vector3.new(2.4, 1.8, 0.1), Vector3.new(-10.5, 8, Kit.Z_N + 0.23), room.wall)
		put("RecipeCard2", Vector3.new(2.4, 1.8, 0.1), Vector3.new(-5.5, 8, Kit.Z_N + 0.23), PINK)
		put("Clock", Vector3.new(0.2, 2, 2), Vector3.new(4, 11, Kit.Z_N + 0.15), WorldPalette.clockFace, {
			shape = Enum.PartType.Cylinder,
			rot = CFrame.Angles(0, math.pi / 2, 0),
		})
		-- 조리 구역 타일 바닥(연하늘)
		put("TileFloor", Vector3.new(16, 0.1, 20), Vector3.new(-9, 0.05, -2.5), WorldPalette.star, {
			material = Enum.Material.CeramicTiles,
		})
		Kit.plant(put, "Plant", -17.5, 12.5, WorldPalette.trunk, WorldPalette.hedge)
	end,
}

return recipe
