--!strict
--[[
	방 안 레시피. 개선계획 §5.3. TowerRenderController 가 부품 단계별로 부른다.
	  big = 큰 가구(부품 2), props = 소품(부품 3), finish = 마무리 장식(완공).
	좌표는 방 로컬(원점 = 발자국 중심·그 층 바닥 윗면, +Z 남쪽). put 이 부지·층 위치로 옮긴다.
	가구 금지 구역(방 로컬 x ≥ 12.5 and z ≥ -2.5, 엘리베이터·패드 자리)은 비운다. 방 하나 ≤ 60 파트.
	P2 는 모든 방이 같은 임시 레시피(좌석마다 의자·책상, 방 색)를 쓴다. 방별 레시피(Rooms/<id>.luau)는 P3.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local RoomConfig = require(ReplicatedStorage.Shared.Config.RoomConfig)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

export type PutOpts = {
	material: Enum.Material?,
	shape: Enum.PartType?,
	rot: CFrame?,
	transparency: number?,
	collide: boolean?, -- 바닥에 놓인 큰 가구만 true
}
export type Put = (name: string, size: Vector3, pos: Vector3, color: Color3, opts: PutOpts?) -> Part
export type Ctx = { room: RoomConfig.Room, floor: number }
export type Builder = (put: Put, ctx: Ctx) -> ()
export type Recipe = { big: Builder, props: Builder, finish: Builder }

local Rooms = {}

local DESK_W, DESK_D, DESK_TOP = 3, 1.6, 0.25
local NORTH_INNER = -14.4 -- 북쪽 벽 안쪽 면(발자국 z0 + 벽 두께 0.6, 방 로컬)

-- 학생은 좌석에서 −Z 를 보고 앉는다(CharacterBuilder). 의자는 좌석 아래, 책상은 그 앞(−Z)
local shared: Recipe = {
	big = function(put, ctx)
		local accent = ctx.room.accent
		for i, s in ctx.room.seats do
			local seatTop = CharacterBuilder.SIT_HIP - 0.15
			put(`Chair{i}`, Vector3.new(2, seatTop, 2), s + Vector3.new(0, seatTop / 2, 0.2), WorldPalette.wood)
			local deskZ = s.Z - 1.9
			put(
				`Desk{i}`,
				Vector3.new(DESK_W, DESK_TOP, DESK_D),
				Vector3.new(s.X, CharacterBuilder.SIT_DESK - DESK_TOP / 2, deskZ),
				accent
			)
			local panelH = CharacterBuilder.SIT_DESK - DESK_TOP
			put(
				`DeskPanel{i}`,
				Vector3.new(DESK_W, panelH, 0.25),
				Vector3.new(s.X, panelH / 2, deskZ - DESK_D / 2 + 0.125),
				accent,
				{ collide = true }
			)
		end
		put("Board", Vector3.new(14, 6, 0.2), Vector3.new(-4, 8, NORTH_INNER + 0.1), WorldPalette.boardDark)
	end,
	props = function(put, ctx)
		for i, s in ctx.room.seats do
			put(
				`Book{i}`,
				Vector3.new(1, 0.2, 0.7),
				Vector3.new(s.X, CharacterBuilder.SIT_DESK + 0.1, s.Z - 2),
				ctx.room.wall
			)
		end
		put("Pot", Vector3.new(1.4, 1.4, 1.4), Vector3.new(-17, 0.7, -12.5), WorldPalette.trunk, {
			shape = Enum.PartType.Cylinder,
			rot = CFrame.Angles(0, 0, math.pi / 2),
		})
		put("Leaf", Vector3.one * 2.4, Vector3.new(-17, 2.4, -12.5), WorldPalette.hedge, {
			shape = Enum.PartType.Ball,
			material = Enum.Material.Grass,
		})
	end,
	finish = function(put, ctx)
		put("Rug", Vector3.new(18, 0.1, 14), Vector3.new(-4, 0.05, -2.5), ctx.room.wall, {
			material = Enum.Material.Fabric,
		})
		put("Banner", Vector3.new(14, 1.2, 0.2), Vector3.new(-4, 11.8, NORTH_INNER + 0.1), ctx.room.accent)
		put("Clock", Vector3.new(0.2, 2, 2), Vector3.new(8, 11, NORTH_INNER + 0.15), WorldPalette.clockFace, {
			shape = Enum.PartType.Cylinder,
			rot = CFrame.Angles(0, math.pi / 2, 0),
		})
	end,
}

--- 방 id 의 레시피. P2 는 전부 같은 임시 레시피
function Rooms.get(_roomId: string): Recipe
	return shared
end

return Rooms
