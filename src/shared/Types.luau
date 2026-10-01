--!strict
--[[
	공용 타입 정의. 서버·클라이언트가 같은 이름으로 같은 것을 가리키는 유일한 지점.
	프로필 형태는 기획서 §11.6, 이벤트 종류는 §11.5 를 그대로 옮겼다.
]]

local Types = {}

export type FacilityId = string -- "desk" … "auditorium"
export type StudentId = string -- "s01" … "s28"
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
	music: boolean,
	haptic: boolean,
}

export type Stats = {
	totalCoins: number,
	totalStickers: number,
	playSeconds: number,
}

-- 꾸미기 배치 1개. cx·cz 는 그리드 칸, rot 는 회전 단계
export type DecorPlacement = {
	item: string,
	cx: number,
	cz: number,
	rot: number,
}

export type Profile = {
	version: number,
	coins: number,
	stickerBoard: number, -- 0 … 39
	giftIndex: number, -- 받은 선물 수
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
	-- 층 쌓기(개선계획 2026-10-01 §2.1)
	floors: { string }, -- 완공한 층의 방 id. floors[i] = (i+2)층
	rooftop: { [string]: boolean }, -- 완공한 옥상 방(garden·observatory)
	towerRoom: string, -- 지금 짓는 방 id. "" = 아직 안 골랐다
	towerParts: number, -- 지금 짓는 방에 산 부품 수(0..3). 완공되면 0
	likes: number, -- 받은 「멋져요」 수
}

export type Seat = {
	facilityId: FacilityId, -- 시설 id 또는 방 id(둘은 겹치지 않는다)
	index: number, -- Seats/S0n 의 n
}

export type GameEventKind =
	"PartBuilt" -- { plot, facilityId, partIndex, partCount }. 마지막 부품이면 뒤에 FacilityBuilt 가 온다
	| "FacilityBuilt"
	| "StudentJoined"
	| "MissionDone"
	| "StickerCollected"
	| "GiftOpened"
	| "Deny"
	| "DecorPlaced"
	| "DecorStored"
	| "DecorBought"
	| "DecorReturned"
	| "RoomChosen" -- { plot, room }. 주인
	| "FloorPart" -- { plot, room, partIndex, floor }. floor = 층 번호, 옥상 방이면 0. 주인(방문객 화면은 PlotState 어트리뷰트로 그린다)
	| "FloorBuilt" -- { plot, room, floor, floors }. 주인
	| "Liked" -- { plot, name }. name = 보낸 사람 DisplayName. 주인
	| "LikeSent" -- { plot }. 보낸 사람

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

export type DenyReason = "coins" | "cooldown" | "owner" | "cell" | "limit" | "owned"

export type SettingKey = "shake" | "sfx" | "music" | "haptic"

return Types
