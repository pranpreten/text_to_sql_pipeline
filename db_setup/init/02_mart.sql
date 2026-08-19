-- =====================================================================
-- 02. 정형 — 분석 마트 (Wide Table)
-- 근거: DAR-006 (조인 없이 즉시 답변하는 와이드 마트),
--       내부 검증 문서 "자유질의_RFP근거_SQL검증" 의 마트 구조 + 파생 컬럼
-- 원천: 클라비 간단분석 (98컬럼) — 표출용 문자열("2,535 만원")을
--       수치형으로 정규화하여 적재하는 것이 전제
-- =====================================================================

CREATE TABLE IF NOT EXISTS mart.mart_simple (
    -- ── 키 (기준년월 × 행정동 × 업종 소분류) ──────────────────────
    crtr_ym        char(6)      NOT NULL,              -- 기준년월 YYYYMM
    sido_cd        varchar(2),
    sido_nm        varchar(30)  NOT NULL,
    sgg_cd         varchar(5),
    sgg_nm         varchar(30),
    admi_cd        varchar(10),                        -- 행정동코드
    admi_nm        varchar(50),                        -- 행정동명
    tpbiz_lclcd    varchar(4),                         -- 업종 대분류 코드
    tpbiz_lclnm    varchar(50),
    tpbiz_mclcd    varchar(6),                         -- 업종 중분류 코드
    tpbiz_mclnm    varchar(50),
    tpbiz_clscd    varchar(8)   NOT NULL,              -- 업종 소분류 코드 (247종)
    tpbiz_nm       varchar(50)  NOT NULL,              -- 업종 소분류명

    -- ── 매출 (만원, 수치 정규화) ─────────────────────────────────
    amt_dong       numeric(14,1),                      -- 행정동 월평균 매출
    amt_sgg        numeric(14,1),                      -- 시군구 평균
    amt_sido       numeric(14,1),                      -- 시도 평균
    amt_low        numeric(14,1),
    amt_high       numeric(14,1),
    amt_on_year    numeric(8,1),                       -- 전년동월 대비 %
    amt_on_month   numeric(8,1),                       -- 전월 대비 %

    -- ── 업소·유동인구 ───────────────────────────────────────────
    upso_cnt_dong  integer,                            -- 업소 수
    pop_day_avg    integer,                            -- 일평균 유동인구
    pop_many_day   varchar(10),                        -- 유동 최다 요일
    pop_many_time  varchar(20),                        -- 유동 최다 시간대

    -- ── 배달 (비중 %) ───────────────────────────────────────────
    baemin_cnt_avg   integer,                          -- 월평균 배달건수
    baemin_wkday_rt  numeric(5,1),
    baemin_wkend_rt  numeric(5,1),
    baemin_age20     numeric(5,1),
    baemin_age30     numeric(5,1),
    baemin_age40     numeric(5,1),
    baemin_age50     numeric(5,1),
    baemin_t2305     numeric(5,1),                     -- 23-05시 비중 등 시간대

    -- ── 파생 컬럼 (적재 시 물리화 — DAR-006 "미리 집계하여 적재") ──
    amt_per_store  numeric(14,1),                      -- 매출/업소수 (포화도)
    pop_per_store  numeric(14,1),                      -- 유동인구/업소수 (잠재수요)
    amt_vs_sgg     numeric(8,2),                       -- 시군구 평균 대비 배율
    amt_vs_sido    numeric(8,2),                       -- 시도 평균 대비 배율
    yoy_grade      varchar(4),                         -- 성장/유지/위축 (±10% 기준)
    rank_in_sgg    integer,                            -- 시군구 내 동종업종 매출 순위
    is_substituted boolean      NOT NULL DEFAULT false,-- 시군구 대체값 행 (랭킹 제외용)

    loaded_at      timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT pk_mart_simple PRIMARY KEY (crtr_ym, sido_nm, admi_nm, tpbiz_clscd),
    CONSTRAINT ck_yoy_grade CHECK (yoy_grade IS NULL OR yoy_grade IN ('성장','유지','위축'))
);

COMMENT ON TABLE  mart.mart_simple IS '간단분석 와이드 마트 — 행정동×업종×월 1행, Text-to-SQL 조회 대상 (조인 불필요)';
COMMENT ON COLUMN mart.mart_simple.is_substituted IS '업소 3개 이하 행정동은 시군구 대체값 제공 — 랭킹/통계 시 WHERE is_substituted=false 필수';
COMMENT ON COLUMN mart.mart_simple.amt_per_store IS '파생: amt_dong/upso_cnt_dong — "가게 하나당 벌이" 질의 대응';
COMMENT ON COLUMN mart.mart_simple.yoy_grade IS '파생: 전년비 +10%이상=성장, -10%이하=위축, 그 외 유지';

-- 자주 나올 질의 패턴용 인덱스 (업종별 랭킹 / 지역 조회)
CREATE INDEX IF NOT EXISTS ix_mart_simple_biz    ON mart.mart_simple (tpbiz_nm, crtr_ym) INCLUDE (amt_dong);
CREATE INDEX IF NOT EXISTS ix_mart_simple_region ON mart.mart_simple (sgg_nm, admi_nm);

-- ── AI용 데이터 사전 (DAR-006) — LLM 프롬프트에 주입할 컬럼 뜻풀이 ──
CREATE TABLE IF NOT EXISTS meta.data_dictionary (
    table_name   varchar(80)  NOT NULL,
    column_name  varchar(80)  NOT NULL,
    korean_name  varchar(100) NOT NULL,       -- 사람이 부르는 이름
    description  text         NOT NULL,       -- 의미·단위·주의사항
    synonyms     text[],                      -- 동의어 ("포화도" → amt_per_store)
    formula      text,                        -- 파생 컬럼 산출식
    biz_rule     text,                        -- 업무 규칙 (예: 극단 증감률 해석 가드레일)
    PRIMARY KEY (table_name, column_name)
);
COMMENT ON TABLE meta.data_dictionary IS 'AI용 데이터 사전 — Text-to-SQL 프롬프트의 스키마 설명 원천';

-- ── 적재 이력 (건수 대사 — DAR-009 무결성 검증의 최소 단위) ──
CREATE TABLE IF NOT EXISTS meta.load_history (
    load_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    target_table varchar(120) NOT NULL,
    source_file  varchar(300),
    row_count    bigint,
    started_at   timestamptz DEFAULT now(),
    finished_at  timestamptz,
    status       varchar(10) DEFAULT 'RUNNING',   -- RUNNING/OK/FAIL
    note         text
);
