--!strict
--[[
	도서관(시설 7) — 24×24 방 + 책장·열람 탁자. 계획서 §3.6 규약.
	  build(plotCFrame, skinIndex) → Model. 모델 이름 = 시설 id = 이 모듈 이름. 파트 25개(≤25), 전부 BuildKit.part.
	  벽 4(남벽은 문 양옆 두 조각 + 상인방)·지붕·바닥판 = 8. 북벽 책장 3 + 책 3 = 6. 동벽 책장 1 + 책 1 = 2.
	  열람 탁자(상판+받침) = 2. 의자 3(좌판 블록+등받이) = 6. 사서 카운터 1.
	  책은 책장 앞면에 얹은 색 판 하나로 상징한다(파트 예산).
	  바닥판은 Shell 바닥 위에 얹는 얇은 판이라 방 바닥 높이 = center.Y + FLOOR_T 이고 자리 Attachment 는 그 높이.
	  Seats/S01~S03 = 탁자 남쪽에 나란히, 탁자(−Z)를 본다. S03 은 규약대로 예비 자리(학생 수 2).
	  스킨: SkinRole "primary" = 책장, "secondary" = 탁자·의자. 벽은 고정 크림색. 색과 재질 모두 스킨 것을 쓴다.
	  Door = 남문 중심 바닥(Shell 바닥 높이), LookVector 가 방 안쪽(−Z). SkinSign = 문 옆 복도 쪽 눈높이.
	  세 Attachment 는 BasePart 아래가 아니므로 CFrame 에 월드 CFrame 을 그대로 넣는다(WorldCFrame 과 같은 값).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local Seats = require(ReplicatedStorage.Shared.Seats)
local SkinConfig = require(ReplicatedStorage.Shared.Config.SkinConfig)

local library = {}

local ROLE_PRIMARY = "primary"
local ROLE_SECONDARY = "secondary"

local FACILITY_ID = script.Name
local SIT_HIP = CharacterBuilder.SIT_HIP
local SIT_DESK = CharacterBuilder.SIT_DESK
local SIGN_EYE = 4.5

local WALL_T = 1
local ROOF_T = 1
local FLOOR_T = 0.2
local DOOR_W = 8
local DOOR_H = 8

local SHELF = Vector3.new(6, 8, 1.2) -- 북벽 책장(가로 6). 동벽 책장은 X·Z 를 바꾼다
local SHELF_DX = { -7, 0, 7 }
local BOOKS_T = 0.4
local BOOKS_PAD = 0.6 -- 책장 가장자리에서 책 판까지
local EAST_SHELF_LEN = 8
local TABLE_TOP = Vector3.new(8, 0.3, 3)
local TABLE_BASE = Vector3.new(6, SIT_DESK - 0.3, 0.6)
local TABLE_DX, TABLE_DZ = -2, 1 -- 탁자 중심 = center + (−2, ·, 1)
local CHAIR_SEAT = Vector3.new(1.6, SIT_HIP, 1.6) -- 바닥부터 좌판까지 통짜
local CHAIR_BACK = Vector3.new(1.6, 1.6, 0.25)
local CHAIR_DX = { -3, 0, 3 }
local CHAIR_DZ = 2.5 -- 탁자 중심 → 의자 중심(+Z)
local COUNTER = Vector3.new(5, 3, 2)
local COUNTER_DX, COUNTER_DZ = -8, 8

local C = {
	wall = Color3.fromRGB(228, 222, 208),
	roof = Color3.fromRGB(70, 72, 76),
	floor = Color3.fromRGB(196, 178, 150),
	counter = Color3.fromRGB(120, 84, 52),
	books = { Color3.fromRGB(190, 70, 60), Color3.fromRGB(70, 110, 170), Color3.fromRGB(200, 160, 60) },
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
	put(model, "Roof", Vector3.new(row.size.X, ROOF_T, row.size.Z), at(plotCFrame, cx, floorY + h - ROOF_T / 2, cz), {
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
			material = Enum.Material.Wood,
		}
	)
end

function library.build(plotCFrame: CFrame, skinIndex: number): Model
	local row = FacilityConfig.BY_ID[FACILITY_ID]
	assert(row ~= nil, `FacilityConfig 에 {FACILITY_ID} 가 없다`)
	assert(row.door == "S", `{FACILITY_ID}: 남문 기준으로 짓는다`)
	local skin = SkinConfig.get(FACILITY_ID, skinIndex)

	local model = Instance.new("Model")
	model.Name = FACILITY_ID
	model:SetAttribute(Keys.ATTR_FACILITY_ID, FACILITY_ID)
	model:SetAttribute(Keys.ATTR_SKIN, skinIndex)

	buildRoom(model, plotCFrame, row)

	local cx, cz = row.center.X, row.center.Z
	local floorY = row.center.Y + FLOOR_T
	local hx, hz = row.size.X / 2, row.size.Z / 2
	local shelfY = floorY + SHELF.Y / 2
	local booksSize = Vector3.new(SHELF.X - BOOKS_PAD, SHELF.Y - BOOKS_PAD * 2, BOOKS_T)

	-- 북벽 책장 3: 뒷면이 북벽 안쪽 면에 닿는다. 책 판은 책장 앞면(+Z)에
	local shelfZ = cz - hz + WALL_T + SHELF.Z / 2
	for i, dx in SHELF_DX do
		local x = cx + dx
		skinned(
			put(
				model,
				string.format("Shelf%02d", i),
				SHELF,
				at(plotCFrame, x, shelfY, shelfZ),
				{ color = skin.primary, material = skin.material }
			),
			ROLE_PRIMARY
		)
		put(
			model,
			string.format("Books%02d", i),
			booksSize,
			at(plotCFrame, x, shelfY, shelfZ + SHELF.Z / 2 + BOOKS_T / 2),
			{
				color = C.books[i],
				material = Enum.Material.SmoothPlastic,
				collide = false,
			}
		)
	end

	-- 동벽 책장 1: 앞면이 −X. 책장을 Y 로 90° 돌려 같은 치수를 쓴다
	local eastX = cx + hx - WALL_T - SHELF.Z / 2
	local eastRot = CFrame.Angles(0, math.pi / 2, 0)
	skinned(
		put(
			model,
			"ShelfE",
			Vector3.new(EAST_SHELF_LEN, SHELF.Y, SHELF.Z),
			at(plotCFrame, eastX, shelfY, cz, eastRot),
			{
				color = skin.primary,
				material = skin.material,
			}
		),
		ROLE_PRIMARY
	)
	put(
		model,
		"BooksE",
		Vector3.new(EAST_SHELF_LEN - BOOKS_PAD, booksSize.Y, BOOKS_T),
		at(plotCFrame, eastX - SHELF.Z / 2 - BOOKS_T / 2, shelfY, cz, eastRot),
		{
			color = C.books[2],
			material = Enum.Material.SmoothPlastic,
			collide = false,
		}
	)

	-- 열람 탁자 + 의자 3(남쪽에 나란히, 탁자를 본다)
	local seats = Instance.new("Folder")
	seats.Name = Keys.SEATS_FOLDER
	seats.Parent = model

	local tableX, tableZ = cx + TABLE_DX, cz + TABLE_DZ
	skinned(
		put(model, "TableTop", TABLE_TOP, at(plotCFrame, tableX, floorY + SIT_DESK - TABLE_TOP.Y / 2, tableZ), {
			color = skin.secondary,
			material = skin.material,
		}),
		ROLE_SECONDARY
	)
	skinned(
		put(model, "TableBase", TABLE_BASE, at(plotCFrame, tableX, floorY + TABLE_BASE.Y / 2, tableZ), {
			color = skin.secondary,
			material = skin.material,
		}),
		ROLE_SECONDARY
	)
	local seatIndex = 0
	for _, dx in CHAIR_DX do
		seatIndex += 1
		local x = tableX + dx
		local seatZ = tableZ + CHAIR_DZ
		local chairName = string.format("Chair%02d", seatIndex)
		skinned(
			put(model, chairName .. "Seat", CHAIR_SEAT, at(plotCFrame, x, floorY + CHAIR_SEAT.Y / 2, seatZ), {
				color = skin.secondary,
				material = skin.material,
			}),
			ROLE_SECONDARY
		)
		skinned(
			put(
				model,
				chairName .. "Back",
				CHAIR_BACK,
				at(plotCFrame, x, floorY + SIT_HIP + CHAIR_BACK.Y / 2, seatZ + CHAIR_SEAT.Z / 2 - CHAIR_BACK.Z / 2),
				{
					color = skin.secondary,
					material = skin.material,
				}
			),
			ROLE_SECONDARY
		)
		-- 탁자(−Z)를 본다. 기본 CFrame 의 LookVector 가 −Z
		attach(seats, Seats.attachmentName(seatIndex), at(plotCFrame, x, floorY, seatZ))
	end
	assert(seatIndex == row.seats, `{FACILITY_ID}: 자리 {seatIndex} ≠ FacilityConfig.seats {row.seats}`)

	-- 사서 카운터: 문 서쪽
	put(model, "Counter", COUNTER, at(plotCFrame, cx + COUNTER_DX, floorY + COUNTER.Y / 2, cz + COUNTER_DZ), {
		color = C.counter,
		material = Enum.Material.Wood,
	})

	local doorZ = cz + hz
	attach(model, Keys.DOOR, at(plotCFrame, cx, row.center.Y, doorZ))
	attach(model, Keys.SKIN_SIGN, at(plotCFrame, cx + DOOR_W / 2 + 1.5, row.center.Y + SIGN_EYE, doorZ + 1.5))

	return model
end

return library
