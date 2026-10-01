--!strict
--[[
	프로필 스키마 마이그레이션. DataService 가 Reconcile 뒤에 부른다.
	Migrations[이전 버전] = 그 버전 데이터를 다음 버전으로 바꾸는 함수. version 증가는 DataService 루프가 한다.
	순수 함수만 둔다(Remotes·서비스·DataStore require 금지). Config 만 읽으므로 Studio 없이 표 하나로 검증할 수 있다.

	2026-10-01 졸업 폐기로 스토어를 새로 열어(PrincipalSchool) 버전 1 부터 다시 센다. 옛 단계는 지웠다.
]]

local Migrations: { [number]: (data: any) -> () } = {}

return Migrations
