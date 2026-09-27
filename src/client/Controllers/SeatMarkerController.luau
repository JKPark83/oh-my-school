--!nonstrict
--[[
	내 자리 표시. 서버가 반마다 새로 지정한 좌석 하나를 화면에 세 곳으로 알린다.

	  교실 안 — 책상 윤곽(Highlight)과 그 위에 뜨는 "내 자리" 팻말
	  좌상단   — "2분단 3번째" 한 줄

	★ 자리를 숨기지 않는다. 18개 중에 어디인지를 알아맞히는 것이 이 게임의 재미였다면
	  표시를 지우는 게 맞지만, 여기서 풀어야 할 문제는 "어디냐"가 아니라
	  "선생님이 도는 사이에 저기까지 어떻게 가느냐"다. 자리를 숨기면 시간에 쫓기며
	  빈자리를 하나씩 눌러보게 되고, 그건 관찰이 아니라 노가다다.

	★ 벽 너머로도 보이게(AlwaysOnTop) 하는 이유도 같다. 문 앞에 서서 경로를
	  미리 짤 수 있어야 한다. 들어가서 두리번거리는 시간은 재미가 아니라 벌점이다.

	★ 세 곳이 겹치는 것은 낭비가 아니다. 팻말은 멀리서 방향을,
	  윤곽은 책상 두 개가 붙어 있을 때 어느 쪽인지를, 좌상단 글자는
	  자리가 등 뒤에 있거나 스트리밍으로 내려가지 않았을 때를 맡는다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local RoomKeys = require(ReplicatedStorage.Shared.Config.RoomKeys)
local HudController = require(script.Parent.HudController)

local WAIT_TIMEOUT = 10

-- 좌상단 글자와 같은 색을 쓴다. 둘이 같은 것을 가리킨다는 걸 색으로 먼저 알린다.
local MARK_COLOR = Color3.fromRGB(120, 220, 160)
-- 채움은 거의 투명하게 둔다. 진하게 칠하면 책상 판이 통째로 빛나서
-- 어두운 복도 쪽 자리일 때 교실 조명보다 이게 더 밝아진다.
local FILL_TRANSPARENCY = 0.72

-- 착석 순간 채움을 이만큼 진하게 번쩍였다가 원래 값으로 돌아온다.
local CLEAR_FLASH_FILL = 0.15
local CLEAR_FLASH_TIME = 0.5

local player = Players.LocalPlayer

local SeatMarkerController = {}

local highlight: Highlight? = nil
local billboard: BillboardGui? = nil

--[[
	"2분단 3번째". 분단·번째는 서버가 교실을 지을 때 좌석에 박아둔 값이라
	여기서 책상 좌표를 다시 계산하지 않는다.

	값이 없으면 자리 이름 대신 "내 자리"로 물러난다. 좌표를 못 읽었다고
	표시를 통째로 지우면, 화면에는 아무 문제도 없어 보이는데 자리만 안 보인다.
]]
local function seatText(seat: BasePart): string
	local col = seat:GetAttribute(RoomKeys.COLUMN_ATTRIBUTE)
	local row = seat:GetAttribute(RoomKeys.ROW_ATTRIBUTE)

	if typeof(col) ~= "number" or typeof(row) ~= "number" then
		return "내 자리"
	end
	return `{col}분단 {row}번째`
end

local function buildMarkers(room: Model)
	local mark = Instance.new("Highlight")
	mark.Name = "AssignedSeat"
	mark.FillColor = MARK_COLOR
	mark.OutlineColor = MARK_COLOR
	mark.FillTransparency = FILL_TRANSPARENCY
	mark.OutlineTransparency = 0
	mark.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	mark.Enabled = false
	mark.Parent = room
	highlight = mark

	local gui = Instance.new("BillboardGui")
	gui.Name = "AssignedSeatTag"
	gui.Size = UDim2.fromOffset(110, 34)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
	gui.AlwaysOnTop = true
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui", WAIT_TIMEOUT)
	billboard = gui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = MARK_COLOR
	label.TextStrokeTransparency = 0.3
	label.Text = "내 자리"
	label.Parent = gui
end

local function moveTo(seat: BasePart)
	if highlight then
		highlight.Adornee = seat
		highlight.Enabled = true
	end
	if billboard then
		billboard.Adornee = seat
		billboard.Enabled = true
	end
	HudController.onAssignedSeat(seatText(seat))
end

--[[
	교실 밖에서는 표시를 지운다.

	★ 지우지 않으면 방금 깬 반의 자리가 운동장까지 따라온다. 다음 반 자리는
	  교실에 들어가는 순간 정해지므로, 그때까지 좌상단에 남아 있는 자리 이름은
	  틀린 정보다 — 없는 것보다 나쁘다.
]]
function SeatMarkerController.onTransition(to: string)
	if to == "class" then
		return
	end
	if highlight then
		highlight.Enabled = false
	end
	if billboard then
		billboard.Enabled = false
	end
	HudController.onAssignedSeat(nil)
end

--[[
	앉았다. 자리 자체가 "여기 맞았다"고 답한다 — 윤곽 채움이 한 번 환해지고 팻말은 내려간다.
	팻말을 내리는 이유: 이미 앉은 자리 위에 "내 자리"가 계속 떠 있으면 아직 할 일이 남은 것처럼 읽힌다.
	윤곽은 남긴다. 운동장으로 나가는 전환(onTransition)이 지운다.
]]
function SeatMarkerController.onCleared()
	if billboard then
		billboard.Enabled = false
	end
	local mark = highlight
	if not mark or not mark.Enabled then
		return
	end
	mark.FillTransparency = CLEAR_FLASH_FILL
	TweenService:Create(
		mark,
		TweenInfo.new(CLEAR_FLASH_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FillTransparency = FILL_TRANSPARENCY }
	):Play()
end

function SeatMarkerController.Start(room: Model)
	buildMarkers(room)

	local seats = room:WaitForChild(RoomKeys.SEATS_FOLDER, WAIT_TIMEOUT)
	assert(seats, "좌석 폴더가 복제되지 않았다.")

	--[[
		좌석마다 어트리뷰트 변화를 듣는다. 반이 바뀔 때마다 서버가 전부 false 로
		내린 뒤 하나만 true 로 올리므로, true 로 올라온 쪽만 보면 된다.

		★ false 를 무시하는 것이 깜빡임을 막는다. 내림과 올림 사이에는
		  "내 자리가 없는" 한 순간이 반드시 있는데, 거기에 반응하면
		  반이 넘어갈 때마다 표시가 한 번씩 사라졌다 나타난다.
	]]
	for _, seat in seats:GetChildren() do
		if not seat:IsA("BasePart") then
			continue
		end

		if seat:GetAttribute(RoomKeys.ASSIGNED_ATTRIBUTE) == true then
			moveTo(seat)
		end

		seat:GetAttributeChangedSignal(RoomKeys.ASSIGNED_ATTRIBUTE):Connect(function()
			if seat:GetAttribute(RoomKeys.ASSIGNED_ATTRIBUTE) == true then
				moveTo(seat)
			end
		end)
	end
end

return SeatMarkerController
