--!strict
--[[
	학년별 교실 외양.

	★ 이 표가 있는 이유는 난이도가 눈에 안 보였기 때문이다.
	  DifficultyTable 이 학년마다 수치를 하나씩 조이고 있었지만, 교실은 여섯 학년이
	  전부 같은 그림이었다. 좌상단 HUD 에 "3학년 7반"이라고 적혀 있어도
	  화면 안의 교실이 1학년과 똑같으면 플레이어에게 학년은 숫자일 뿐이다.
	  올라왔다는 것은 읽는 게 아니라 보이는 것이어야 한다.

	★ 바꾸는 것은 색과 글자와 체구뿐이다. 교실의 치수 — 46 x 38, 책상 3분단 x 6열,
	  선생님 z = -15, 엄폐물 발자국 — 는 한 칸도 안 건드린다. 그 값들 위에서
	  난이도가 검증됐고, 학년마다 방 모양이 달라지면 그 검증이 통째로 무효가 된다.
	  같은 방에서 같은 문제를 푸는데 방의 얼굴만 달라진다.

	★ 체구(bodyScale)만은 예외적으로 가구를 따라 움직인다. 1학년 아이와 6학년 아이가
	  같은 크기면 학년이 안 보이는데, 아이만 키우면 엉덩이가 의자에서 뜬다.
	  그래서 교실 템플릿이 이 값으로 책상·의자 "높이만" 다시 잡는다.
	  X/Z 발자국은 그대로다 — 감지는 전부 수평 판정이라 높이는 영향이 없다.
]]

local GradeTheme = {}

export type Theme = {
	label: string, -- "1학년". 문패와 안내판이 반 번호를 붙여 쓴다

	-- 색. 굽도리·문틀·게시판 테두리처럼 교실 곳곳에 흩어져 있는 액센트다.
	-- 학년이 오를수록 채도가 내려가고 어두워진다 — 저학년 교실이 알록달록한 것은
	-- 취향이 아니라 실제로 그렇기 때문이고, 그 차이가 곧 학년 표시다.
	accent: Color3,
	accentDark: Color3,
	deskTop: Color3,
	chair: Color3,
	curtain: Color3,
	book: Color3, -- 책상 위 교과서

	-- 글자. 칠판·급훈·시간표·게시판은 전부 학년마다 다른 말을 한다
	board: string,
	motto: string,
	timetable: string,
	notice: string,

	--[[
		이번 학년에 새로 조여지는 것 한 줄. 칠판 옆 안내판에 걸린다.

		★ DifficultyTable 의 주석에 적혀 있던 말을 화면으로 꺼낸 것이다.
		  거기 적힌 "학년마다 새로 조이는 항목을 하나씩만 둔다"는 원칙은
		  플레이어가 그 항목이 무엇인지 알 때만 원칙으로 작동한다.
		  모르면 그냥 "어쩐지 어려워졌다"이고, 그건 실력으로 넘을 수 없다.
	]]
	hint: string,

	-- 학생 체구. 교실 가구 높이도 이 값을 따라간다
	bodyScale: number,
}

