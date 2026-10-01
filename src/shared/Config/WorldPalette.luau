--!strict
--[[
	세상 색의 단일 소스. 개선계획 §3.1 #1(팔레트 표).

	역할 이름으로 색을 고른다. 부지·광장·나무는 RGB 를 직접 적지 않고 여기서 가져온다.
	회색 톤 대신 따뜻한 톤을 쓴다. 빨강 계열은 지붕에도 쓰지 않는다(기획서 §12.2 부정 피드백 오해 방지).
	게임 신호 색(pad·sticker·star)은 플레이 표시라 톤을 바꾸지 않고 자리만 여기로 옮겼다.
]]

local rgb = Color3.fromRGB

local WorldPalette = {
	-- ── 팔레트 표(§3.1) ──
	wall = rgb(245, 235, 215),
	trim = rgb(250, 250, 245),
	floorIndoor = rgb(226, 206, 172),
	lawn = rgb(120, 190, 90),
	path = rgb(236, 214, 170),
	hedge = rgb(80, 160, 80),
	trunk = rgb(130, 90, 60),
	blossom = rgb(255, 182, 206),
	soil = rgb(150, 108, 72), -- 화단 흙판(PropLibrary.flowerbed)
	lampIron = rgb(46, 44, 48), -- 벽등 쇠틀(PropLibrary.wallLamp 폴백)
	lampGlow = rgb(255, 214, 150), -- 벽등 불빛(전구 Neon·PointLight)
	-- 잎 3종. Tree 가 시드로 하나를 고른다
	leaf = {
		rgb(110, 190, 80),
		rgb(80, 160, 70),
		rgb(140, 200, 90),
	},
	-- 지붕은 시설마다 하나씩. 교실부터
	roof = {
		classroom = rgb(86, 156, 230),
		clockTower = rgb(70, 150, 140),
	},

	-- ── 부지 껍데기(PlotShell) ──
	stone = rgb(214, 196, 168), -- 교문 기둥·계단·착지대
	gateBeam = rgb(74, 118, 184),
	gateLeaf = rgb(96, 136, 196),
	gateSign = rgb(46, 96, 74),
	lightText = rgb(250, 250, 245),
	darkText = rgb(72, 56, 44),
	wood = rgb(120, 86, 56), -- 팻말 기둥
	signBoard = rgb(240, 228, 200),
	desk = rgb(58, 110, 190),
	deskDome = rgb(200, 230, 250),
	cork = rgb(198, 154, 104),
	ghost = rgb(200, 212, 228),
	ghostText = rgb(80, 92, 116),
	spawn = rgb(242, 224, 186),
	pole = rgb(236, 232, 222),
	flag = rgb(70, 110, 180),

	-- ── 게임 신호(톤 유지) ──
	pad = rgb(52, 211, 153),
	sticker = rgb(250, 204, 21),
	star = rgb(135, 206, 250),

	-- ── 광장(Plaza) ──
	plazaLawn = rgb(108, 178, 82), -- 부지 잔디와 살짝 달라야 부지 경계가 보인다
	plazaPavement = rgb(228, 212, 184),
	podium = rgb(240, 228, 205),
	podiumStep = rgb(226, 210, 182),
	boardDark = rgb(40, 56, 90), -- 순위판 바탕(흰 글자)
	notice = rgb(150, 108, 66),
	noticeCell = rgb(236, 226, 200),
	boardPost = rgb(110, 90, 70),
	benchWood = rgb(170, 120, 72),
	benchLeg = rgb(84, 72, 64),
	clockFace = rgb(250, 250, 245),
}

return WorldPalette
