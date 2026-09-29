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
	playSeconds: number,
}

-- 꾸미기 배치 1개. cx·cz 는 그리드 칸, rot 는 회전 단계, f 는 층(nil = 1층)
export type DecorPlacement = {
	item: string,
	cx: number,
	cz: number,
	rot: number,
	f: number?,
}

export type Profile = {
	version: number,
	coins: number,
	stickerBoard: number, -- 0 … 39
	giftIndex: number, -- 받은 선물 수
	graduations: number,
	facilities: { [FacilityId]: boolean },
	buildParts: number, -- 다음 시설에 이미 산 부품 수(0..부품 수-1). 시설이 완공되면 0
	students: { [StudentId]: number }, -- 보유 수(중복 포함). 0 이면 키 없음
	missions: Missions,
	settings: Settings,
	stats: Stats,
	decorOwned: { [string]: number }, -- 꾸미기 아이템 id → 보관함 수
	decorPlaced: { DecorPlacement },
	decorPaid: { [string]: { number } }, -- 아이템 id → 산 값 스택(돌려주기는 맨 뒤 값). 비면 키 없음. 무료로 받은 것은 없다
	decorStarter: boolean, -- 튜토리얼 화분을 받았는지(한 번만 준다)
	towerFloors: number,
}

export type Seat = {
	facilityId: FacilityId,
	index: number, -- Seats/S0n 의 n
}

export type GameEventKind =
	"PartBuilt" -- { plot, facilityId, partIndex, partCount }. 마지막 부품이면 뒤에 FacilityBuilt 가 온다
	| "FacilityBuilt"
	| "StudentJoined"
	| "MissionDone"
	| "Graduated"
	| "StickerCollected"
	| "GiftOpened"
	| "Deny"
	| "DecorPlaced"
	| "DecorStored"
	| "DecorBought"
	| "DecorReturned"
	| "FloorBuilt"
	| "ElevatorRide"

-- 선물판 40칸이 차서 선물 1개를 받음. 본인에게만
export type GiftOpened = {
	giftIndex: number,
	kind: "coins" | "item", -- item 이면 보관함에 1개 들어가고 coins 는 0
	coins: number,
	boardCells: number,
	item: string?, -- kind == "item" 일 때 DecorConfig id
}

-- 꾸미기(W5). 전부 본인에게만. slot 은 decorPlaced 순번
export type DecorPlaced = {
	slot: number,
	item: string,
	cx: number,
	cz: number,
	rot: number,
	f: number,
	moved: boolean, -- true = MoveDecor(자리 옮김), false = PlaceDecor(보관함에서 꺼냄)
}

export type DecorStored = {
	slot: number, -- 빠진 순번. 뒤 순번은 하나씩 당겨진다
	item: string,
}

export type DecorBought = {
	item: string,
	coins: number, -- 낸 코인
	student: string?, -- 친구 아이템으로 새로 온 학생
}

export type DecorReturned = {
	item: string,
	coins: number, -- 돌려받은 코인
}

-- 층 올리기(W6). 주인에게만. floor = 방금 산 층 번호, coins = 낸 코인
export type FloorBuilt = {
	plot: number,
	floor: number,
	coins: number,
}

-- 엘리베이터를 탄 사람에게만. floor = 도착 층
export type ElevatorRide = {
	plot: number,
	floor: number,
}

export type DenyReason = "coins" | "cooldown" | "owner" | "cell" | "limit" | "owned" | "locked"

export type SettingKey = "shake" | "sfx" | "haptic"

return Types
