--!strict
--[[
	방 레시피 공용 타입·치수·가구 도우미. 레시피 파일(Rooms/<id>.luau)이 쓴다.
	좌표는 방 로컬: 원점 = 발자국 중심·그 층 바닥 윗면, +Z 남쪽(남쪽 벽 = 창 면), 북쪽이 −Z.
	도우미는 put 만 부른다. 주석의 「n 파트」가 그 도우미가 쓰는 파트 수다(방 ≤ 60, 옥상 방 ≤ 45).
	검사: tools/check_rooms.luau(사용법은 그 파일 머리말).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local PlotLayout = require(ReplicatedStorage.Shared.PlotLayout)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)
local RoomConfig = require(ReplicatedStorage.Shared.Config.RoomConfig)

export type PutOpts = {
	material: Enum.Material?,
	shape: Enum.PartType?,
	rot: CFrame?,
	transparency: number?,
	collide: boolean?, -- 바닥에 놓인 큰 가구만 true
	mesh: PropAssets.MeshAsset?, -- id 0 이거나 불러오기 실패면 보통 파트(P5 가 채운다)
}
export type Put = (name: string, size: Vector3, pos: Vector3, color: Color3, opts: PutOpts?) -> BasePart
export type Ctx = { room: RoomConfig.Room, floor: number }
export type Builder = (put: Put, ctx: Ctx) -> ()
export type Recipe = { big: Builder, props: Builder, finish: Builder }
export type Side = "N" | "W" | "E"

local Kit = {}

local FOOT = PlotLayout.TOWER_FOOTPRINT
local CX, CZ = (FOOT.x0 + FOOT.x1) / 2, (FOOT.z0 + FOOT.z1) / 2
local WALL_T = 0.6
local PILLAR_HALF = 1.5 -- TowerRenderController PILLAR(3) / 2

-- 방 안 치수(방 로컬)
Kit.X_IN = (FOOT.x1 - FOOT.x0) / 2 - WALL_T -- 19.4: 동·서 벽 안쪽 면 x = ±X_IN
Kit.Z_N = FOOT.z0 - CZ + WALL_T -- -14.4: 북쪽 벽 안쪽 면
Kit.Z_S = FOOT.z1 - CZ - WALL_T -- 14.4: 남쪽 벽(창) 안쪽 면
Kit.CEIL = PlotLayout.FLOOR_STEP - 1 -- 18: 천장(위층 바닥판 아랫면)
-- 가구 금지 구역(엘리베이터 도착·탑 패드): x ≥ CLEAR.x and z ≥ CLEAR.z
Kit.CLEAR = Vector2.new(PlotLayout.TOWER_CLEAR.x0 - CX, PlotLayout.TOWER_CLEAR.z0 - CZ) -- (12.5, -2.5)
-- 엘리베이터 기둥이 방 북동 모서리를 파고든다: x ≥ PILLAR.x and z ≤ PILLAR.z
Kit.PILLAR = Vector2.new(FOOT.x1 - CX - PILLAR_HALF, FOOT.z0 - CZ + PILLAR_HALF) -- (18.5, -13.5)
-- 엘리베이터 도착 자리(통로 시작점)
Kit.ARRIVAL = Vector2.new(
	PlotLayout.ELEVATOR_XZ.X - CX + PlotLayout.ARRIVAL_OFFSET.X,
	PlotLayout.ELEVATOR_XZ.Y - CZ + PlotLayout.ARRIVAL_OFFSET.Z
) -- (17.5, 6.5)

-- 의자·책상(학생 좌석 기준). 학생은 좌석에서 −Z(yaw 0)를 보고 앉는다
Kit.SIT_HIP = CharacterBuilder.SIT_HIP
Kit.SIT_DESK = CharacterBuilder.SIT_DESK
local DESK_W, DESK_D, DESK_TOP = 3, 1.6, 0.25
local DESK_AHEAD = 1.9 -- 좌석 → 책상 가운데

--- 가구를 놓을 수 있는 곳. 층 방 = 벽 안쪽 전체, 옥상 방 = RoomConfig 의 zone
function Kit.zone(room: RoomConfig.Room): RoomConfig.Zone
	return room.zone or { x0 = -Kit.X_IN, x1 = Kit.X_IN, z0 = Kit.Z_N, z1 = Kit.Z_S }
end

local function yawOf(deg: number?): CFrame
	return CFrame.Angles(0, math.rad(deg or 0), 0)
end

--- 좌석 s 에서 yaw 로 돌린 오프셋(앞 = −Z)
local function around(s: Vector3, yaw: CFrame, offset: Vector3): Vector3
	return s + yaw:VectorToWorldSpace(offset)
end

--- 좌석 앞 책상 윗면 가운데(책·소품 놓을 자리)
function Kit.deskTop(s: Vector3, yaw: number?): Vector3
	return around(s, yawOf(yaw), Vector3.new(0, Kit.SIT_DESK, -DESK_AHEAD))
end

--- 의자 1 파트(Chair{i}). 벤치·스툴 대신 써도 된다(학생은 앉는 포즈뿐)
function Kit.chair(put: Put, i: number, s: Vector3, color: Color3, yaw: number?)
	local h = Kit.SIT_HIP - 0.15
	local r = yawOf(yaw)
	put(`Chair{i}`, Vector3.new(2, h, 2), around(s, r, Vector3.new(0, h / 2, 0.2)), color, { rot = r })
end

--- 좌석 한 벌 3 파트: 의자 + 책상판 + 앞판(충돌)
function Kit.seat(put: Put, i: number, s: Vector3, chairColor: Color3, deskColor: Color3, yaw: number?)
	local r = yawOf(yaw)
	Kit.chair(put, i, s, chairColor, yaw)
	put(
		`Desk{i}`,
		Vector3.new(DESK_W, DESK_TOP, DESK_D),
		around(s, r, Vector3.new(0, Kit.SIT_DESK - DESK_TOP / 2, -DESK_AHEAD)),
		deskColor,
		{ rot = r }
	)
	local panelH = Kit.SIT_DESK - DESK_TOP
	put(
		`DeskPanel{i}`,
		Vector3.new(DESK_W, panelH, 0.25),
		around(s, r, Vector3.new(0, panelH / 2, -DESK_AHEAD - DESK_D / 2 + 0.125)),
		deskColor,
		{ rot = r, collide = true }
	)
end

--- 낮은 탁자 2 파트: 윗판 + 기둥(충돌). (x, z) 바닥 가운데, h = 윗면 높이
function Kit.lowTable(put: Put, name: string, x: number, z: number, w: number, d: number, h: number, color: Color3)
	local top = 0.3
	put(name, Vector3.new(w, top, d), Vector3.new(x, h - top / 2, z), color)
	put(
		name .. "Leg",
		Vector3.new(math.min(w, d) * 0.4, h - top, math.min(w, d) * 0.4),
		Vector3.new(x, (h - top) / 2, z),
		color,
		{ collide = true }
	)
end

--- 벽에 붙는 판 기준(side 벽 안쪽 면). along = 벽을 따라간 좌표(N 은 x, W·E 는 z), depth = 벽에서 나온 두께
local function onWall(side: Side, along: number, y: number, depth: number): (Vector3, boolean)
	if side == "N" then
		return Vector3.new(along, y, Kit.Z_N + depth / 2), false
	elseif side == "W" then
		return Vector3.new(-Kit.X_IN + depth / 2, y, along), true
	end
	return Vector3.new(Kit.X_IN - depth / 2, y, along), true
end

local function wallSize(sideways: boolean, w: number, h: number, depth: number): Vector3
	return if sideways then Vector3.new(depth, h, w) else Vector3.new(w, h, depth)
end

--- 책장 2 파트: 몸통(충돌, 깊이 1.2) + 앞면 책 판(fill 색). 벽에 붙고 바닥에 선다
function Kit.shelf(put: Put, name: string, side: Side, along: number, w: number, h: number, color: Color3, fill: Color3)
	local d = 1.2
	local pos, sideways = onWall(side, along, h / 2, d)
	put(name, wallSize(sideways, w, h, d), pos, color, { collide = true })
	local front, _ = onWall(side, along, h / 2, d * 2) -- 몸통 앞면에 0.05 묻힌다
	put(name .. "Books", wallSize(sideways, w - 0.4, h - 0.6, 0.1), front, fill)
end

--- 벽 칠판·화면·게시판 1 파트(두께 0.2). y = 가운데 높이
function Kit.board(put: Put, name: string, side: Side, along: number, y: number, w: number, h: number, color: Color3)
	local pos, sideways = onWall(side, along, y, 0.2)
	put(name, wallSize(sideways, w, h, 0.2), pos, color)
end

--- 깔개 1 파트(높이 0.1, 좌석 상자 아래라 학생과 겹쳐도 된다)
function Kit.rug(put: Put, name: string, x: number, z: number, w: number, d: number, color: Color3)
	put(name, Vector3.new(w, 0.1, d), Vector3.new(x, 0.05, z), color, { material = Enum.Material.Fabric })
end

--- 세운 원기둥 1 파트. pos = 가운데
function Kit.cylinder(put: Put, name: string, pos: Vector3, dia: number, h: number, color: Color3, opts: PutOpts?)
	local o: PutOpts = table.clone(opts or {})
	o.shape = Enum.PartType.Cylinder
	o.rot = CFrame.Angles(0, 0, math.pi / 2) -- 원기둥 축(X)을 세운다
	put(name, Vector3.new(h, dia, dia), pos, color, o)
end

--- 공 1 파트. pos = 가운데
function Kit.ball(put: Put, name: string, pos: Vector3, dia: number, color: Color3, opts: PutOpts?)
	local o: PutOpts = table.clone(opts or {})
	o.shape = Enum.PartType.Ball
	put(name, Vector3.one * dia, pos, color, o)
end

--- 화분 2 파트: 화분(원기둥) + 잎(공, 화분에 아래가 묻힌다)
function Kit.plant(put: Put, name: string, x: number, z: number, pot: Color3, leaf: Color3)
	Kit.cylinder(put, name .. "Pot", Vector3.new(x, 0.7, z), 1.4, 1.4, pot)
	Kit.ball(put, name .. "Leaf", Vector3.new(x, 2.4, z), 2.4, leaf, { material = Enum.Material.Grass })
end

return Kit
