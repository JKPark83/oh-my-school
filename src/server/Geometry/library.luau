--!strict
--[[
	도서관(시설 7) — 30×30 방 + 책장·열람 탁자. 계획서 §3.6 규약.
	  build(plotCFrame) → Model. 모델 이름 = 시설 id = 이 모듈 이름. 파트 25개(≤25), 전부 BuildKit.part.
	  벽 4(남벽은 문 양옆 두 조각 + 상인방)·지붕·바닥판 = 8. 북벽 책장 3 + 책 3 = 6. 동벽 책장 1 + 책 1 = 2.
	  열람 탁자(상판+받침) = 2. 의자 3(좌판 블록+등받이) = 6. 사서 카운터 1.
	  책은 책장 앞면에 얹은 판 하나다(파트 예산). 판 앞면에 책등 그림 Texture(BuildKit.bookshelf, 파트 아님)를 붙이고,
	  id 0 이거나 못 불러오면 색 판으로 보인다. 사서 카운터 앞면에 「대출·반납」 글자(SurfaceGui).
	  바닥판은 Shell 바닥 위에 얹는 얇은 판이라 방 바닥 높이 = center.Y + FLOOR_T 이고 자리 Attachment 는 그 높이.
	  Seats/S01~S03 = 탁자 남쪽에 나란히, 탁자(−Z)를 본다. S03 은 규약대로 예비 자리(학생 수 2).
	  Door = 남문 중심 바닥(Shell 바닥 높이), LookVector 가 방 안쪽(−Z).
	  부품 4개(PartIndex): (1) 바닥판+벽 (2) 상인방+지붕 (3) 책장·책 (4) 열람 탁자·의자·사서 카운터.
	  두 Attachment 는 BasePart 아래가 아니므로 CFrame 에 월드 CFrame 을 그대로 넣는다(WorldCFrame 과 같은 값).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local CharacterBuilder = require(ReplicatedStorage.Shared.CharacterBuilder)
local FacilityConfig = require(ReplicatedStorage.Shared.Config.FacilityConfig)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local Seats = require(ReplicatedStorage.Shared.Seats)

local library = {}

local COLOR_PRIMARY = Color3.fromRGB(140, 95, 55)
local COLOR_SECONDARY = Color3.fromRGB(100, 65, 35)
local MATERIAL = Enum.Material.Wood

local FACILITY_ID = script.Name
local SIT_HIP = CharacterBuilder.SIT_HIP
local SIT_DESK = CharacterBuilder.SIT_DESK

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
	label = Color3.fromRGB(252, 240, 210),
	books = { Color3.fromRGB(190, 70, 60), Color3.fromRGB(70, 110, 170), Color3.fromRGB(200, 160, 60) },
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

--- 벽 4(남벽은 문 양옆 두 조각 + 상인방)·지붕·바닥판 = 파트 8개. 바닥판·벽은 부품 1, 상인방·지붕은 부품 2
local function buildRoom(model: Model, plotCFrame: CFrame, row: FacilityConfig.Facility)
	local cx, floorY, cz = row.center.X, row.center.Y, row.center.Z
	local hx, hz = row.size.X / 2, row.size.Z / 2
	local h = row.size.Y
	local y = floorY + h / 2
	partIndex = 1
	-- 부품 1. 바닥판: 벽 속으로 0.4 묻어 벽 안쪽 면과 면이 겹치지 않게 한다
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
	local wallN =
		put(model, "WallN", Vector3.new(row.size.X, h, WALL_T), at(plotCFrame, cx, y, cz - hz + WALL_T / 2), wallOpts())
	local sideLen = row.size.Z - WALL_T * 2
	local wallW =
		put(model, "WallW", Vector3.new(WALL_T, h, sideLen), at(plotCFrame, cx - hx + WALL_T / 2, y, cz), wallOpts())
	local wallE =
		put(model, "WallE", Vector3.new(WALL_T, h, sideLen), at(plotCFrame, cx + hx - WALL_T / 2, y, cz), wallOpts())
	local sz = cz + hz - WALL_T / 2
	local side = (row.size.X - DOOR_W) / 2
	put(model, "WallSW", Vector3.new(side, h, WALL_T), at(plotCFrame, cx - hx + side / 2, y, sz), wallOpts())
	put(model, "WallSE", Vector3.new(side, h, WALL_T), at(plotCFrame, cx + hx - side / 2, y, sz), wallOpts())
	-- 문 없는 세 벽 바깥 면에 창(§3.1 #8). id 0 이면 안 붙는다
	BuildKit.window(wallN, Enum.NormalId.Front)
	BuildKit.window(wallW, Enum.NormalId.Left)
	BuildKit.window(wallE, Enum.NormalId.Right)
	partIndex = 2 -- 상인방 + 지붕
	put(
		model,
		"Lintel",
		Vector3.new(DOOR_W, h - DOOR_H, WALL_T),
		at(plotCFrame, cx, floorY + (DOOR_H + h) / 2, sz),
		wallOpts()
	)
	-- 지붕은 벽 안쪽만 덮는다. 벽 위까지 덮으면 벽 윗면·바깥면과 겹쳐 깜빡인다(z-fighting)
	-- 평지붕 유지: 파트 25(한도)라 박공 쐐기 1개를 더 넣을 수 없다(§3.1 #7)
	local roofSize = Vector3.new(row.size.X - WALL_T * 2, ROOF_T, row.size.Z - WALL_T * 2)
	put(model, "Roof", roofSize, at(plotCFrame, cx, floorY + h - ROOF_T / 2, cz), {
		color = C.roof,
		material = Enum.Material.Concrete,
		fade = true,
		light = true,
	})
end

function library.build(plotCFrame: CFrame): Model
	local row = FacilityConfig.BY_ID[FACILITY_ID]
	assert(row ~= nil, `FacilityConfig 에 {FACILITY_ID} 가 없다`)
	assert(row.door == "S", `{FACILITY_ID}: 남문 기준으로 짓는다`)

	local model = Instance.new("Model")
	model.Name = FACILITY_ID
	model:SetAttribute(Keys.ATTR_FACILITY_ID, FACILITY_ID)

	buildRoom(model, plotCFrame, row)

	local cx, cz = row.center.X, row.center.Z
	local floorY = row.center.Y + FLOOR_T
	local hx, hz = row.size.X / 2, row.size.Z / 2
	local shelfY = floorY + SHELF.Y / 2
	local booksSize = Vector3.new(SHELF.X - BOOKS_PAD, SHELF.Y - BOOKS_PAD * 2, BOOKS_T)

	-- 부품 3. 북벽 책장 3: 뒷면이 북벽 안쪽 면에 닿는다. 책 판은 책장 앞면(+Z)에
	partIndex = 3
	local shelfZ = cz - hz + WALL_T + SHELF.Z / 2
	for i, dx in SHELF_DX do
		local x = cx + dx
		put(
			model,
			string.format("Shelf%02d", i),
			SHELF,
			at(plotCFrame, x, shelfY, shelfZ),
			{ color = COLOR_PRIMARY, material = MATERIAL }
		)
		local books = put(
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
		BuildKit.bookshelf(books, Enum.NormalId.Back) -- +Z = 방 안쪽
	end

	-- 동벽 책장 1: 앞면이 −X. 책장을 Y 로 90° 돌려 같은 치수를 쓴다
	local eastX = cx + hx - WALL_T - SHELF.Z / 2
	local eastRot = CFrame.Angles(0, math.pi / 2, 0)
	put(model, "ShelfE", Vector3.new(EAST_SHELF_LEN, SHELF.Y, SHELF.Z), at(plotCFrame, eastX, shelfY, cz, eastRot), {
		color = COLOR_PRIMARY,
		material = MATERIAL,
	})
	local booksE = put(
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
	BuildKit.bookshelf(booksE, Enum.NormalId.Front) -- Y 90° 회전이라 −Z 가 월드 −X = 방 안쪽

	-- 부품 4. 열람 탁자 + 의자 3(남쪽에 나란히, 탁자를 본다) + 사서 카운터
	partIndex = 4
	local seats = Instance.new("Folder")
	seats.Name = Keys.SEATS_FOLDER
	seats.Parent = model

	local tableX, tableZ = cx + TABLE_DX, cz + TABLE_DZ
	put(model, "TableTop", TABLE_TOP, at(plotCFrame, tableX, floorY + SIT_DESK - TABLE_TOP.Y / 2, tableZ), {
		color = COLOR_SECONDARY,
		material = MATERIAL,
	})
	put(model, "TableBase", TABLE_BASE, at(plotCFrame, tableX, floorY + TABLE_BASE.Y / 2, tableZ), {
		color = COLOR_SECONDARY,
		material = MATERIAL,
	})
	local seatIndex = 0
	for _, dx in CHAIR_DX do
		seatIndex += 1
		local x = tableX + dx
		local seatZ = tableZ + CHAIR_DZ
		local chairName = string.format("Chair%02d", seatIndex)
		put(model, chairName .. "Seat", CHAIR_SEAT, at(plotCFrame, x, floorY + CHAIR_SEAT.Y / 2, seatZ), {
			color = COLOR_SECONDARY,
			material = MATERIAL,
		})
		put(
			model,
			chairName .. "Back",
			CHAIR_BACK,
			at(plotCFrame, x, floorY + SIT_HIP + CHAIR_BACK.Y / 2, seatZ + CHAIR_SEAT.Z / 2 - CHAIR_BACK.Z / 2),
			{
				color = COLOR_SECONDARY,
				material = MATERIAL,
			}
		)
		-- 탁자(−Z)를 본다. 기본 CFrame 의 LookVector 가 −Z
		attach(seats, Seats.attachmentName(seatIndex), at(plotCFrame, x, floorY, seatZ))
	end
	assert(seatIndex == row.seats, `{FACILITY_ID}: 자리 {seatIndex} ≠ FacilityConfig.seats {row.seats}`)

	-- 사서 카운터: 문 서쪽
	local counter =
		put(model, "Counter", COUNTER, at(plotCFrame, cx + COUNTER_DX, floorY + COUNTER.Y / 2, cz + COUNTER_DZ), {
			color = C.counter,
			material = Enum.Material.Wood,
		})
	BuildKit.surfaceText(counter, Enum.NormalId.Front, "<b>대출 · 반납</b>", C.label, 1.2) -- −Z = 방 안쪽

	local doorZ = cz + hz
	attach(model, Keys.DOOR, at(plotCFrame, cx, row.center.Y, doorZ))

	BuildKit.assertPartIndex(model, FacilityConfig.partCount(FACILITY_ID))
	return model
end

return library
