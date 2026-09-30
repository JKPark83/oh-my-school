--!strict
--[[
	사물함(시설 3) — 교실 1 동벽 안쪽 면에 붙는 가구. 계획서 §3.6 규약.
	  build(plotCFrame) → Model. 모델 이름 = 시설 id = 이 모듈 이름. 파트 11개(≤25), 전부 BuildKit.part.
	  FacilityConfig.locker 의 center (−46,0,−47.5) 는 동벽 안쪽 면 위 바닥점, size (1.6,6,12) 는 몸통이다.
	  몸통은 벽에서 방 쪽(−X)으로 붙는다. 서쪽 면에 문짝 8개(4열×2단), 위 마감·아래 받침.
	  자리·문 없음.
	  부품 3개(PartIndex): (1) 몸통+아래 받침 (2) 아랫단 문짝 4 (3) 윗단 문짝 4+위 마감.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local PropAssets = require(ReplicatedStorage.Shared.Config.PropAssets)

local locker = {}

local COLOR_PRIMARY = Color3.fromRGB(150, 150, 155)
local MATERIAL = Enum.Material.Metal

local FACILITY_ID = script.Name

local COLS, ROWS = 4, 2
local PANEL_T = 0.1
local PANEL_GAP = 0.2
local TRIM_T = 0.3

local COLOR_TRIM = Color3.fromRGB(70, 72, 76)
-- 문짝 색은 열마다 다르다(파스텔). 문 그림(PropAssets.INTERIOR.LOCKER_DOOR)이 투명 덧그림이라 이 색이 비친다.
-- 그림 id 가 0 이면 색 판만 남는다
local DOOR_COLORS = {
	Color3.fromRGB(128, 178, 222),
	Color3.fromRGB(138, 204, 150),
	Color3.fromRGB(240, 208, 112),
	Color3.fromRGB(236, 158, 176),
}

--- 부지 로컬 위치(+회전) → 월드 CFrame
local function at(plotCFrame: CFrame, x: number, y: number, z: number, rot: CFrame?): CFrame
	local cf = plotCFrame * CFrame.new(x, y, z)
	return if rot then cf * rot else cf
end

-- 지금 짓는 부품 번호. build 가 1 로 시작해 부품 경계마다 올린다
local partIndex = 1

--- BuildKit.part 를 월드 CFrame 으로 부르고 부품 번호(Keys.ATTR_PART_INDEX)를 붙인다
local function put(parent: Instance, name: string, size: Vector3, cf: CFrame, opts: BuildKit.Opts): Part
	opts.cframe = cf.Rotation
	local p = BuildKit.part(parent, name, size, cf.Position, opts)
	p:SetAttribute(Keys.ATTR_PART_INDEX, partIndex)
	return p
end

function locker.build(plotCFrame: CFrame): Model
	local row = FacilityConfig.BY_ID[FACILITY_ID]
	assert(row ~= nil, `FacilityConfig 에 {FACILITY_ID} 가 없다`)

	local model = Instance.new("Model")
	model.Name = FACILITY_ID
	model:SetAttribute(Keys.ATTR_FACILITY_ID, FACILITY_ID)

	local wallX, floorY, cz = row.center.X, row.center.Y, row.center.Z
	local depth, height, length = row.size.X, row.size.Y, row.size.Z
	local cx = wallX - depth / 2 -- 몸통 중심. 동쪽 면이 벽에 닿는다

	partIndex = 1
	put(model, "Body", row.size, at(plotCFrame, cx, floorY + height / 2, cz), {
		color = COLOR_PRIMARY,
		material = MATERIAL,
	})

	-- 문짝: 서쪽 면에 얇게 얹는다. 열·단 사이 틈으로 몸통 색이 보인다
	local panelW = length / COLS - PANEL_GAP
	local panelH = height / ROWS - PANEL_GAP
	local faceX = wallX - depth - PANEL_T / 2
	for c = 1, COLS do
		for r = 1, ROWS do
			partIndex = r + 1 -- 아랫단은 부품 2, 윗단은 부품 3
			local z = cz - length / 2 + (c - 0.5) * (length / COLS)
			local y = floorY + (r - 0.5) * (height / ROWS)
			local door = put(
				model,
				string.format("Door%02d", (c - 1) * ROWS + r),
				Vector3.new(PANEL_T, panelH, panelW),
				at(plotCFrame, faceX, y, z),
				{
					color = DOOR_COLORS[c],
					material = Enum.Material.SmoothPlastic,
					collide = false,
				}
			)
			BuildKit.decal(door, Enum.NormalId.Left, PropAssets.INTERIOR.LOCKER_DOOR) -- 로컬 −X = 방 쪽
		end
	end

	-- 위 마감·아래 받침: 몸통보다 조금 크다. 서쪽으로 문짝(PANEL_T)보다 더 나와야 문짝 앞면과 겹치지 않는다
	local trimSize = Vector3.new(depth + 0.4, TRIM_T, length + 0.4)
	partIndex = 3
	put(model, "Trim", trimSize, at(plotCFrame, cx, floorY + height + TRIM_T / 2, cz), {
		color = COLOR_TRIM,
		material = Enum.Material.Metal,
		collide = false,
	})
	partIndex = 1
	put(model, "Plinth", trimSize, at(plotCFrame, cx, floorY + TRIM_T / 2, cz), {
		color = COLOR_TRIM,
		material = Enum.Material.Metal,
	})

	BuildKit.assertPartIndex(model, FacilityConfig.partCount(FACILITY_ID))
	return model
end

return locker
