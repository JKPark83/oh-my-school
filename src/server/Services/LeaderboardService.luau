--!strict
--[[
	광장 「높은 학교」 리더보드. 기획서 §6.4·§12.2, 개선계획(2026-10-01) §6.1.
	  OrderedDataStore "SchoolFloors"(값 = 완공 층 수) TOP 10 을 60초마다 읽어 Workspace.Plaza.Leaderboard 의 SurfaceGui 에 그린다.
	  이름은 UserService:GetUserInfosByUserIdsAsync 의 DisplayName(60초 캐시). 실패하면 「교장 #끝4자리」.
	  Username 은 어디에도 쓰지 않는다. submit 은 층을 완공할 때 부른다(P2).
	Studio 에서는 "SchoolFloors_Dev" 를 쓰고, DataStore 호출이 실패해도 조용히 넘어간다.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")
local Workspace = game:GetService("Workspace")

local Keys = require(ReplicatedStorage.Shared.Config.Keys)

local LeaderboardService = {}

-- 기획서 §6.4 수치·이름
local STORE_NAME = "SchoolFloors"
local TOP_N = 10
local REFRESH_INTERVAL = 60 -- 초
local TITLE_TEXT = "높은 학교"
local FALLBACK_PREFIX = "교장 #"

type Row = { userId: number, value: number }

local store: OrderedDataStore? = nil
local displayNames: { [number]: string } = {}
local rowLabels: { TextLabel } = {}

local function quietWarn(message: string)
	if not RunService:IsStudio() then
		warn(message)
	end
end

local function nameOf(userId: number): string
	return displayNames[userId] or `{FALLBACK_PREFIX}{string.format("%04d", userId % 10000)}`
end

local function newGui(part: BasePart): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = part
	return gui
end

local function newLabel(parent: Instance, name: string, order: number, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, height)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.5
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	label.Parent = parent
	return label
end

--- 보드 파트를 찾아 행 라벨 10개를 만든다. 없으면 warn 후 그리지 않는다
local function ensureBoard()
	local plaza = Workspace:FindFirstChild(Keys.PLAZA)
	local part = if plaza then plaza:FindFirstChild(Keys.LEADERBOARD, true) else nil
	if not part or not part:IsA("BasePart") then
		warn(`[LeaderboardService] Workspace.{Keys.PLAZA}.{Keys.LEADERBOARD} 가 없어 보드를 그리지 않는다`)
		return
	end
	local gui = part:FindFirstChildOfClass("SurfaceGui") or newGui(part)

	local frame = Instance.new("Frame")
	frame.Name = "Rows"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.PaddingTop = UDim.new(0.03, 0)
	padding.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.005, 0)
	layout.Parent = frame

	local title = newLabel(frame, "Title", 0, 0.14)
	title.Text = TITLE_TEXT
	title.TextXAlignment = Enum.TextXAlignment.Center
	for i = 1, TOP_N do
		rowLabels[i] = newLabel(frame, `Row{i}`, i, 0.078)
	end
	frame.Parent = gui
end

local function fetchTop(): { Row }?
	local activeStore = store
	if not activeStore then
		return nil
	end
	local ok, page = pcall(function()
		return activeStore:GetSortedAsync(false, TOP_N):GetCurrentPage()
	end)
	if not ok then
		quietWarn(`[LeaderboardService] 읽기 실패: {page}`)
		return nil
	end
	local rows: { Row } = {}
	for _, entry in page :: { any } do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(rows, { userId = userId, value = entry.value })
		end
	end
	return rows
end

local function refreshNames(rows: { Row })
	local ids: { number } = {}
	for _, row in rows do
		table.insert(ids, row.userId)
	end
	if #ids == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(ids)
	end)
	if not ok then
		quietWarn(`[LeaderboardService] 이름 조회 실패: {infos}`)
		return
	end
	for _, info in infos :: { any } do
		displayNames[info.Id] = info.DisplayName
	end
end

local function render(rows: { Row })
	for i, label in rowLabels do
		local row = rows[i]
		label.Text = if row then `{i}. {nameOf(row.userId)}  {row.value}층` else ""
	end
end

local function refresh()
	local rows = fetchTop()
	if not rows then
		return
	end
	refreshNames(rows)
	render(rows)
end

--- 완공 층 수 제출. yield 하지 않는다
function LeaderboardService.submit(player: Player, floors: number)
	local activeStore = store
	if not activeStore then
		return
	end
	local key = tostring(player.UserId)
	task.spawn(function()
		local ok, err = pcall(function()
			activeStore:SetAsync(key, floors)
		end)
		if not ok then
			quietWarn(`[LeaderboardService] 제출 실패 {key}: {err}`)
		end
	end)
end

--- 스토어 준비 + 보드 라벨 생성 + 60초 갱신 루프
function LeaderboardService.Start()
	local ok, result = pcall(function()
		-- Studio 에서 실제 DataStore 를 켜도 라이브 보드에 테스트 기록이 섞이지 않게 DataService 처럼 "_Dev" 를 붙인다
		return DataStoreService:GetOrderedDataStore(if RunService:IsStudio() then STORE_NAME .. "_Dev" else STORE_NAME)
	end)
	if ok then
		store = result
	else
		quietWarn(`[LeaderboardService] OrderedDataStore 열기 실패: {result}`)
	end

	ensureBoard()

	if store and #rowLabels > 0 then
		task.spawn(function()
			while true do
				refresh()
				task.wait(REFRESH_INTERVAL)
			end
		end)
	end
end

return LeaderboardService
