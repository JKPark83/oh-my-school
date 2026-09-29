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
Keys.SPAWN = "Spawn" -- SpawnLocation
Keys.GATE = "Gate"
Keys.GATE_SIGN = "GateSign"
Keys.SIGNPOST = "Signpost" -- 「우리 학교로」 팻말(ProximityPrompt)
Keys.ADMISSION_DESK = "AdmissionDesk" -- 입학 접수대
Keys.PRINCIPAL_CHAIR = "PrincipalChair" -- 교장실 Seat
Keys.GRADUATION_BELL = "GraduationBell" -- 강당 단상 종
Keys.SILHOUETTE = "Silhouette" -- 미건설 시설 실루엣
Keys.CONSTRUCTION = "Construction" -- 2층 「공사 중」 실루엣
Keys.STICKER_BOARD = "StickerBoard" -- 현관 서쪽 벽 3D 스티커판
Keys.PROTOTYPES = "CharacterPrototypes" -- ReplicatedStorage 사람 원형 폴더
Keys.SKIN_SIGN = "SkinSign" -- 페인트 롤러 팻말 위치 Attachment
Keys.DOOR = "Door" -- 시설 모델의 문 Attachment(학생이 걸어 들어오는 지점)
Keys.LEADERBOARD = "Leaderboard" -- 광장 리더보드 파트
Keys.HOME_PROMPT = "HomePrompt" -- 「우리 학교로」 ProximityPrompt(광장 팻말·부지 팻말)
Keys.ADMISSION_PROMPT = "AdmissionPrompt" -- 입학 접수대 ProximityPrompt

-- PlotState 폴더 어트리뷰트(기획서 §11.4)
Keys.ATTR_OWNER_ID = "OwnerId" -- number, 0 = 빈 부지
Keys.ATTR_OWNER_NAME = "OwnerName" -- string
Keys.ATTR_GRADUATIONS = "Graduations" -- number
Keys.ATTR_FACILITIES = "Facilities" -- CSV "desk,board"
Keys.ATTR_SKINS = "Skins" -- CSV "desk:2,board:1"
Keys.ATTR_STUDENTS = "Students" -- CSV "s01,s02"
Keys.ATTR_INCOME = "Income" -- number, 초당 수입

-- 파트·모델 어트리뷰트
Keys.ATTR_BUILT = "Built" -- 시설 모델: 서버가 넣을 때 true. 클라가 등장 연출 트리거로 쓴다
Keys.ATTR_COLLECTED = "Collected" -- 스티커: true 면 수집됨(리스폰 대기)
Keys.ATTR_GOLD = "Gold" -- 스티커: 다음 스폰이 금 스티커
Keys.ATTR_FACILITY_ID = "FacilityId" -- 패드·실루엣 ↔ 시설
Keys.ATTR_PLOT_ID = "PlotId" -- 부지 번호(1~12)
Keys.ATTR_PAD_STATE = "PadState" -- "active" | "next" | "hidden" | "built"
Keys.ATTR_STICKER_ID = "StickerId" -- 스티커 스폰 번호(1~8)
Keys.ATTR_SKIN = "Skin" -- 시설 모델: 적용된 스킨 번호
Keys.ATTR_SKIN_ROLE = "SkinRole" -- 시설 파트: "primary" | "secondary" (스킨 색을 받는 파트)

-- 플레이어 어트리뷰트
Keys.ATTR_PLOT = "Plot" -- player:GetAttribute("Plot") = 부지 번호

Keys.COLLISION_GROUP_PLAYERS = "Players"
Keys.PLOT_COUNT = 12

-- 사용자에게 보이는 고정 문구
Keys.KICK_RELOAD = "다시 들어와 주세요"
Keys.KICK_SAVE = "저장이 안 됐어요"

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
