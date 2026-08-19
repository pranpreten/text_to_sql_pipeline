# -*- coding: utf-8 -*-
"""
상권 AI 질의 데모 — Text-to-SQL 파이프라인 (단일 파일)

실행:
  conda activate sbiz
  pip install fastapi uvicorn requests psycopg2-binary python-dotenv
  (.env 파일에 UPSTAGE_API_KEY 채우기)
  uvicorn app:app --reload --port 8000
  → 브라우저에서 http://localhost:8000

흐름 (질문 1건당):
  [1] 시스템 프롬프트 조립  ← DB의 데이터 사전 3종 (서버 시작 때 1회 로딩)
  [2] Solar 호출 #1         → 질문을 SQL로 변환
  [3] 가드레일 검사          → SELECT만·허용 테이블만·LIMIT 강제
  [4] DB 실행               → 결과 행 획득
  [5] Solar 호출 #2         → 결과를 한국어 답변으로 작성
"""
import os
import re
import json

import requests
import psycopg2
import psycopg2.extras
from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

# ── 설정 (.env에서 읽음) ─────────────────────────────────────────────
load_dotenv()
UPSTAGE_API_KEY = os.getenv("UPSTAGE_API_KEY", "")
UPSTAGE_URL = os.getenv("UPSTAGE_URL", "https://api.upstage.ai/v1/chat/completions")
MODEL = os.getenv("UPSTAGE_MODEL", "solar-pro4")
DSN = os.getenv("SBIZ_DSN", "postgresql://postgres:postgres@localhost:5432/postgres")

ALLOWED_TABLE = "clean.simple_analysis"   # LLM이 조회할 수 있는 유일한 테이블
MAX_ROWS = 50                              # 결과 행수 상한 (LIMIT 강제)

app = FastAPI(title="상권 AI 데모")


# ═════════════════════════════════════════════════════════════════════
# [1] 시스템 프롬프트 조립 — 데이터 사전 3종을 DB에서 읽어 텍스트로
# ═════════════════════════════════════════════════════════════════════
def build_system_prompt() -> str:
    conn = psycopg2.connect(DSN)
    cur = conn.cursor()

    # 1-1. 컬럼 사전 → "- 컬럼명: 설명 (동의어: ...)" 목록
    cur.execute("""SELECT column_name, korean_name, description, synonyms
                   FROM meta.data_dictionary ORDER BY grp, column_name""")
    col_lines = []
    for col, kor, desc, syn in cur.fetchall():
        line = f"- {col} ({kor}): {desc}"
        if syn:
            line += f" [동의어: {', '.join(syn)}]"
        col_lines.append(line)

    # 1-2. 업무 규칙 → 번호 목록
    cur.execute("SELECT rule_id, rule FROM meta.business_rules ORDER BY rule_id")
    rule_lines = [f"{rid}. {rule}" for rid, rule in cur.fetchall()]

    # 1-3. few-shot 예시 → 질문/SQL 쌍
    cur.execute("SELECT question, sql FROM meta.query_examples ORDER BY ex_id")
    ex_lines = [f"질문: {q}\nSQL: {s}" for q, s in cur.fetchall()]

    conn.close()

    # 1-4. 하나의 프롬프트로 합치기
    return f"""너는 소상공인 상권 데이터 분석가다.
사용자의 질문을 아래 테이블에 대한 PostgreSQL SELECT 쿼리 하나로 변환하라.

[테이블: {ALLOWED_TABLE}] — 행 1개 = 기준년월 x 행정동 x 업종 조합
{chr(10).join(col_lines)}

[반드시 지킬 규칙]
{chr(10).join(rule_lines)}

[예시]
{chr(10).join(ex_lines)}

[출력 형식]
- SQL 쿼리 딱 하나만 출력한다. 설명·마크다운·세미콜론 없이.
- 최신 데이터 기준 질문이면 crtr_ym=(SELECT max(crtr_ym) FROM {ALLOWED_TABLE}) 를 쓴다.
- 답할 수 없는 질문(예측, 개별 점포, 데이터 범위 밖)이면 SQL 대신 'IMPOSSIBLE: 이유'를 출력한다."""


