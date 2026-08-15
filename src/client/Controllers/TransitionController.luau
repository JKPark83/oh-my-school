--!nonstrict
--[[
	허브 ↔ 교실 전환 화면.

	★ 이 검은 화면의 진짜 일은 연출이 아니라 은폐다.
	  서버는 화면을 덮으라고 보낸 다음 RequestStreamAroundAsync 로 5000 스터드 밖
	  교실이 내려오기를 기다린다. 그 대기 시간이 그대로 보이면 "렉"이고,
	  실내화로 갈아신는 연출이 덮으면 "학교에 들어가는 장면"이 된다.

	  그래서 페이드인은 서버의 TRANSITION_HOLD 보다 확실히 짧아야 하고,
	  페이드아웃은 텔레포트가 끝난 뒤에 시작해야 한다.

	FeedbackController 의 오버레이와 따로 두는 이유는, 그쪽은 성공/실패 타이밍에
	맞춰진 물건이라서다. 두 연출이 같은 프레임을 공유하면 서로의 트윈을 잡아먹는다.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local WAIT_TIMEOUT = 10

local FADE_IN = 0.18
local HOLD = 0.42 -- 서버 TRANSITION_HOLD(0.55)보다 짧다. 끝나기 전에 페이드아웃이 시작된다
local FADE_OUT = 0.3

local MESSAGES = {
	class = "실내화로 갈아신는 중…",
	hub = "복도로 나가는 중…",
}

local player = Players.LocalPlayer

local TransitionController = {}

local overlay: Frame
local label: TextLabel
local token = 0

function TransitionController.onTransition(packet)
	if not overlay then
		return
	end
	token += 1
	local mine = token

	label.Text = MESSAGES[packet.to] or ""
	overlay.BackgroundTransparency = 1
	label.TextTransparency = 1

	TweenService:Create(overlay, TweenInfo.new(FADE_IN), { BackgroundTransparency = 0 }):Play()
	TweenService:Create(label, TweenInfo.new(FADE_IN), { TextTransparency = 0.15 }):Play()

	task.delay(FADE_IN + HOLD, function()
		if token ~= mine then
			return
		end
		TweenService:Create(overlay, TweenInfo.new(FADE_OUT), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, TweenInfo.new(FADE_OUT), { TextTransparency = 1 }):Play()
	end)
end

function TransitionController.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Transition"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 8 -- 성공/실패 연출보다도 위. 전환 중에는 아무것도 보이면 안 된다
	gui.Parent = player:WaitForChild("PlayerGui", WAIT_TIMEOUT)

	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Parent = gui

	label = Instance.new("TextLabel")
	label.Name = "Message"
	label.Size = UDim2.new(1, 0, 0, 34)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 24
	label.TextColor3 = Color3.fromRGB(235, 235, 235)
	label.TextTransparency = 1
	label.Text = ""
	label.Parent = gui
end

return TransitionController
