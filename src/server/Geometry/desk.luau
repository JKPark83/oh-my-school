--!strict
--[[
	책걸상(시설 1) — 교실 1 안 가구. 계획서 §3.6 규약.
	  build(plotCFrame) → Model. 모델 이름 = 시설 id = 이 모듈 이름. 파트 24개(≤25), 전부 BuildKit.part.
	  교실 1 의 벽·지붕·남문은 Shell 에 있으므로 여기는 2인 책상 3 + 의자 6 만 놓는다.
	  줄 간격 4(center.Z −4·0·+4), 자리 x = center.X ± 1.5. 전부 칠판(−Z)을 본다.
	  Seats/S01~S06 = 의자 아래 바닥 중심, LookVector −Z. 1줄 왼쪽부터 번호를 매긴다.
	  Door = 교실 1 남문 중심(기획서 §7.2 (−60,−32.5)), LookVector 가 방 안쪽(−Z).
	  두 Attachment 는 BasePart 아래가 아니므로 CFrame 에 월드 CFrame 을 그대로 넣는다(WorldCFrame 과 같은 값).
	  책상 상판 윗면 = CharacterBuilder.SIT_DESK, 좌판 윗면 = SIT_HIP — 앉은 NPC 와 맞물린다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local Seats = require(ReplicatedStorage.Shared.Seats)

local desk = {}

local COLOR_PRIMARY = Color3.fromRGB(160, 110, 60)
local COLOR_SECONDARY = Color3.fromRGB(90, 60, 30)
local MATERIAL = Enum.Material.Wood

local FACILITY_ID = script.Name
local SIT_HIP = CharacterBuilder.SIT_HIP
local SIT_DESK = CharacterBuilder.SIT_DESK
local CLASS1_DOOR = Vector3.new(-60, 0, -32.5) -- 교실 1 남문 중심(기획서 §7.2). 벽은 Shell 소유

local ROW_DZ = { -4, 0, 4 }
local SEAT_DX = 1.5
local SEAT_DZ = 1.6 -- 책상 줄 z → 의자 중심 z
local DESK_TOP = Vector3.new(5.4, 0.3, 2.2)
local DESK_PANEL = Vector3.new(5, 2.4, 0.2)
local CHAIR_SEAT = Vector3.new(1.6, 0.3, 1.6)
local CHAIR_BACK = Vector3.new(1.6, 1.8, 0.25)
local CHAIR_POST = Vector3.new(0.4, SIT_HIP - CHAIR_SEAT.Y, 0.4)

local COLOR_STEEL = Color3.fromRGB(120, 122, 126)

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

function desk.build(plotCFrame: CFrame): Model
	local row = FacilityConfig.BY_ID[FACILITY_ID]
	assert(row ~= nil, `FacilityConfig 에 {FACILITY_ID} 가 없다`)

	local model = Instance.new("Model")
	model.Name = FACILITY_ID
	model:SetAttribute(Keys.ATTR_FACILITY_ID, FACILITY_ID)

	local seats = Instance.new("Folder")
	seats.Name = Keys.SEATS_FOLDER
	seats.Parent = model

	local cx, floorY = row.center.X, row.center.Y
	local seatIndex = 0
	for r, dz in ROW_DZ do
		local z = row.center.Z + dz
		local deskName = string.format("Desk%02d", r)
		put(model, deskName .. "Top", DESK_TOP, at(plotCFrame, cx, floorY + SIT_DESK - DESK_TOP.Y / 2, z), {
			color = COLOR_PRIMARY,
			material = MATERIAL,
		})
		-- 앞판(칠판 쪽 −Z). 상판 앞 가장자리 바로 안쪽, 바닥에서 0.2 띄운다
		put(
			model,
			deskName .. "Panel",
			DESK_PANEL,
			at(plotCFrame, cx, floorY + 0.2 + DESK_PANEL.Y / 2, z - DESK_TOP.Z / 2 + DESK_PANEL.Z / 2),
			{
				color = COLOR_PRIMARY,
				material = MATERIAL,
			}
		)

		for _, dx in { -SEAT_DX, SEAT_DX } do
			seatIndex += 1
			local x = cx + dx
			local cz = z + SEAT_DZ
			local chairName = string.format("Chair%02d", seatIndex)
			put(model, chairName .. "Post", CHAIR_POST, at(plotCFrame, x, floorY + CHAIR_POST.Y / 2, cz), {
				color = COLOR_STEEL,
				material = Enum.Material.Metal,
			})
			put(model, chairName .. "Seat", CHAIR_SEAT, at(plotCFrame, x, floorY + SIT_HIP - CHAIR_SEAT.Y / 2, cz), {
				color = COLOR_SECONDARY,
				material = MATERIAL,
			})
			put(
				model,
				chairName .. "Back",
				CHAIR_BACK,
				at(plotCFrame, x, floorY + SIT_HIP + CHAIR_BACK.Y / 2, cz + CHAIR_SEAT.Z / 2 - CHAIR_BACK.Z / 2),
				{
					color = COLOR_SECONDARY,
					material = MATERIAL,
				}
			)
			-- 학생은 칠판(−Z)을 본다. 기본 CFrame 의 LookVector 가 −Z
			attach(seats, Seats.attachmentName(seatIndex), at(plotCFrame, x, floorY, cz))
		end
	end
	assert(seatIndex == row.seats, `{FACILITY_ID}: 자리 {seatIndex} ≠ FacilityConfig.seats {row.seats}`)

	attach(model, Keys.DOOR, at(plotCFrame, CLASS1_DOOR.X, floorY, CLASS1_DOOR.Z))

	return model
end

return desk
