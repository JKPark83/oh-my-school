--!strict
--[[
	로딩 화면. ReplicatedFirst 에서 가장 먼저 돌아 검정 화면 + 제목을 띄운다(기획서 §11.2, 최대 3초).

	  ★ 이 파일은 아무것도 require 하지 않는다. ReplicatedFirst 는 ReplicatedStorage.Shared 가
	    내려오기 전에 실행되므로 Keys·Config 를 기다리면 로딩 화면이 로딩을 기다리는 꼴이 된다.
	  ★ 끝나는 조건: game.Loaded 와 RemoteEvents 폴더 둘 다. 어느 쪽이 늦어도 3초가 지나면 무조건 걷는다 —
	    검정 화면이 오래 남는 것은 "멈춘 게임"으로 보인다.
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- TODO(통합): Remotes.luau 의 FOLDER_NAME 과 같은 문자열. Shared 를 require 할 수 없어 여기 한 번 더 적는다
local REMOTES_FOLDER = "RemoteEvents"
local REMOTES_TIMEOUT = 30
local MAX_SECONDS = 3
local FADE_SECONDS = 0.3

local TITLE = "교장이 되어보자!"
local PROGRESS_WORLD = "학교 문을 여는 중"
local PROGRESS_REMOTES = "친구들을 부르는 중"

local BACKGROUND = Color3.fromRGB(0, 0, 0)
local TITLE_COLOR = Color3.fromRGB(251, 191, 36) -- §8.1 노랑
local PROGRESS_COLOR = Color3.fromRGB(229, 231, 235)

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "Loading"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = BACKGROUND
backdrop.BorderSizePixel = 0
backdrop.Parent = gui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.46)
title.Size = UDim2.new(0.8, 0, 0, 48)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextScaled = true
title.TextColor3 = TITLE_COLOR
title.Text = TITLE
title.Parent = backdrop

local titleSize = Instance.new("UITextSizeConstraint")
titleSize.MinTextSize = 20
titleSize.MaxTextSize = 40
titleSize.Parent = title

local progress = Instance.new("TextLabel")
progress.Name = "Progress"
progress.AnchorPoint = Vector2.new(0.5, 0.5)
progress.Position = UDim2.fromScale(0.5, 0.6)
progress.Size = UDim2.new(0.8, 0, 0, 22)
progress.BackgroundTransparency = 1
progress.Font = Enum.Font.GothamMedium
progress.TextScaled = true
progress.TextColor3 = PROGRESS_COLOR
progress.TextTransparency = 0.25
progress.Text = PROGRESS_WORLD
progress.Parent = backdrop

local progressSize = Instance.new("UITextSizeConstraint")
progressSize.MinTextSize = 14
progressSize.MaxTextSize = 18
progressSize.Parent = progress

gui.Parent = playerGui

local finished = false

local function finish()
	if finished then
		return
	end
	finished = true

	local info = TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(backdrop, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(title, info, { TextTransparency = 1 }):Play()
	TweenService:Create(progress, info, { TextTransparency = 1 }):Play()
	task.delay(FADE_SECONDS, function()
		gui:Destroy()
	end)
end

-- 3초 상한. 무엇이 늦든 검정 화면은 여기서 끝난다
task.delay(MAX_SECONDS, finish)

task.spawn(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	if finished then
		return
	end
	progress.Text = PROGRESS_REMOTES
	ReplicatedStorage:WaitForChild(REMOTES_FOLDER, REMOTES_TIMEOUT)
	finish()
end)