SYSTEM_PROMPT = None  # 서버 시작 시 1회 채워짐 (아래 startup 참고)


@app.on_event("startup")
def startup():
    global SYSTEM_PROMPT
    SYSTEM_PROMPT = build_system_prompt()
    print(f"시스템 프롬프트 조립 완료 ({len(SYSTEM_PROMPT):,}자)")


# ═════════════════════════════════════════════════════════════════════
# [2]·[5] Solar 호출 — OpenAI 호환 chat/completions
# ═════════════════════════════════════════════════════════════════════
def call_solar(system: str, user: str) -> str:
    resp = requests.post(
        UPSTAGE_URL,
        headers={"Authorization": f"Bearer {UPSTAGE_API_KEY}"},
        json={
            "model": MODEL,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "temperature": 0,          # SQL 생성은 창의성 불필요 — 결정적으로
        },
        timeout=60,
    )
    resp.raise_for_status()
    return resp.json()["choices"][0]["message"]["content"].strip()


# ═════════════════════════════════════════════════════════════════════
# [3] 가드레일 — LLM이 짠 SQL을 실행 전에 검사
# ═════════════════════════════════════════════════════════════════════
FORBIDDEN = re.compile(
    r"\b(insert|update|delete|drop|alter|create|truncate|grant|copy)\b|;|--", re.I)


def check_sql(sql: str) -> str:
    """통과하면 정리된 SQL 반환, 문제 있으면 ValueError"""
    # 마크다운 코드펜스가 붙어오면 제거
    sql = re.sub(r"^```\w*|```$", "", sql.strip(), flags=re.M).strip()

    if sql.upper().startswith("IMPOSSIBLE"):
        raise ValueError(sql)                        # LLM이 스스로 거부한 경우
    if not sql.upper().startswith("SELECT"):
        raise ValueError("SELECT 쿼리가 아님")
    if FORBIDDEN.search(sql):
        raise ValueError("금지된 키워드 포함")
    if ALLOWED_TABLE not in sql:
        raise ValueError(f"허용 테이블({ALLOWED_TABLE}) 외 접근")
    if not re.search(r"\bLIMIT\s+\d+", sql, re.I):
        sql += f" LIMIT {MAX_ROWS}"                  # LIMIT 없으면 강제로 부착

    # 자동 교정: 문자(text) 타입 코드 컬럼을 숫자로 비교하면 따옴표를 붙여줌
    # (예: crtr_ym=202603 → crtr_ym='202603')  — text=integer 오류 방어
    sql = re.sub(r"\b(crtr_ym|sido_cd|sgg_cd|admi_cd|tpbiz_lclcd|tpbiz_mclcd|tpbiz_clscd)(\s*=\s*)(\d+)\b",
                 r"\1\2'\3'", sql, flags=re.I)
    return sql


# ═════════════════════════════════════════════════════════════════════
# [4] DB 실행
# ═════════════════════════════════════════════════════════════════════
def run_sql(sql: str) -> list[dict]:
    conn = psycopg2.connect(DSN)
    conn.set_session(readonly=True)                  # 이 연결로는 읽기만 가능
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute(f"SET statement_timeout = '10s'")    # 폭주 쿼리 10초 컷
    cur.execute(sql)
    rows = [dict(r) for r in cur.fetchmany(MAX_ROWS)]
    conn.close()
    return rows


# ═════════════════════════════════════════════════════════════════════
# API 엔드포인트 — 웹화면이 여기로 질문을 보냄
# ═════════════════════════════════════════════════════════════════════
class Ask(BaseModel):
    question: str


