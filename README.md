# 소상공인 데이터 Text-to-SQL 파이프라인

소상공인 관련 정형 데이터를 PostgreSQL에 적재하고 데이터 사전을 이용해 자연어 질문을 SQL 조회로 연결하는 프로젝트다. 생성 SQL, 조회 결과와 답변을 웹 화면에서 함께 확인할 수 있다.

## 처리 흐름

`원천 CSV → 정제·적재 → 데이터 사전과 업무 규칙 → 자연어 질문 → Solar SQL 생성 → SQL 검사·조회 → 답변`

조회용 앱과 데이터를 준비하는 적재 도구를 구분한다. 앱의 SQL 검사는 허용된 조회 범위를 검사하고, 실제 DB 접근 권한과 읽기 전용 설정을 함께 사용하도록 구성되어 있다.

## 주요 파일

| 경로 | 역할 |
|---|---|
| `app/app.py` | FastAPI 질의응답 앱과 SQL 검사·조회 |
| `app/test_questions.py` | 예제 질문 확인 코드 |
| `db_setup/docker-compose.yml` | 로컬 PostgreSQL 개발 환경 |
| `db_setup/init/` | 확장·스키마·마트·RAG 초기 SQL |
| `load_csv.py` | CSV 정규화와 적재 |
| `load_wide_table.py` | 와이드 테이블 적재 |
| `data_dictionary.sql` | 데이터 사전·업무 규칙·질의 예제 |
| `apply_dictionary.py` | 데이터 사전 SQL 적용 |
| `데이터품질관련/` | 평가·품질 점검 자료 |

## 준비할 것

- PostgreSQL과 필요한 스키마·테이블, 실제 조회 데이터
- Upstage API 키와 사용할 모델 설정
- 적재용 계정과 조회용 계정의 연결 정보
- 적재 스크립트가 기대하는 원천 CSV·엑셀 자료

DB 초기 SQL만 실행하면 실제 상권 데이터까지 채워지는 것은 아니다. `db_setup/`의 초기 설계와 앱이 실제 참조하는 테이블·사전 컬럼이 맞는지 확인하고 적재를 완료해야 한다. 원천 데이터 전체와 실행 중인 DB는 저장소만으로 제공되지 않는다.

## 실행 방법

새 로컬 개발 DB를 준비하는 경우 저장소 루트에서 다음 명령을 사용한다.

```powershell
docker compose -f db_setup/docker-compose.yml up -d
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install fastapi uvicorn requests psycopg2-binary python-dotenv pandas openpyxl
```

연결 계정·암호·DB 이름은 현재 Docker 설정과 일치시킨다. 데이터 준비는 각 적재 스크립트의 입력 경로를 맞춘 뒤 수행한다. `apply_dictionary.py`는 사전 객체를 재생성하므로 기존 DB에 적용하기 전에 대상 스키마를 확인한다.

조회용 환경변수를 설정하고 앱을 실행한다.

```powershell
$env:UPSTAGE_API_KEY = "본인_API_키"
$env:SBIZ_DSN = "postgresql://조회계정:암호@localhost:5432/DB이름"
.\.venv\Scripts\python.exe -m uvicorn app.app:app --host 127.0.0.1 --port 8000
```

`http://localhost:8000`에서 질문을 입력한다. 모델 설정은 `UPSTAGE_MODEL`, API 주소는 `UPSTAGE_URL`로 지정할 수 있다. API 키와 DB 암호는 환경변수 또는 로컬 설정으로 관리한다.

## 결과 확인과 한계

화면에서 자연어 답변, 생성 SQL, 결과 행을 함께 확인한다. SQL 문법이 맞아도 지역·업종·기간·집계 기준의 해석이 틀릴 수 있으므로 데이터 사전과 실제 결과를 대조해야 한다. 전체 데이터베이스를 자동 이해하는 범용 서비스가 아니라 준비한 사전·스키마·데이터 범위의 실험 앱이다.

---

[GitHub 저장소](https://github.com/pranpreten/text_to_sql_pipeline) · [문서 작성 기준 코드](https://github.com/pranpreten/text_to_sql_pipeline/tree/30a1e18dc8e4478902d3e46088ea6a08f016c2ca)
