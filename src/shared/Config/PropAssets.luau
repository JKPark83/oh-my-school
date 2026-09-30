--!strict
--[[
	소품 메시·창 텍스처·Creator Store 모델의 에셋 id 단일 소스. 개선계획 §3.1 #6~#10.

	통합이 Studio 에서 얻은 값을 채운다. id 0 = 폴백(메시는 파트로 짓고, 창 텍스처는 안 붙인다).
	메시·텍스처 id 는 게임 소유자 계정에 올린 것이어야 한다. 다른 계정·그룹 게임으로 옮기면 가장 먼저 깨진다.
	불러오기가 실패해도 폴백이 동작한다(PropLibrary·BuildKit.window 가 pcall·id 0 검사를 한다).
]]

local PropAssets = {}

export type MeshAsset = {
	id: number, -- 0 = 파트 폴백
	size: Vector3, -- 지을 때 맞출 크기(스터드)
	triangles: number, -- 삼각형 수(성능 예산 기록용)
}

-- 여러 파트로 나뉜 메시 하나. offset = 밑면 중심에서 파트 중심까지(스터드, 파트 회전 0)
export type MeshPiece = {
	name: string,
	id: number, -- 0 = 전체를 파트 폴백
	texture: number, -- 원래 텍스처(0 = 없음)
	size: Vector3,
	offset: Vector3,
}

export type PieceAsset = {
	pieces: { MeshPiece },
	triangles: number, -- 파트를 모두 더한 삼각형 수
}

export type StoreModel = {
	id: number,
	name: string,
	creator: string,
	url: string,
	parts: number, -- 들어올 BasePart 수(게이트 때). 다르면 warn, STORE_PARTS_MAX_RATIO 배를 넘으면 버린다
	use: "plaza", -- 광장에만 둔다(비핵심)
}

-- 교실형 시설 바깥벽 창. 한 칸(타일) = 창 하나. U 는 벽 가로, V 는 세로.
-- 그림: assets/textures/window.png(256×512, 흰 틀·십자 창살·유리 205,235,255, 가장자리 투명). 2026-09-30 게임 소유자 계정 업로드.
-- sill     = 벽 파트 아랫면에서 그림 속 창 아랫변까지 높이(계약 +3)
-- tileSill = 타일 아랫변에서 그림 속 창 아랫변까지(스터드, studsPerTile.Y 기준). 그림 불투명 행 96~416 px → (512−416)/512 × 12
-- BuildKit.window 가 이 값으로 OffsetStudsV 를 구한다
PropAssets.WINDOW_TEXTURE = {
	id = 81776882157738,
	studsPerTile = Vector2.new(6, 12),
	sill = 3,
	tileSill = 2.25,
}

--[[
	창 Texture 를 폭 width·높이 height 인 벽 면에 붙일 때의 StudsPerTileU 와 OffsetStudsV.
	  U: 벽 폭을 창 칸으로 딱 나눈다(칸 폭 ≈ studsPerTile.X). 벽 양 끝에서 창이 잘리지 않고, OffsetStudsU 는 0 이다.
	  V: 옆면 텍스처는 면 윗변에서 아래로 타일링된다는 가정. 타일 윗변 = OffsetStudsV + k·V.
	     그림 속 창 아랫변(타일 윗변 + V − tileSill)이 면 윗변에서 height − sill 에 오게 한다.
	     벽이 sill + V 보다 높으면 위 칸 창의 아랫부분이 벽 윗변에 조금 보인다.
]]
function PropAssets.windowTile(width: number, height: number): (number, number)
	local spec = PropAssets.WINDOW_TEXTURE
	local tileU = width / math.max(1, math.round(width / spec.studsPerTile.X))
	local tileV = spec.studsPerTile.Y
	return tileU, (height - spec.sill - (tileV - spec.tileSill)) % tileV
end

-- 도서관 책 판 앞면. 한 칸(타일) = 책장 한 칸 폭, 세로는 책 판 높이 전체(선반 4단).
-- 그림: assets/textures/bookshelf.png(320×800, 책등 색·높이·띠·제목 라벨이 제각각, 선반 판 4개, 가로로 이어 붙여도 책이 안 잘린다).
-- 2026-09-30 게임 소유자 계정 업로드. id 0 이면 색 판 폴백
PropAssets.BOOKSHELF_TEXTURE = {
	id = 126193849530960,
	studsPerTileU = 2.7, -- 그림 비율 0.4 × 책 판 높이 6.8
}

