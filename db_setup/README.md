# 로컬 개발 DB — PostgreSQL 16 + pgvector (Docker)

소상공인 AI 데이터 파트 개발용. 운영(Rocky Linux + PG16 + pgvector_16)과 동일 메이저 버전.
정형(mart, Text-to-SQL용)과 비정형(rag, 벡터 검색용)을 한 인스턴스에 스키마로 분리.

## 0. 사전 준비 (윈도우)
1. Docker Desktop 설치 — https://www.docker.com/products/docker-desktop/
   (설치 중 "Use WSL 2" 기본값 그대로. 설치 후 재부팅 1회)
2. 이 폴더(`db_setup`)를 아무 데나 두고 PowerShell로 이동

## 1. 실행
```powershell
cd C:\Users\USER\bigdata_sbiz\RAG\db_setup
docker compose up -d
docker compose logs -f db     # "database system is ready" 확인 후 Ctrl+C
```
init/ 폴더의 SQL 3개가 **최초 1회** 자동 실행된다 (01 확장·스키마 → 02 마트 → 03 RAG).
스키마를 고치고 처음부터 다시 만들려면: `docker compose down -v` 후 다시 `up -d`.

## 2. 접속 정보
| 항목 | 값 |
|---|---|
| Host / Port | localhost : 5432 |
| DB | sbizdb |
| 관리 계정 | sbiz / sbiz1234! (compose에서 변경) |
| 읽기전용 계정 | ai_reader / reader1234! (Text-to-SQL 에이전트용 — mart·rag·meta SELECT만) |

DBeaver 등 GUI로 붙거나: `docker compose exec db psql -U sbiz -d sbizdb`

## 3. 설치 검증
```sql
SELECT version();                                        -- PostgreSQL 16.x
SELECT extversion FROM pg_extension WHERE extname='vector';
\dn                                                      -- raw/stg/mart/rag/meta
-- 벡터 동작 스모크 테스트
SELECT '[1,2,3]'::vector(3) <=> '[3,2,1]'::vector(3) AS cosine_dist;
```

## 4. 구조 요약
```
raw   원천 무변형 (ELT Raw Zone)          ← xlsx/월배치 그대로
stg   스테이징 (정규화·검증·비식별 중간)
mart  mart_simple: 행정동×업종×월 와이드 테이블 + 파생컬럼 (조인 0회)
rag   document(문서 원장) ─┬─ chunk(청크+vector(1024))
                           ├─ HNSW 인덱스 (cosine, expired 제외 partial)
                           ├─ replace_document(): 문서 단위 통째 교체
                           └─ expire_closed_notices(): 공고 마감 배치
meta  data_dictionary(AI용 데이터 사전) + load_history(건수 대사)
```

## 5. 설계 근거 메모
- **vector(1024)** — Upstage `solar-embedding-2-passage/query` 1,024차원 (KT 가이드 확인).
  적재는 passage 모델, 질의는 query 모델 — 서로 다른 모델이지만 같은 벡터 공간.
- **HNSW + partial index** (`WHERE NOT expired`) — 만료 공고는 인덱스에서 제외되어
  "구버전 노출 차단"(DAR-007)이 검색 레이어 기본값이 됨.
- **expired/domain 을 chunk에 비정규화** — 벡터 검색 전에 메타 필터로 후보를 좁히는
  하이브리드 검색 패턴(SFR-004) 대응.
- **갱신 규칙** — 내용 변경=문서 단위 삭제 후 재적재(replace_document), 공고 마감=플래그만.
- **ai_reader 읽기전용** — SFR-003 SQL 가드레일(SELECT 외 차단, 허용 스키마 제한)의 DB 레벨 구현.
- 검색 시 정확도 조정: `SET hnsw.ef_search = 100;` (기본 40, 높일수록 recall↑ 속도↓)

## 6. 다음 단계
1. wide_table xlsx 30개 → 수치 정규화 → `mart.mart_simple` 적재 스크립트
2. `meta.data_dictionary` 채우기 (간단분석 보고서 샘플.xlsx 의 컬럼정의 시트가 출발점)
3. 법령 1종으로 파싱→청킹→임베딩→`rag.chunk` 적재 E2E 파이프라인 검증
4. 운영 반영 시: 이 init SQL을 Rocky Linux 서버(pgvector_16 설치 문서 절차)에서 그대로 실행
```
