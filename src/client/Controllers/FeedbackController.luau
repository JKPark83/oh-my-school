--!nonstrict
--[[
	성공/실패 연출.

	두 연출 모두 서버가 플레이어를 얼려두는 시간(ProgressService 의 CLEAR_HOLD 0.9초 /
	FAIL_HOLD 1.0초) 안에 끝나야 한다. 연출이 서버보다 길면 이미 문 앞으로 돌아온
	플레이어 위에 "통과!" 글자가 남고, 짧으면 아무것도 안 하는 정적이 생긴다.

	실패 연출의 목적은 벌이 아니라 학습이다.
	"왜 죽었는지"를 반드시 같이 띄운다 — 억울함 방지 3종 세트의 세 번째다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local RoomKeys = require(ReplicatedStorage.Shared.Config.RoomKeys)
local CameraController = require(script.Parent.CameraController)

local WAIT_TIMEOUT = 10

local CLEAR_ZOOM = 8 -- 성공 시 좁히는 화각(도)
local CLEAR_ZOOM_IN = 0.18
local CLEAR_HOLD = 0.62
local CLEAR_FADE = 0.2

local FAIL_FLASH = 0.4 -- 붉게 멈춰 있는 시간
local FAIL_TO_BLACK = 0.35
local FAIL_BLACK_HOLD = 1.05 -- 서버가 문 앞으로 되돌리는 시점
local FAIL_FADE_OUT = 0.4
local FAIL_ZOOM = 10 -- 적발 순간 즉시 좁히는 화각(도). 시선이 나한테 꽂히는 느낌
local FAIL_ZOOM_OUT = 0.3 -- 좁힌 화각이 제자리로 풀리는 시간

local TITLE_SIZE = 56
local FAIL_TITLE_PUNCH = 18 -- 제목이 이만큼 큰 채로 나타나 제자리로 줄어든다(픽셀)

--[[
	실패 사유. 서버는 키만 보내고 문장은 여기서 만든다.

	★ 문장이 왜 잡혔는지를 정확히 말해야 한다. "들켰다"로 뭉뚱그리면 같은 실수를
	  반복하게 된다 — 무엇을 고쳐야 하는지가 사유 안에 들어 있어야 다음 판이 달라진다.
]]
local REASONS = {
	moved_in_sight = "선생님이 보는 앞에서 움직였다",
	wrong_seat = "남의 자리에 앉았다",
}

local player = Players.LocalPlayer

local FeedbackController = {}

-- buildGui() 전에는 전부 nil 이다. Start() 가 유일한 초기화 지점이다.
local overlay: Frame
local title: TextLabel
local subtitle: TextLabel
local teacherArm: BasePart?

-- 연출이 겹치면 늦게 시작한 쪽만 살아남는다.
-- task.delay 로 예약해둔 콜백이 뒤늦게 화면을 건드리는 것을 막는다.
local token = 0

local function tween(target: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(target, info, goal):Play()
end

local function setFov(value: number, time: number)
	local camera = Workspace.CurrentCamera
	if camera then
		tween(camera, time, { FieldOfView = value })
	end
end

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Feedback"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui", WAIT_TIMEOUT)

	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Parent = gui

	title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 90)
	title.Position = UDim2.fromScale(0.5, 0.42)
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = TITLE_SIZE
	title.TextTransparency = 1
	title.TextStrokeTransparency = 1
	title.Text = ""
	title.Parent = gui

	subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, 0, 0, 40)
	subtitle.Position = UDim2.fromScale(0.5, 0.53)
	subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextSize = 24
	subtitle.TextTransparency = 1
	subtitle.TextStrokeTransparency = 1
	subtitle.TextColor3 = Color3.fromRGB(235, 235, 235)
	subtitle.Text = ""
	subtitle.Parent = gui
end