-- 방 안 디테일 그림(Decal/Texture). 그림 원본은 tools/make_interior_textures.py 가 assets/textures/ 에 만든다.
-- 2026-09-30 게임 소유자 계정 업로드. id 0 이면 그 장식만 빠지고 파트는 그대로 보인다
PropAssets.INTERIOR = {
	LOCKER_DOOR = 118044559496398, -- 사물함 문 한 칸: 환기구·이름표·손잡이(투명 덧그림, 문 색이 비친다)
	CABINET = 138121015793531, -- 실험대 아래 수납장: 문 2짝·손잡이·서랍(투명 덧그림)
	REAGENT_SHELF = 97858711469174, -- 시약장 앞면: 선반 3단의 병·플라스크
	POSTER_PERIODIC = 71679361990193, -- 주기율표 포스터(제목 포함)
	FLOOR_TILE = 115351275941700, -- 바닥 타일 2×2(Texture, 한 장 = FLOOR_TILE_STUDS)
	WAINSCOT = 92495608817163, -- 벽 아래 걸레받이 띠(흰 그림, Decal.Color3 로 물들인다)
	BULLETIN = 84095873609622, -- 교실 게시판 "우리 반 게시판"(코르크·그림)
	CLOCK = 138739129865742, -- 벽시계 10:10(원 밖 투명)
}
PropAssets.FLOOR_TILE_STUDS = 8

-- 메시 원본을 기다리는 상한(초, 요청 시작부터). 넘으면 파트 폴백. 부팅(PlotService.Start)이 에셋 서버에 묶이지 않게
PropAssets.MESH_TIMEOUT = 5

--[[
	소품 메시(2026-09-30 게임 소유자 계정 업로드, CreateMeshPartAsync 로 불러오기 확인).
	  flowerbed id 0 = 파트 폴백. 메시(89627977834807, 삼각형 600)는 1.79×1.5×1.29 로 만들어져 4×2 로 늘리면 비율이 깨지고,
	            한 색이면 꽃색이 사라져 흙판 + 꽃 뭉치 3 파트(팔레트 색)가 낫다.
]]
PropAssets.MESHES = {
	flowerbed = { id = 0, size = Vector3.new(4, 1.6, 2), triangles = 0 } :: MeshAsset,
}

--[[
	나무(2026-10-01 generate_mesh, 게임 소유자 계정). 줄기·잎 2파트에 원래 텍스처를 쓴다(팔레트 색 아님).
	옛 나무(메시 1개, 삼각형 1,488, 초록 한 색)는 줄기까지 초록이라 브로콜리처럼 보여 바꿨다.
	잎 4,594 + 줄기 406 = 5,000. 크기는 생성물 그대로(가로 7 · 높이 7.68), PropLibrary 가 0.85~1.15 배로 흔든다.
]]
PropAssets.TREE = {
	pieces = {
		{
			name = "Trunk",
			id = 138095690243968,
			texture = 115801787263442,
			size = Vector3.new(3.5885, 6.271, 3.6473),
			offset = Vector3.new(0.1015, 3.1353, -0.1864),
		},
		{
			name = "Leaves",
			id = 113328258589502,
			texture = 78791543336333,
			size = Vector3.new(7, 5.2329, 6.8751),
			offset = Vector3.new(0, 5.0617, 0),
		},
	},
	triangles = 5000,
} :: PieceAsset

--[[
	≤3개. 출처 표(이름·만든 이·주소)를 같이 적는다. 비면 광장에 아무것도 안 넣는다.
	InsertService:LoadAsset 은 Roblox 가 만든 것과 게임 소유자 것만 불러온다. 다른 만든 이의 무료 모델 16개는
	「User is not authorized」 로 실패해 뺐다(쓰려면 소유자 계정에 다시 올린다). 벤치 23153972(Roblox)는 파트 14 로 뺐다.
	Mailbox: 스크립트 0·조명 0·Seat 0, 4×4.1×4, Part 7 + WedgePart 2. 빨간 파트 2(우체통 몸통, 피드백 아님).
]]
-- 스토어 모델 파트 수가 entry.parts × 이 값을 넘으면 버린다(에셋이 바뀌어 광장 예산을 조용히 깨지 않게)
PropAssets.STORE_PARTS_MAX_RATIO = 2

PropAssets.STORE_MODELS = {
	{
		id = 56449011,
		name = "Mailbox",
		creator = "Roblox",
		url = "https://create.roblox.com/store/asset/56449011",
		parts = 9,
		use = "plaza",
	},
} :: { StoreModel }

return PropAssets
