--!strict
--[[
	교실 2(시설 5) — 30×30 방 + 책걸상. 계획서 §3.6 규약.
	  build(plotCFrame) → Model. 모델 이름 = 시설 id = 이 모듈 이름. 파트 25개(≤25), 전부 BuildKit.part(의자 판은 BuildKit.seat).
	  벽 4(남벽은 문 양옆 두 조각 + 상인방) + 지붕 = 7. 바닥은 Shell 바닥을 그대로 쓴다(교실 1 과 같다).
	  칠판은 파트 대신 북벽 안쪽 면 SurfaceGui 의 초록 Frame 이다(파트 예산 때문).
	  2인 책상 3(상판+앞판) + 의자 6(좌판 블록+등받이) = 18. 줄 간격 4, 자리 x = center.X ± 1.5. 전부 칠판(−Z)을 본다.
	  Seats/S01~S06 = 의자 아래 바닥 중심, LookVector −Z. Door = 남문 중심 바닥, LookVector 가 방 안쪽(−Z).
	  부품 3개(PartIndex): (1) 벽(상인방 빼고) (2) 상인방+지붕 (3) 책걸상.
	  두 Attachment 는 BasePart 아래가 아니므로
	  CFrame 에 월드 CFrame 을 그대로 넣는다(WorldCFrame 과 같은 값).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local Seats = require(ReplicatedStorage.Shared.Seats)

local class2 = {}

local COLOR_PRIMARY = Color3.fromRGB(245, 235, 215)
local COLOR_SECONDARY = Color3.fromRGB(200, 180, 150)
local MATERIAL = Enum.Material.SmoothPlastic

local FACILITY_ID = script.Name
local SIT_HIP = CharacterBuilder.SIT_HIP
local SIT_DESK = CharacterBuilder.SIT_DESK

local WALL_T = 1
local ROOF_T = 1
local DOOR_W = 8
local DOOR_H = 8

local ROW_DZ = { -4, 0, 4 }
local SEAT_DX = 1.5
local SEAT_DZ = 1.6
local DESK_TOP = Vector3.new(5.4, 0.3, 2.2)
local DESK_PANEL = Vector3.new(5, 2.4, 0.2)
local CHAIR_SEAT = Vector3.new(1.6, SIT_HIP, 1.6) -- 바닥부터 좌판까지 통짜
local CHAIR_BACK = Vector3.new(1.6, 1.6, 0.25)

local C = {
	roof = Color3.fromRGB(70, 72, 76),
	chair = Color3.fromRGB(78, 80, 86),
	chalkboard = Color3.fromRGB(40, 90, 60),
	chalkboardFrame = Color3.fromRGB(120, 80, 40),
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

--- put 의 Seat 판. 학생 자리(seatIndex)는 Disabled 라 플레이어가 학생과 겹쳐 앉지 않는다
local function putSeat(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	opts: BuildKit.Opts,
	seatIndex: number
): Seat
	opts.cframe = cf.Rotation
	local p = BuildKit.seat(parent, name, size, cf.Position, opts, BuildKit.studentSeat(script.Name, seatIndex))
	p:SetAttribute(Keys.ATTR_PART_INDEX, partIndex)
	return p
end

--- 월드 CFrame 을 그대로 가진 Attachment(부모가 BasePart 가 아니다)
local function attach(parent: Instance, name: string, cf: CFrame): Attachment
	local att = Instance.new("Attachment")
	att.Name = name
	att.CFrame = cf
	att.Parent = parent
	return att
end

--- 벽 4(남벽은 문 양옆 두 조각 + 상인방)·지붕 = 파트 7개. 북벽을 돌려준다(칠판을 붙인다)
local function buildRoom(model: Model, plotCFrame: CFrame, row: FacilityConfig.Facility): Part
	local cx, floorY, cz = row.center.X, row.center.Y, row.center.Z
	local hx, hz = row.size.X / 2, row.size.Z / 2
	local h = row.size.Y
	local y = floorY + h / 2
	partIndex = 1
	local function wall(name: string, size: Vector3, x: number, wy: number, z: number): Part
		return put(
			model,
			name,
			size,
			at(plotCFrame, x, wy, z),
			{ color = COLOR_PRIMARY, material = Enum.Material.Plaster, fade = true }
		)
	end
	local north = wall("WallN", Vector3.new(row.size.X, h, WALL_T), cx, y, cz - hz + WALL_T / 2)
	local sideLen = row.size.Z - WALL_T * 2
	local westWall = wall("WallW", Vector3.new(WALL_T, h, sideLen), cx - hx + WALL_T / 2, y, cz)
	local eastWall = wall("WallE", Vector3.new(WALL_T, h, sideLen), cx + hx - WALL_T / 2, y, cz)
	local sz = cz + hz - WALL_T / 2
	local side = (row.size.X - DOOR_W) / 2
	wall("WallSW", Vector3.new(side, h, WALL_T), cx - hx + side / 2, y, sz)
	wall("WallSE", Vector3.new(side, h, WALL_T), cx + hx - side / 2, y, sz)
	-- 문 없는 세 벽 바깥 면에 창(§3.1 #8). id 0 이면 안 붙는다
	BuildKit.window(north, Enum.NormalId.Front)
	BuildKit.window(westWall, Enum.NormalId.Left)
	BuildKit.window(eastWall, Enum.NormalId.Right)
	partIndex = 2 -- 상인방 + 지붕
	wall("Lintel", Vector3.new(DOOR_W, h - DOOR_H, WALL_T), cx, floorY + (DOOR_H + h) / 2, sz)
	-- 평지붕 유지: 파트 25(한도)라 박공 쐐기 1개를 더 넣을 수 없다(§3.1 #7)
	-- 지붕은 벽 안쪽만 덮는다. 벽 위까지 덮으면 벽 윗면·바깥면과 겹쳐 깜빡인다(z-fighting)
	local roofSize = Vector3.new(row.size.X - WALL_T * 2, ROOF_T, row.size.Z - WALL_T * 2)
	put(model, "Roof", roofSize, at(plotCFrame, cx, floorY + h - ROOF_T / 2, cz), {
		color = C.roof,
		material = Enum.Material.Concrete,
		fade = true,
		light = true,
	})
	return north
end

--- 북벽 안쪽 면(+Z)에 칠판 그림. 파트 0개
local function paintChalkboard(north: Part)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1
	gui.Parent = north

	-- 칠판 12×4, 아랫변 높이 3 → 세로 중심 5. 비율은 벽 크기에서 구한다
	local wallW, wallH = north.Size.X, north.Size.Y
	local frame = Instance.new("Frame")
	frame.Name = "ChalkboardFrame"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromScale(12.6 / wallW, 4.6 / wallH)
	frame.Position = UDim2.fromScale(0.5, (wallH - 5) / wallH)
	frame.BackgroundColor3 = C.chalkboardFrame
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local face = Instance.new("Frame")
	face.Name = "Chalkboard"
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Size = UDim2.fromScale(12 / 12.6, 4 / 4.6)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.BackgroundColor3 = C.chalkboard
	face.BorderSizePixel = 0
	face.Parent = frame
end

function class2.build(plotCFrame: CFrame): Model
	local row = FacilityConfig.BY_ID[FACILITY_ID]
	assert(row ~= nil, `FacilityConfig 에 {FACILITY_ID} 가 없다`)
	assert(row.door == "S", `{FACILITY_ID}: 남문 기준으로 짓는다`)

	local model = Instance.new("Model")
	model.Name = FACILITY_ID
	model:SetAttribute(Keys.ATTR_FACILITY_ID, FACILITY_ID)

	local north = buildRoom(model, plotCFrame, row)
	paintChalkboard(north)

	local seats = Instance.new("Folder")
	seats.Name = Keys.SEATS_FOLDER
	seats.Parent = model

	local cx, floorY, cz = row.center.X, row.center.Y, row.center.Z
	partIndex = 3 -- 책걸상
	local seatIndex = 0
	for r, dz in ROW_DZ do
		local z = cz + dz
		local deskName = string.format("Desk%02d", r)
		put(model, deskName .. "Top", DESK_TOP, at(plotCFrame, cx, floorY + SIT_DESK - DESK_TOP.Y / 2, z), {
			color = COLOR_SECONDARY,
			material = MATERIAL,
		})
		put(
			model,
			deskName .. "Panel",
			DESK_PANEL,
			at(plotCFrame, cx, floorY + 0.2 + DESK_PANEL.Y / 2, z - DESK_TOP.Z / 2 + DESK_PANEL.Z / 2),
			{
				color = COLOR_SECONDARY,
				material = MATERIAL,
			}
		)
		for _, dx in { -SEAT_DX, SEAT_DX } do
			seatIndex += 1
			local x = cx + dx
			local seatZ = z + SEAT_DZ
			local chairName = string.format("Chair%02d", seatIndex)
			putSeat(model, chairName .. "Seat", CHAIR_SEAT, at(plotCFrame, x, floorY + CHAIR_SEAT.Y / 2, seatZ), {
				color = C.chair,
				material = Enum.Material.SmoothPlastic,
			}, seatIndex)
			put(
				model,
				chairName .. "Back",
				CHAIR_BACK,
				at(plotCFrame, x, floorY + SIT_HIP + CHAIR_BACK.Y / 2, seatZ + CHAIR_SEAT.Z / 2 - CHAIR_BACK.Z / 2),
				{
					color = C.chair,
					material = Enum.Material.SmoothPlastic,
				}
			)
			attach(seats, Seats.attachmentName(seatIndex), at(plotCFrame, x, floorY, seatZ))
		end
	end
	assert(seatIndex == row.seats, `{FACILITY_ID}: 자리 {seatIndex} ≠ FacilityConfig.seats {row.seats}`)

	local doorZ = cz + row.size.Z / 2
	attach(model, Keys.DOOR, at(plotCFrame, cx, floorY, doorZ))

	BuildKit.assertPartIndex(model, FacilityConfig.partCount(FACILITY_ID))
	return model
end

return class2
