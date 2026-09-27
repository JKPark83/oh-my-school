--!strict
--[[
	사람 모델의 메시 매니페스트. Studio 의 AI 메시 생성(generate_mesh)으로 뽑아
	Roblox 에 올라간 MeshPart 에셋 ID 와, 조립에 필요한 치수뿐이다.

	★ 이 파일이 생기면서 "업로드 없이 돌아간다"는 옛 규칙은 폐기됐다.
	  상자 몸 + SurfaceGui 얼굴은 플레이 거리에서 사람으로 읽히지 않았다.
	  메시는 이 계정에 올라가 있고, 게임도 같은 계정 소유라 런타임에
	  AssetService:CreateMeshPartAsync 로 바로 불러올 수 있다. (CharacterBuilder.preload)

	★ 숫자는 손으로 적은 것이 아니라 Studio 에서 생성 모델을 읽어 찍은 값이다.
	  root = 생성 모델 바운딩박스의 바닥 중심을 Y 축으로 180도 돌린 프레임.
	  offset/yaw = 그 root 기준 각 파트의 상대 CFrame(위치 + Y 회전).
	  생성 모델은 +Z 를 보고 나오는데 이 프로젝트의 얼굴 방향은 -Z 라서 root 를 돌려 뒀다.
	  파트마다 yaw 가 붙어 있는 이유는 생성기가 메시 지오메트리와 파트 회전을
	  나눠 굽기 때문이다. 위치만 옮기고 회전을 버리면 팔이 등에 달린다.

	★ 치수는 "생성 단위"다(대체로 키 6~7). CharacterBuilder 가 height 를 기준으로
	  목표 키(SIT_HEIGHT/STAND_HEIGHT x 체구 배율)에 맞춰 통째로 줄인다.
	  hip 은 앉은 자세에서 엉덩이(의자에 닿는 면)가 모델 바닥에서 얼마나 위에 있는가다.
	  발이 의자 아래로 늘어지므로 0 이 아니다. 의자와 겹쳐 놓고 눈으로 맞춘 값이다.

	새 변형을 넣으려면: Studio 에서 같은 프롬프트 규격(5분할, 의자 없음, 정면 +Z)으로
	생성한 뒤 같은 방식으로 덤프해 여기 붙인다. 코드는 안 바뀐다.
]]

local CharacterAssets = {}

export type PartDef = {
	name: string, -- Head / Torso / ArmLeft / ArmRight / Legs
	mesh: number,
	texture: number,
	size: Vector3,
	offset: Vector3,
	yaw: number, -- 라디안
}

export type Variant = {
	height: number, -- 생성 단위 키(바운딩박스)
	hip: number, -- 앉은 자세 엉덩이 높이(생성 단위). 서 있는 변형은 0
	parts: { PartDef },
}

-- 앉은 학생의 목표 키(스터드, 체구 배율 1 기준). 머리가 크므로 한 줄 간격(4)에 맞춰 낮게 잡았다.
CharacterAssets.SIT_HEIGHT = 4.8
-- 서 있는 선생님의 목표 키(스터드). 로블록스 기본 캐릭터와 비슷하다.
CharacterAssets.STAND_HEIGHT = 5.6

-- 좌석 번호로 순환 배정되는 학생 변형. 남녀가 섞이도록 번갈아 둔다.
local STUDENTS: { string } = {
	"BOY_A",
	"GIRL_A",
	"BOY_B",
	"GIRL_B",
	"BOY_C",
	"GIRL_C",
	"BOY_D",
	"GIRL_D",
	"GIRL_E",
}

-- 슬롯 번호로 번갈아 배정되는 선생님 변형.
local TEACHERS: { string } = { "TEACHER_M", "TEACHER_F" }

