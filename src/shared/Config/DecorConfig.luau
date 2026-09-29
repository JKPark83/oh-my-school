--!strict
--[[
	꾸미기 아이템 27개. 개선계획 §3.5 #3·#5, §7 질문 7·9.
	  일반 12(상점, 처음부터) · 선물 6(상점에 없음. 선물판 순번으로만 받는다) · 친구 9(사면 그 학생이 함께 온다)
	가격(price)은 1회차 기준이고 docs/sim/sim-parts.py 의 DECOR_PRICES 와 같아야 한다(check-config.py 가 대조).
	졸업 N회면 priceOf 가 × PRICE_SCALE^N 한다. 가격 계산은 서버가 한다(클라는 무엇을 살지만 보낸다).

	모양(parts)은 클라가 DecorBuilder 로 그리는 로컬 파트다. 서버 파트는 0 이다.
	  offset 은 아이템 발자국(w×d 칸) 가운데 · 바닥 윗면 y0 기준 파트 중심. rot 은 이 가운데를 축으로 돈다.
	  cylinder 는 세워서 그린다. size 는 (지름, 높이, 지름).
	  아이템당 6개 이하(질문 9: 배치 40 × 6 = 240 클라 파트 상한). 빨강 계열 색은 쓰지 않는다(기획서 §12.2).
]]

local FacilityConfig = require(script.Parent.FacilityConfig)
local PlotLayout = require(script.Parent.Parent.PlotLayout)
local StudentConfig = require(script.Parent.StudentConfig)
local Types = require(script.Parent.Parent.Types)

local DecorConfig = {}

export type Kind = "general" | "friend" | "gift"

export type Part = {
	shape: "block" | "ball" | "cylinder" | "wedge",
	size: Vector3,
	offset: Vector3, -- 발자국 가운데·바닥 y0 기준
	color: Color3,
	material: Enum.Material?,
	transparency: number?,
}

export type Item = {
	id: string, -- 영문 ≤10자. DecorCodec 은 id 대신 LIST 순번을 쓴다
	name: string, -- 물건 이름 ≤6자
	kind: Kind,
	price: number, -- 1회차 기준. gift 는 0(상점에 없음)
	unlock: number, -- 이 졸업 횟수부터 상점 진열. general·gift 는 0
	student: string?, -- friend 만. 사면 이 학생이 온다
	w: number, -- x 칸 수(rot 0·2). rot 1·3 이면 d 와 바뀐다
	d: number, -- z 칸 수
	parts: { Part },
}

