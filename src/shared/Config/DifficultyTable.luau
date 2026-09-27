--!strict
--[[
	학년/반별 선생님 수치.

	핵심 원칙: 2~6학년은 코드가 아니라 데이터다.
	여기에 학년 항목을 추가하는 것만으로 콘텐츠가 늘어나야 한다.

	반 1 → 반 12는 first / last 사이를 선형 보간한다.
	반마다 표를 손으로 쓰지 않는다.
]]

local Types = require(script.Parent.Parent.Types)

local CLASSES_PER_GRADE = 12

--[[
	학년 사이는 이어 붙인다 — N학년 last 와 N+1학년 first 가 같은 값이다.
	12반을 깨고 다음 학년 1반에 들어갔을 때 갑자기 쉬워지거나 어려워지면
	"올라왔다"가 아니라 "다른 게임이 됐다"가 된다.

	★ 학년마다 새로 조이는 항목을 하나씩만 둔다. 여섯 수치를 매번 같이 올리면
	  왜 어려워졌는지 알 수 없고, 알 수 없는 난이도는 실력으로 넘을 수 없다.

	    2학년 — 페이크 턴. 처음으로 "예고가 거짓일 수 있다"를 배운다
	    3학년 — 시야각. 이제 분단 끝자리도 안전하지 않다
	    4학년 — 응시 시간. 얼어 있어야 하는 시간이 길어진다
	    5학년 — 몸 도는 속도. 예고를 보고 멈추는 손이 빨라야 한다
	    6학년 — 판서 시간. 쉴 틈이 사라진다
]]
local BANDS: { [number]: { first: Types.TeacherConfig, last: Types.TeacherConfig } } = {
	-- 1학년: 페이크 턴 0%.
	-- 첫 학년에서 배워야 할 규칙은 "예고를 보면 멈춘다" 하나뿐이다.
	-- 여기에 낚시를 섞으면 규칙 자체를 못 배운다.
	[1] = {
		first = { teachTime = 5.0, warnTime = 0.75, turnTime = 0.45, watchTime = 1.6, fovDeg = 90, fakeChance = 0 },
		last = { teachTime = 3.5, warnTime = 0.60, turnTime = 0.45, watchTime = 2.2, fovDeg = 90, fakeChance = 0 },
	},

	-- 2학년: 페이크 턴이 들어온다. 1반은 0.10 이라 열 번에 한 번이다 —
	-- 처음 당했을 때 "방금 뭐였지"가 되어야지, 매번 당하면 예고를 안 믿게 된다.
	[2] = {
		first = { teachTime = 3.5, warnTime = 0.60, turnTime = 0.45, watchTime = 2.2, fovDeg = 90, fakeChance = 0.10 },
		last = { teachTime = 3.2, warnTime = 0.56, turnTime = 0.45, watchTime = 2.6, fovDeg = 95, fakeChance = 0.30 },
	},

	-- 3학년: 시야각 95 → 115. 여기서 엄폐물이 처음으로 필수가 된다.
	[3] = {
		first = { teachTime = 3.2, warnTime = 0.56, turnTime = 0.45, watchTime = 2.6, fovDeg = 95, fakeChance = 0.30 },
		last = { teachTime = 3.0, warnTime = 0.52, turnTime = 0.42, watchTime = 2.9, fovDeg = 115, fakeChance = 0.35 },
	},

	-- 4학년: 응시 2.9 → 3.6초. 수치는 하나지만 체감은 "참는 게임"으로 바뀐다.
	[4] = {
		first = { teachTime = 3.0, warnTime = 0.52, turnTime = 0.42, watchTime = 2.9, fovDeg = 115, fakeChance = 0.35 },
		last = { teachTime = 2.8, warnTime = 0.48, turnTime = 0.40, watchTime = 3.6, fovDeg = 120, fakeChance = 0.40 },
	},

	-- 5학년: 회전 0.40 → 0.30초. 예고 0.44 에 회전 0.30 이면 멈출 예산이 0.74 초다.
	-- 눈치(+0.1)를 안 샀으면 여기서 벽에 부딪힌다 — 그러라고 파는 물건이다.
	[5] = {
		first = { teachTime = 2.8, warnTime = 0.48, turnTime = 0.40, watchTime = 3.6, fovDeg = 120, fakeChance = 0.40 },
		last = { teachTime = 2.6, warnTime = 0.44, turnTime = 0.30, watchTime = 4.0, fovDeg = 125, fakeChance = 0.45 },
	},

	-- 6학년: 판서 2.6 → 1.8초. 한 걸음 반이면 다음 예고가 뜬다.
	-- 12반이 이 게임의 끝이므로 여기만 예고를 0.40 아래로 내린다.
	[6] = {
		first = { teachTime = 2.6, warnTime = 0.44, turnTime = 0.30, watchTime = 4.0, fovDeg = 125, fakeChance = 0.45 },
		last = { teachTime = 1.8, warnTime = 0.38, turnTime = 0.26, watchTime = 4.4, fovDeg = 130, fakeChance = 0.50 },
	},
}

