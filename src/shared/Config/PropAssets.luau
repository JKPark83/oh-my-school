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
	texture: number?, -- 원래 텍스처(없으면 파트 색을 입힌다)
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
	NET = 125450629287113, -- 축구 골대 그물 4×4 칸(투명 바탕 흰 줄, Texture 로 깐다. 0 이면 흰 반투명 판)
	HOOP_NET = 106264961943235, -- 농구 그물 마름모 2×2 칸(투명 바탕 흰 줄, Texture 로 깐다. 0 이면 흰 반투명 판)
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
	주인공 소품 메시(P5, 2026-10-02 Studio 메시 생성으로 만들어 게임 소유자 계정에 올렸다). 방마다 한두 개.
	  · 전부 한 덩어리 MeshPart + 원래 텍스처. 앞(정면)이 +Z 다(예외: 2026-10-03 에 만든 robotarm·dinosaur 와
	    lectern 아래 새 키들은 −Z). size 는 만든 그대로의 크기라 비율로만 쓴다.
	  · 클라만 쓴다(client/MeshCache). 층 쌓기 방은 Rooms/Kit.hero, 1층 시설은 InteriorRenderController 의 hero.
	  · id 가 0 이거나 못 불러오면 레시피가 그 자리를 파트로 짓는다.
	  · 삼각형 예산(기획서 §12.1): 층 방 하나 ≤ 10,000, 1층 시설 하나 ≤ 6,000.
	  · 올렸지만 안 쓰는 것: 체육관 뜀틀 70614742892634(서버 뜀틀이 이미 있고 방 파트 상한 16 이 찼다).
]]
PropAssets.HERO = {
	-- 미술실 이젤
	easel = {
		id = 96778598060402,
		texture = 99222712226432,
		size = Vector3.new(3.866, 6.000, 3.433),
		triangles = 1186,
	} :: MeshAsset,
	-- 컴퓨터실 컴퓨터(둥근 모니터 + 키보드)
	computer = {
		id = 78608019305396,
		texture = 138581128872401,
		size = Vector3.new(4.000, 3.276, 3.163),
		triangles = 1498,
	} :: MeshAsset,
	-- 방송실 카메라(받침은 파트)
	camera = {
		id = 88148426784576,
		texture = 99259905251958,
		size = Vector3.new(3.376, 4.270, 6.000),
		triangles = 2376,
	} :: MeshAsset,
	-- 요리실 가스레인지·오븐
	stove = {
		id = 139592776915418,
		texture = 116329955182294,
		size = Vector3.new(5.407, 6.000, 4.044),
		triangles = 2366,
	} :: MeshAsset,
	-- 댄스실 스피커
	speaker = {
		id = 102281057644806,
		texture = 135929759277500,
		size = Vector3.new(2.321, 6.000, 2.239),
		triangles = 1920,
	} :: MeshAsset,
	-- 코딩로봇실 로봇 팔(둥근 받침·주황 팔·집게, 2026-10-03 다시 만듦). 앞 = −Z: 집게가 −Z 로 뻗는다
	robotarm = {
		id = 105893901729989,
		texture = 103707194722311,
		size = Vector3.new(2.500, 3.379, 3.705),
		triangles = 1982,
	} :: MeshAsset,
	-- 코딩로봇실 바퀴 로봇
	rover = {
		id = 127806762745904,
		texture = 130456899187463,
		size = Vector3.new(2.395, 3.000, 1.442),
		triangles = 1196,
	} :: MeshAsset,
	-- 영어체험실 가게
	stall = {
		id = 117138893734484,
		texture = 107280353571922,
		size = Vector3.new(7.267, 8.000, 4.809),
		triangles = 2428,
	} :: MeshAsset,
	-- 돌봄교실 곰 인형
	bear = {
		id = 135239448763276,
		texture = 81658468484901,
		size = Vector3.new(2.133, 3.000, 1.934),
		triangles = 1500,
	} :: MeshAsset,
	-- 교무실 복사기
	copier = {
		id = 113793820750970,
		texture = 132014390874777,
		size = Vector3.new(4.751, 3.794, 5.000),
		triangles = 1770,
	} :: MeshAsset,
	-- 전시실 공룡 화석 뼈대(티라노, 갈비 사이가 뚫림, 2026-10-03 다시 만듦). 앞 = −Z: 머리가 −Z
	dinosaur = {
		id = 96816735894628,
		texture = 118969854246804,
		size = Vector3.new(4.000, 7.522, 9.386),
		triangles = 5482,
	} :: MeshAsset,
	-- 전시실·복도 트로피
	trophy = {
		id = 91745675938798,
		texture = 116058333119970,
		size = Vector3.new(2.232, 4.000, 1.458),
		triangles = 1288,
	} :: MeshAsset,
	-- 옥상정원 꽃 덩굴 문
	arch = {
		id = 133025776012634,
		texture = 117510415804079,
		size = Vector3.new(8.000, 7.618, 3.763),
		triangles = 2488,
	} :: MeshAsset,
	-- 옥상정원 분수
	fountain = {
		id = 107779413878530,
		texture = 88606053725281,
		size = Vector3.new(6.000, 4.917, 5.995),
		triangles = 2376,
	} :: MeshAsset,
	-- 천문대 망원경
	telescope = {
		id = 78336418283145,
		texture = 124935983986664,
		size = Vector3.new(3.021, 6.000, 4.664),
		triangles = 2386,
	} :: MeshAsset,
	-- 천문대 로켓
	rocket = {
		id = 98833396412810,
		texture = 128214638871826,
		size = Vector3.new(2.097, 6.000, 1.520),
		triangles = 1546,
	} :: MeshAsset,
	-- 사물함 책가방
	backpack = {
		id = 89379326213843,
		texture = 87460020437638,
		size = Vector3.new(2.143, 3.000, 2.384),
		triangles = 1494,
	} :: MeshAsset,
	-- 급식실 배식대
	counter = {
		id = 87934425741993,
		texture = 84400000421382,
		size = Vector3.new(8.000, 7.046, 4.683),
		triangles = 2382,
	} :: MeshAsset,
	-- 도서관·교실 지구본
	globe = {
		id = 136211906853197,
		texture = 102275712094742,
		size = Vector3.new(2.490, 3.000, 2.050),
		triangles = 1456,
	} :: MeshAsset,
	-- 보건실 침대(머리맡이 −Z)
	bed = {
		id = 120992832932517,
		texture = 88860029233546,
		size = Vector3.new(3.954, 3.930, 7.000),
		triangles = 1880,
	} :: MeshAsset,
	-- 과학실 현미경
	microscope = {
		id = 93997462882077,
		texture = 138680107435996,
		size = Vector3.new(1.988, 3.000, 1.649),
		triangles = 1348,
	} :: MeshAsset,
	-- 과학실 플라스크
	flasks = {
		id = 117661223686773,
		texture = 91202557465745,
		size = Vector3.new(2.627, 3.000, 1.409),
		triangles = 1494,
	} :: MeshAsset,
	-- 음악실 드럼
	drums = {
		id = 130554595778952,
		texture = 116255109095872,
		size = Vector3.new(6.000, 4.246, 2.288),
		triangles = 2490,
	} :: MeshAsset,
	-- 체육관 공 카트
	ballcart = {
		id = 120408447662560,
		texture = 84519629578794,
		size = Vector3.new(3.838, 5.000, 2.149),
		triangles = 2000,
	} :: MeshAsset,
	-- 운동장 시상대
	podium = {
		id = 76836348412095,
		texture = 71035013299200,
		size = Vector3.new(7.000, 2.918, 3.251),
		triangles = 1312,
	} :: MeshAsset,
	-- 교장실 책상(스탠드·화분 포함 높이)
	principaldesk = {
		id = 131803893381238,
		texture = 136575204085146,
		size = Vector3.new(4.523, 5.000, 2.253),
		triangles = 2340,
	} :: MeshAsset,
	-- 강당 연단
	lectern = {
		id = 112256689602283,
		texture = 132341444607968,
		size = Vector3.new(3.968, 5.000, 3.466),
		triangles = 1286,
	} :: MeshAsset,
	-- 아래는 2026-10-03 generate_mesh 로 만든 것. 앞(정면)이 전부 −Z 다(위 P5 메시와 반대) → 레시피 yaw 에 180 을 더한다
	-- 미술실 석고상(곱슬머리 머리·어깨)
	bust = {
		id = 128373287498109,
		texture = 80336182489489,
		size = Vector3.new(1.106, 1.707, 1.200),
		triangles = 1998,
	} :: MeshAsset,
	-- 방송실 믹서(페이더·노브·미터·헤드폰)
	mixer = {
		id = 95242537043903,
		texture = 124585443322319,
		size = Vector3.new(1.277, 1.000, 0.992),
		triangles = 1772,
	} :: MeshAsset,
	-- 돌봄교실 흔들목마(머리가 −Z)
	rockinghorse = {
		id = 89999256887156,
		texture = 98738247977349,
		size = Vector3.new(1.400, 2.638, 3.022),
		triangles = 1978,
	} :: MeshAsset,
	-- 컴퓨터실 서버 랙(유리문·불빛)
	serverRack = {
		id = 140723904612222,
		texture = 118591948945218,
		size = Vector3.new(2.086, 3.213, 2.000),
		triangles = 952,
	} :: MeshAsset,
	-- 요리실 조리대(윗면 평평, 화구 1·싱크, 위로 튀어나온 것 없음)
	cookcounter = {
		id = 100723810927403,
		texture = 84971449597492,
		size = Vector3.new(4.314, 2.875, 2.298),
		triangles = 1168,
	} :: MeshAsset,
	-- 댄스실 붐박스
	boombox = {
		id = 75249291437117,
		texture = 72783653080991,
		size = Vector3.new(2.384, 1.600, 0.866),
		triangles = 1494,
	} :: MeshAsset,
	-- 영어체험실 비행기(천장에 매단다, 기수가 −Z)
	airplane = {
		id = 128948837841845,
		texture = 100956940339011,
		size = Vector3.new(4.244, 2.200, 4.148),
		triangles = 2930,
	} :: MeshAsset,
}

