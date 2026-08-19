# -*- coding: utf-8 -*-
"""
평가용 모범답안지 생성기 — 질문 10개 + 검증된 SQL로 정답을 DB에서 직접 출력

사용법:
  conda activate sbiz
  python test_questions.py
출력된 정답을 보고, 웹데모(localhost:8000)에 같은 질문을 던져서
  ① 생성된 SQL이 비슷한 논리인가  ② 답변 수치가 일치하는가  를 비교.

Q10은 함정 질문 — 정답이 "답변 거부"인 케이스 (개별 점포 조회 불가 규칙).
"""
import os
import psycopg2

DSN = os.environ.get("SBIZ_DSN", "postgresql://postgres:postgres@localhost:5432/postgres")

# (질문, 정답 SQL, 채점 포인트)
TESTS = [
 ("Q1. 명동에서 치킨집 하는데 요즘 어때요?",
  """SELECT crtr_ym, amt_dong, amt_sgg, amt_on_year, upso_count_dong, pop_month_avg_cnt
     FROM clean.simple_analysis
     WHERE admi_nm='명동' AND tpbiz_clscd_nm='치킨' AND grain='dong'
       AND crtr_ym=(SELECT max(crtr_ym) FROM clean.simple_analysis)""",
  "최신월 기준, 매출·전년비·업소수·유동인구가 답변에 있어야"),

 ("Q2. 서울에서 치킨 장사 제일 잘되는 동네 3곳은?",
  """SELECT sgg_nm, admi_nm, amt_dong
     FROM clean.simple_analysis
     WHERE sido_nm_std='서울특별시' AND tpbiz_clscd_nm='치킨'
       AND grain='dong' AND is_substituted=false
       AND crtr_ym=(SELECT max(crtr_ym) FROM clean.simple_analysis)
     ORDER BY amt_dong DESC NULLS LAST LIMIT 3""",
  "SQL에 sido_nm_std + is_substituted=false 필터가 있는지"),

 ("Q3. 전국에서 카페 매출 1등 동네는 어디야?",
  """SELECT sido_nm_std, sgg_nm, admi_nm, amt_dong
     FROM clean.simple_analysis
     WHERE tpbiz_clscd_nm='카페' AND grain='dong' AND is_substituted=false
       AND crtr_ym=(SELECT max(crtr_ym) FROM clean.simple_analysis)
     ORDER BY amt_dong DESC NULLS LAST LIMIT 1""",
  "전국 = 시도 필터 없음. 합계행(grain) 안 섞였는지"),

 ("Q4. 구의1동에서 치킨이랑 카페 중 뭐가 나아?",
  """SELECT tpbiz_clscd_nm, amt_dong, upso_count_dong
     FROM clean.simple_analysis
     WHERE admi_nm='구의1동' AND tpbiz_clscd_nm IN ('치킨','카페') AND grain='dong'
       AND crtr_ym=(SELECT max(crtr_ym) FROM clean.simple_analysis)""",
  "두 업종을 한 쿼리로 비교, 매출+업소수 함께 언급"),

 ("Q5. 서울에서 유동인구는 10만 넘는데 치킨집이 3개 이하인 동네 있어?",
  """SELECT sgg_nm, admi_nm, pop_month_avg_cnt, upso_count_dong
     FROM clean.simple_analysis
     WHERE sido_nm_std='서울특별시' AND tpbiz_clscd_nm='치킨' AND grain='dong'
       AND pop_month_avg_cnt>=100000 AND upso_count_dong BETWEEN 1 AND 3
       AND crtr_ym=(SELECT max(crtr_ym) FROM clean.simple_analysis)
     ORDER BY pop_month_avg_cnt DESC LIMIT 5""",
  "역질의. 이 질문은 업소 1~3 조건이라 is_substituted 필터를 빼야 정상"),

 ("Q6. 서울에서 작년보다 치킨 장사가 제일 나빠진 동네 3곳은?",
  """SELECT sgg_nm, admi_nm, amt_on_year
     FROM clean.simple_analysis
     WHERE sido_nm_std='서울특별시' AND tpbiz_clscd_nm='치킨'
       AND grain='dong' AND is_substituted=false AND amt_on_year IS NOT NULL
       AND crtr_ym=(SELECT max(crtr_ym) FROM clean.simple_analysis)
     ORDER BY amt_on_year ASC LIMIT 3""",
  "하락 = 오름차순 정렬. NULL 제외했는지"),

 ("Q7. 서울에서 카페 가게 하나당 벌이가 제일 좋은 동네는? (업소 5개 이상)",
  """SELECT sgg_nm, admi_nm, ROUND(amt_dong/NULLIF(upso_count_dong,0),1) AS amt_per_store
     FROM clean.simple_analysis
     WHERE sido_nm_std='서울특별시' AND tpbiz_clscd_nm='카페'
       AND grain='dong' AND is_substituted=false AND upso_count_dong>=5
       AND crtr_ym=(SELECT max(crtr_ym) FROM clean.simple_analysis)
     ORDER BY amt_per_store DESC NULLS LAST LIMIT 3""",
  "파생 계산(매출÷업소수)을 SQL에서 하는지"),

 ("Q8. 20대 상대로 카페 배달하려면 서울 어디가 좋아?",
  """SELECT sgg_nm, admi_nm, baemin_age_20
     FROM clean.simple_analysis
     WHERE sido_nm_std='서울특별시' AND tpbiz_clscd_nm='카페' AND grain='dong'
       AND baemin_age_20 IS NOT NULL
       AND crtr_ym=(SELECT max(crtr_ym) FROM clean.simple_analysis)
     ORDER BY baemin_age_20 DESC LIMIT 3""",
  "배달 컬럼 사용 + NULL 제외 (배달 결측 90%)"),

 ("Q9. 명동 치킨 매출이 3월부터 5월까지 어떻게 변했어?",
  """SELECT crtr_ym, amt_dong, amt_on_month
     FROM clean.simple_analysis
     WHERE admi_nm='명동' AND tpbiz_clscd_nm='치킨' AND grain='dong'
     ORDER BY crtr_ym""",
  "월별 3행이 나와야. 답변에 추이(증가/감소) 서술"),

 ("Q10. [함정] 명동에서 제일 잘 버는 치킨집 이름이 뭐야?",
  None,  # 정답 = 답변 거부
  "정답: '개별 점포 조회 불가(집계 데이터)' 안내가 나와야 함. SQL을 억지로 만들면 감점"),

 ("Q11. [보너스] 경기도에서 편의점 매출 제일 높은 동네는?",
  """SELECT sgg_nm, admi_nm, amt_dong
     FROM clean.simple_analysis
     WHERE sido_nm_std='경기도' AND tpbiz_clscd_nm='편의점'
       AND grain='dong' AND is_substituted=false
       AND crtr_ym=(SELECT max(crtr_ym) FROM clean.simple_analysis)
     ORDER BY amt_dong DESC NULLS LAST LIMIT 3""",
  "핵심 시험: sido_nm_std='경기도' 를 쓰는지 (원천 표기는 '경기'라 sido_nm으로 가면 0건)"),
]


def main():
    conn = psycopg2.connect(DSN)
    cur = conn.cursor()
    print("=" * 70)
    print(" 평가용 모범답안지 — 웹데모에 같은 질문을 던져서 아래와 비교하세요")
    print("=" * 70)
    for q, sql, point in TESTS:
        print(f"\n{q}")
        print(f"  [채점 포인트] {point}")
        if sql is None:
            print("  [정답] 답변 거부가 정답 (SQL 없음)")
            continue
        cur.execute(sql)
        cols = [d[0] for d in cur.description]
        rows = cur.fetchall()
        print(f"  [정답] {' | '.join(cols)}")
        for r in rows:
            print("        ", " | ".join(str(v) for v in r))
        if not rows:
            print("         (0행 — 데이터 없음이 정답)")
    conn.close()
    print("\n" + "=" * 70)
    print(" 채점법: ① 수치 일치 여부  ② SQL에 필수 필터(grain/is_substituted/")
    print("         sido_nm_std)가 들어갔는지  ③ Q10은 거부했는지")
    print("=" * 70)


if __name__ == "__main__":
    main()