@app.post("/ask")
def ask(body: Ask):
    q = body.question.strip()
    try:
        # [2] 질문 → SQL
        sql_raw = call_solar(SYSTEM_PROMPT, q)
        # [3] 검사
        sql = check_sql(sql_raw)
        # [4] 실행
        rows = run_sql(sql)
        # [5] 결과 → 한국어 답변
        answer = call_solar(
            "너는 소상공인 상담 도우미다. 조회 결과만 근거로 간결하게 한국어로 답하라. "
            "수치는 단위(만원/명/개/%)를 붙이고, 데이터 기준 시점을 문장 끝에 밝혀라. "
            "결과가 비어 있으면 '해당 데이터가 없다'고 답하라. 추측·예측 금지.",
            f"질문: {q}\n\n조회 결과(JSON):\n{json.dumps(rows, ensure_ascii=False, default=str)}",
        )
        return {"ok": True, "question": q, "sql": sql, "rows": rows, "answer": answer}
    except ValueError as e:                          # 가드레일에 걸림 / LLM 거부
        return {"ok": False, "question": q, "error": str(e)}
    except Exception as e:                           # 그 외 (API·DB 오류)
        return {"ok": False, "question": q, "error": f"{type(e).__name__}: {e}"}


# ═════════════════════════════════════════════════════════════════════
# 웹화면 — 최소한의 단일 페이지 (질문 입력 → 답변/SQL/표 표시)
# ═════════════════════════════════════════════════════════════════════
PAGE = """<!DOCTYPE html>
<html lang="ko"><head><meta charset="UTF-8"><title>상권 AI 데모</title>
<style>
 body{font-family:'Malgun Gothic',sans-serif;max-width:800px;margin:30px auto;padding:0 16px}
 h1{font-size:20px} #q{width:75%;padding:10px;font-size:15px}
 button{padding:10px 18px;font-size:15px;cursor:pointer}
 .box{border:1px solid #ddd;border-radius:8px;padding:14px;margin:12px 0;white-space:pre-wrap}
 .sql{background:#f6f8fa;font-family:Consolas,monospace;font-size:13px}
 table{border-collapse:collapse;font-size:13px;margin-top:8px}
 td,th{border:1px solid #ddd;padding:4px 8px}
 .dim{color:#888;font-size:13px}
</style></head><body>
<h1>상권 AI 데모 <span class="dim">(clean.simple_analysis · 2026.03~05 전국)</span></h1>
<input id="q" placeholder="예: 서울에서 치킨 장사 제일 잘되는 동네 어디야?">
<button onclick="ask()">질문</button>
<div id="out"></div>
<script>
async function ask(){
  const q = document.getElementById('q').value;
  const out = document.getElementById('out');
  out.innerHTML = '<div class="box">생각 중...</div>';
  const r = await fetch('/ask', {method:'POST',
    headers:{'Content-Type':'application/json'}, body:JSON.stringify({question:q})});
  const d = await r.json();
  if(!d.ok){ out.innerHTML = '<div class="box">답변 불가: '+d.error+'</div>'; return; }
  let table = '';
  if(d.rows.length){
    const cols = Object.keys(d.rows[0]);
    table = '<table><tr>'+cols.map(c=>'<th>'+c+'</th>').join('')+'</tr>'
      + d.rows.map(r=>'<tr>'+cols.map(c=>'<td>'+(r[c]??'')+'</td>').join('')+'</tr>').join('')
      + '</table>';
  }
  out.innerHTML = '<div class="box"><b>답변</b><br>'+d.answer+'</div>'
    + '<div class="box sql"><b>생성된 SQL</b><br>'+d.sql+'</div>'
    + '<div class="box"><b>조회 결과 '+d.rows.length+'행</b>'+table+'</div>';
}
document.getElementById('q').addEventListener('keydown', e=>{if(e.key==='Enter')ask()});
</script></body></html>"""


@app.get("/", response_class=HTMLResponse)
def home():
    return PAGE
