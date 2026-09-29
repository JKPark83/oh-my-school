--!strict
--[[
	칠판(시설 2) — 교실 1 북벽 안쪽 면에 붙는 가구. 계획서 §3.6 규약.
	  build(plotCFrame, skinIndex) → Model. 모델 이름 = 시설 id = 이 모듈 이름. 파트 6개(≤25), 전부 BuildKit.part.
	  FacilityConfig.board 의 center (−60,0,−61.5) 는 북벽 안쪽 면 위 바닥점이다. 칠판은 그 면에서 방 쪽(+Z)으로 붙는다.
	  틀(secondary) + 칠판면(primary) + 분필받침 + 지우개 + 시계 + 급훈 액자. 자리·문 없음.
	  SkinSign = 칠판 왼쪽 옆 눈높이. BasePart 아래가 아니므로 CFrame 에 월드 CFrame 을 그대로 넣는다.
	  글자는 BuildKit.surfaceText(한글은 SurfaceGui 로만 낼 수 있다).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local SkinConfig = require(ReplicatedStorage.Shared.Config.SkinConfig)

local board = {}

local ROLE_PRIMARY = "primary"
local ROLE_SECONDARY = "secondary"
-- TODO(통합): 급훈·칠판 글씨는 기획서에 없다. 문구를 정하면 Config 로 뺀다
local TEXT_MOTTO = "바르고 슬기롭게"
local TEXT_CHALK = "오늘도 즐겁게!"

local FACILITY_ID = script.Name
local SIGN_EYE = 4.5

local BOARD_BOTTOM = 3 -- 칠판면 아랫변 높이
local FRAME_PAD = 0.3 -- 틀이 칠판면보다 사방으로 더 나온 폭
local FRAME_T = 0.3
local FACE_T = 0.2
local TRAY = Vector3.new(0, 0.2, 0.6) -- X 는 칠판 폭
local ERASER = Vector3.new(1.2, 0.4, 0.4)
local CLOCK_D = 1.6
local MOTTO = Vector3.new(5, 1.2, 0.2)

local C = {
	tray = Color3.fromRGB(150, 150, 148),
	eraser = Color3.fromRGB(60, 62, 66),
	clock = Color3.fromRGB(240, 240, 236),
	motto = Color3.fromRGB(236, 230, 214),
	text = Color3.fromRGB(40, 40, 44),
	chalk = Color3.fromRGB(240, 240, 236),
}

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

function board.build(plotCFrame: CFrame, skinIndex: number): Model
	local row = FacilityConfig.BY_ID[FACILITY_ID]
	assert(row ~= nil, `FacilityConfig 에 {FACILITY_ID} 가 없다`)
	local skin = SkinConfig.get(FACILITY_ID, skinIndex)

	local model = Instance.new("Model")
	model.Name = FACILITY_ID
	model:SetAttribute(Keys.ATTR_FACILITY_ID, FACILITY_ID)
	model:SetAttribute(Keys.ATTR_SKIN, skinIndex)

	local cx, floorY, wallZ = row.center.X, row.center.Y, row.center.Z
	local w, h = row.size.X, row.size.Y
	local faceY = floorY + BOARD_BOTTOM + h / 2

	-- 틀: 벽면에 붙는다. 칠판면: 틀 앞에 얹는다
	skinned(
		put(
			model,
			"Frame",
			Vector3.new(w + FRAME_PAD * 2, h + FRAME_PAD * 2, FRAME_T),
			at(plotCFrame, cx, faceY, wallZ + FRAME_T / 2),
			{
				color = skin.secondary,
				material = skin.material,
			}
		),
		ROLE_SECONDARY
	)
	local face = skinned(
		put(model, "Face", Vector3.new(w, h, FACE_T), at(plotCFrame, cx, faceY, wallZ + FRAME_T + FACE_T / 2), {
			color = skin.primary,
			material = skin.material,
		}),
		ROLE_PRIMARY
	)
	BuildKit.surfaceText(face, Enum.NormalId.Back, TEXT_CHALK, C.chalk, 0.9)

	-- 분필받침 + 지우개
	local trayZ = wallZ + FRAME_T + TRAY.Z / 2
	put(model, "Tray", Vector3.new(w, TRAY.Y, TRAY.Z), at(plotCFrame, cx, floorY + BOARD_BOTTOM - TRAY.Y / 2, trayZ), {
		color = C.tray,
		material = Enum.Material.Metal,
	})
	put(model, "Eraser", ERASER, at(plotCFrame, cx + w / 2 - 1.2, floorY + BOARD_BOTTOM + ERASER.Y / 2, trayZ), {
		color = C.eraser,
		material = Enum.Material.Fabric,
		collide = false,
	})

	-- 시계: Cylinder 축이 X 라 Y 로 90° 돌려 면이 방(+Z)을 보게 한다
	put(
		model,
		"Clock",
		Vector3.new(0.2, CLOCK_D, CLOCK_D),
		at(plotCFrame, cx + w / 2 + 3, floorY + 9.5, wallZ + 0.1, CFrame.Angles(0, math.pi / 2, 0)),
		{
			color = C.clock,
			material = Enum.Material.SmoothPlastic,
			shape = Enum.PartType.Cylinder,
			collide = false,
		}
	)

	-- 급훈 액자: 칠판 위 가운데
	local motto = put(
		model,
		"Motto",
		MOTTO,
		at(plotCFrame, cx, floorY + BOARD_BOTTOM + h + FRAME_PAD + 0.4 + MOTTO.Y / 2, wallZ + MOTTO.Z / 2),
		{
			color = C.motto,
			material = Enum.Material.Wood,
			collide = false,
		}
	)
	BuildKit.surfaceText(motto, Enum.NormalId.Back, TEXT_MOTTO, C.text, 0.55)

	attach(model, Keys.SKIN_SIGN, at(plotCFrame, cx - w / 2 - 2, floorY + SIGN_EYE, wallZ + 0.5))

	return model
end

return board
