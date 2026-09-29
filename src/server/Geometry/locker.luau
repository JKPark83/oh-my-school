--!strict
--[[
	사물함(시설 3) — 교실 1 동벽 안쪽 면에 붙는 가구. 계획서 §3.6 규약.
	  build(plotCFrame, skinIndex) → Model. 모델 이름 = 시설 id = 이 모듈 이름. 파트 11개(≤25), 전부 BuildKit.part.
	  FacilityConfig.locker 의 center (−46,0,−47.5) 는 동벽 안쪽 면 위 바닥점, size (1.6,6,12) 는 몸통이다.
	  몸통은 벽에서 방 쪽(−X)으로 붙는다. 서쪽 면에 문짝 8개(4열×2단), 위 마감·아래 받침.
	  스킨: SkinRole "primary" = 몸통, "secondary" = 문짝. 색과 재질 모두 스킨 것을 쓴다. 자리·문 없음.
	  SkinSign = 사물함 남쪽 끝 옆 눈높이. BasePart 아래가 아니므로 CFrame 에 월드 CFrame 을 그대로 넣는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local SkinConfig = require(ReplicatedStorage.Shared.Config.SkinConfig)

local locker = {}

local ROLE_PRIMARY = "primary"
local ROLE_SECONDARY = "secondary"

local FACILITY_ID = script.Name
local SIGN_EYE = 4.5

local COLS, ROWS = 4, 2
local PANEL_T = 0.1
local PANEL_GAP = 0.2
local TRIM_T = 0.3

local COLOR_TRIM = Color3.fromRGB(70, 72, 76)

--- 부지 로컬 위치(+회전) → 월드 CFrame
local function at(plotCFrame: CFrame, x: number, y: number, z: number, rot: CFrame?): CFrame
	local cf = plotCFrame * CFrame.new(x, y, z)
	return if rot then cf * rot else cf
end

--- BuildKit.part 를 월드 CFrame 으로 부른다
local function put(parent: Instance, name: string, size: Vector3, cf: CFrame, opts: BuildKit.Opts): Part
	opts.cframe = cf.Rotation
	return BuildKit.part(parent, name, size, cf.Position, opts)
end

--- 월드 CFrame 을 그대로 가진 Attachment(부모가 BasePart 가 아니다)
local function attach(parent: Instance, name: string, cf: CFrame): Attachment
	local att = Instance.new("Attachment")
	att.Name = name
	att.CFrame = cf
	att.Parent = parent
	return att
end

local function skinned(part: Part, role: string): Part
	part:SetAttribute(Keys.ATTR_SKIN_ROLE, role)
	return part
end

function locker.build(plotCFrame: CFrame, skinIndex: number): Model
	local row = FacilityConfig.BY_ID[FACILITY_ID]
	assert(row ~= nil, `FacilityConfig 에 {FACILITY_ID} 가 없다`)
	local skin = SkinConfig.get(FACILITY_ID, skinIndex)

	local model = Instance.new("Model")
	model.Name = FACILITY_ID
	model:SetAttribute(Keys.ATTR_FACILITY_ID, FACILITY_ID)
	model:SetAttribute(Keys.ATTR_SKIN, skinIndex)

	local wallX, floorY, cz = row.center.X, row.center.Y, row.center.Z
	local depth, height, length = row.size.X, row.size.Y, row.size.Z
	local cx = wallX - depth / 2 -- 몸통 중심. 동쪽 면이 벽에 닿는다

	skinned(
		put(model, "Body", row.size, at(plotCFrame, cx, floorY + height / 2, cz), {
			color = skin.primary,
			material = skin.material,
		}),
		ROLE_PRIMARY
	)

	-- 문짝: 서쪽 면에 얇게 얹는다. 열·단 사이 틈으로 몸통 색이 보인다
	local panelW = length / COLS - PANEL_GAP
	local panelH = height / ROWS - PANEL_GAP
	local faceX = wallX - depth - PANEL_T / 2
	for c = 1, COLS do
		for r = 1, ROWS do
			local z = cz - length / 2 + (c - 0.5) * (length / COLS)
			local y = floorY + (r - 0.5) * (height / ROWS)
			skinned(
				put(
					model,
					string.format("Door%02d", (c - 1) * ROWS + r),
					Vector3.new(PANEL_T, panelH, panelW),
					at(plotCFrame, faceX, y, z),
					{
						color = skin.secondary,
						material = skin.material,
						collide = false,
					}
				),
				ROLE_SECONDARY
			)
		end
	end

	-- 위 마감·아래 받침: 몸통보다 조금 크다. 서쪽으로 문짝(PANEL_T)보다 더 나와야 문짝 앞면과 겹치지 않는다
	local trimSize = Vector3.new(depth + 0.4, TRIM_T, length + 0.4)
	put(model, "Trim", trimSize, at(plotCFrame, cx, floorY + height + TRIM_T / 2, cz), {
		color = COLOR_TRIM,
		material = Enum.Material.Metal,
		collide = false,
	})
	put(model, "Plinth", trimSize, at(plotCFrame, cx, floorY + TRIM_T / 2, cz), {
		color = COLOR_TRIM,
		material = Enum.Material.Metal,
	})

	attach(model, Keys.SKIN_SIGN, at(plotCFrame, cx - 1, floorY + SIGN_EYE, cz + length / 2 + 1))

	return model
end

return locker
