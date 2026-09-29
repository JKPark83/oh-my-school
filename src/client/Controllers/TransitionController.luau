--!strict
--[[
	화면 전환 오버레이. 기획서 §9.5(졸업식 검은 화면)·§8.4(플래시 제한).
	  fadeTo(alpha, seconds)   검은 오버레이를 alpha(0 투명 ~ 1 불투명)로
	  cut()                    즉시 투명
	  flash(alpha, seconds)    흰 플래시. α ≤ 0.7, ≤ 0.08초, 1초에 한 번까지
	  message(text, seconds)   가운데 문구를 seconds 동안

	★ 이 오버레이는 다른 GUI 보다 위(DisplayOrder 8)다. 전환 중에는 아무것도 보이면 안 된다.
	  FeedbackController 의 연출과 같은 프레임을 쓰지 않는다 — 트윈이 서로를 잡아먹는다.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local WAIT_TIMEOUT = 10

-- §8.4 플래시 제한
local FLASH_MAX_ALPHA = 0.7
local FLASH_MAX_SECONDS = 0.08
local FLASH_MIN_INTERVAL = 1

local MESSAGE_FADE = 0.2

local player = Players.LocalPlayer

local TransitionController = {}

local overlay: Frame? = nil
local flashFrame: Frame? = nil
local label: TextLabel? = nil

local overlayTween: Tween? = nil
local labelToken = 0
local lastFlash = -math.huge

local function stopOverlayTween()
	local tween = overlayTween
	if tween then
		tween:Cancel()
		overlayTween = nil
	end
end

--- 검은 오버레이를 alpha 불투명도로 seconds 에 걸쳐
function TransitionController.fadeTo(alpha: number, seconds: number)
	local frame = overlay
	if not frame then
		return
	end
	stopOverlayTween()
	local goal = { BackgroundTransparency = 1 - math.clamp(alpha, 0, 1) }
	if seconds <= 0 then
		frame.BackgroundTransparency = goal.BackgroundTransparency
		return
	end
	local tween = TweenService:Create(frame, TweenInfo.new(seconds, Enum.EasingStyle.Sine), goal)
	overlayTween = tween
	tween:Play()
end

--- 즉시 투명
function TransitionController.cut()
	TransitionController.fadeTo(0, 0)
end

--- 흰 플래시. 접근성 한도(α 0.7, 0.08초, 초당 1회)를 넘는 값은 깎는다
function TransitionController.flash(alpha: number, seconds: number)
	local frame = flashFrame
	if not frame then
		return
	end
	local now = os.clock()
	if now - lastFlash < FLASH_MIN_INTERVAL then
		return
	end
	lastFlash = now
	local a = math.clamp(alpha, 0, FLASH_MAX_ALPHA)
	local s = math.clamp(seconds, 0, FLASH_MAX_SECONDS)
	frame.BackgroundTransparency = 1 - a
	TweenService:Create(frame, TweenInfo.new(s, Enum.EasingStyle.Linear), { BackgroundTransparency = 1 }):Play()
end

--- 가운데 문구를 seconds 동안 보여준다
function TransitionController.message(text: string, seconds: number)
	local target = label
	if not target then
		return
	end
	labelToken += 1
	local mine = labelToken
	target.Text = text
	target.TextTransparency = 1
	TweenService:Create(target, TweenInfo.new(MESSAGE_FADE), { TextTransparency = 0 }):Play()
	task.delay(seconds, function()
		if labelToken ~= mine then
			return
		end
		TweenService:Create(target, TweenInfo.new(MESSAGE_FADE), { TextTransparency = 1 }):Play()
	end)
end

function TransitionController.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Transition"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 8 -- 성공/실패 연출보다도 위. 전환 중에는 아무것도 보이면 안 된다
	gui.Parent = player:WaitForChild("PlayerGui", WAIT_TIMEOUT)

	local black = Instance.new("Frame")
	black.Name = "Overlay"
	black.Size = UDim2.fromScale(1, 1)
	black.BackgroundColor3 = Color3.new(0, 0, 0)
	black.BackgroundTransparency = 1
	black.BorderSizePixel = 0
	black.Parent = gui
	overlay = black

	local white = Instance.new("Frame")
	white.Name = "Flash"
	white.Size = UDim2.fromScale(1, 1)
	white.BackgroundColor3 = Color3.new(1, 1, 1)
	white.BackgroundTransparency = 1
	white.BorderSizePixel = 0
	white.Parent = gui
	flashFrame = white

	local text = Instance.new("TextLabel")
	text.Name = "Message"
	text.Size = UDim2.new(1, 0, 0, 34)
	text.Position = UDim2.fromScale(0.5, 0.5)
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamMedium
	text.TextSize = 24
	text.TextColor3 = Color3.fromRGB(235, 235, 235)
	text.TextTransparency = 1
	text.Text = ""
	text.Parent = gui
	label = text
end

return TransitionController
