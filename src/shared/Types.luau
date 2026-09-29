--!strict
--[[
	공용 타입 정의. 서버·클라이언트가 같은 이름으로 같은 것을 가리키는 유일한 지점.
	프로필 형태는 기획서 §11.6, 이벤트 종류는 §11.5 를 그대로 옮겼다.
]]

local Types = {}

export type FacilityId = string -- "desk" … "auditorium"
export type StudentId = string -- "s01" … "s24"
export type PlotId = number -- 1 … 12
export type Tier = "평범" | "반장" | "전교1등" | "전설"

export type Missions = {
	day: number, -- KST 기준 일 번호. 바뀌면 진행도 초기화
	stickers: number,
	built: number,
	chair: boolean,
	done: { boolean }, -- [1..3]
}

export type Settings = {
	shake: boolean,
	sfx: boolean,
	haptic: boolean,
}

export type Stats = {
	totalCoins: number,
	totalStickers: number,
	totalPulls: number,
	playSeconds: number,
}

export type Profile = {
	version: number,
	coins: number,
	tickets: number,
	stickerBoard: number, -- 0 … 59
	graduations: number,
	facilities: { [FacilityId]: boolean },
	students: { [StudentId]: number }, -- 보유 수(중복 포함). 0 이면 키 없음
	pity: number, -- 마지막 전설 이후 뽑은 횟수
	missions: Missions,
	settings: Settings,
	stats: Stats,
}

export type Seat = {
	facilityId: FacilityId,
	index: number, -- Seats/S0n 의 n
}

export type GameEventKind =
	"FacilityBuilt"
	| "StudentJoined"
	| "GachaResult"
	| "MissionDone"
	| "Graduated"
	| "StickerCollected"
	| "Deny"

export type GachaResult = {
	studentId: StudentId,
	tier: Tier,
	isDupe: boolean,
	dupeCount: number,
	boardCells: number,
	ticketsLeft: number,
	pityLeft: number,
	seq: number,
}

export type SettingKey = "shake" | "sfx" | "haptic"

return Types
