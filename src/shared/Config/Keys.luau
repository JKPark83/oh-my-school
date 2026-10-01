--!strict
--[[
	태그·어트리뷰트·인스턴스 이름 문자열의 유일한 출처.
	서버와 클라이언트가 같은 문자열을 두 군데에 적지 않게 한다.
]]

local Keys = {}

-- CollectionService 태그
Keys.FADE_TAG = "Fade" -- 카메라와 캐릭터 사이에 끼면 투명해지는 벽·지붕
Keys.PAD_TAG = "Pad" -- 구매 패드
Keys.STICKER_TAG = "Sticker" -- 칭찬스티커 파트
Keys.STAR_TAG = "Star" -- 방문객 별

-- 폴더·모델 이름
Keys.PLOTS_FOLDER = "Plots" -- Workspace.Plots
Keys.PLOT_STATE_FOLDER = "PlotState" -- ReplicatedStorage.PlotState
Keys.PLAZA = "Plaza" -- Workspace.Plaza
Keys.SHELL = "Shell" -- 부지 안 무료 껍데기(현관·교실1·담장·교문)
Keys.SEATS_FOLDER = "Seats" -- 시설 모델 안 Attachment S01…
Keys.PADS_FOLDER = "Pads"
Keys.STICKERS_FOLDER = "Stickers"
Keys.STARS_FOLDER = "Stars"
Keys.TOWER_FOLDER = "Tower" -- 부지 모델 안 탑 서버 파트(Geometry/Tower)
Keys.TOWER_PAD = "TowerPad" -- 층 패드 파트
Keys.TOWER_PAD_ID = "tower" -- 층 패드의 FacilityId(시설 id 와 겹치지 않는다)
Keys.ELEVATOR_PROMPT = "ElevatorPrompt" -- 엘리베이터 ProximityPrompt
Keys.SPAWN = "Spawn" -- SpawnLocation
Keys.GATE = "Gate"
Keys.GATE_SIGN = "GateSign"
Keys.SIGNPOST = "Signpost" -- 「우리 학교로」 팻말(ProximityPrompt)
Keys.ADMISSION_DESK = "AdmissionDesk" -- 입학 접수대
Keys.PRINCIPAL_CHAIR = "PrincipalChair" -- 교장실 Seat
Keys.SILHOUETTE = "Silhouette" -- 미건설 시설 실루엣
Keys.CONSTRUCTION = "Construction" -- 2층 「공사 중」 실루엣
Keys.STICKER_BOARD = "StickerBoard" -- 현관 서쪽 벽 3D 스티커판
Keys.PROTOTYPES = "CharacterPrototypes" -- ReplicatedStorage 사람 원형 폴더
Keys.DOOR = "Door" -- 시설 모델의 문 Attachment(옛 전학 걷기 출발점. 지금 전학은 자리에서 「짠」이라 읽는 곳이 없다)
Keys.LEADERBOARD = "Leaderboard" -- 광장 리더보드 파트
Keys.HOME_PROMPT = "HomePrompt" -- 「우리 학교로」 ProximityPrompt(광장 팻말·부지 팻말)

-- PlotState 폴더 어트리뷰트(기획서 §11.4)
Keys.ATTR_OWNER_ID = "OwnerId" -- number, 0 = 빈 부지
Keys.ATTR_OWNER_NAME = "OwnerName" -- string
Keys.ATTR_FACILITIES = "Facilities" -- CSV "desk,board"
Keys.ATTR_STUDENTS = "Students" -- CSV "s01,s02"
Keys.ATTR_INCOME = "Income" -- number, 초당 수입
Keys.ATTR_DECOR = "Decor" -- DecorCodec 문자열. 빈 부지는 ""
Keys.ATTR_FLOORS = "Floors" -- CSV "art,computer". 3층부터 순서대로
Keys.ATTR_ROOFTOP = "Rooftop" -- CSV "garden"
Keys.ATTR_TOWER_ROOM = "TowerRoom" -- 지금 짓는 방 id 또는 ""
Keys.ATTR_TOWER_PARTS = "TowerParts" -- 0..3
Keys.ATTR_LIKES = "Likes" -- number
Keys.ATTR_RANK = "Rank" -- 1..12, 0 = 층 없음. 같은 서버 안 높이 순위

-- 파트·모델 어트리뷰트
Keys.ATTR_BUILT = "Built" -- 시설 모델: 마지막 부품을 넣어 완공될 때 true
Keys.ATTR_PARTS = "Parts" -- 시설 모델: 지금까지 넣은 부품 수(number). 클라가 등장 연출 트리거로 쓴다
Keys.ATTR_PART_INDEX = "PartIndex" -- 시설 BasePart: 부품 번호(1..부품 수). Geometry 가 붙인다
Keys.ATTR_COLLECTED = "Collected" -- 스티커: true 면 수집됨(리스폰 대기)
Keys.ATTR_GOLD = "Gold" -- 스티커: 다음 스폰이 금 스티커
Keys.ATTR_FACILITY_ID = "FacilityId" -- 패드·실루엣 ↔ 시설
Keys.ATTR_PLOT_ID = "PlotId" -- 부지 번호(1~12)
Keys.ATTR_PAD_STATE = "PadState" -- "active" | "next" | "hidden" | "built"
Keys.ATTR_PAD_BASE = "PadBase" -- 구매 패드: 지금 자리 CFrame(서버). 부품마다 옮겨 가서 클라 눌림 연출의 기준을 여기서 읽는다
Keys.ATTR_STICKER_ID = "StickerId" -- 스티커 스폰 번호(1~8)

-- 플레이어 어트리뷰트
Keys.ATTR_PLOT = "Plot" -- player:GetAttribute("Plot") = 부지 번호

Keys.COLLISION_GROUP_PLAYERS = "Players"
Keys.PLOT_COUNT = 12

-- 사용자에게 보이는 고정 문구
Keys.KICK_RELOAD = "다시 들어와 주세요"

--- 부지 번호 → "Plot01" 꼴 이름
function Keys.plotName(plotId: number): string
	return string.format("Plot%02d", plotId)
end

--- "Plot07" → 7. 아니면 nil
function Keys.plotIdOf(name: string): number?
	local digits = string.match(name, "^Plot(%d%d)$")
	return if digits then tonumber(digits) else nil
end

return Keys