local function V(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local VARIANTS: { [string]: Variant } = {
	-- 남색 조끼 + 흰 셔츠, 검은 머리 (7b8ccb50)
	BOY_A = {
		height = 7.406,
		hip = 1.4,
		parts = {
			{
				name = "ArmLeft",
				mesh = 90160780720917,
				texture = 140398760872702,
				size = V(1.049, 1.928, 2.088),
				offset = V(-0.219, 2.712, -1.229),
				yaw = 2.193,
			},
			{
				name = "ArmRight",
				mesh = 110160983493070,
				texture = 119013718130700,
				size = V(1.013, 1.939, 2.089),
				offset = V(1.097, 2.715, 0.606),
				yaw = 2.193,
			},
			{
				name = "Head",
				mesh = 94088697565647,
				texture = 114014867865119,
				size = V(4.028, 3.617, 3.962),
				offset = V(-0.016, 5.597, 0.011),
				yaw = 2.193,
			},
			{
				name = "Legs",
				mesh = 112746413165292,
				texture = 122751174342909,
				size = V(2.695, 1.998, 1.558),
				offset = V(0.986, 0.999, -0.721),
				yaw = 2.193,
			},
			{
				name = "Torso",
				mesh = 86453741266206,
				texture = 90343446493631,
				size = V(2.676, 3.071, 2.401),
				offset = V(-0.225, 2.492, 0.154),
				yaw = 2.193,
			},
		},
	},
	-- 뾰족머리, 빨강·흰 줄무늬 티 (f17d8b22)
	BOY_B = {
		height = 6.510,
		hip = 0.86,
		parts = {
			{
				name = "ArmLeft",
				mesh = 122187707181679,
				texture = 90910007271467,
				size = V(1.060, 1.465, 1.591),
				offset = V(-0.507, 1.700, -1.072),
				yaw = 2.615,
			},
			{
				name = "ArmRight",
				mesh = 99229443340803,
				texture = 121907471405583,
				size = V(1.050, 1.466, 1.584),
				offset = V(1.173, 1.701, -0.095),
				yaw = 2.615,
			},
			{
				name = "Head",
				mesh = 99474808020373,
				texture = 77931004101645,
				size = V(4.834, 4.008, 3.764),
				offset = V(-0.059, 4.506, 0.102),
				yaw = 2.615,
			},
			{
				name = "Legs",
				mesh = 89122141811333,
				texture = 89115460584717,
				size = V(2.882, 1.225, 1.654),
				offset = V(0.584, 0.615, -1.017),
				yaw = 2.615,
			},
			{
				name = "Torso",
				mesh = 73135271688380,
				texture = 119188129758134,
				size = V(2.437, 2.687, 1.870),
				offset = V(0.022, 1.343, -0.046),
				yaw = 2.615,
			},
		},
	},
	-- 주황 점퍼, 졸린 얼굴 (62ea1c3a)
	BOY_C = {
		height = 6.094,
		hip = 0.74,
		parts = {
			{
				name = "ArmLeft",
				mesh = 138387615531855,
				texture = 97691147576296,
				size = V(0.935, 1.538, 1.543),
				offset = V(-0.526, 1.480, -0.921),
				yaw = 2.615,
			},
			{
				name = "ArmRight",
				mesh = 104929365922991,
				texture = 84315282845311,
				size = V(0.933, 1.539, 1.541),
				offset = V(1.053, 1.479, -0.004),
				yaw = 2.615,
			},
			{
				name = "Head",
				mesh = 120026244352031,
				texture = 128052818016917,
				size = V(4.205, 3.654, 3.811),
				offset = V(-0.048, 4.267, 0.082),
				yaw = 2.615,
			},
			{
				name = "Legs",
				mesh = 129355162050727,
				texture = 91594989091073,
				size = V(2.802, 1.053, 2.194),
				offset = V(0.449, 0.527, -0.784),
				yaw = 2.615,
			},
			{
				name = "Torso",
				mesh = 140429719706978,
				texture = 97846461940223,
				size = V(2.477, 2.855, 2.070),
				offset = V(-0.140, 1.436, 0.218),
				yaw = 2.615,
			},
		},
	},
	-- 갈색 바가지머리, 안경, 초록 후드 (28b4baab)
	BOY_D = {
		height = 6.235,
		hip = 0.86,
		parts = {
			{
				name = "ArmLeft",
				mesh = 123498477263267,
				texture = 123743061306911,
				size = V(1.001, 1.568, 1.440),
				offset = V(-0.659, 1.745, -0.771),
				yaw = 2.615,
			},
			{
				name = "ArmRight",
				mesh = 113769964395730,
				texture = 76074606339618,
				size = V(1.075, 1.570, 1.441),
				offset = V(0.968, 1.743, 0.176),
				yaw = 2.615,
			},
			{
				name = "Head",
				mesh = 81274660499456,
				texture = 75200187177451,
				size = V(4.000, 3.408, 3.656),
				offset = V(-0.120, 4.530, 0.207),
				yaw = 2.615,
			},
			{
				name = "Legs",
				mesh = 83434225918204,
				texture = 107115002507669,
				size = V(3.168, 1.233, 2.944),
				offset = V(0.302, 0.617, -0.513),
				yaw = 2.615,
			},
			{
				name = "Torso",
				mesh = 104786958339487,
				texture = 81877089517007,
				size = V(2.789, 3.118, 2.468),
				offset = V(-0.261, 1.570, 0.446),
				yaw = 2.615,
			},
		},
	},
	-- 땋은 양갈래, 파란 체육복 (8397d22f)
	GIRL_A = {
		height = 6.388,
		hip = 0.95,
		parts = {
			{
				name = "ArmLeft",
				mesh = 105270436256988,
				texture = 128610411013899,
				size = V(1.257, 2.183, 1.662),
				offset = V(-0.429, 1.842, -0.836),
				yaw = 2.615,
			},
			{
				name = "ArmRight",
				mesh = 122951026980157,
				texture = 74432431611662,
				size = V(1.199, 2.190, 1.627),
				offset = V(1.458, 1.847, 0.252),
				yaw = 2.615,
			},
			{
				name = "Head",
				mesh = 78478001036837,
				texture = 86352465734048,
				size = V(4.590, 3.853, 3.612),
				offset = V(-0.098, 4.462, 0.168),
				yaw = 2.615,
			},
			{
				name = "Legs",
				mesh = 85937249776760,
				texture = 89504103371760,
				size = V(2.664, 1.359, 2.809),
				offset = V(0.552, 0.679, -0.368),
				yaw = 2.615,
			},
			{
				name = "Torso",
				mesh = 106808192917244,
				texture = 114024896337896,
				size = V(2.876, 2.145, 2.427),
				offset = V(0.204, 2.042, 0.239),
				yaw = 2.615,
			},
		},
	},
	-- 단발 + 노란 머리띠, 멜빵바지 (7134eb0a)
	GIRL_B = {
		height = 6.025,
		hip = 0.84,
		parts = {
			{
				name = "ArmLeft",
				mesh = 120709072811361,
				texture = 112404525672074,
				size = V(0.807, 1.326, 1.283),
				offset = V(-0.514, 1.662, -0.722),
				yaw = 2.615,
			},
			{
				name = "ArmRight",
				mesh = 72840899793460,
				texture = 77159321227343,
				size = V(0.777, 0.871, 1.083),
				offset = V(0.906, 1.438, -0.017),
				yaw = 2.615,
			},
			{
				name = "Head",
				mesh = 93936963497946,
				texture = 77155430789465,
				size = V(4.423, 3.694, 3.795),
				offset = V(-0.051, 4.179, 0.088),
				yaw = 2.615,
			},
			{
				name = "Legs",
				mesh = 99918390670253,
				texture = 79717452761920,
				size = V(3.756, 1.196, 1.930),
				offset = V(0.521, 0.598, -0.894),
				yaw = 2.615,
			},
			{
				name = "Torso",
				mesh = 128434250660704,
				texture = 101520305523722,
				size = V(1.915, 2.733, 1.803),
				offset = V(-0.045, 1.423, 0.070),
				yaw = 2.615,
			},
		},
	},
	-- 작은 양갈래, 빨간 안경, 크림색 가디건 (37d02a74)
	GIRL_C = {
		height = 5.973,
		hip = 1.1,
		parts = {
			{
				name = "ArmLeft",
				mesh = 140697701582292,
				texture = 76895168359491,
				size = V(1.074, 0.934, 0.661),
				offset = V(-1.557, 3.362, -0.906),
				yaw = 2.615,
			},
			{
				name = "ArmRight",
				mesh = 74026771213088,
				texture = 110463956901811,
				size = V(2.022, 3.031, 1.507),
				offset = V(1.344, 2.315, 0.299),
				yaw = 2.615,
			},
			{
				name = "Head",
				mesh = 128228964850880,
				texture = 93568922824007,
				size = V(5.313, 3.652, 3.576),
				offset = V(-0.107, 4.147, 0.183),
				yaw = 2.615,
			},
			{
				name = "Legs",
				mesh = 89852956720204,
				texture = 110447089827048,
				size = V(2.493, 2.186, 2.248),
				offset = V(0.440, 1.124, -0.757),
				yaw = 2.615,
			},
			{
				name = "Torso",
				mesh = 87016533655425,
				texture = 108184612091295,
				size = V(2.705, 2.554, 2.815),
				offset = V(0.062, 1.277, -0.115),
				yaw = 2.615,
			},
		},
	},
	-- 갈색 높은 포니테일, 연보라 스웨터 (5e5fb3ef)
	GIRL_D = {
		height = 5.828,
		hip = 0.75,
		parts = {
			{
				name = "ArmLeft",
				mesh = 121569829591608,
				texture = 118016186307609,
				size = V(1.509, 2.026, 0.845),
				offset = V(1.093, 1.295, 0.599),
				yaw = 2.615,
			},
			{
				name = "ArmRight",
				mesh = 99588377153720,
				texture = 102431502500722,
				size = V(1.506, 2.021, 0.840),
				offset = V(-1.062, 1.297, -0.654),
				yaw = 2.615,
			},
			{
				name = "Head",
				mesh = 97759711101548,
				texture = 136412637791967,
				size = V(3.620, 3.552, 3.764),
				offset = V(-0.218, 4.052, 0.366),
				yaw = 2.615,
			},
			{
				name = "Legs",
				mesh = 130403448255668,
				texture = 133031592234831,
				size = V(2.008, 1.071, 2.298),
				offset = V(0.578, 0.535, -1.005),
				yaw = 2.615,
			},
			{
				name = "Torso",
				mesh = 112236423783990,
				texture = 106095662618435,
				size = V(2.599, 2.483, 2.543),
				offset = V(0.101, 1.349, -0.184),
				yaw = 2.615,
			},
		},
	},
	-- 빨간 끈 양갈래, 분홍 가디건 (cce84663)
	GIRL_E = {
		height = 6.624,
		hip = 0.6,
		parts = {
			{
				name = "ArmLeft",
				mesh = 89097111676732,
				texture = 133590246239940,
				size = V(1.066, 1.767, 1.595),
				offset = V(-0.916, 1.801, -0.552),
				yaw = -3.122,
			},
			{
				name = "ArmRight",
				mesh = 132799072822453,
				texture = 77692375359239,
				size = V(1.059, 1.768, 1.599),
				offset = V(0.893, 1.803, -0.587),
				yaw = -3.122,
			},
			{
				name = "Head",
				mesh = 108703637896978,
				texture = 119344790056310,
				size = V(6.483, 3.886, 4.000),
				offset = V(0, 4.681, 0),
				yaw = -3.122,
			},
			{
				name = "Legs",
				mesh = 96262544020298,
				texture = 99044213422568,
				size = V(2.036, 0.858, 2.075),
				offset = V(-0.013, 0.429, -0.902),
				yaw = -3.122,
			},
			{
				name = "Torso",
				mesh = 128510316887906,
				texture = 125392530536664,
				size = V(3.021, 2.947, 3.307),
				offset = V(0.002, 1.604, -0.061),
				yaw = -3.122,
			},
		},
	},
	-- 남자 선생님. 서 있는 자세 (ca28e8cf)
	TEACHER_M = {
		height = 5.509,
		hip = 0,
		parts = {
			{
				name = "ArmLeft",
				mesh = 109239438737888,
				texture = 87354369985085,
				size = V(0.828, 1.880, 0.658),
				offset = V(-0.747, 2.216, 0.474),
				yaw = -2.579,
			},
			{
				name = "ArmRight",
				mesh = 70720402772573,
				texture = 78908216449298,
				size = V(1.395, 2.160, 0.918),
				offset = V(0.505, 2.359, -0.322),
				yaw = -2.579,
			},
			{
				name = "Head",
				mesh = 103237712074656,
				texture = 81734569842296,
				size = V(2.615, 2.462, 1.800),
				offset = V(0, 4.278, 0),
				yaw = -2.579,
			},
			{
				name = "Legs",
				mesh = 95319218570124,
				texture = 133037701120261,
				size = V(1.586, 1.937, 1.141),
				offset = V(-0.064, 0.968, -0.093),
				yaw = -2.579,
			},
			{
				name = "Torso",
				mesh = 100932423318737,
				texture = 108927737470298,
				size = V(1.484, 1.657, 1.221),
				offset = V(-0.003, 2.479, 0),
				yaw = -2.579,
			},
		},
	},
	-- 여자 선생님. 서 있는 자세 (d11240da)
	TEACHER_F = {
		height = 10.849,
		hip = 0,
		parts = {
			{
				name = "ArmLeft",
				mesh = 108109731738682,
				texture = 73929649603247,
				size = V(1.714, 3.887, 1.486),
				offset = V(-1.169, 4.637, -1.030),
				yaw = 2.615,
			},
			{
				name = "ArmRight",
				mesh = 75242936098452,
				texture = 135213022016980,
				size = V(1.725, 3.888, 1.495),
				offset = V(1.470, 4.638, 0.502),
				yaw = 2.615,
			},
			{
				name = "Head",
				mesh = 95817174245118,
				texture = 81658987713589,
				size = V(4.589, 4.576, 4.000),
				offset = V(0.006, 8.561, 0.004),
				yaw = 2.615,
			},
			{
				name = "Legs",
				mesh = 112812019177568,
				texture = 85188117975624,
				size = V(2.424, 3.406, 1.703),
				offset = V(0.284, 1.703, -0.489),
				yaw = 2.615,
			},
			{
				name = "Torso",
				mesh = 130951092837627,
				texture = 140401855815978,
				size = V(3.215, 5.851, 2.902),
				offset = V(0.157, 3.952, -0.277),
				yaw = 2.615,
			},
		},
	},
}

CharacterAssets.STUDENTS = STUDENTS
CharacterAssets.TEACHERS = TEACHERS
CharacterAssets.VARIANTS = VARIANTS

return CharacterAssets
