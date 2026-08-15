--!nonstrict
--[[
	예고 신호. 이 게임에서 "억울함"을 없애는 마지막 장치다.

	서버는 상태만 보내고, 연출은 전부 클라 몫이다.
	세 신호 모두 warnTime(0.60~0.75초) "안에" 완결되어야 한다.
	0.6초 안에 인지 → 판단 → 손가락까지 가야 하므로, 신호가 늦게 시작하면
	그 지연 자체가 억울함이 된다. 그래서 페이드인은 0.12초로 짧게 잡았다.

	  1. 분필 소리가 뚝 끊긴다 — 가장 강한 신호. 청각은 반사 신경을 직접 건드린다
	  2. 어깨가 한 번 들썩이고 팔이 칠판에서 떨어진다 — 시각 백업.
	     ★ 이 2번은 TeacherPoseController 가 한다. 원래 여기 있었는데,
	       판서 애니메이션이 매 프레임 같은 파트의 CFrame 을 쓰기 시작하면서
	       트윈과 주인이 둘이 되어버렸다. 파트 하나의 CFrame 주인은 하나여야 한다.
	  3. 화면 가장자리 비네트 — 아주 옅게. 화면을 가리면 안 된다
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local RoomKeys = require(ReplicatedStorage.Shared.Config.RoomKeys)
local SoundConfig = require(ReplicatedStorage.Shared.Config.SoundConfig)

local WAIT_TIMEOUT = 10

local VIGNETTE_ALPHA = 0.45 -- 0 이 완전 불투명. 값이 낮을수록 진하다
local VIGNETTE_FADE_IN = 0.12
local VIGNETTE_THICKNESS = 110 -- 화면 가장자리에서 안쪽으로 번지는 픽셀

local player = Players.LocalPlayer

local SignalController = {}

local vignette: CanvasGroup? = nil
local chalkSound: Sound? = nil
local fadeOutTween: Tween? = nil

--[[
	비네트는 이미지 에셋 없이 만든다.
	가장자리 프레임 4개에 각각 UIGradient 로 안쪽 페이드를 주면,
	radial 이미지 없이도 "가장자리가 어두워지는" 느낌이 나온다.

	4개를 CanvasGroup 에 담는 이유는 GroupTransparency 하나로
	전체 세기를 트윈할 수 있기 때문이다. 프레임마다 따로 트윈할 필요가 없다.
]]
local function makeEdge(
	parent: CanvasGroup,
	size: UDim2,
	position: UDim2,
	anchor: Vector2,
	rotation: number,
	flip: boolean
)
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = anchor
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BorderSizePixel = 0
	frame.Parent = parent

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = if flip
		then NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
		else NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	gradient.Parent = frame
end

local function buildVignette(): CanvasGroup
	local gui = Instance.new("ScreenGui")
	gui.Name = "WarningVignette"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = -1 -- 디버그 HUD 아래에 깐다
	gui.Parent = player:WaitForChild("PlayerGui", WAIT_TIMEOUT)

	local group = Instance.new("CanvasGroup")
	group.Name = "Edges"
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.GroupTransparency = 1 -- 평소에는 완전히 투명
	group.Parent = gui

	local t = VIGNETTE_THICKNESS
	makeEdge(group, UDim2.new(1, 0, 0, t), UDim2.fromScale(0, 0), Vector2.zero, 90, false)
	makeEdge(group, UDim2.new(1, 0, 0, t), UDim2.fromScale(0, 1), Vector2.new(0, 1), 90, true)
	makeEdge(group, UDim2.new(0, t, 1, 0), UDim2.fromScale(0, 0), Vector2.zero, 0, false)
	makeEdge(group, UDim2.new(0, t, 1, 0), UDim2.fromScale(1, 0), Vector2.new(1, 0), 0, true)

	return group
end

--[[
	@param duration warnTime. 페이드아웃은 남은 시간을 전부 써서 부드럽게 사라진다.
]]
local function flashVignette(duration: number)
	if not vignette then
		return
	end
	if fadeOutTween then
		fadeOutTween:Cancel()
	end

	local fadeIn = TweenService:Create(
		vignette,
		TweenInfo.new(VIGNETTE_FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ GroupTransparency = VIGNETTE_ALPHA }
	)

	local fadeOutTime = math.max(duration - VIGNETTE_FADE_IN, 0.1)
	fadeOutTween = TweenService:Create(
		vignette,
		TweenInfo.new(fadeOutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ GroupTransparency = 1 }
	)

	fadeIn.Completed:Connect(function()
		if fadeOutTween then
			fadeOutTween:Play()
		end
	end)
	fadeIn:Play()
end

--[[
	init.client 의 상태 핸들러가 version 필터를 통과시킨 패킷만 넘겨준다.
	여기서 다시 필터링하지 않는다 — 순서 판단은 한 곳에서만 한다.
]]
function SignalController.onTeacherState(state: string, duration: number)
	if state == "TEACHING" then
		if chalkSound then
			chalkSound:Play()
		end
		return
	end

	-- 판서가 아닌 모든 상태에서 분필 소리는 멈춘다.
	-- "소리가 끊긴다"가 신호이므로, 정지가 예고보다 한 프레임이라도 늦으면 안 된다.
	if chalkSound then
		chalkSound:Stop()
	end

	-- WARNING 과 FAKE_TURN 은 플레이어에게 똑같이 보여야 한다.
	-- 낚시인지 아닌지 구분되면 낚시가 아니다.
	if state == "WARNING" or state == "FAKE_TURN" then
		flashVignette(duration)
	end
end

function SignalController.Start(room: Model)
	vignette = buildVignette()

	local teacher = room:WaitForChild(RoomKeys.TEACHER, WAIT_TIMEOUT)
	assert(teacher, "선생님 모델이 복제되지 않았다.")

	--[[
		★ 분필 소리는 반드시 선생님 위치에서 난다. 3D 사운드여야
		  "소리가 어디서 끊겼는지"로 선생님을 찾을 수 있다.
	]]
	local head = teacher:WaitForChild("Head", WAIT_TIMEOUT) :: BasePart
	local chalk = SoundConfig.create("chalk")
	chalk.Parent = head
	chalkSound = chalk

	--[[
		수업 목소리는 판서와 달리 계속 돈다. 이게 같이 끊기면 신호가 둘이 되고,
		둘이 되면 어느 쪽이 신호인지 헷갈린다. 교실은 계속 살아 있고,
		멈추는 것은 분필 하나뿐이어야 한다.
	]]
	local lecture = SoundConfig.create("lecture")
	lecture.Parent = head
	lecture:Play()

	--[[
		첫 판서 소리는 여기서 시작한다.
		이 컨트롤러는 교실에 처음 들어가는 전환 중에 붙는데, 그때 이미
		서버는 TEACHING 을 한 번 보내고 지나간 뒤다. 그 패킷을 놓쳐서
		첫 사이클 내내 분필이 안 울리면, 하필 첫 판에서 예고 신호가 없다.
	]]
	chalk:Play()
end

return SignalController
