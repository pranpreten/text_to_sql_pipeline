-- =====================================================================
-- 01. 확장 + 스키마 골격
-- 프로젝트 구조: Raw DB(원천 복제) → New DB(재설계) → Wide Table(마트)
-- 로컬 개발에서는 DB 하나(sbizdb)에 스키마로 구분한다.
--   raw   : 원천 그대로 (문자열 그대로, 무변형 적재 — ELT의 L)
--   stg   : 스테이징 (정규화·검증 중간 단계)
--   mart  : AI 분석용 와이드 테이블 (Text-to-SQL 이 조회하는 곳, 조인 0회)
--   rag   : 비정형 — 문서·청크·벡터 (pgvector)
--   meta  : 데이터 사전, 코드 매핑 등 관리용
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS vector;      -- pgvector
CREATE EXTENSION IF NOT EXISTS pg_trgm;     -- 한국어 부분일치 검색 보조 (하이브리드 검색용)

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS stg;
CREATE SCHEMA IF NOT EXISTS mart;
CREATE SCHEMA IF NOT EXISTS rag;
CREATE SCHEMA IF NOT EXISTS meta;

COMMENT ON SCHEMA raw  IS '원천 무변형 적재 (ELT Raw Zone)';
COMMENT ON SCHEMA stg  IS '스테이징 — 정규화/검증/비식별 중간 단계';
COMMENT ON SCHEMA mart IS 'AI 분석용 마트 (Wide Table, Text-to-SQL 대상)';
COMMENT ON SCHEMA rag  IS 'RAG — 문서/청크/임베딩 (pgvector)';
COMMENT ON SCHEMA meta IS '데이터 사전·코드 매핑·적재 이력';

-- 서비스(읽기 전용) 계정: Text-to-SQL 에이전트가 쓸 계정은 SELECT만 허용
-- (RFP SFR-003 SQL 가드레일: DML 원천 차단)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'ai_reader') THEN
    CREATE ROLE ai_reader LOGIN PASSWORD 'reader1234!';  -- TODO: 변경
  END IF;
END $$;

GRANT USAGE ON SCHEMA mart, rag, meta TO ai_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA mart GRANT SELECT ON TABLES TO ai_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA rag  GRANT SELECT ON TABLES TO ai_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA meta GRANT SELECT ON TABLES TO ai_reader;
-- raw/stg 는 ai_reader 에게 아예 노출하지 않는다 (허용 테이블 외 접근 금지)
