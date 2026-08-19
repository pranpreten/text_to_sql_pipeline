# -*- coding: utf-8 -*-
"""
클라비 간단분석 CSV(엑셀에서 시트별 저장한 3개 파일) → PostgreSQL 적재

대상: csv변환 폴더의 *.csv 3개 (Result 1/2/3 시트를 CSV UTF-8로 저장한 것)
  ※ 파일명의 월과 실제 내용은 다를 수 있음(시트 경계에서 월이 섞임) — 무관.
     스크립트는 파일명이 아니라 데이터의 CRTR_YM 값으로 처리함.

적재 구조 (기존 load_wide_table.py와 동일):
  raw.simple_analysis   원본 문자열 그대로 (전부 TEXT)
  clean.simple_analysis 전처리 완료 — 단위제거·수치화 / "-"→NULL /
                        grain(dong·sgg·sido) / is_substituted / sido_nm_std

사용법:
  conda activate sbiz
  python load_csv.py "C:/Users/USER/bigdata_sbiz/샘플데이터/csv변환"

다시 처음부터: psql에서 TRUNCATE raw.simple_analysis, clean.simple_analysis; 후 재실행
"""
import glob
import io
import os
import re
import sys
import time

import pandas as pd
import psycopg2

DSN = os.environ.get("SBIZ_DSN", "postgresql://postgres:postgres@localhost:5432/postgres")
CHUNK = 100_000

TEXT_COLS = {
    "CRTR_YM", "SIDO_CD", "SIDO_NM", "SGG_CD", "SGG_NM", "ADMI_CD", "ADMI_NM",
    "TPBIZ_LCLCD", "TPBIZ_LCLCD_NM", "TPBIZ_MCLCD", "TPBIZ_MCLCD_NM",
    "TPBIZ_CLSCD", "TPBIZ_CLSCD_NM",
    "SIMPLE_INFO_MANY_DAY_POP", "SIMPLE_INFO_MANY_TIME_POP",
    "SIMPLE_INFO_EXPLAN", "AMT_EXPLAN", "BAEMIN_EXPLAN", "UPSO_EXPLAN", "POP_EXPLAN",
    "SANGWON1_DONG", "SANGWON2_DONG", "SANGWON3_DONG", "SANGWON4_DONG", "SANGWON5_DONG",
    "RGN_CD",
}
NUM_RE = re.compile(r"^-?\d[\d,]*\.?\d*$")
SIDO_STD = {"경기": "경기도", "충북": "충청북도", "충남": "충청남도",
            "경북": "경상북도", "경남": "경상남도"}


def to_number(v):
    if v is None:
        return None
    s = str(v).strip()
    if s in ("", "-", "–"):
        return None
    s = re.sub(r"(만원|명|개|%|건)", "", s).replace(",", "").strip()
    if s in ("", "-", "–"):
        return None
    return float(s) if NUM_RE.match(s) else None


def ensure_tables(conn, cols):
    raw_cols = ",\n".join(f"    {c.lower()} text" for c in cols)
    clean_cols = ",\n".join(
        f"    {c.lower()} text" if c in TEXT_COLS else f"    {c.lower()} numeric" for c in cols)
    with conn.cursor() as cur:
        cur.execute("CREATE SCHEMA IF NOT EXISTS raw; CREATE SCHEMA IF NOT EXISTS clean;")
        cur.execute(f"CREATE TABLE IF NOT EXISTS raw.simple_analysis (\n{raw_cols},\n"
                    "    source_file text,\n    loaded_at timestamptz DEFAULT now());")
        cur.execute(f"CREATE TABLE IF NOT EXISTS clean.simple_analysis (\n{clean_cols},\n"
                    "    sido_nm_std text,\n    grain varchar(4) NOT NULL,\n"
                    "    is_substituted boolean NOT NULL,\n    source_file text);")
        cur.execute("CREATE INDEX IF NOT EXISTS ix_clean_key ON clean.simple_analysis (crtr_ym, tpbiz_clscd, grain);"
                    "CREATE INDEX IF NOT EXISTS ix_clean_region ON clean.simple_analysis (sgg_nm, admi_nm);")
    conn.commit()