--[[
	선생님이 손가락질한다. WATCHING 중에는 서버가 선생님을 움직이지 않으므로
	클라이언트가 팔 하나를 잠깐 들어도 서버 상태와 충돌하지 않는다.
	RETURNING 이 시작되면 서버의 PivotTo 가 팔 위치를 덮어써서 저절로 원위치된다.
]]
local function pointFinger()
	local arm = teacherArm
	if not arm then
		return
	end

	local base = arm.CFrame
	tween(arm, 0.14, { CFrame = base * CFrame.new(0, 0.4, -1.0) * CFrame.Angles(-math.pi / 2, 0, 0) })

	local mine = token
	task.delay(FAIL_BLACK_HOLD, function()
		if token == mine and arm.Parent then
			tween(arm, 0.2, { CFrame = base })
		end
	end)
end

function FeedbackController.onCleared(payload)
	if not title then
		return
	end
	token += 1
	local mine = token

	overlay.BackgroundTransparency = 1
	title.Text = `✨ {payload.grade}학년 {payload.class}반 통과`
	title.TextColor3 = Color3.fromRGB(180, 255, 190)
	title.TextTransparency = 1
	subtitle.Text = "빈자리에 앉았다"
	subtitle.TextTransparency = 1

	setFov(CameraController.FIELD_OF_VIEW - CLEAR_ZOOM, CLEAR_ZOOM_IN)
	tween(title, 0.12, { TextTransparency = 0 })
	tween(subtitle, 0.12, { TextTransparency = 0.15 })

	task.delay(CLEAR_HOLD, function()
		if token ~= mine then
			return
		end
		setFov(CameraController.FIELD_OF_VIEW, CLEAR_FADE)
		tween(title, CLEAR_FADE, { TextTransparency = 1 })
		tween(subtitle, CLEAR_FADE, { TextTransparency = 1 })
	end)
end

function FeedbackController.onCaught(reason: string)
	if not title then
		return
	end
	token += 1
	local mine = token

	-- 붉게 멈춘다. 페이드인 없이 즉시 — 적발의 순간은 부드러우면 안 된다.
	overlay.BackgroundColor3 = Color3.fromRGB(120, 20, 20)
	overlay.BackgroundTransparency = 0.5

	-- 화각도 즉시 좁히고 천천히 푼다. 줌인은 한 프레임, 복귀는 0.3초 —
	-- 맞는 쪽이 빠르고 풀리는 쪽이 느려야 "맞았다"가 된다.
	local camera = Workspace.CurrentCamera
	if camera then
		camera.FieldOfView = CameraController.FIELD_OF_VIEW - FAIL_ZOOM
	end
	setFov(CameraController.FIELD_OF_VIEW, FAIL_ZOOM_OUT)

	title.Text = "야! 너 뭐야!"
	title.TextColor3 = Color3.fromRGB(255, 225, 225)
	title.TextTransparency = 0
	title.TextSize = TITLE_SIZE + FAIL_TITLE_PUNCH
	tween(title, 0.1, { TextSize = TITLE_SIZE })
	subtitle.Text = REASONS[reason] or reason
	subtitle.TextTransparency = 0.1

	pointFinger()

	task.delay(FAIL_FLASH, function()
		if token ~= mine then
			return
		end
		overlay.BackgroundColor3 = Color3.new(0, 0, 0)
		tween(overlay, FAIL_TO_BLACK, { BackgroundTransparency = 0 })
	end)

	task.delay(FAIL_BLACK_HOLD, function()
		if token ~= mine then
			return
		end
		tween(overlay, FAIL_FADE_OUT, { BackgroundTransparency = 1 })
		tween(title, FAIL_FADE_OUT, { TextTransparency = 1 })
		tween(subtitle, FAIL_FADE_OUT, { TextTransparency = 1 })
	end)
end

function FeedbackController.Start(room: Model)
	buildGui()

	local teacher = room:WaitForChild(RoomKeys.TEACHER, WAIT_TIMEOUT)
	assert(teacher, "선생님 모델이 복제되지 않았다.")
	teacherArm = teacher:WaitForChild("ArmRight", WAIT_TIMEOUT) :: BasePart
end

return FeedbackController
