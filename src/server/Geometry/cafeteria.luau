--!strict
--[[
	급식실(시설 6) — 30×30 방 + 배식대·식탁. 계획서 §3.6 규약.
	  build(plotCFrame) → Model. 모델 이름 = 시설 id = 이 모듈 이름. 파트 25개(≤25), 전부 BuildKit.part.
	  벽 4(남벽은 문 양옆 두 조각 + 상인방)·지붕·바닥판 = 8. 배식대(몸통+상판+식판 3) = 5. 식탁 2(상판+다리) = 4. 의자 4(좌판 블록+등받이) = 8.
	  바닥판은 Shell 바닥 위에 얹는 얇은 판이라 방 바닥 높이 = center.Y + FLOOR_T 이고 자리 Attachment 는 그 높이.
	  식탁마다 마주 앉는 자리 둘: S01·S03 은 −Z 를, S02·S04 는 +Z 를 본다(Attachment LookVector).
	  Door = 남문 중심 바닥(Shell 바닥 높이), LookVector 가 방 안쪽(−Z).
	  두 Attachment 는 BasePart 아래가 아니므로 CFrame 에 월드 CFrame 을 그대로 넣는다(WorldCFrame 과 같은 값).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local Seats = require(ReplicatedStorage.Shared.Seats)

local cafeteria = {}

local COLOR_PRIMARY = Color3.fromRGB(240, 240, 240)
local COLOR_SECONDARY = Color3.fromRGB(180, 180, 180)
local MATERIAL = Enum.Material.SmoothPlastic

local FACILITY_ID = script.Name
local SIT_HIP = CharacterBuilder.SIT_HIP
local SIT_DESK = CharacterBuilder.SIT_DESK

local WALL_T = 1
local ROOF_T = 1
local FLOOR_T = 0.2
local DOOR_W = 8
local DOOR_H = 8

local COUNTER = Vector3.new(16, 3, 2)
local COUNTER_TOP = Vector3.new(16.4, 0.2, 2.4)
local TRAY = Vector3.new(2, 0.25, 1.4)
local TABLE_TOP = Vector3.new(6, 0.3, 2.4)
local TABLE_DX = 6 -- center.X ± 6
local TABLE_DZ = 1 -- 식탁 줄 z = center.Z + 1
local CHAIR_SEAT = Vector3.new(1.6, SIT_HIP, 1.6) -- 바닥부터 좌판까지 통짜
local CHAIR_BACK = Vector3.new(1.6, 1.6, 0.25)
local CHAIR_DZ = 2.2 -- 식탁 중심 → 의자 중심

local C = {
	wall = Color3.fromRGB(228, 222, 208),
	roof = Color3.fromRGB(70, 72, 76),
	floor = Color3.fromRGB(206, 206, 200),
	steel = Color3.fromRGB(190, 192, 198),
	trays = { Color3.fromRGB(230, 140, 60), Color3.fromRGB(80, 130, 200), Color3.fromRGB(110, 170, 90) },
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

local function wallOpts(): BuildKit.Opts
	return { color = C.wall, material = Enum.Material.Concrete, fade = true }
end

--- 벽 4(남벽은 문 양옆 두 조각 + 상인방)·지붕·바닥판 = 파트 8개
local function buildRoom(model: Model, plotCFrame: CFrame, row: FacilityConfig.Facility)
	local cx, floorY, cz = row.center.X, row.center.Y, row.center.Z
	local hx, hz = row.size.X / 2, row.size.Z / 2
	local h = row.size.Y
	local y = floorY + h / 2
	put(model, "WallN", Vector3.new(row.size.X, h, WALL_T), at(plotCFrame, cx, y, cz - hz + WALL_T / 2), wallOpts())
	local sideLen = row.size.Z - WALL_T * 2
	put(model, "WallW", Vector3.new(WALL_T, h, sideLen), at(plotCFrame, cx - hx + WALL_T / 2, y, cz), wallOpts())
	put(model, "WallE", Vector3.new(WALL_T, h, sideLen), at(plotCFrame, cx + hx - WALL_T / 2, y, cz), wallOpts())
	local sz = cz + hz - WALL_T / 2
	local side = (row.size.X - DOOR_W) / 2
	put(model, "WallSW", Vector3.new(side, h, WALL_T), at(plotCFrame, cx - hx + side / 2, y, sz), wallOpts())
	put(model, "WallSE", Vector3.new(side, h, WALL_T), at(plotCFrame, cx + hx - side / 2, y, sz), wallOpts())
	put(
		model,
		"Lintel",
		Vector3.new(DOOR_W, h - DOOR_H, WALL_T),
		at(plotCFrame, cx, floorY + (DOOR_H + h) / 2, sz),
		wallOpts()
	)
	-- 지붕은 벽 안쪽만 덮는다. 벽 위까지 덮으면 벽 윗면·바깥면과 겹쳐 깜빡인다(z-fighting)
	local roofSize = Vector3.new(row.size.X - WALL_T * 2, ROOF_T, row.size.Z - WALL_T * 2)
	put(model, "Roof", roofSize, at(plotCFrame, cx, floorY + h - ROOF_T / 2, cz), {
		color = C.roof,
		material = Enum.Material.Concrete,
		fade = true,
		light = true,
	})
	-- 바닥판: 벽 속으로 0.4 묻어 벽 안쪽 면과 면이 겹치지 않게 한다
	put(
		model,
		"Floor",
		Vector3.new(row.size.X - WALL_T * 0.4, FLOOR_T, row.size.Z - WALL_T * 0.4),
		at(plotCFrame, cx, floorY + FLOOR_T / 2, cz),
		{
			color = C.floor,
			material = Enum.Material.SmoothPlastic,
		}
	)
end

function cafeteria.build(plotCFrame: CFrame): Model
	local row = FacilityConfig.BY_ID[FACILITY_ID]
	assert(row ~= nil, `FacilityConfig 에 {FACILITY_ID} 가 없다`)
	assert(row.door == "S", `{FACILITY_ID}: 남문 기준으로 짓는다`)

	local model = Instance.new("Model")
	model.Name = FACILITY_ID
	model:SetAttribute(Keys.ATTR_FACILITY_ID, FACILITY_ID)

	buildRoom(model, plotCFrame, row)

	local cx, cz = row.center.X, row.center.Z
	local floorY = row.center.Y + FLOOR_T
	local hz = row.size.Z / 2

	-- 배식대: 북벽 안쪽 면에 붙인다
	local counterZ = cz - hz + WALL_T + COUNTER.Z / 2
	put(
		model,
		"Counter",
		COUNTER,
		at(plotCFrame, cx, floorY + COUNTER.Y / 2, counterZ),
		{ color = C.steel, material = Enum.Material.Metal }
	)
	put(model, "CounterTop", COUNTER_TOP, at(plotCFrame, cx, floorY + COUNTER.Y + COUNTER_TOP.Y / 2, counterZ), {
		color = C.steel,
		material = Enum.Material.Metal,
	})
	for i, color in C.trays do
		put(
			model,
			string.format("Tray%02d", i),
			TRAY,
			at(plotCFrame, cx + (i - 2) * 5, floorY + COUNTER.Y + COUNTER_TOP.Y + TRAY.Y / 2, counterZ),
			{
				color = color,
				material = Enum.Material.SmoothPlastic,
				collide = false,
			}
		)
	end

	local seats = Instance.new("Folder")
	seats.Name = Keys.SEATS_FOLDER
	seats.Parent = model

	-- 식탁 둘, 식탁마다 마주 보는 의자 둘. 자리 번호는 서쪽 식탁 −Z·+Z, 동쪽 식탁 −Z·+Z
	local tableZ = cz + TABLE_DZ
	local legSize = Vector3.new(0.8, SIT_DESK - TABLE_TOP.Y, 0.8)
	local seatIndex = 0
	for t, dx in { -TABLE_DX, TABLE_DX } do
		local x = cx + dx
		local tableName = string.format("Table%02d", t)
		put(model, tableName .. "Top", TABLE_TOP, at(plotCFrame, x, floorY + SIT_DESK - TABLE_TOP.Y / 2, tableZ), {
			color = COLOR_PRIMARY,
			material = MATERIAL,
		})
		put(model, tableName .. "Leg", legSize, at(plotCFrame, x, floorY + legSize.Y / 2, tableZ), {
			color = COLOR_SECONDARY,
			material = MATERIAL,
		})
		-- facing = 학생이 보는 방향의 z 부호. −1 이면 기본 CFrame(LookVector −Z), +1 이면 180° 돌린다
		for _, facing in { -1, 1 } do
			seatIndex += 1
			local rot = if facing < 0 then CFrame.identity else CFrame.Angles(0, math.pi, 0)
			local base = at(plotCFrame, x, floorY, tableZ - facing * CHAIR_DZ, rot)
			local chairName = string.format("Chair%02d", seatIndex)
			put(model, chairName .. "Seat", CHAIR_SEAT, base * CFrame.new(0, CHAIR_SEAT.Y / 2, 0), {
				color = COLOR_SECONDARY,
				material = MATERIAL,
			})
			-- 등받이는 보는 방향의 반대(로컬 +Z)
			put(
				model,
				chairName .. "Back",
				CHAIR_BACK,
				base * CFrame.new(0, SIT_HIP + CHAIR_BACK.Y / 2, CHAIR_SEAT.Z / 2 - CHAIR_BACK.Z / 2),
				{
					color = COLOR_SECONDARY,
					material = MATERIAL,
				}
			)
			attach(seats, Seats.attachmentName(seatIndex), base)
		end
	end
	assert(seatIndex == row.seats, `{FACILITY_ID}: 자리 {seatIndex} ≠ FacilityConfig.seats {row.seats}`)

	local doorZ = cz + hz
	attach(model, Keys.DOOR, at(plotCFrame, cx, row.center.Y, doorZ))

	return model
end

return cafeteria