DecorConfig.CELL = PlotLayout.CELL
DecorConfig.GRID = PlotLayout.GRID
DecorConfig.MAX_PLACED = 40 -- 모든 층 합(§3.6 #10)
DecorConfig.MAX_OWNED = 10 -- 아이템 하나당 보관함 + 배치 합 상한
DecorConfig.TUTORIAL_ITEM = "planter" -- 새 프로필 보관함에 넣어 두는 아이템(튜토리얼 ④)
DecorConfig.TUTORIAL_FREE = 2

local MAX_PARTS = 6
local MAX_ID_LEN = 10

-- ── 색(빨강 계열 없음) ──────────────────────────────────────────
local rgb = Color3.fromRGB
local C = {
	pot = rgb(150, 100, 60),
	soil = rgb(120, 86, 56),
	leaf = rgb(110, 190, 80),
	leafDark = rgb(80, 160, 70),
	leafLight = rgb(140, 200, 90),
	trunk = rgb(130, 90, 60),
	wood = rgb(170, 120, 72),
	woodDark = rgb(110, 80, 56),
	leg = rgb(84, 72, 64),
	metal = rgb(120, 125, 135),
	steel = rgb(74, 118, 184),
	glow = rgb(255, 240, 180),
	water = rgb(110, 180, 230),
	stone = rgb(214, 196, 168),
	white = rgb(245, 245, 240),
	cream = rgb(250, 240, 220),
	sign = rgb(240, 228, 200),
	yellow = rgb(250, 204, 21),
	gold = rgb(240, 190, 60),
	orange = rgb(245, 158, 11),
	pink = rgb(255, 182, 206),
	purple = rgb(170, 140, 230),
	sky = rgb(135, 206, 250),
	blue = rgb(70, 120, 200),
	navy = rgb(40, 56, 90),
	green = rgb(90, 170, 110),
	bear = rgb(198, 154, 104),
	piano = rgb(44, 44, 52),
	dark = rgb(72, 56, 44),
	tiger = rgb(240, 236, 228),
}
local M = Enum.Material

local function V(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function block(size: Vector3, offset: Vector3, color: Color3, material: Enum.Material?, alpha: number?): Part
	return { shape = "block", size = size, offset = offset, color = color, material = material, transparency = alpha }
end

local function ball(d: number, offset: Vector3, color: Color3, material: Enum.Material?, alpha: number?): Part
	return {
		shape = "ball",
		size = V(d, d, d),
		offset = offset,
		color = color,
		material = material,
		transparency = alpha,
	}
end

-- 세운 원기둥. 지름 d, 높이 h
local function cyl(d: number, h: number, offset: Vector3, color: Color3, material: Enum.Material?, alpha: number?): Part
	return {
		shape = "cylinder",
		size = V(d, h, d),
		offset = offset,
		color = color,
		material = material,
		transparency = alpha,
	}
end

local function wedge(size: Vector3, offset: Vector3, color: Color3, material: Enum.Material?): Part
	return { shape = "wedge", size = size, offset = offset, color = color, material = material }
end

local LIST: { Item } = {
	-- ── 일반 12 ──
	{
		id = "planter",
		name = "화분",
		kind = "general",
		price = 2500,
		unlock = 0,
		w = 1,
		d = 1,
		parts = {
			cyl(2.4, 2, V(0, 1, 0), C.pot, M.Slate),
			ball(2.8, V(0, 2.9, 0), C.leaf, M.Grass),
		},
	},
	{
		id = "bench",
		name = "벤치",
		kind = "general",
		price = 23000,
		unlock = 0,
		w = 2,
		d = 1,
		parts = {
			block(V(7, 0.4, 2), V(0, 1.6, 0), C.wood, M.Wood),
			block(V(7, 1.6, 0.3), V(0, 2.6, -0.9), C.wood, M.Wood),
			block(V(0.4, 1.4, 1.8), V(-3, 0.7, 0), C.leg, M.Metal),
			block(V(0.4, 1.4, 1.8), V(3, 0.7, 0), C.leg, M.Metal),
		},
	},
	{
		id = "lamp",
		name = "가로등",
		kind = "general",
		price = 23000,
		unlock = 0,
		w = 1,
		d = 1,
		parts = {
			cyl(1.2, 0.4, V(0, 0.2, 0), C.leg, M.Metal),
			cyl(0.4, 7, V(0, 3.9, 0), C.leg, M.Metal),
			ball(1.6, V(0, 7.8, 0), C.glow, M.Neon),
		},
	},
	{
		id = "mailbox",
		name = "우체통",
		kind = "general",
		price = 2500,
		unlock = 0,
		w = 1,
		d = 1,
		parts = {
			block(V(0.5, 2.5, 0.5), V(0, 1.25, 0), C.metal, M.Metal),
			block(V(1.6, 1.8, 1.4), V(0, 3.4, 0), C.blue, M.SmoothPlastic),
			block(V(1, 0.15, 0.1), V(0, 3.8, 0.72), C.navy, M.SmoothPlastic),
		},
	},
	{
		id = "fountain",
		name = "분수",
		kind = "general",
		price = 100000,
		unlock = 0,
		w = 2,
		d = 2,
		parts = {
			cyl(8, 1.2, V(0, 0.6, 0), C.stone, M.Concrete),
			cyl(7.2, 0.2, V(0, 1.1, 0), C.water, M.Glass, 0.3),
			cyl(1.2, 3, V(0, 2.5, 0), C.stone, M.Concrete),
			cyl(3, 0.5, V(0, 4.2, 0), C.stone, M.Concrete),
			ball(1, V(0, 4.8, 0), C.water, M.Glass, 0.2),
		},
	},
	{
		id = "tree",
		name = "나무",
		kind = "general",
		price = 23000,
		unlock = 0,
		w = 1,
		d = 1,
		parts = {
			cyl(0.9, 4, V(0, 2, 0), C.trunk, M.Wood),
			ball(4, V(0, 5, 0), C.leafDark, M.Grass),
			ball(2.6, V(0.8, 6.6, 0.3), C.leafLight, M.Grass),
		},
	},
	{
		id = "flowerbed",
		name = "꽃밭",
		kind = "general",
		price = 2500,
		unlock = 0,
		w = 2,
		d = 1,
		parts = {
			block(V(8.6, 0.5, 3.6), V(0, 0.25, 0), C.soil, M.Ground),
			block(V(8, 0.4, 3), V(0, 0.6, 0), C.leaf, M.Grass),
			ball(1.2, V(-3, 1, 0), C.pink, M.SmoothPlastic),
			ball(1.2, V(-1, 1, 0.6), C.yellow, M.SmoothPlastic),
			ball(1.2, V(1, 1, -0.6), C.purple, M.SmoothPlastic),
			ball(1.2, V(3, 1, 0), C.pink, M.SmoothPlastic),
		},
	},
	{
		id = "signpost",
		name = "표지판",
		kind = "general",
		price = 2500,
		unlock = 0,
		w = 1,
		d = 1,
		parts = {
			block(V(0.4, 4, 0.4), V(0, 2, 0), C.wood, M.Wood),
			block(V(3, 1.6, 0.3), V(0, 3.6, 0), C.sign, M.Wood),
		},
	},
	{
		id = "bikerack",
		name = "자전거대",
		kind = "general",
		price = 23000,
		unlock = 0,
		w = 2,
		d = 1,
		parts = {
			block(V(8, 0.3, 1.2), V(0, 0.15, 0), C.metal, M.Metal),
			block(V(0.3, 2, 2), V(-3, 1.3, 0), C.sky, M.Metal),
			block(V(0.3, 2, 2), V(0, 1.3, 0), C.sky, M.Metal),
			block(V(0.3, 2, 2), V(3, 1.3, 0), C.sky, M.Metal),
			block(V(8, 0.3, 0.3), V(0, 2.3, 0), C.metal, M.Metal),
		},
	},
	{
		id = "swing",
		name = "그네",
		kind = "general",
		price = 100000,
		unlock = 0,
		w = 2,
		d = 1,
		parts = {
			block(V(0.4, 6, 0.4), V(-4, 3, 0), C.steel, M.Metal),
			block(V(0.4, 6, 0.4), V(4, 3, 0), C.steel, M.Metal),
			block(V(8.4, 0.4, 0.4), V(0, 6.2, 0), C.steel, M.Metal),
			block(V(0.12, 4, 0.12), V(-0.8, 4, 0), C.metal, M.Metal),
			block(V(0.12, 4, 0.12), V(0.8, 4, 0), C.metal, M.Metal),
			block(V(1.8, 0.2, 0.9), V(0, 2, 0), C.yellow, M.SmoothPlastic),
		},
	},
	{
		id = "slide",
		name = "미끄럼틀",
		kind = "general",
		price = 100000,
		unlock = 0,
		w = 2,
		d = 1,
		parts = {
			block(V(3, 4, 3), V(-3, 2, 0), C.yellow, M.SmoothPlastic),
			block(V(0.3, 4.4, 2), V(-4.7, 2.2, 0), C.metal, M.Metal),
			wedge(V(2.4, 4, 4.6), V(1, 2, 0), C.purple, M.SmoothPlastic),
		},
	},
	{
		id = "pond",
		name = "연못",
		kind = "general",
		price = 100000,
		unlock = 0,
		w = 2,
		d = 2,
		parts = {
			cyl(9, 0.4, V(0, 0.2, 0), C.stone, M.Slate),
			cyl(8, 0.1, V(0, 0.45, 0), C.water, M.Glass, 0.2),
			cyl(1.4, 0.1, V(1.5, 0.52, 1), C.green, M.SmoothPlastic),
			cyl(1.4, 0.1, V(-2, 0.52, -1.5), C.green, M.SmoothPlastic),
			ball(0.6, V(1.5, 0.7, 1), C.pink, M.SmoothPlastic),
		},
	},

	-- ── 선물 6(질문 7. GIFT_ORDER 순번으로만 받는다) ──
	{
		id = "balloons",
		name = "풍선",
		kind = "gift",
		price = 0,
		unlock = 0,
		w = 1,
		d = 1,
		parts = {
			block(V(0.6, 0.6, 0.6), V(0, 0.3, 0), C.metal, M.Metal),
			block(V(0.08, 5, 0.08), V(0, 3, 0), C.white, M.SmoothPlastic),
			ball(1.6, V(-0.6, 6, 0), C.yellow, M.SmoothPlastic),
			ball(1.6, V(0.6, 6.4, 0.3), C.sky, M.SmoothPlastic),
			ball(1.6, V(0, 7.2, -0.4), C.purple, M.SmoothPlastic),
		},
	},
	{
		id = "trophy",
		name = "트로피",
		kind = "gift",
		price = 0,
		unlock = 0,
		w = 1,
		d = 1,
		parts = {
			block(V(1.6, 0.8, 1.6), V(0, 0.4, 0), C.woodDark, M.Wood),
			cyl(0.4, 1.2, V(0, 1.4, 0), C.gold, M.Metal),
			cyl(1.6, 1.4, V(0, 2.7, 0), C.gold, M.Metal),
			ball(0.5, V(-1, 2.8, 0), C.gold, M.Metal),
			ball(0.5, V(1, 2.8, 0), C.gold, M.Metal),
		},
	},
	{
		id = "teddy",
		name = "곰인형",
		kind = "gift",
		price = 0,
		unlock = 0,
		w = 1,
		d = 1,
		parts = {
			ball(2.2, V(0, 1.1, 0), C.bear, M.Fabric),
			ball(1.6, V(0, 2.8, 0), C.bear, M.Fabric),
			ball(0.6, V(-0.6, 3.5, 0), C.bear, M.Fabric),
			ball(0.6, V(0.6, 3.5, 0), C.bear, M.Fabric),
			ball(0.6, V(0, 2.7, 0.7), C.cream, M.Fabric),
		},
	},
	{
		id = "rainbow",
		name = "무지개깃발",
		kind = "gift",
		price = 0,
		unlock = 0,
		w = 1,
		d = 1,
		parts = {
			cyl(0.3, 6, V(0, 3, 0), C.white, M.Metal),
			block(V(2.4, 0.3, 0.1), V(1.35, 5.6, 0), C.orange, M.Fabric),
			block(V(2.4, 0.3, 0.1), V(1.35, 5.3, 0), C.yellow, M.Fabric),
			block(V(2.4, 0.3, 0.1), V(1.35, 5.0, 0), C.leaf, M.Fabric),
			block(V(2.4, 0.3, 0.1), V(1.35, 4.7, 0), C.sky, M.Fabric),
			block(V(2.4, 0.3, 0.1), V(1.35, 4.4, 0), C.purple, M.Fabric),
		},
	},
	{
		id = "starlamp",
		name = "별조명",
		kind = "gift",
		price = 0,
		unlock = 0,
		w = 1,
		d = 1,
		parts = {
			cyl(1.2, 0.4, V(0, 0.2, 0), C.leg, M.Metal),
			cyl(0.3, 3, V(0, 1.9, 0), C.white, M.Metal),
			ball(1.6, V(0, 4, 0), C.yellow, M.Neon),
			ball(2.4, V(0, 4, 0), C.glow, M.Neon, 0.7),
		},
	},
	{
		id = "cake",
		name = "케이크",
		kind = "gift",
		price = 0,
		unlock = 0,
		w = 1,
		d = 1,
		parts = {
			cyl(2.6, 1, V(0, 0.5, 0), C.cream, M.SmoothPlastic),
			cyl(2.7, 0.2, V(0, 1.1, 0), C.pink, M.SmoothPlastic),
			cyl(1.8, 0.8, V(0, 1.6, 0), C.cream, M.SmoothPlastic),
			cyl(0.2, 0.8, V(0, 2.4, 0), C.sky, M.SmoothPlastic),
			ball(0.3, V(0, 2.95, 0), C.yellow, M.Neon),
		},
	},

	-- ── 친구 9(§3.5 친구 아이템 표. 학생 이름은 쓰지 않는다) ──
	{
		id = "bookcart",
		name = "책수레",
		kind = "friend",
		price = 79000,
		unlock = 0,
		student = "s14",
		w = 1,
		d = 1,
		parts = {
			block(V(3.2, 0.4, 2), V(0, 0.2, 0), C.metal, M.Metal),
			block(V(3, 1.6, 1.8), V(0, 1.2, 0), C.wood, M.Wood),
			block(V(0.5, 1, 1.4), V(-0.9, 2.5, 0), C.blue, M.SmoothPlastic),
			block(V(0.5, 1, 1.4), V(-0.3, 2.5, 0), C.yellow, M.SmoothPlastic),
			block(V(0.5, 1, 1.4), V(0.3, 2.5, 0), C.green, M.SmoothPlastic),
			block(V(0.5, 1, 1.4), V(0.9, 2.5, 0), C.purple, M.SmoothPlastic),
		},
	},
	{
		id = "telescope",
		name = "망원경",
		kind = "friend",
		price = 79000,
		unlock = 0,
		student = "s17",
		w = 1,
		d = 1,
		parts = {
			cyl(1.6, 0.2, V(0, 0.1, 0), C.leg, M.Metal),
			cyl(0.3, 3, V(0, 1.7, 0), C.leg, M.Metal),
			block(V(0.9, 0.9, 3.2), V(0, 3.4, 0), C.navy, M.SmoothPlastic),
			block(V(0.5, 0.5, 0.6), V(0, 3.4, -1.9), C.metal, M.Metal),
			ball(0.8, V(0, 3.4, 1.6), C.sky, M.Glass),
		},
	},
	{
		id = "rocket",
		name = "로켓모형",
		kind = "friend",
		price = 79000,
		unlock = 0,
		student = "s22",
		w = 1,
		d = 2,
		parts = {
			block(V(4, 0.3, 8), V(0, 0.15, 0), C.metal, M.Metal),
			cyl(2, 6, V(0, 3.3, 0), C.white, M.SmoothPlastic),
			ball(2, V(0, 6.3, 0), C.blue, M.SmoothPlastic),
			block(V(0.2, 2, 1.6), V(-1.1, 1.3, 0), C.blue, M.SmoothPlastic),
			block(V(0.2, 2, 1.6), V(1.1, 1.3, 0), C.blue, M.SmoothPlastic),
			ball(0.8, V(0, 4.4, 0.8), C.sky, M.Glass),
		},
	},
	{
		id = "ballbin",
		name = "공바구니",
		kind = "friend",
		price = 1100000,
		unlock = 2,
		student = "s15",
		w = 1,
		d = 1,
		parts = {
			cyl(2.6, 1.6, V(0, 0.8, 0), C.sky, M.SmoothPlastic, 0.3),
			ball(1, V(-0.5, 1.8, 0), C.orange, M.SmoothPlastic),
			ball(1, V(0.5, 1.8, 0.3), C.yellow, M.SmoothPlastic),
			ball(1, V(0, 2, -0.5), C.blue, M.SmoothPlastic),
			ball(1, V(0.2, 2.2, 0.4), C.white, M.SmoothPlastic),
		},
	},
	{
		id = "easel",
		name = "이젤",
		kind = "friend",
		price = 1100000,
		unlock = 3,
		student = "s16",
		w = 1,
		d = 1,
		parts = {
			block(V(0.2, 4.5, 0.2), V(-0.8, 2.25, 0.2), C.wood, M.Wood),
			block(V(0.2, 4.5, 0.2), V(0.8, 2.25, 0.2), C.wood, M.Wood),
			block(V(0.2, 4.5, 0.2), V(0, 2.25, -0.6), C.wood, M.Wood),
			block(V(2.2, 1.8, 0.1), V(0, 3.2, 0.35), C.white, M.Fabric),
			block(V(1, 0.6, 0.12), V(0, 3.3, 0.4), C.sky, M.SmoothPlastic),
		},
	},
	{
		id = "globe",
		name = "지구본",
		kind = "friend",
		price = 1000000,
		unlock = 4,
		student = "s19",
		w = 1,
		d = 1,
		parts = {
			cyl(1.2, 0.3, V(0, 0.15, 0), C.woodDark, M.Wood),
			cyl(0.3, 1.2, V(0, 0.9, 0), C.gold, M.Metal),
			ball(2, V(0, 2.5, 0), C.blue, M.SmoothPlastic),
			ball(1.2, V(0.4, 2.8, 0.4), C.leaf, M.SmoothPlastic),
		},
	},
	{
		id = "piano",
		name = "피아노",
		kind = "friend",
		price = 780000,
		unlock = 6,
		student = "s20",
		w = 2,
		d = 1,
		parts = {
			block(V(6, 4.2, 1.6), V(0, 2.1, -0.8), C.piano, M.SmoothPlastic),
			block(V(6, 0.4, 1.2), V(0, 2.4, 0.6), C.white, M.SmoothPlastic),
			block(V(5.6, 0.1, 0.4), V(0, 2.65, 0.4), C.piano, M.SmoothPlastic),
			block(V(3, 0.4, 1.2), V(0, 1.4, 2), C.wood, M.Wood),
			block(V(2.6, 1.2, 0.8), V(0, 0.6, 2), C.piano, M.SmoothPlastic),
		},
	},
	{
		id = "labtable",
		name = "실험탁자",
		kind = "friend",
		price = 660000,
		unlock = 7,
		student = "s21",
		w = 2,
		d = 1,
		parts = {
			block(V(7.6, 2.8, 3), V(0, 1.4, 0), C.metal, M.SmoothPlastic),
			block(V(8, 0.4, 3.4), V(0, 3, 0), C.white, M.SmoothPlastic),
			cyl(0.8, 1.2, V(-2, 3.8, 0), C.green, M.Glass, 0.3),
			ball(1, V(0, 3.7, 0.3), C.purple, M.Glass, 0.3),
			cyl(0.5, 1.6, V(2, 4, 0), C.sky, M.Glass, 0.3),
		},
	},
	{
		id = "tiger",
		name = "호랑이석상",
		kind = "friend",
		price = 550000,
		unlock = 8,
		student = "s24",
		w = 2,
		d = 2,
		parts = {
			block(V(6, 1, 6), V(0, 0.5, 0), C.stone, M.Concrete),
			block(V(5, 2.4, 2.2), V(-0.5, 2.2, 0), C.tiger, M.Marble),
			block(V(2.2, 2.2, 2.2), V(2.6, 3.4, 0), C.tiger, M.Marble),
			block(V(0.3, 2.5, 2.3), V(-1, 2.2, 0), C.dark, M.Marble),
			ball(0.7, V(2.6, 4.7, -0.6), C.tiger, M.Marble),
			ball(0.7, V(2.6, 4.7, 0.6), C.tiger, M.Marble),
		},
	},
}

-- 선물판 순번 → 선물 아이템(질문 7, 잠정). 없는 순번은 코인
local GIFT_ORDER: { [number]: string } = {
	[1] = "balloons",
	[2] = "trophy",
	[3] = "teddy",
	[5] = "rainbow",
	[8] = "starlamp",
	[12] = "cake",
}

local BY_ID: { [string]: Item } = {}
local INDEX: { [string]: number } = {}

-- ── 로드 assert ─────────────────────────────────────────────────
do
	local counts = { general = 0, friend = 0, gift = 0 }
	for i, item in LIST do
		assert(BY_ID[item.id] == nil, `DecorConfig: id 중복 {item.id}`)
		assert(#item.id <= MAX_ID_LEN, `DecorConfig: id 가 {MAX_ID_LEN}자를 넘는다 {item.id}`)
		assert((utf8.len(item.name) or 99) <= 6, `DecorConfig: 이름이 6자를 넘는다 {item.id}`)
		assert(
			#item.parts >= 1 and #item.parts <= MAX_PARTS,
			`DecorConfig: parts 가 1~{MAX_PARTS}개가 아니다 {item.id}`
		)
		assert(
			(item.w == 1 or item.w == 2) and (item.d == 1 or item.d == 2),
			`DecorConfig: w·d 는 1 또는 2 {item.id}`
		)
		counts[item.kind] += 1
		if item.kind == "friend" then
			local studentId = item.student
			assert(studentId, `DecorConfig: friend 에 student 가 없다 {item.id}`)
			local student = StudentConfig.BY_ID[studentId]
			assert(student, `DecorConfig: StudentConfig 에 없는 학생 {studentId}`)
			assert(
				student.unlock.kind == "friend" and student.unlock.value == item.unlock,
				`DecorConfig: {item.id} 의 unlock 이 StudentConfig {studentId} 친구 해금값과 다르다`
			)
		else
			assert(item.student == nil, `DecorConfig: friend 가 아닌데 student 가 있다 {item.id}`)
			assert(item.unlock == 0, `DecorConfig: {item.id} unlock 은 0 이어야 한다`)
		end
		if item.kind == "gift" then
			assert(item.price == 0, `DecorConfig: gift 가격은 0 {item.id}`)
		else
			assert(item.price > 0, `DecorConfig: 가격이 없다 {item.id}`)
		end
		BY_ID[item.id] = item
		INDEX[item.id] = i
	end
	assert(
		counts.general == 12 and counts.gift == 6 and counts.friend == 9,
		`DecorConfig: 종류별 개수가 12/6/9 가 아니다 ({counts.general}/{counts.gift}/{counts.friend})`
	)
	for n, id in GIFT_ORDER do
		local item = BY_ID[id]
		assert(item and item.kind == "gift", `DecorConfig: GIFT_ORDER[{n}] {id} 가 gift 아이템이 아니다`)
	end
	assert(BY_ID[DecorConfig.TUTORIAL_ITEM], "DecorConfig: TUTORIAL_ITEM 이 LIST 에 없다")
end

DecorConfig.LIST = LIST
DecorConfig.BY_ID = BY_ID
DecorConfig.GIFT_ORDER = GIFT_ORDER

function DecorConfig.byId(id: string): Item?
	return BY_ID[id]
end

--- LIST 순번(1..27). DecorCodec 이 id 대신 쓴다
function DecorConfig.indexOf(id: string): number?
	return INDEX[id]
end

--- 선물판 giftIndex 번째 선물이 아이템이면 그 id, 코인이면 nil
function DecorConfig.giftAt(giftIndex: number): string?
	return GIFT_ORDER[giftIndex]
end

--- 졸업 graduations 회 기준 가격(서버가 계산). gift 는 0
function DecorConfig.priceOf(id: string, graduations: number): number
	local item = BY_ID[id]
	if not item then
		return 0
	end
	return math.floor(item.price * FacilityConfig.PRICE_SCALE ^ graduations + 0.5)
end

--- 상점에 진열되나. gift 는 상점에 없다
function DecorConfig.isShown(item: Item, graduations: number): boolean
	return item.kind ~= "gift" and graduations >= item.unlock
end

--- 아이템 id 의 보관함 + 배치 합(MAX_OWNED 와 비교한다)
function DecorConfig.heldCount(owned: { [string]: number }, placed: { Types.DecorPlacement }, id: string): number
	local n = owned[id] or 0
	for _, p in placed do
		if p.item == id then
			n += 1
		end
	end
	return n
end

return DecorConfig
