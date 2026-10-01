--!strict
--[[
	요리실 레시피. 조리대 4개(서쪽 2×2)·냉장고·가스레인지 오븐(북쪽 벽)·그릇 선반·앞치마 걸이(서쪽 벽)·시식 탁자와 케이크(가운데 북편).
	가스레인지 오븐은 메시(PropAssets.HERO.stove)가 준비되면 메시 1, 아니면 파트 2(몸통·창).
	좌석: [1]~[4] 조리대 남쪽 스툴(북쪽을 본다), [5]·[6] 시식 탁자.
	파트 big 23 · props 22 · finish 14 = 59(폴백) / big 22 → 58(메시).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(script.Parent.Kit)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local rgb = Color3.fromRGB
local DARK = rgb(52, 54, 60) -- 버너·싱크
local STEEL = rgb(200, 205, 212)
local APPLIANCE = rgb(236, 240, 244)
local PINK = rgb(255, 176, 206)

-- 조리대 가운데(x, z). 좌석[1]~[4] 의 북쪽 2.6
local COUNTERS = { Vector2.new(-13, -8.6), Vector2.new(-5, -8.6), Vector2.new(-13, 3.4), Vector2.new(-5, 3.4) }
local COUNTER_TOP = Kit.SIT_DESK
local TABLE = Vector2.new(5, -5.5) -- 시식 탁자

local recipe: Kit.Recipe = {
	big = function(put, ctx)
		local room = ctx.room
		for i, c in COUNTERS do
			put(
				`Counter{i}`,
				Vector3.new(5, COUNTER_TOP - 0.3, 3),
				Vector3.new(c.X, (COUNTER_TOP - 0.3) / 2, c.Y),
				WorldPalette.trim,
				{
					collide = true,
				}
			)
			put(`CounterTop{i}`, Vector3.new(5.2, 0.3, 3.2), Vector3.new(c.X, COUNTER_TOP - 0.15, c.Y), room.accent)
		end
		for i, s in room.seats do
			Kit.chair(put, i, s, WorldPalette.wood, room.seatYaw)
		end
		-- 냉장고(북쪽 벽 동편)
		put("Fridge", Vector3.new(4, 9, 2.5), Vector3.new(14, 4.5, Kit.Z_N + 1.25), APPLIANCE, { collide = true })
		put("FridgeLine", Vector3.new(3.8, 0.1, 0.1), Vector3.new(14, 6, Kit.Z_N + 2.5), STEEL)
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
		Kit.lowTable(put, "TasteTable", TABLE.X, TABLE.Y, 6, 3, Kit.SIT_DESK, WorldPalette.wood)
		Kit.shelf(put, "Shelf", "W", -1, 6, 5, WorldPalette.wood, WorldPalette.trim)
	end,
	props = function(put, _ctx)
		local top = COUNTER_TOP
		for i, c in COUNTERS do
			local bx, z = c.X - 1.4, c.Y - 0.3
			Kit.cylinder(put, `Burner{i}`, Vector3.new(bx, top + 0.05, z), 1.2, 0.1, DARK)
			Kit.cylinder(put, `Sink{i}`, Vector3.new(c.X + 1.4, top + 0.04, z), 1.3, 0.08, DARK, {
				material = Enum.Material.Metal,
			})
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
		-- 선반 위 그릇 2·양념통 3(선반 윗면 y 5, x -19.4~-18.2)
		Kit.cylinder(put, "Bowl1", Vector3.new(-18.8, 5.2, -3.2), 1, 0.4, WorldPalette.trim)
		Kit.cylinder(put, "Bowl2", Vector3.new(-18.8, 5.2, -2), 1, 0.4, WorldPalette.star)
		local jars = { WorldPalette.sticker, WorldPalette.hedge, WorldPalette.trunk }
		for i, color in jars do
			Kit.cylinder(put, `Spice{i}`, Vector3.new(-18.8, 5.35, -0.8 + (i - 1) * 0.7), 0.4, 0.7, color)
		end
		-- 케이크(시식 탁자 가운데)
		local cake = Vector3.new(TABLE.X, Kit.SIT_DESK, TABLE.Y - 0.3)
		Kit.cylinder(put, "Cake", cake + Vector3.new(0, 0.4, 0), 1.6, 0.8, rgb(255, 224, 232))
		Kit.cylinder(put, "CakeCream", cake + Vector3.new(0, 0.875, 0), 1.7, 0.15, WorldPalette.trim)
		Kit.cylinder(put, "Candle", cake + Vector3.new(0, 1.2, 0), 0.15, 0.5, WorldPalette.sticker, {
			material = Enum.Material.Neon,
		})
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
		-- 조리대 줄 위 천장 조명 2
		for i, c in { COUNTERS[1], COUNTERS[3] } do
			put(`Lamp{i}`, Vector3.new(10, 0.4, 1.2), Vector3.new(-9, Kit.CEIL - 0.2, c.Y), WorldPalette.lampGlow)
		end
		-- 오늘의 요리 판 + 요리 카드 2
		Kit.board(put, "MenuBoard", "N", -8, 8, 10, 5, WorldPalette.boardDark)
		put("RecipeCard1", Vector3.new(2.4, 1.8, 0.1), Vector3.new(-10.5, 8, Kit.Z_N + 0.23), room.wall)
		put("RecipeCard2", Vector3.new(2.4, 1.8, 0.1), Vector3.new(-5.5, 8, Kit.Z_N + 0.23), PINK)
		Kit.board(put, "Banner", "N", -8, 11.8, 10, 1.2, room.accent)
		put("Clock", Vector3.new(0.2, 2, 2), Vector3.new(4, 11, Kit.Z_N + 0.15), WorldPalette.clockFace, {
			shape = Enum.PartType.Cylinder,
			rot = CFrame.Angles(0, math.pi / 2, 0),
		})
		Kit.rug(put, "TileFloor", -9, -2.5, 16, 20, WorldPalette.trim)
		Kit.plant(put, "Plant", -17.5, 12.5, WorldPalette.trunk, WorldPalette.hedge)
	end,
}

return recipe