--[[
	꾸미기 물건 메시(2026-10-03). 키 = DecorConfig 아이템 id. 없는 아이템은 DecorConfig.parts 로만 짓는다.
	  · DecorBuilder 가 메시를 파트 폴백의 상자(모든 파트를 감싼 상자) 와 발자국 90% 중 큰 쪽(가로·세로), 파트 상자 높이 안에
	    비율 그대로 가장 크게 넣는다. size 는 만든 그대로라 비율로만 쓴다.
	  · yaw = 메시 앞을 +Z(파트 폴백의 앞)로 돌리는 각도(도). P5 HERO 는 0, 2026-10-03 생성 메시는 180.
	  · 클라만 쓴다(client/MeshCache.decor). id 0·못 불러옴·아직 안 옴이면 파트로 짓는다. 고스트는 텍스처를 뗀 같은 메시다.
	  · 풍선·무지개깃발·별조명은 파트로 둔다(생성기가 풍선 줄을 못 만들고, 깃발은 6색 줄무늬로 나왔고, 별조명은 메시면 Neon 빛이 없다).
	  · height = 파트 상자 높이 대신 쓸 높이 상한. 폴백이 납작한 물건(연못·화단)이 발자국을 채우게 한다.
	  · 삼각형: 새로 만든 것은 ≤ 1,500(기획서 §12.1 꾸미기 메시). 생성기가 상한을 넘긴 공 바구니만 2,132.
]]
export type DecorMesh = {
	asset: MeshAsset,
	yaw: number,
	height: number?,
}