--[[
	종이 울릴 때까지의 시간(초). 학년별 first → last 로 이 표도 같이 좁아진다.

	★ 시간을 넘겨도 실패가 아니다. 넘기면 퍼펙트 별 하나를 못 받을 뿐이고,
	  자리에 앉으면 반은 그대로 통과한다. 제한 시간을 실패 조건으로 만들면
	  "선생님을 완벽하게 읽었는데 3초 늦어서 죽었다"가 생기는데,
	  그건 이 게임이 없애기로 한 억울함 그 자체다.

	★ 이 표가 있어야 이동 3단계가 비로소 의미를 갖는다. 시계가 없으면
	  살금살금이 언제나 정답이고, 걷기·달리기와 균형감각·실내화는 장식이 된다.
	  느린 쪽이 안전하다면 안전을 포기할 이유를 시계가 만들어줘야 한다.

	수치의 근거 — 한 사이클에서 실제로 움직일 수 있는 시간의 비율이 학년마다 다르다.
	1학년 1반은 판서 5.0 / 사이클 8.3 이라 60%를 걸을 수 있지만,
	6학년 12반은 판서 1.8 / 사이클 7.1 이라 25%뿐이다. 같은 45 스터드를 가도
	걸리는 시간이 두 배 넘게 차이 나므로, 종도 그만큼 좁혀야 같은 압박이 된다.
	1학년 1반 50초는 자리가 문 앞이라 사실상 무제한이다 — 배우는 반에서는
	시계를 보지 말라는 뜻이고, 시계는 12반에 가까워질수록 서서히 존재감이 생긴다.
]]
local BELL: { [number]: { first: number, last: number } } = {
	[1] = { first = 50, last = 34 },
	[2] = { first = 34, last = 32 },
	[3] = { first = 32, last = 30 },
	[4] = { first = 30, last = 28 },
	[5] = { first = 28, last = 26 },
	[6] = { first = 26, last = 20 },
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- 반 1 → 12 를 0 → 1 로. 두 표가 같은 자로 재야 한 학년 안에서 곡선이 어긋나지 않는다.
local function progress(class: number): number
	return (math.clamp(class, 1, CLASSES_PER_GRADE) - 1) / (CLASSES_PER_GRADE - 1)
end

local DifficultyTable = {}

DifficultyTable.CLASSES_PER_GRADE = CLASSES_PER_GRADE

--[[
	다음 학년이 있는가. 12반을 깬 뒤 어디로 갈지를 진행 쪽에서 여기에 물어본다.

	★ 마지막 학년 번호(6)를 ProgressService 에 상수로 적어두지 않는 이유다.
	  적어두면 학년을 하나 늘릴 때 고칠 곳이 표와 진행 두 군데가 되고,
	  둘 중 하나를 잊으면 "7학년 난이도 정의가 없다"로 서버가 멈춘다.
]]
function DifficultyTable.has(grade: number): boolean
	return BANDS[grade] ~= nil
end

function DifficultyTable.get(grade: number, class: number): Types.TeacherConfig
	local band = BANDS[grade]
	assert(band, `{grade}학년 난이도 정의가 없다. DifficultyTable.BANDS에 추가해야 한다.`)

	local t = progress(class)
	local first, last = band.first, band.last

	return {
		teachTime = lerp(first.teachTime, last.teachTime, t),
		warnTime = lerp(first.warnTime, last.warnTime, t),
		turnTime = lerp(first.turnTime, last.turnTime, t),
		watchTime = lerp(first.watchTime, last.watchTime, t),
		fovDeg = lerp(first.fovDeg, last.fovDeg, t),
		fakeChance = lerp(first.fakeChance, last.fakeChance, t),
	}
end

--[[
	이 반의 종까지 몇 초인가.

	★ TeacherConfig 에 넣지 않고 따로 두는 이유는 이게 선생님의 수치가 아니기 때문이다.
	  선생님은 종이 울리든 말든 똑같이 판서하고 똑같이 돌아본다. 종은 반에 걸린
	  시계지 선생님의 성격이 아니고, 섞어두면 "눈치" 업그레이드처럼 선생님 수치를
	  건드리는 것들이 실수로 종까지 밀어버린다.
]]
function DifficultyTable.bellTime(grade: number, class: number): number
	local band = BELL[grade]
	assert(band, `{grade}학년 종 시간 정의가 없다. DifficultyTable.BELL 에 추가해야 한다.`)

	return lerp(band.first, band.last, progress(class))
end

return DifficultyTable
