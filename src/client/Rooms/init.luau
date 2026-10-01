--!strict
--[[
	방 안 레시피. 개선계획 §5.3. TowerRenderController 가 부품 단계별로 부른다.
	  big = 큰 가구(부품 2), props = 소품(부품 3), finish = 마무리 장식(완공).
	Rooms.get(id) 는 이 폴더의 <id>.luau(Recipe 를 돌려준다)를 쓰고, 없으면 아래 공용 임시 레시피를 쓴다.
	타입·치수·가구 도우미는 Kit.luau. 검사는 tools/check_rooms.luau.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Kit)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

export type PutOpts = Kit.PutOpts
export type Put = Kit.Put
export type Ctx = Kit.Ctx
export type Builder = Kit.Builder
export type Recipe = Kit.Recipe

local Rooms = {}
Rooms.Kit = Kit

-- 공용 임시 레시피: 좌석마다 의자·책상, 방 색. 옥상 방은 벽 장식 없이 자기 구역 안에만
local shared: Recipe = {
	big = function(put, ctx)
		local room = ctx.room
		for i, s in room.seats do
			Kit.seat(put, i, s, WorldPalette.wood, room.accent, room.seatYaw)
		end
		if room.kind == "floor" then
			Kit.board(put, "Board", "N", -4, 8, 14, 6, WorldPalette.boardDark)
		end
	end,
	props = function(put, ctx)
		local room = ctx.room
		for i, s in room.seats do
			put(
				`Book{i}`,
				Vector3.new(1, 0.2, 0.7),
				Kit.deskTop(s, room.seatYaw) + Vector3.new(0, 0.1, 0),
				room.wall,
				{ rot = CFrame.Angles(0, math.rad(room.seatYaw or 0), 0) }
			)
		end
		-- 층 방은 북서 모서리, 옥상 방은 구역 남동 모서리(좌석·책상이 북쪽에 몰린다)
		local z = Kit.zone(room)
		local px, pz = if room.zone then z.x1 - 2 else z.x0 + 2, if room.zone then z.z1 - 2 else z.z0 + 2
		Kit.plant(put, "Plant", px, pz, WorldPalette.trunk, WorldPalette.hedge)
	end,
	finish = function(put, ctx)
		local room = ctx.room
		if room.kind == "floor" then
			Kit.rug(put, "Rug", -4, 0, 20, 10, room.wall)
			Kit.board(put, "Banner", "N", -4, 11.8, 14, 1.2, room.accent)
			put("Clock", Vector3.new(0.2, 2, 2), Vector3.new(8, 11, Kit.Z_N + 0.15), WorldPalette.clockFace, {
				shape = Enum.PartType.Cylinder,
				rot = CFrame.Angles(0, math.pi / 2, 0),
			})
		else
			local z = Kit.zone(room)
			local cx = (z.x0 + z.x1) / 2
			Kit.rug(put, "Rug", cx, (z.z0 + z.z1) / 2, z.x1 - z.x0 - 2, z.z1 - z.z0 - 2, room.wall)
			-- 이름 팻말(TowerRender 가 "Sign" 남쪽 면에 방 이름을 붙인다)
			put("Sign", Vector3.new(6, 3, 0.3), Vector3.new(cx, 1.5, z.z1 - 0.5), room.accent)
		end
	end,
}

local cache: { [string]: Recipe } = {}

--- 방 id 의 레시피. Rooms/<id>.luau 가 없으면 공용 임시 레시피
function Rooms.get(roomId: string): Recipe
	local known = cache[roomId]
	if known then
		return known
	end
	local module = script:FindFirstChild(roomId)
	local recipe: Recipe = if module and module:IsA("ModuleScript") then require(module) :: any else shared
	cache[roomId] = recipe
	return recipe
end

return Rooms
