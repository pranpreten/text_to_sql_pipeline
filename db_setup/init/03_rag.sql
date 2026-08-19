-- =====================================================================
-- 03. 비정형 — RAG (문서 / 청크 / 벡터)
-- 근거: 내부 설계 "벡터DB구축_구조정리" —
--   · 청크 1개 = 행 1개, 문서 = document_id 묶음
--   · 메타데이터 = 공통층 + 유형별층(법령/공고/보고서)
--   · 갱신 = 문서 단위 삭제 후 재적재 / 공고 마감 = expired 플래그만
-- 임베딩: Upstage solar-embedding-2-passage/query = 1,024차원 (KT 가이드 확인)
-- =====================================================================

-- ── 문서 원장 ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rag.document (
    document_id   varchar(120) PRIMARY KEY,       -- 예: 공고-2026-0412, 법령-소상공인기본법
    domain        varchar(20)  NOT NULL,          -- law / notice / report (컬렉션 구분)
    title         text         NOT NULL,
    source_url    text,                           -- 출처 링크 (답변 하단 표기용)
    file_hash     char(64),                       -- SHA-256 — 변경 감지
    version       integer      NOT NULL DEFAULT 1,
    expired       boolean      NOT NULL DEFAULT false,  -- 검색 노출 차단 스위치
    raw_json      jsonb,                          -- Document Parse 원본 결과 (원형 보관)
    doc_meta      jsonb        NOT NULL DEFAULT '{}'::jsonb,  -- 유형별층
    ingested_at   timestamptz  NOT NULL DEFAULT now(),
    updated_at    timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT ck_domain CHECK (domain IN ('law','notice','report'))
);

COMMENT ON TABLE rag.document IS '문서 원장 — 갱신·만료의 관리 단위. 내용 변경 시 이 문서의 청크 전부 삭제 후 재적재';
COMMENT ON COLUMN rag.document.doc_meta IS
  '유형별 메타 — law: {법령명,시행일,개정일} / notice: {사업명,지역,업종,신청시작일,마감일} / report: {발행기관,발행일}';

-- ── 청크 (벡터 + 원문 조각 + 메타) ────────────────────────────────
CREATE TABLE IF NOT EXISTS rag.chunk (
    chunk_id     varchar(150) PRIMARY KEY,        -- 예: 0412_c01
    document_id  varchar(120) NOT NULL REFERENCES rag.document(document_id) ON DELETE CASCADE,
    chunk_index  integer      NOT NULL,           -- 문서 내 순번
    chunk_text   text         NOT NULL,           -- 원문 조각
    chunk_meta   jsonb        NOT NULL DEFAULT '{}'::jsonb,
        -- 검색 필터·출처 표기용: law={조번호,항번호,조제목} / notice={목차항목} / report={챕터,페이지}
    domain       varchar(20)  NOT NULL,           -- document.domain 비정규화 (필터 속도)
    expired      boolean      NOT NULL DEFAULT false,  -- document.expired 비정규화
    embedding    vector(1024),                    -- solar-embedding-2-passage
    token_count  integer,
    created_at   timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT uq_chunk UNIQUE (document_id, chunk_index)
);

COMMENT ON TABLE rag.chunk IS '청크 1행 = 검색 최소 단위. expired/domain은 검색 필터 성능 위해 문서에서 비정규화';

-- ── 인덱스 ────────────────────────────────────────────────────────
-- 벡터 검색 (코사인). 유효 문서만 대상 → partial index
CREATE INDEX IF NOT EXISTS ix_chunk_hnsw
    ON rag.chunk USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64)
    WHERE NOT expired;

-- 메타 필터 (도메인·문서)
CREATE INDEX IF NOT EXISTS ix_chunk_domain ON rag.chunk (domain) WHERE NOT expired;
CREATE INDEX IF NOT EXISTS ix_chunk_doc    ON rag.chunk (document_id);
CREATE INDEX IF NOT EXISTS ix_chunk_meta   ON rag.chunk USING gin (chunk_meta jsonb_path_ops);

-- 키워드 보조 검색 (하이브리드용 — 한국어 형태소 분석기 없이 trigram 부분일치)
CREATE INDEX IF NOT EXISTS ix_chunk_trgm   ON rag.chunk USING gin (chunk_text gin_trgm_ops);

-- ── 문서 교체(갱신) 헬퍼 — "문서 단위 통째 교체가 표준" ──────────
CREATE OR REPLACE FUNCTION rag.replace_document(p_document_id varchar)
RETURNS void LANGUAGE sql AS $$
    DELETE FROM rag.chunk WHERE document_id = p_document_id;
    UPDATE rag.document
       SET version = version + 1, updated_at = now()
     WHERE document_id = p_document_id;
$$;
COMMENT ON FUNCTION rag.replace_document IS '기존 청크 삭제 + 버전 증가. 이후 파싱→청킹→임베딩 재수행하여 INSERT';

-- ── 공고 마감 배치 (DAR-010 자동 동기화의 만료 트리거) ────────────
CREATE OR REPLACE FUNCTION rag.expire_closed_notices()
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n integer;
BEGIN
    UPDATE rag.document d
       SET expired = true, updated_at = now()
     WHERE d.domain = 'notice'
       AND NOT d.expired
       AND (d.doc_meta->>'마감일')::date < CURRENT_DATE;
    GET DIAGNOSTICS n = ROW_COUNT;
    UPDATE rag.chunk c SET expired = true
      FROM rag.document d
     WHERE c.document_id = d.document_id AND d.expired AND NOT c.expired;
    RETURN n;
END $$;
COMMENT ON FUNCTION rag.expire_closed_notices IS '마감일 지난 공고 expired=true (재임베딩 불필요, 가장 가벼운 갱신). 배치로 매일 호출';

-- ── 검색 예시 뷰 (에코아이티 인계용 참고 — Top-K 코사인) ──────────
-- SELECT chunk_id, document_id, chunk_text,
--        1 - (embedding <=> :query_vec) AS score
--   FROM rag.chunk
--  WHERE NOT expired AND domain = :domain      -- 메타 필터 먼저
--  ORDER BY embedding <=> :query_vec
--  LIMIT 3;