PropAssets.DECOR = {
	-- P5 주인공 소품을 그대로 쓴다
	easel = { asset = PropAssets.HERO.easel, yaw = 0 } :: DecorMesh,
	trophy = { asset = PropAssets.HERO.trophy, yaw = 0 } :: DecorMesh,
	fountain = { asset = PropAssets.HERO.fountain, yaw = 0 } :: DecorMesh,
	telescope = { asset = PropAssets.HERO.telescope, yaw = 0 } :: DecorMesh,
	rocket = { asset = PropAssets.HERO.rocket, yaw = 0 } :: DecorMesh,
	globe = { asset = PropAssets.HERO.globe, yaw = 0 } :: DecorMesh,
	teddy = { asset = PropAssets.HERO.bear, yaw = 0 } :: DecorMesh,
	-- 2026-10-03 Studio 메시 생성(게임 소유자 계정)
	bench = {
		asset = {
			id = 129647804260510,
			texture = 136796766243550,
			size = Vector3.new(5.025, 2.979, 2.4),
			triangles = 1378,
		},
		yaw = 180,
	} :: DecorMesh,
	lamp = {
		asset = {
			id = 122249960451174,
			texture = 131031489313637,
			size = Vector3.new(1.497, 8.6, 1.484),
			triangles = 1144,
		},
		yaw = 180,
	} :: DecorMesh,
	mailbox = {
		asset = {
			id = 133863834922141,
			texture = 78434023215728,
			size = Vector3.new(1.6, 2.47, 0.952),
			triangles = 1132,
		},
		yaw = 180,
	} :: DecorMesh,
	planter = {
		asset = {
			id = 116384304036971,
			texture = 92080466630759,
			size = Vector3.new(2.963, 3.739, 3.0),
			triangles = 1500,
		},
		yaw = 180,
	} :: DecorMesh,
	tree = {
		asset = {
			id = 79865512411746,
			texture = 123425864960883,
			size = Vector3.new(4.5, 4.521, 4.432),
			triangles = 1500,
		},
		yaw = 180,
	} :: DecorMesh,
	signpost = {
		asset = {
			id = 87035783753506,
			texture = 108796790839639,
			size = Vector3.new(3.091, 3.105, 0.8),
			triangles = 1488,
		},
		yaw = 180,
	} :: DecorMesh,
	bikerack = {
		asset = {
			id = 137493166722518,
			texture = 121292555355100,
			size = Vector3.new(4.51, 2.5, 1.773),
			triangles = 1466,
		},
		yaw = 180,
	} :: DecorMesh,
	swing = {
		asset = {
			id = 88728073357577,
			texture = 108313881067706,
			size = Vector3.new(5.442, 5.886, 4.0),
			triangles = 1428,
		},
		yaw = 180,
	} :: DecorMesh,
	slide = {
		asset = {
			id = 116008477512602,
			texture = 110823161791122,
			size = Vector3.new(2.055, 3.324, 3.6),
			triangles = 1492,
		},
		yaw = 180,
	} :: DecorMesh,
	ballbin = {
		asset = {
			id = 139558026220269,
			texture = 120894615840504,
			size = Vector3.new(2.8, 1.437, 2.777),
			triangles = 2132,
		},
		yaw = 180,
	} :: DecorMesh,
	piano = {
		asset = {
			id = 134726022862557,
			texture = 74760168822767,
			size = Vector3.new(4.77, 4.2, 3.24),
			triangles = 1372,
		},
		yaw = 180,
	} :: DecorMesh,
	labtable = {
		asset = {
			id = 130279531781625,
			texture = 74100116419583,
			size = Vector3.new(6.661, 4.8, 3.093),
			triangles = 1444,
		},
		yaw = 180,
	} :: DecorMesh,
	tiger = {
		asset = {
			id = 103224835074959,
			texture = 109225794187744,
			size = Vector3.new(4.137, 5, 3.868),
			triangles = 1492,
		},
		yaw = 180,
	} :: DecorMesh,
	cake = {
		asset = {
			id = 124268470908819,
			texture = 84244342436362,
			size = Vector3.new(2.656, 2.744, 2.7),
			triangles = 1498,
		},
		yaw = 180,
	} :: DecorMesh,
	pond = {
		asset = {
			id = 84201716950550,
			texture = 104204342966327,
			size = Vector3.new(5.236, 1.5, 5.219),
			triangles = 1500,
		},
		yaw = 180,
		height = 2.6, -- 폴백 높이(1)에 맞추면 9 스터드 발자국을 반만 채운다
	} :: DecorMesh,
	flowerbed = {
		asset = {
			id = 85431338387556,
			texture = 124437981823040,
			size = Vector3.new(4.855, 1.6, 2.927),
			triangles = 1492,
		},
		yaw = 180,
		height = 2.5, -- 연못과 같은 이유
	} :: DecorMesh,
	bookcart = {
		asset = {
			id = 84613068697461,
			texture = 95301898571676,
			size = Vector3.new(3.151, 3, 1.783),
			triangles = 1474,
		},
		yaw = 180,
	} :: DecorMesh,
} :: { [string]: DecorMesh }

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
	현관 바깥 벽등(2026-10-01 generate_mesh, 게임 소유자 계정). 검은 쇠 육각 등 + 덩굴 받침 + 벽판, 원래 텍스처를 쓴다.
	생성 상한 3,000 삼각형. offset 은 벽판 뒷면 아래 중심에서 잰다. 등은 +Z 쪽으로 나와 있다(PropLibrary 가 벽 바깥으로 돌린다).
	크기는 생성물 그대로(1.19 × 2.32 × 1.80), PropLibrary.wallLamp 가 키운다.
]]
PropAssets.WALL_LAMP = {
	pieces = {
		{
			name = "Bracket",
			id = 107380996051748,
			texture = 137846753139561,
			size = Vector3.new(0.7948, 1.964, 1.3251),
			offset = Vector3.new(0.0004, 1.2785, 0.6627),
		},
		{
			name = "Frame",
			id = 85640793939644,
			texture = 121813891223357,
			size = Vector3.new(1.1852, 2.3244, 1.0282),
			offset = Vector3.new(0, 1.1622, 1.2862),
		},
		{
			name = "Glass",
			id = 123074667595245,
			texture = 124379781077536,
			size = Vector3.new(0.8329, 0.692, 0.741),
			offset = Vector3.new(0.0005, 0.8626, 1.271),
		},
		{
			name = "Bulb",
			id = 80820247685502,
			texture = 74144008261721,
			size = Vector3.new(0.3442, 0.3525, 0.36),
			offset = Vector3.new(-0.0046, 0.6943, 1.2559),
		},
	},
	triangles = 3000,
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