def copy_df(cur, df, table, cols):
    buf = io.StringIO()
    df.to_csv(buf, index=False, header=False)
    buf.seek(0)
    cur.copy_expert(f'COPY {table} ({",".join(cols)}) FROM STDIN WITH (FORMAT csv, NULL \'\')', buf)


def load_file(path, conn):
    label = os.path.basename(path)
    total = 0
    reader = pd.read_csv(path, dtype=str, chunksize=CHUNK, encoding="utf-8-sig",
                         keep_default_na=False, na_values=[])
    header_cols = None
    for chunk in reader:
        if header_cols is None:
            header_cols = [c.strip().upper() for c in chunk.columns]
            chunk.columns = header_cols
            ensure_tables(conn, header_cols)
        else:
            chunk.columns = header_cols
        # 혹시 섞여 들어온 중복 헤더행 제거
        chunk = chunk[chunk["CRTR_YM"] != "CRTR_YM"]
        if chunk.empty:
            continue

        with conn.cursor() as cur:
            rdf = chunk.replace("", None).copy()
            rdf["source_file"] = label
            copy_df(cur, rdf, "raw.simple_analysis",
                    [c.lower() for c in header_cols] + ["source_file"])

            cdf = pd.DataFrame()
            for c in header_cols:
                col = chunk[c].replace("", None)
                if c in TEXT_COLS:
                    cdf[c.lower()] = col.map(lambda v: None if v is not None and str(v).strip() == "-" else v)
                else:
                    cdf[c.lower()] = col.map(to_number)
            cdf["sido_nm_std"] = chunk["SIDO_NM"].str.strip().map(lambda v: SIDO_STD.get(v, v))
            admi = chunk["ADMI_NM"].fillna("").str.strip()
            sgg = chunk["SGG_NM"].fillna("").str.strip()
            cdf["grain"] = "dong"
            cdf.loc[admi == "", "grain"] = "sgg"
            cdf.loc[(admi == "") & (sgg == ""), "grain"] = "sido"
            upso = cdf["upso_count_dong"]
            cdf["is_substituted"] = (cdf["grain"] == "dong") & upso.notna() & (upso <= 3)
            cdf["source_file"] = label
            copy_df(cur, cdf, "clean.simple_analysis", list(cdf.columns))
        conn.commit()
        total += len(chunk)
        print(f"  {label}: 누적 {total:,}행", flush=True)
    return total


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else "."
    files = sorted(glob.glob(os.path.join(folder, "*.csv")))
    files = [f for f in files if os.path.getsize(f) > 0]
    if not files:
        print(f"CSV 없음: {folder}"); sys.exit(1)
    print(f"대상 {len(files)}개: {[os.path.basename(f) for f in files]}")
    for f in glob.glob(os.path.join(folder, "*.csv")):
        if os.path.getsize(f) == 0:
            print(f"⚠ 0바이트 파일 건너뜀: {os.path.basename(f)} — 다시 저장 필요!")

    conn = psycopg2.connect(DSN)
    t0 = time.time(); total = 0
    for f in files:
        total += load_file(f, conn)

    with conn.cursor() as cur:
        cur.execute("""SELECT crtr_ym, count(DISTINCT sido_nm) sido, count(*) rows,
                              count(*) FILTER (WHERE grain='dong') dong,
                              count(*) FILTER (WHERE is_substituted) sub
                       FROM clean.simple_analysis GROUP BY crtr_ym ORDER BY 1;""")
        print("\n[적재 검증] 월 | 시도수 | 전체행 | 동행 | 대체값행")
        for r in cur.fetchall():
            print(f"  {r[0]} | {r[1]:>2} | {r[2]:>9,} | {r[3]:>9,} | {r[4]:>9,}")
        cur.execute("""SELECT count(*) FROM (SELECT crtr_ym, sido_cd, admi_cd, tpbiz_clscd
                       FROM clean.simple_analysis WHERE grain='dong'
                       GROUP BY 1,2,3,4 HAVING count(*)>1) d;""")
        print(f"  중복 키: {cur.fetchone()[0]}건 (0이어야 정상)")
    conn.close()
    print(f"\n완료 — {total:,}행 ({(time.time()-t0)/60:.1f}분)")


if __name__ == "__main__":
    main()
