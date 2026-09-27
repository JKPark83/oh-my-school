--!strict
--[[
	공용 타입 정의.
	서버·클라이언트가 같은 이름으로 같은 것을 가리키게 하는 유일한 지점.
]]

local Types = {}

-- 선생님 상태.
--   TEACHING  : 칠판을 보고 판서 중. 감지 OFF
--   WARNING   : 예고 신호(분필 멈춤 + 어깨 들썩). 아직 감지 OFF
--   TURNING   : 몸을 돌리는 중. 후반 50%부터 감지 ON
--   WATCHING  : 정면 응시. 감지 ON
--   RETURNING : 다시 칠판으로. 감지 OFF
--   FAKE_TURN : 어깨만 들썩이고 안 돌아봄(낚시). 감지 OFF. 1학년은 미사용
export type TeacherState = "TEACHING" | "WARNING" | "TURNING" | "WATCHING" | "RETURNING" | "FAKE_TURN"

export type TeacherConfig = {
	teachTime: number, -- 판서 지속 시간(초). 실제로는 ±20% 흔들림
	warnTime: number, -- 예고 신호 지속 시간(초). 플레이어의 반응 예산
	turnTime: number, -- 몸을 다 돌리는 데 걸리는 시간(초)
	watchTime: number, -- 응시 지속 시간(초). 실제로는 ±25% 흔들림
	fovDeg: number, -- 시야각 전체 각도(도). 판정에는 절반만 쓴다
	fakeChance: number, -- 페이크 턴 확률 0~1
}

-- 선생님 1명의 런타임 상태. 주인은 TeacherAI 하나뿐이다.
export type Teacher = {
	model: Model,
	head: BasePart,
	config: TeacherConfig,

	-- 이 선생님을 보고 있는 플레이어. 교실이 12개가 되면서 상태 패킷이
	-- 전체 방송이 아니라 이 한 명에게만 나가야 하므로 필요해졌다.
	owner: Player?,

	state: TeacherState,
	stateVersion: number, -- 단조 증가. 클라가 순서 뒤바뀐 패킷을 버리는 근거
	stateStartedAt: number, -- os.clock() 기준
	stateEndsAt: number, -- os.clock() 기준
	watchStartedAt: number, -- 감지가 실제로 켜지는 시각. GRACE 계산에 쓴다
	lastWasFake: boolean, -- 2연속 페이크 금지용

	teachYaw: number, -- 칠판을 보는 기준 각도(라디안)
	basePivot: CFrame, -- 회전 전 기준 CFrame
}

-- 이동 3단계.
--   SNEAK : 느리지만 예고를 보고 멈추면 항상 안전하다
--   WALK  : 기본. 멈출 수 있을지 없을지가 아슬아슬하다
--   RUN   : 빠르지만 예고를 보고 나서 멈추면 늦는다. 소음까지 낸다
export type MoveMode = "SNEAK" | "WALK" | "RUN"

export type MoveModeConfig = {
	speed: number, -- stud/s
	stopTime: number, -- 감속 시상수(초). 속도가 1/e 로 줄어드는 데 걸리는 시간
	noisy: boolean, -- 선생님의 판서를 끊고 조기 회전을 유발하는가
	label: string, -- HUD 표시용
}

-- 서버 → 클라 선생님 상태 패킷. 이 게임의 유일한 선생님 상태 채널이다.
export type TeacherStatePacket = {
	version: number,
	state: TeacherState,
	duration: number,
}

-- 업그레이드 보유 여부. 키는 Config/Upgrades 의 키와 1:1이다.
export type UpgradeMap = { [string]: boolean }

--[[
	DataStore 에 그대로 내려가는 값. Instance·함수·순환 참조가 들어가면 안 된다.

	version 은 지금 쓸 일이 없어도 반드시 넣는다. 스키마가 바뀌는 날
	이 필드가 없으면 기존 플레이어 데이터를 통째로 버려야 한다.
]]
export type Profile = {
	version: number,
	grade: number,
	class: number,
	stars: number,
	upgrades: UpgradeMap,
	cleared: { [string]: boolean }, -- "1-3" 형식. 이미 준 별을 두 번 주지 않기 위한 것
	perfect: { [string]: boolean },
	gradeCleared: { [string]: boolean }, -- "1" 형식. 학년 최초 수료 보너스용
	totalSeconds: number,
	attempts: number,
	caught: number,
}

-- 서버 → 클라. HUD 와 클라 이동 보정에 필요한 만큼만 내려간다.
export type ProfilePacket = {
	grade: number,
	class: number,
	stars: number,
	upgrades: UpgradeMap,
	totalSeconds: number,

	-- 종까지 남은 초. 교실 밖에서는 없다 — 운동장에는 울릴 종이 없다.
	bellSeconds: number?,
}

return Types
