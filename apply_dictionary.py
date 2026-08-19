# -*- coding: utf-8 -*-
"""
AI용 데이터 사전을 DB에 적용하는 스크립트.
  meta.data_dictionary  컬럼 사전 102개 (원천 98 + 적재 생성 4)
  meta.business_rules   업무 규칙 10개 (LLM 답변 가드레일)
  meta.query_examples   검증된 few-shot 예시 SQL 8개

사용법:
  conda activate sbiz
  python apply_dictionary.py            # 같은 폴더의 data_dictionary.sql 적용
재실행 안전 (DROP 후 재생성 방식 — 사전 수정 시 sql 고치고 다시 실행)
"""
import os
import sys

import psycopg2

DSN = os.environ.get("SBIZ_DSN", "postgresql://postgres:postgres@localhost:5432/postgres")
SQL_FILE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "data_dictionary.sql")

sql = open(SQL_FILE, encoding="utf-8").read()
conn = psycopg2.connect(DSN)
with conn.cursor() as cur:
    cur.execute(sql)
conn.commit()

with conn.cursor() as cur:
    for t in ["data_dictionary", "business_rules", "query_examples"]:
        cur.execute(f"SELECT count(*) FROM meta.{t}")
        print(f"meta.{t}: {cur.fetchone()[0]}건")
conn.close()
print("적용 완료")