local THEMES: { [number]: Theme } = {
	[1] = {
		label = "1학년",
		accent = Color3.fromRGB(240, 196, 92), -- 노랑
		accentDark = Color3.fromRGB(206, 158, 66),
		deskTop = Color3.fromRGB(226, 192, 142),
		chair = Color3.fromRGB(212, 174, 122),
		curtain = Color3.fromRGB(252, 240, 206),
		book = Color3.fromRGB(246, 214, 120),
		board = "받아쓰기\n\n1. 학교종이 땡땡땡\n2. 우리 모두 다 같이",
		motto = "바르고 슬기롭게",
		timetable = "1교시 국어\n2교시 수학\n3교시 통합\n4교시 체육",
		notice = "우리들의 그림",
		hint = "돌아보기 전에 어깨가 먼저 움직인다",
		bodyScale = 0.78,
	},

	[2] = {
		label = "2학년",
		accent = Color3.fromRGB(158, 206, 118), -- 연두
		accentDark = Color3.fromRGB(122, 168, 92),
		deskTop = Color3.fromRGB(218, 184, 134),
		chair = Color3.fromRGB(202, 164, 114),
		curtain = Color3.fromRGB(236, 246, 224),
		book = Color3.fromRGB(150, 202, 128),
		board = "구구단\n\n2단  2 4 6 8 10\n3단  3 6 9 12 15",
		motto = "스스로 하는 어린이",
		timetable = "1교시 국어\n2교시 수학\n3교시 바슬즐\n4교시 음악",
		notice = "칭찬 나무",
		hint = "돌아보는 척만 할 때가 있다",
		bodyScale = 0.82,
	},

	[3] = {
		label = "3학년",
		accent = Color3.fromRGB(126, 186, 226), -- 하늘
		accentDark = Color3.fromRGB(94, 146, 190),
		deskTop = Color3.fromRGB(206, 172, 124),
		chair = Color3.fromRGB(190, 152, 106),
		curtain = Color3.fromRGB(224, 238, 248),
		book = Color3.fromRGB(112, 172, 216),
		board = "나눗셈\n\n24 ÷ 3 = ?\n36 ÷ 4 = ?",
		motto = "서로 돕고 함께 자라기",
		timetable = "1교시 국어\n2교시 수학\n3교시 사회\n4교시 체육",
		notice = "우리 반 규칙",
		hint = "시야가 넓어졌다. 분단 끝자리도 안 보이지 않는다",
		bodyScale = 0.86,
	},

	[4] = {
		label = "4학년",
		accent = Color3.fromRGB(232, 154, 88), -- 주황
		accentDark = Color3.fromRGB(188, 118, 62),
		deskTop = Color3.fromRGB(192, 156, 110),
		chair = Color3.fromRGB(176, 138, 94),
		curtain = Color3.fromRGB(246, 230, 212),
		book = Color3.fromRGB(224, 140, 84),
		board = "분수\n\n1/2 + 1/3 = ?\n대분수를 가분수로",
		motto = "생각하고 실천하자",
		timetable = "1교시 국어\n2교시 수학\n3교시 과학\n4교시 영어",
		notice = "독서 기록장",
		hint = "한 번 돌아보면 오래 본다. 참아야 한다",
		bodyScale = 0.89,
	},

	[5] = {
		label = "5학년",
		accent = Color3.fromRGB(164, 142, 206), -- 보라
		accentDark = Color3.fromRGB(124, 104, 166),
		deskTop = Color3.fromRGB(174, 140, 100),
		chair = Color3.fromRGB(158, 126, 88),
		curtain = Color3.fromRGB(232, 226, 244),
		book = Color3.fromRGB(150, 128, 194),
		board = "소수의 곱셈\n\n0.6 × 0.4 = ?\n비율을 백분율로",
		motto = "꿈을 향해 한 걸음씩",
		timetable = "1교시 국어\n2교시 수학\n3교시 사회\n4교시 실과",
		notice = "모둠 발표 자료",
		hint = "몸 도는 속도가 빨라졌다",
		bodyScale = 0.92,
	},

	[6] = {
		label = "6학년",
		accent = Color3.fromRGB(92, 116, 168), -- 남색
		accentDark = Color3.fromRGB(64, 84, 128),
		deskTop = Color3.fromRGB(156, 124, 90),
		chair = Color3.fromRGB(142, 112, 80),
		curtain = Color3.fromRGB(220, 226, 238),
		book = Color3.fromRGB(84, 108, 158),
		board = "원의 넓이\n\n반지름 × 반지름 × 3.14\n지름 10cm 인 원은?",
		motto = "유종의 미",
		timetable = "1교시 국어\n2교시 수학\n3교시 과학\n4교시 영어",
		notice = "졸업 앨범 사진",
		hint = "판서가 짧다. 쉴 틈이 없다",
		bodyScale = 0.95,
	},
}

--[[
	@param grade 학년. 표에 없는 값이면 가장 가까운 학년으로 물러난다.

	★ assert 하지 않는다. DifficultyTable 은 학년 정의가 없으면 서버를 세우는 것이 맞다 —
	  없는 난이도로 판을 열면 그 판은 판정이 없다. 하지만 이건 색과 글자다.
	  칠판 문구가 없다고 교실을 못 열 이유는 없고, 표를 하나 빠뜨렸을 때
	  게임이 통째로 멈추는 쪽이 훨씬 나쁘다.
]]
function GradeTheme.get(grade: number): Theme
	return THEMES[math.clamp(math.floor(grade), 1, 6)] :: Theme
end

return GradeTheme
