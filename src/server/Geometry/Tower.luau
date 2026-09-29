--!strict
--[[
	탑(층 올리기) 서버 파트. 개선계획 §3.6 #6·#7.

	Tower.refresh(plotModel, plotCFrame, towerFloors, hasAuditorium) 가 부지 모델 안 Keys.TOWER_FOLDER 폴더를 다시 짓는다.
	  강당이 없으면 폴더를 비운다(파트 0). 있으면 파트 2n+3(n = towerFloors, 단 n = 0 이면 지붕이 없어 2):
	    고정  Elevator02(2층 엘리베이터 앵커) · TowerPad(층 구매 패드) · Roof(꼭대기 지붕, n ≥ 1 일 때)
	    층마다 FloorNN(바닥판) · ElevatorNN(엘리베이터 앵커. ProximityPrompt Up/Down 은 앵커 안 같은 이름 Attachment 위·아래에)
	  벽·칸 외형·층 번호·기본 가구는 클라가 그린다(질문 14). 여기는 서다·타다·사다 판정에 필요한 것만 둔다.
	  층 수가 바뀌면 지붕 자리도 바뀌므로 통째로 다시 짓는다(파트가 적다). 같은 층 수면 건드리지 않는다.

	Tower.ghost(plotCFrame, n) 는 다음 층 유령(Silhouette 슬롯에 넣을 Model)을 만든다.
	Tower.arrival(plotCFrame, n) 는 n층 엘리베이터 앞 도착 자리 CFrame(바닥 윗면)을 준다.

	★ 3층 바닥판은 강당 지붕(윗면 y 37.2 = TOWER_BASE_Y)과 같은 자리다. 면이 겹쳐 깜빡이지 않게
	  바닥판을 LIFT 만큼 올리고 발자국을 INSET 만큼 안으로 줄였다. 클라 벽은 floorY 그대로 써도 0.05 차이라 보이지 않는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildKit = require(script.Parent.Parent.BuildKit)
local Keys = require(ReplicatedStorage.Shared.Config.Keys)
local PlotLayout = require(ReplicatedStorage.Shared.PlotLayout)
local TowerConfig = require(ReplicatedStorage.Shared.Config.TowerConfig)
local WorldPalette = require(ReplicatedStorage.Shared.Config.WorldPalette)

local Tower = {}

local PLATE_T = 1 -- 바닥판·지붕 두께
local LIFT = 0.05 -- 바닥판 윗면을 floorY 보다 이만큼 올린다(강당 지붕과 면 겹침 방지)
local INSET = 0.05 -- 바닥판 발자국을 사방으로 이만큼 줄인다(강당 지붕 옆면과 겹침 방지)
local ANCHOR_SIZE = Vector3.new(4, 6, 4) -- 엘리베이터 프롬프트 앵커(투명). 한 칸(CELL 5) 안
local ARRIVE_Z = 4 -- 3층부터 도착 자리 = 앵커에서 +Z(교문 쪽) 4스터드. DecorGrid 가 막는 칸 앞 칸. 2층은 PlotLayout.ELEVATOR_ARRIVAL_2
local PROMPT_DY = 1.5 -- ▲ 는 앵커 중심 위, ▼ 는 아래 Attachment 에 달아 두 프롬프트 UI 가 겹치지 않게 한다
local PAD_T = 0.4 -- PlotShell PAD_SIZE 와 같은 두께
local PAD_LIFT = 0.2 -- PlotShell PAD_LIFT 와 같다
local PROMPT_DISTANCE = 8 -- PlotShell.makePrompt 와 같다
local GHOST_TRANSPARENCY = 0.7 -- PlotService SILHOUETTE_TRANSPARENCY 와 같다
local PAD_ID = "tower" -- TowerPad 의 FacilityId. 시설 id 와 겹치지 않는다

local SECOND_FLOOR = 2
local SECOND_FLOOR_TOP = PlotLayout.WALL_H + PlotLayout.AUDITORIUM_FLOOR_T -- 강당 바닥 윗면 18.2

local foot = PlotLayout.TOWER_FOOTPRINT
local FOOT_CENTER = Vector2.new((foot.x0 + foot.x1) / 2, (foot.z0 + foot.z1) / 2)
local FOOT_SIZE = Vector2.new(foot.x1 - foot.x0 - INSET * 2, foot.z1 - foot.z0 - INSET * 2)

--- n층 바닥 윗면 y(부지 기준). 2층은 강당 바닥, 3층부터 TowerConfig.floorY + LIFT
function Tower.floorTop(n: number): number
	if n == SECOND_FLOOR then
		return SECOND_FLOOR_TOP
	end
	return TowerConfig.floorY(n) + LIFT
end

--- n층 엘리베이터 앵커 중심(부지 로컬)
function Tower.anchorLocal(n: number): Vector3
	return Vector3.new(PlotLayout.ELEVATOR.X, Tower.floorTop(n) + ANCHOR_SIZE.Y / 2, PlotLayout.ELEVATOR.Y)
end

--- n층 엘리베이터 앞 도착 자리(바닥 윗면). PlotService.teleport 가 +4 올려서 놓는다
--- 2층은 남쪽 칸이 TOWER_PAD 라 북쪽 칸(PlotLayout.ELEVATOR_ARRIVAL_2)에 내린다
function Tower.arrival(plotCFrame: CFrame, n: number): CFrame
	local spot = if n == SECOND_FLOOR
		then PlotLayout.ELEVATOR_ARRIVAL_2
		else Vector2.new(PlotLayout.ELEVATOR.X, PlotLayout.ELEVATOR.Y + ARRIVE_Z)
	return plotCFrame * CFrame.new(spot.X, Tower.floorTop(n), spot.Y)
end

local function at(plotCFrame: CFrame, x: number, y: number, z: number): Vector3
	return plotCFrame:PointToWorldSpace(Vector3.new(x, y, z))
end

-- 발자국 크기 판(윗면 = top)
local function plate(parent: Instance, name: string, plotCFrame: CFrame, top: number, color: Color3): Part
	local p = BuildKit.part(
		parent,
		name,
		Vector3.new(FOOT_SIZE.X, PLATE_T, FOOT_SIZE.Y),
		at(plotCFrame, FOOT_CENTER.X, top - PLATE_T / 2, FOOT_CENTER.Y),
		{ color = color, material = Enum.Material.SmoothPlastic, cframe = plotCFrame.Rotation, fade = true }
	)
	p.CanTouch = false
	return p
end

-- 프롬프트는 앵커 안 Attachment(dy 만큼 위·아래)에 단다. 판정(PlotService.rideElevator)은 Attachment 의 부모 앵커를 본다
local function makePrompt(
	anchorPart: BasePart,
	name: string,
	actionText: string,
	objectText: string,
	dy: number
): ProximityPrompt
	local holder = Instance.new("Attachment")
	holder.Name = name
	holder.Position = Vector3.new(0, dy, 0)
	holder.Parent = anchorPart
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = holder
	return prompt
end

-- n층 엘리베이터 앵커. top = 꼭대기 층 번호(2 + towerFloors). 위층이 있으면 Up, 3층부터 Down
local function anchor(parent: Instance, plotCFrame: CFrame, n: number, top: number)
	local local_ = Tower.anchorLocal(n)
	local p = BuildKit.part(
		parent,
		string.format("Elevator%02d", n),
		ANCHOR_SIZE,
		at(plotCFrame, local_.X, local_.Y, local_.Z),
		{
			color = WorldPalette.ghost,
			transparency = 1,
			cframe = plotCFrame.Rotation,
			collide = false,
			cast = false,
		}
	)
	p.CanTouch = false
	p.CanQuery = false
	p:SetAttribute(Keys.ATTR_FLOOR, n)
	if n < top then
		makePrompt(p, Keys.ELEVATOR_UP, "▲", `{n + 1}층`, PROMPT_DY)
	end
	if n >= TowerConfig.FIRST_FLOOR then
		local down = makePrompt(p, Keys.ELEVATOR_DOWN, "▼", `{n - 1}층`, -PROMPT_DY)
		-- 한 앵커에 프롬프트가 둘이라 키를 나눈다(Up 은 기본 E·ButtonX)
		down.KeyboardKeyCode = Enum.KeyCode.Q
		down.GamepadKeyCode = Enum.KeyCode.ButtonY
	end
end

local function towerPad(parent: Instance, plotCFrame: CFrame, canBuy: boolean)
	local c = PlotLayout.TOWER_PAD
	local size = PlotLayout.TOWER_PAD_SIZE
	local p = BuildKit.part(
		parent,
		Keys.TOWER_PAD,
		Vector3.new(size.X, PAD_T, size.Y),
		at(plotCFrame, c.X, c.Y + PAD_LIFT, c.Z),
		{
			color = WorldPalette.pad,
			transparency = 1, -- 모양은 클라가 그린다(PlotShell 패드와 같다)
			cframe = plotCFrame.Rotation,
			collide = false,
			cast = false,
		}
	)
	-- 판정은 PlotService.onTowerPad 가 HRP 위치로 한다. Touched 는 쓰지 않는다
	p.CanTouch = false
	p:SetAttribute(Keys.ATTR_FACILITY_ID, PAD_ID)
	p:SetAttribute(Keys.ATTR_PAD_STATE, if canBuy then "active" else "built")
	p:AddTag(Keys.PAD_TAG)
end

--- 부지 모델의 Tower 폴더를 towerFloors 층으로 맞춘다. 강당이 없으면 비운다
function Tower.refresh(plotModel: Instance, plotCFrame: CFrame, towerFloors: number, hasAuditorium: boolean)
	local folder: Instance
	local found = plotModel:FindFirstChild(Keys.TOWER_FOLDER)
	if found then
		folder = found
	else
		folder = Instance.new("Folder")
		folder.Name = Keys.TOWER_FOLDER
		folder.Parent = plotModel
	end
	local shown = if hasAuditorium then towerFloors else -1
	if folder:GetAttribute(Keys.ATTR_TOWER_FLOORS) == shown then
		return
	end
	folder:ClearAllChildren()
	folder:SetAttribute(Keys.ATTR_TOWER_FLOORS, shown)
	if not hasAuditorium then
		return
	end

	local top = SECOND_FLOOR + towerFloors
	anchor(folder, plotCFrame, SECOND_FLOOR, top)
	towerPad(folder, plotCFrame, TowerConfig.nextFloor(towerFloors) ~= nil)
	for n = TowerConfig.FIRST_FLOOR, top do
		local floor =
			plate(folder, string.format("Floor%02d", n), plotCFrame, Tower.floorTop(n), TowerConfig.colorOf(n))
		floor:SetAttribute(Keys.ATTR_FLOOR, n)
		anchor(folder, plotCFrame, n, top)
	end
	if towerFloors >= 1 then
		-- 꼭대기 층 천장. 0층이면 강당 지붕이 그 자리다
		local roof = plate(folder, "Roof", plotCFrame, Tower.floorTop(top + 1), WorldPalette.roof.classroom)
		roof:SetAttribute(Keys.ATTR_FLOOR, top + 1)
	end
end

--[[
	다음 층 유령: 다음 층이 들어설 자리(발자국 × 한 층 높이) 반투명 상자 하나.
	바닥판 모양만 세우면 바로 아래 지붕(강당 지붕·Roof)과 같은 자리라 보이지 않는다.
	Name 은 호출자가 Keys.SILHOUETTE 로 붙인다.
]]
function Tower.ghost(plotCFrame: CFrame, n: number): Model
	local model = Instance.new("Model")
	local bottom = Tower.floorTop(n) -- 아래 지붕 윗면
	local height = PlotLayout.FLOOR_STEP - PLATE_T
	local p = BuildKit.part(
		model,
		string.format("Floor%02d", n),
		Vector3.new(FOOT_SIZE.X, height, FOOT_SIZE.Y),
		at(plotCFrame, FOOT_CENTER.X, bottom + height / 2, FOOT_CENTER.Y),
		{
			color = WorldPalette.ghost,
			transparency = GHOST_TRANSPARENCY,
			cframe = plotCFrame.Rotation,
			collide = false,
			cast = false,
		}
	)
	p.CanQuery = false
	p.CanTouch = false
	model:SetAttribute(Keys.ATTR_FLOOR, n)
	return model
end

return Tower
