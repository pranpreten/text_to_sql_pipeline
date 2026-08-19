# -*- coding: utf-8 -*-
"""
클라비 간단분석 wide_table xlsx → PostgreSQL 적재 스크립트

두 층으로 적재한다:
  raw.simple_analysis   : 원형 그대로 (전부 TEXT — ELT 원칙, 원본 보존)
  clean.simple_analysis : 전처리 완료 (단위 제거·수치화·집계행 구분 플래그)

전처리 규칙:
  1. "2,535 만원" / "132,263명" / "0 개" / "27.2%"  → 숫자 (단위·콤마 제거)
  2. "-", "- 만원", "- %", 빈값                       → NULL
  3. grain 컬럼 생성: dong(행정동) / sgg(시군구 집계행) / sido(시도 집계행)
     ※ 원천 파일에 세 단위 행이 섞여 있음 — 랭킹·집계 시 WHERE grain='dong' 필수
  4. is_substituted: 업소 3개 이하 행정동은 시군구 대체값 제공(원천 정책)
     → 동 단위인데 upso_count_dong<=3 이면 true (랭킹 왜곡 방지 필터용)

사용법:
  pip install pandas openpyxl psycopg2-binary
  python load_wide_table.py "C:/Users/USER/bigdata_sbiz/샘플데이터/wide_table"
  (DB 접속은 아래 DSN 수정 또는 환경변수 SBIZ_DSN)
"""
import io
import os
import re
import sys
import glob
import time

import pandas as pd
import psycopg2

DSN = os.environ.get("SBIZ_DSN", "postgresql://postgres:postgres@localhost:5432/postgres")

# ── 컬럼 분류 ──────────────────────────────────────────────────────
TEXT_COLS = {
    "CRTR_YM", "SIDO_CD", "SIDO_NM", "SGG_CD", "SGG_NM", "ADMI_CD", "ADMI_NM",
    "TPBIZ_LCLCD", "TPBIZ_LCLCD_NM", "TPBIZ_MCLCD", "TPBIZ_MCLCD_NM",
    "TPBIZ_CLSCD", "TPBIZ_CLSCD_NM",
    "SIMPLE_INFO_MANY_DAY_POP", "SIMPLE_INFO_MANY_TIME_POP",
    "SIMPLE_INFO_EXPLAN", "AMT_EXPLAN", "BAEMIN_EXPLAN", "UPSO_EXPLAN", "POP_EXPLAN",
    "SANGWON1_DONG", "SANGWON2_DONG", "SANGWON3_DONG", "SANGWON4_DONG", "SANGWON5_DONG",
    "RGN_CD",
}
# 나머지 컬럼은 전부 수치로 정제 (만원/개/명/% 단위 혼재)

NUM_RE = re.compile(r"^-?\d[\d,]*\.?\d*$")

# 시도명 표준화 — 원천이 약칭/정식명칭 혼용 (30개 파일 전수 스캔으로 확인된 16종 전부)
SIDO_STD = {
    "경기": "경기도", "충북": "충청북도", "충남": "충청남도",
    "경북": "경상북도", "경남": "경상남도",
    # 나머지 11종은 정식명칭으로 들어있음 (서울특별시, 전남광주통합특별시 등) — 그대로 유지
}


def to_number(v):
    """'2,535 만원' → 2535.0 / '-' → None / '27.2%' → 27.2 / 14212 → 14212.0"""
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    s = str(v).strip()
    if s in ("", "-", "–"):
        return None
    # 단위·공백 제거
    s = re.sub(r"(만원|명|개|%|건)", "", s).replace(",", "").strip()
    if s in ("", "-", "–"):
        return None
    return float(s) if NUM_RE.match(s) else None


