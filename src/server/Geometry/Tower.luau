--!strict
--[[
	탑(층 쌓기) 서버 파트. 개선계획(2026-10-01 층 쌓기) §5.2·§5.4.

	Tower.refresh(...) 가 부지 모델 안 Tower 폴더를 맞춘다. 강당이 없으면 비운다(파트 0). 있으면 파트 = 바닥판 + 8:
	  FloorNN   층마다 바닥판(3층부터. 짓는 중인 층 방은 부품 1 부터 그 층 바닥판도)
	  Roof      맨 위 판 = 옥상 바닥. 층이 0 이면 강당 지붕 바로 위
	  RoofRail1~4  Roof 둘레 투명 충돌 벽(옥상에서 떨어지지 않게. 난간 모양은 클라가 그린다)
	  TowerPad  층 패드(PAD_TAG, FacilityId "tower"). 부품 1(뼈대)은 다 지은 맨 위 층 바닥(층 방이 없으면 강당)의
	            TOWER_PAD_XZ, 부품 2~4 는 짓는 층(옥상 방이면 옥상) 방 안 partPads 자리(1층 시설 패드처럼 옮겨 다닌다)
	  ElevatorF1·ElevatorF2  1층(현관)·2층(강당) 엘리베이터 앵커(투명, 충돌 없음)
	엘리베이터 프롬프트(이름 ElevatorPrompt)는 바닥판·Roof 의 Attachment "Elevator" 와 1·2층 앵커에 단다.
	누르면 클라가 층 버튼 패널을 연다(서버는 RideElevator 만 판정한다).
	벽·창·간판·가구·난간 모양·옥상 방은 전부 클라가 그린다.

	파트는 이름으로 다시 쓴다(있으면 자리만 옮긴다). 서 있는 바닥을 지웠다 다시 만들지 않게.

	★ 3층 바닥판·0층 Roof 는 강당 지붕(윗면 TOWER_BASE_Y)과 같은 자리다. 면이 겹쳐 깜빡이지 않게
	  윗면을 LIFT 만큼 올리고 발자국을 INSET 만큼 안으로 줄였다. 클라가 floorY 그대로 그려도 0.05 차이라 보이지 않는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local PlotLayout = require(ReplicatedStorage.Shared.PlotLayout)
local RoomConfig = require(ReplicatedStorage.Shared.Config.RoomConfig)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local Tower = {}

-- 클라와 맞추는 이름(Keys)
Tower.FOLDER = Keys.TOWER_FOLDER
Tower.PAD = Keys.TOWER_PAD
Tower.PROMPT = Keys.ELEVATOR_PROMPT
Tower.PAD_ID = Keys.TOWER_PAD_ID

local PLATE_T = 1 -- 바닥판·Roof 두께
local LIFT = 0.05 -- 3층부터 바닥판 윗면 = floorY + LIFT
local INSET = 0.05
local RAIL_H = 6
local RAIL_T = 1
local ANCHOR_SIZE = Vector3.new(4, 6, 4)
local PROMPT_UP = 3 -- 바닥 윗면에서 프롬프트까지(HRP 높이쯤)
local PAD_SIZE = Vector3.new(4, 0.4, 4) -- PlotShell 패드와 같다
local PAD_LIFT = 0.2
local PROMPT_DISTANCE = 8 -- PlotShell 과 같다
local TEXT_OBJECT = "엘리베이터"
local TEXT_ACTION = "타기"

local foot = PlotLayout.TOWER_FOOTPRINT
local FOOT_CENTER = Vector2.new((foot.x0 + foot.x1) / 2, (foot.z0 + foot.z1) / 2)
local FOOT_SIZE = Vector2.new(foot.x1 - foot.x0 - INSET * 2, foot.z1 - foot.z0 - INSET * 2)
local PLATE_SIZE = Vector3.new(FOOT_SIZE.X, PLATE_T, FOOT_SIZE.Y)
local MAX_FLOOR_ROOMS = RoomConfig.MAX_FLOOR - RoomConfig.FIRST_FLOOR + 1
local ROOF_KINDS = 0
for _, room in RoomConfig.LIST do
	if room.kind == "roof" then
		ROOF_KINDS += 1
	end
end

--- n층 바닥 윗면 y(부지 로컬). 3층부터 LIFT 를 더한다
function Tower.floorTop(n: number): number
	return RoomConfig.floorY(n) + (if n >= RoomConfig.FIRST_FLOOR then LIFT else 0)
end

--- n층 엘리베이터 도착 자리(바닥 윗면, 월드). 엘리베이터에서 멀어지는 쪽을 본다. PlotService.teleport 가 +4 올려서 놓는다
function Tower.arrival(plotCFrame: CFrame, n: number): CFrame
	local spot = PlotLayout.elevatorSpot(n)
	local offset = PlotLayout.arrivalOffset(n)
	local p = Vector3.new(spot.X, Tower.floorTop(n), spot.Z) + offset
	return plotCFrame * CFrame.lookAlong(p, offset.Unit)
end

local function makePrompt(parent: Instance)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = Tower.PROMPT
	prompt.ObjectText = TEXT_OBJECT
	prompt.ActionText = TEXT_ACTION
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
end

--- 이름이 name 인 파트를 부지 로컬 중심 center 에 둔다. 있으면 자리만 맞춘다. 새로 만들었으면 두 번째 값이 true
local function ensure(
	folder: Instance,
	plotCFrame: CFrame,
	name: string,
	size: Vector3,
	center: Vector3,
	opts: BuildKit.Opts
): (BasePart, boolean)
	local cf = plotCFrame * CFrame.new(center)
	local found = folder:FindFirstChild(name)
	if found and found:IsA("BasePart") then
		if (found.Position - cf.Position).Magnitude > 1e-3 then
			found.CFrame = cf
		end
		return found, false
	end
	opts.cframe = cf.Rotation
	local p = BuildKit.part(folder, name, size, cf.Position, opts)
	p.CanTouch = false
	return p, true
end

-- n층 바닥판(윗면 = floorTop(n)). 처음 만들 때 엘리베이터 칸 위에 프롬프트 Attachment 를 단다
local function plate(folder: Instance, plotCFrame: CFrame, name: string, n: number, color: Color3)
	local center = Vector3.new(FOOT_CENTER.X, Tower.floorTop(n) - PLATE_T / 2, FOOT_CENTER.Y)
	-- fade(FADE_TAG) 를 달지 않는다: 클라 TowerFade 가 Tower 폴더를 따로 흐리게 한다. 둘이 같은 파트를 건드리면 깜빡인다
	local p, new = ensure(folder, plotCFrame, name, PLATE_SIZE, center, { color = color })
	if new then
		local holder = Instance.new("Attachment")
		holder.Name = "Elevator"
		holder.Position = Vector3.new(
			PlotLayout.ELEVATOR_XZ.X - FOOT_CENTER.X,
			PLATE_T / 2 + PROMPT_UP,
			PlotLayout.ELEVATOR_XZ.Y - FOOT_CENTER.Y
		)
		holder.Parent = p
		makePrompt(holder)
	end
end

--[[
	부지 모델의 Tower 폴더를 프로필 상태에 맞춘다.
	floors = 완공 층 방 id(floors[i] = i+2 층), rooftop = 완공 옥상 방 id 목록,
	towerRoom·towerParts = 짓는 방과 산 부품 수, hasAuditorium = 강당 완공
]]
function Tower.refresh(
	plotModel: Instance,
	plotCFrame: CFrame,
	floors: { string },
	rooftop: { string },
	towerRoom: string,
	towerParts: number,
	hasAuditorium: boolean
)
	local folder = plotModel:FindFirstChild(Tower.FOLDER)
	if not folder then
		local made = Instance.new("Folder")
		made.Name = Tower.FOLDER
		made.Parent = plotModel
		folder = made
	end
	assert(folder, "Tower 폴더")
	if not hasAuditorium then
		folder:ClearAllChildren()
		return
	end

	-- 층 방을 짓는 중(부품 1 이상)이면 그 층 바닥판이 서고 Roof 가 한 층 위로 간다
	local roofN = RoomConfig.roofFloor(#floors, towerRoom, towerParts)
	-- Roof 가 내려가면(짓던 층 방을 버림: DevCheat) 그 위 바닥판을 치운다
	for _, child in folder:GetChildren() do
		local n = tonumber(string.match(child.Name, "^Floor(%d+)$"))
		if n and n >= roofN then
			child:Destroy()
		end
	end
	for n = RoomConfig.FIRST_FLOOR, roofN - 1 do
		plate(folder, plotCFrame, string.format("Floor%02d", n), n, WorldPalette.stone)
	end
	plate(folder, plotCFrame, "Roof", roofN, WorldPalette.roof.classroom)

	-- Roof 둘레 투명 벽(북·남·서·동)
	local roofTop = Tower.floorTop(roofN)
	local y = roofTop + RAIL_H / 2
	local hx, hz = FOOT_SIZE.X / 2 - RAIL_T / 2, FOOT_SIZE.Y / 2 - RAIL_T / 2
	local rails = {
		{ Vector3.new(FOOT_SIZE.X, RAIL_H, RAIL_T), Vector3.new(0, 0, -hz) },
		{ Vector3.new(FOOT_SIZE.X, RAIL_H, RAIL_T), Vector3.new(0, 0, hz) },
		{ Vector3.new(RAIL_T, RAIL_H, FOOT_SIZE.Y), Vector3.new(-hx, 0, 0) },
		{ Vector3.new(RAIL_T, RAIL_H, FOOT_SIZE.Y), Vector3.new(hx, 0, 0) },
	}
	for i, rail in rails do
		local center = Vector3.new(FOOT_CENTER.X, y, FOOT_CENTER.Y) + rail[2]
		local p = ensure(folder, plotCFrame, `RoofRail{i}`, rail[1], center, {
			color = WorldPalette.ghost,
			transparency = 1,
			cast = false,
		})
		p.CanQuery = false
	end

	-- 1층·2층 타는 곳
	local anchors: { [string]: Vector3 } = { ElevatorF1 = PlotLayout.ELEVATOR_F1, ElevatorF2 = PlotLayout.ELEVATOR_F2 }
	for name, spot in anchors do
		local p, new = ensure(folder, plotCFrame, name, ANCHOR_SIZE, spot + Vector3.new(0, ANCHOR_SIZE.Y / 2, 0), {
			color = WorldPalette.ghost,
			transparency = 1,
			collide = false,
			cast = false,
		})
		if new then
			p.CanQuery = false
			makePrompt(p)
		end
	end

	-- 층 패드: 부품 1 은 다 지은 맨 위 층 바닥(층 방이 없으면 강당)의 TOWER_PAD_XZ.
	-- 부품 2~4 는 짓는 층(옥상 방이면 옥상) 방 안 partPads 자리. 엘리베이터로 그 층에 간다(RoomConfig.canRide)
	local padN, padXZ = RoomConfig.topFloor(#floors), PlotLayout.TOWER_PAD_XZ
	local spot = RoomConfig.padLocal(towerRoom, towerParts)
	if spot then
		padN = if RoomConfig.buildingKind(towerRoom, towerParts) == "floor" then padN + 1 else roofN
		padXZ = FOOT_CENTER + spot -- 방 원점(origin) x·z = 발자국 중심
	end
	local padCenter = Vector3.new(padXZ.X, Tower.floorTop(padN) + PAD_LIFT, padXZ.Y)
	local pad, newPad = ensure(folder, plotCFrame, Tower.PAD, PAD_SIZE, padCenter, {
		color = WorldPalette.pad,
		transparency = 1, -- 모양은 클라가 그린다(PlotShell 패드와 같다)
		collide = false,
		cast = false,
	})
	if newPad then
		pad:SetAttribute(Keys.ATTR_FACILITY_ID, Tower.PAD_ID)
		pad:AddTag(Keys.PAD_TAG)
	end
	-- 지을 것이 남아 있으면 active(방을 안 골랐으면 올라서면 클라가 방 고르기 패널을 연다)
	local full = #floors >= MAX_FLOOR_ROOMS and #rooftop >= ROOF_KINDS
	pad:SetAttribute(Keys.ATTR_PAD_BASE, pad.CFrame)
	pad:SetAttribute(Keys.ATTR_PAD_STATE, if towerRoom ~= "" or not full then "active" else "built")
end

return Tower