def load_file(path: str, conn) -> tuple[int, int]:
    df = pd.read_excel(path, dtype=str)          # 전부 문자열로 읽음 (원형 보존)
    df.columns = [c.strip().upper() for c in df.columns]
    cols = list(df.columns)

    # ── raw 층: 그대로 ──────────────────────────────────────────
    buf = io.StringIO()
    df.to_csv(buf, index=False, header=False)
    buf.seek(0)
    with conn.cursor() as cur:
        cur.copy_expert(
            f'COPY raw.simple_analysis ({",".join(c.lower() for c in cols)}, source_file) '
            f"FROM STDIN WITH (FORMAT csv, NULL '')",
            _append_const(buf, os.path.basename(path)),
        )
        raw_n = cur.rowcount

    # ── clean 층: 수치화 + 플래그 ────────────────────────────────
    cdf = pd.DataFrame()
    for c in cols:
        if c in TEXT_COLS:
            cdf[c.lower()] = df[c].where(df[c].notna() & (df[c].str.strip() != "") & (df[c].str.strip() != "-"), None)
        else:
            cdf[c.lower()] = df[c].map(to_number)

    cdf["sido_nm_std"] = df["SIDO_NM"].str.strip().map(lambda v: SIDO_STD.get(v, v))

    admi = df["ADMI_NM"].fillna("").str.strip()
    sgg = df["SGG_NM"].fillna("").str.strip()
    cdf["grain"] = "dong"
    cdf.loc[admi == "", "grain"] = "sgg"
    cdf.loc[(admi == "") & (sgg == ""), "grain"] = "sido"

    upso = cdf["upso_count_dong"]
    cdf["is_substituted"] = (cdf["grain"] == "dong") & upso.notna() & (upso <= 3)
    cdf["source_file"] = os.path.basename(path)

    buf2 = io.StringIO()
    cdf.to_csv(buf2, index=False, header=False)
    buf2.seek(0)
    with conn.cursor() as cur:
        cur.copy_expert(
            f'COPY clean.simple_analysis ({",".join(cdf.columns)}) '
            f"FROM STDIN WITH (FORMAT csv, NULL '')",
            buf2,
        )
        clean_n = cur.rowcount

    conn.commit()
    return raw_n, clean_n


def _append_const(buf: io.StringIO, const: str) -> io.StringIO:
    """CSV 각 행 끝에 source_file 상수 컬럼 추가"""
    out = io.StringIO()
    for line in buf:
        out.write(line.rstrip("\n") + f",{const}\n")
    out.seek(0)
    return out


def ensure_tables(conn, sample_path: str):
    df = pd.read_excel(sample_path, nrows=1, dtype=str)
    cols = [c.strip().upper() for c in df.columns]
    raw_cols = ",\n".join(f"    {c.lower()} text" for c in cols)
    clean_cols = ",\n".join(
        f"    {c.lower()} text" if c in TEXT_COLS else f"    {c.lower()} numeric"
        for c in cols
    )
    with conn.cursor() as cur:
        cur.execute("CREATE SCHEMA IF NOT EXISTS raw; CREATE SCHEMA IF NOT EXISTS clean;")
        cur.execute(f"""
            CREATE TABLE IF NOT EXISTS raw.simple_analysis (
{raw_cols},
    source_file text,
    loaded_at timestamptz DEFAULT now()
            );""")
        cur.execute(f"""
            CREATE TABLE IF NOT EXISTS clean.simple_analysis (
{clean_cols},
    sido_nm_std text,                   -- 시도명 표준화 (약칭 '경기'→'경기도' 등)
    grain varchar(4) NOT NULL,          -- dong / sgg / sido (집계행 구분)
    is_substituted boolean NOT NULL,    -- 업소 3개 이하 → 시군구 대체값 행
    source_file text
            );""")
        cur.execute("""
            CREATE INDEX IF NOT EXISTS ix_clean_key
                ON clean.simple_analysis (crtr_ym, tpbiz_clscd, grain);
            CREATE INDEX IF NOT EXISTS ix_clean_region
                ON clean.simple_analysis (sgg_nm, admi_nm);
        """)
    conn.commit()


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else "."
    files = sorted(glob.glob(os.path.join(folder, "클라비*part*.xlsx")))
    if not files:
        print(f"xlsx 파일 없음: {folder}")
        sys.exit(1)
    print(f"대상 파일 {len(files)}개 / DB: {DSN.split('@')[-1]}")

    conn = psycopg2.connect(DSN)
    ensure_tables(conn, files[0])

    total_raw = total_clean = 0
    t0 = time.time()
    for i, f in enumerate(files, 1):
        t = time.time()
        r, c = load_file(f, conn)
        total_raw += r
        total_clean += c
        print(f"[{i:2d}/{len(files)}] {os.path.basename(f)}  raw {r:,} / clean {c:,}  ({time.time()-t:.1f}s)")

    # 검증 요약
    with conn.cursor() as cur:
        cur.execute("""
            SELECT grain, count(*), count(*) FILTER (WHERE is_substituted)
              FROM clean.simple_analysis GROUP BY grain ORDER BY grain;
        """)
        print("\n[적재 검증] grain별 행수 / 대체값 행수")
        for g, n, s in cur.fetchall():
            print(f"  {g:5s} {n:>10,} {s:>10,}")
        cur.execute("SELECT count(DISTINCT crtr_ym), count(DISTINCT sido_nm), count(DISTINCT tpbiz_clscd) FROM clean.simple_analysis;")
        ym, sido, biz = cur.fetchone()
        print(f"  기준월 {ym}종 / 시도 {sido}개 / 업종 {biz}종")
    conn.close()
    print(f"\n완료 — raw {total_raw:,}행 / clean {total_clean:,}행 ({(time.time()-t0)/60:.1f}분)")


if __name__ == "__main__":
    main()
