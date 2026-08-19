-- =====================================================================
-- AI용 데이터 사전 시드 (DAR-006 초안)
-- 대상: clean.simple_analysis (추후 마트 승격 시 table_name만 교체)
-- 생성: 2026.08.18 · 근거: 공식 컬럼정의서 + 실데이터 282만행 EDA
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS meta;

DROP TABLE IF EXISTS meta.data_dictionary;
CREATE TABLE meta.data_dictionary (
    table_name   varchar(80)  NOT NULL,
    column_name  varchar(80)  NOT NULL,
    grp          varchar(40),
    korean_name  varchar(120),
    description  text,
    synonyms     text[],
    example      text,
    PRIMARY KEY (table_name, column_name)
);

DROP TABLE IF EXISTS meta.business_rules;
CREATE TABLE meta.business_rules (
    rule_id   int PRIMARY KEY,
    rule      text NOT NULL,
    reason    text
);

DROP TABLE IF EXISTS meta.query_examples;
CREATE TABLE meta.query_examples (
    ex_id     int PRIMARY KEY,
    question  text NOT NULL,
    sql       text NOT NULL,
    note      text
);


INSERT INTO meta.data_dictionary VALUES
('clean.simple_analysis','crtr_ym','간단분석 기본정보','기준년월','기준년월(YYYYMM). 보유: 202603~202605. 문자(text) 타입 — 반드시 따옴표로 비교: crtr_ym=''202603'' (crtr_ym=202603 처럼 숫자 비교 금지)',ARRAY['기준월','년월'],'202603'),
('clean.simple_analysis','admi_cd','간단분석 기본정보','행정동코드','행정동코드',NULL,'11140605'),
('clean.simple_analysis','admi_nm','간단분석 기본정보','행정동명','행정동명. 합계행에서는 NULL',ARRAY['동네','동','행정동'],'을지로동'),
('clean.simple_analysis','tpbiz_clscd','간단분석 기본정보','소분류 업종코드','소분류 업종코드',NULL,'I21006'),
('clean.simple_analysis','tpbiz_clscd_nm','간단분석 기본정보','소분류 업종명','업종 소분류명(247종) — 실제 업종 조회 기준. 일상어(호프집 등)→코드 매핑은 동의어 사전 확장 필요',ARRAY['업종','가게 종류'],'치킨'),
('clean.simple_analysis','simple_info_amt','간단분석 정보요약','월 평균 매출','표출용 월평균 매출 문자열. 업소≤3 동네는 시군구 값이 대신 들어감 — 분석·답변에 사용 금지, AMT_DONG 사용',NULL,'2,535 만원'),
('clean.simple_analysis','simple_info_upso','간단분석 정보요약','선택업종 업소수','선택업종 업소수',NULL,'7개'),
('clean.simple_analysis','simple_info_day_pop','간단분석 정보요약','일 평균 유동인구','일 평균 유동인구',NULL,'132,263명'),
('clean.simple_analysis','simple_info_many_day_pop','간단분석 정보요약','유동인구 많은 요일','유동인구 많은 요일',NULL,'수요일'),
('clean.simple_analysis','simple_info_many_time_pop','간단분석 정보요약','유동인구 많은 시간대','유동인구 많은 시간대',NULL,'14-18시'),
('clean.simple_analysis','simple_info_explan','간단분석 정보요약','분석결과 해설','분석결과 해설',NULL,'을지로동은 전년동월대비 치킨 업종의 월평균 매출액이 감소, 업소 수는 감소되어, 을지로동의 치킨 업종의 활력'),
('clean.simple_analysis','amt_low','매출분석','최저 매출','동네 동종 업소 최저 매출(만원)',NULL,'1,056'),
('clean.simple_analysis','amt_avg','매출분석','월 평균 매출','동네 동종 업소 평균 매출 — AMT_DONG과 동일 값',NULL,'2,535 만원'),
('clean.simple_analysis','amt_high','매출분석','최고 매출','동네 동종 업소 최고 매출(만원)',NULL,'4,116'),
('clean.simple_analysis','amt_dong','매출분석','행정동 매출','행정동 동종업종 월평균 매출(만원) — 동네 매출의 정본. 업소≤3이면 NULL(비공개 정책). ''평균''이지 총액 아님',ARRAY['매출','월매출','장사'],'2535'),
('clean.simple_analysis','amt_sgg','매출분석','시군구 매출','같은 업종의 시군구 월평균 매출(만원). 동 행 안에 함께 있어 비교에 사용',ARRAY['구 평균'],'2177'),
('clean.simple_analysis','amt_sido','매출분석','시도 매출','같은 업종의 시도 월평균 매출(만원)',ARRAY['시도 평균','서울 평균'],'1565'),
('clean.simple_analysis','amt_on_year','매출분석','전년동월대비 매출','전년동월 대비 매출 증감률(%). 극단값(+4897% 등)은 전년 기저효과 — 답변 시 ''전년 기준치 참고'' 병기',ARRAY['전년비','작년 대비'],'-23.8%'),
('clean.simple_analysis','amt_on_month','매출분석','전월대비 매출','전월 대비 매출 증감률(%)',ARRAY['전월비'],'11.1%'),
('clean.simple_analysis','amt_explan','매출분석','분석결과 해설','분석결과 해설',NULL,'을지로동의 동종업종 월평균 매출액은 전년동월대비 23.8% 낮고, 전월대비 11.1% 증가했습니다.'),
('clean.simple_analysis','baemin_month_avg_cnt','배달 분석','월평균 배달주문건수','월평균 배달주문건수. 배달 발생 업종·동네만 값 존재(결측 ~90%)',ARRAY['배달','배달건수'],'62'),
('clean.simple_analysis','baemin_weekday','배달 분석','주중 배달건수 비율','주중 배달건수 비율',NULL,'66.4%'),
('clean.simple_analysis','baemin_weekend','배달 분석','주말 배달건수 비율','주말 배달건수 비율',NULL,'33.6%'),
('clean.simple_analysis','baemin_mon','배달 분석','월요일 배달건수 비율','월요일 배달건수 비율',NULL,'11.5%'),
('clean.simple_analysis','baemin_tus','배달 분석','화요일 배달건수 비율','화요일 배달건수 비율',NULL,'13.1%'),
('clean.simple_analysis','baemin_wed','배달 분석','수요일 배달건수 비율','수요일 배달건수 비율',NULL,'16.4%'),
('clean.simple_analysis','baemin_thu','배달 분석','목요일 배달건수 비율','목요일 배달건수 비율',NULL,'12.3%'),
('clean.simple_analysis','baemin_fri','배달 분석','금요일 배달건수 비율','금요일 배달건수 비율',NULL,'13.1%'),
('clean.simple_analysis','baemin_sat','배달 분석','토요일 배달건수 비율','토요일 배달건수 비율',NULL,'20.5%'),
('clean.simple_analysis','baemin_sun','배달 분석','일요일 배달건수 비율','일요일 배달건수 비율',NULL,'13.1%'),
('clean.simple_analysis','baemin_time_05_09','배달 분석','05~09시 배달건수 비율','05~09시 배달건수 비율',NULL,'10.4%'),
('clean.simple_analysis','baemin_time_09_12','배달 분석','09~12시 배달건수 비율','09~12시 배달건수 비율',NULL,'0.0%'),
('clean.simple_analysis','baemin_time_12_14','배달 분석','12~14시 배달건수 비율','12~14시 배달건수 비율',NULL,'0.0%'),
('clean.simple_analysis','baemin_time_14_18','배달 분석','14~18시 배달건수 비율','14~18시 배달건수 비율',NULL,'10.4%'),
('clean.simple_analysis','baemin_time_18_23','배달 분석','18~23시 배달건수 비율','18~23시 배달건수 비율',NULL,'33.9%'),
('clean.simple_analysis','baemin_time_23_05','배달 분석','23~05시 배달건수 비율','23~05시 배달건수 비율',NULL,'45.3%'),
('clean.simple_analysis','baemin_age_10','배달 분석','10대 이하 배달건수 비율','10대 이하 배달건수 비율',NULL,'4.3%'),
('clean.simple_analysis','baemin_age_20','배달 분석','20대 배달건수 비율','배달 주문 중 20대 비중(%)',ARRAY['20대'],'27.4%'),
('clean.simple_analysis','baemin_age_30','배달 분석','30대 배달건수 비율','30대 배달건수 비율',NULL,'32.5%'),
('clean.simple_analysis','baemin_age_40','배달 분석','40대 배달건수 비율','40대 배달건수 비율',NULL,'21.4%'),
('clean.simple_analysis','baemin_age_50','배달 분석','50대 배달건수 비율','50대 배달건수 비율',NULL,'12.8%'),
('clean.simple_analysis','baemin_age_60','배달 분석','60대 이상 배달건수 비율','60대 이상 배달건수 비율',NULL,'1.7%'),
('clean.simple_analysis','baemin_m','배달 분석','남성 배달건수 비율','남성 배달건수 비율',NULL,'61.5%'),
('clean.simple_analysis','baemin_w','배달 분석','여성 배달건수 비율','여성 배달건수 비율',NULL,'38.5%'),
('clean.simple_analysis','baemin_explan','배달 분석','분석결과 해설','분석결과 해설',NULL,'선택 지역의 배달 매출은 전년동월대비 31.1% 낮고, 전월 대비 31.9% 증가했습니다. 고객특성으로는 남'),
('clean.simple_analysis','upso_count','업종분석','선택업종 업소수','선택업종 업소수',NULL,'7개'),
('clean.simple_analysis','upso_count_dong','업종분석','행정동 업소수','행정동 업소수. 결측 없음(0도 값). is_substituted 판별 기준',ARRAY['업소수','가게 수','경쟁'],'7'),
('clean.simple_analysis','upso_count_sgg','업종분석','시군구 업소수','시군구 업소수(합계)',NULL,'133'),
('clean.simple_analysis','upso_count_sido','업종분석','시도 업소수','시도 업소수(합계)',NULL,'5462'),
('clean.simple_analysis','upso_on_year','업종분석','전년도월대비 업소수 증감률','업소수 전년동월 대비 증감률(%). 매출 증감과 교차 → 과점화/레드오션 판별',NULL,'-12.5%'),
('clean.simple_analysis','upso_on_month','업종분석','전월대비 업소수 증감률','전월대비 업소수 증감률',NULL,'0.0%'),
('clean.simple_analysis','upso_explan','업종분석','분석결과 해설','분석결과 해설',NULL,'을지로동의 치킨 업소 수는 전년동월대비 12.5% 적고, 전월 대비 같습니다.'),
('clean.simple_analysis','pop_month_avg_cnt','유동인구 분석','일 평균 유동인구','일 평균 유동인구(명). 업종 무관 동 단위 값 — 같은 동이면 업종 달라도 동일. 합계행은 지역 전체 합계',ARRAY['유동인구','손님','사람'],'132,263명'),
('clean.simple_analysis','pop_weekday','유동인구 분석','주중 유동인구 비율','주중 유동인구 비율',NULL,'81.3%'),
('clean.simple_analysis','pop_weekend','유동인구 분석','주말 유동인구 비율','주말 유동인구 비율',NULL,'18.7%'),
('clean.simple_analysis','pop_mon','유동인구 분석','월요일 유동인구 비율','월요일 유동인구 비율',NULL,'15.1%'),
('clean.simple_analysis','pop_tus','유동인구 분석','화요일 유동인구 비율','화요일 유동인구 비율',NULL,'15.2%'),
('clean.simple_analysis','pop_wed','유동인구 분석','수요일 유동인구 비율','수요일 유동인구 비율',NULL,'17.7%'),
('clean.simple_analysis','pop_thu','유동인구 분석','목요일 유동인구 비율','목요일 유동인구 비율',NULL,'16.1%'),
('clean.simple_analysis','pop_fri','유동인구 분석','금요일 유동인구 비율','금요일 유동인구 비율',NULL,'17.2%'),
('clean.simple_analysis','pop_sat','유동인구 분석','토요일 유동인구 비율','토요일 유동인구 비율',NULL,'10.3%'),
('clean.simple_analysis','pop_sun','유동인구 분석','일요일 유동인구 비욜','일요일 유동인구 비욜',NULL,'8.5%'),
('clean.simple_analysis','pop_time_05_09','유동인구 분석','05~09시 유동인구 비율','05~09시 유동인구 비율',NULL,'20.9%'),
('clean.simple_analysis','pop_time_09_12','유동인구 분석','09~12시 유동인구 비율','09~12시 유동인구 비율',NULL,'18.2%'),
('clean.simple_analysis','pop_time_12_14','유동인구 분석','12~14시 유동인구 비율','12~14시 유동인구 비율',NULL,'10.9%'),
('clean.simple_analysis','pop_time_14_18','유동인구 분석','14~18시 유동인구 비율','14~18시 유동인구 비율',NULL,'23.9%'),
('clean.simple_analysis','pop_time_18_23','유동인구 분석','18~23시 유동인구 비율','18~23시 유동인구 비율',NULL,'22.4%'),
('clean.simple_analysis','pop_time_23_05','유동인구 분석','23~05시 유동인구 비율','23~05시 유동인구 비율',NULL,'3.7%'),
('clean.simple_analysis','pop_explan','유동인구 분석','분서결과 해설','분서결과 해설',NULL,'유동인구가 가장 많은 요일은 수요일이고, 가장 많은 시간대는 14-18시입니다.'),
('clean.simple_analysis','sangwon1_dong','상권비교','상권1 행정동','상권1 행정동',NULL,'서울특별시 종로구 부암동'),
('clean.simple_analysis','sangwon1_amt','상권비교','상권1 매출','상권1 매출',NULL,'13,241만원'),
('clean.simple_analysis','sangwon1_pop','상권비교','상권1 유동인구','상권1 유동인구',NULL,'82,445명'),
('clean.simple_analysis','sangwon1_upso_count','상권비교','상권1 업소수','상권1 업소수',NULL,'2개'),
('clean.simple_analysis','sangwon2_dong','상권비교','상권2 행정동','상권2 행정동',NULL,'서울특별시 종로구 삼청동'),
('clean.simple_analysis','sangwon2_amt','상권비교','상권2 매출','상권2 매출',NULL,'6,747만원'),
('clean.simple_analysis','sangwon2_pop','상권비교','상권2 유동인구','상권2 유동인구',NULL,'57,412명'),
('clean.simple_analysis','sangwon2_upso_count','상권비교','상권2 업소수','상권2 업소수',NULL,'1개'),
('clean.simple_analysis','sangwon3_dong','상권비교','상권3 행정동','상권3 행정동',NULL,'서울특별시 강남구 도곡2동'),
('clean.simple_analysis','sangwon3_amt','상권비교','상권3 매출','상권3 매출',NULL,'6,064만원'),
('clean.simple_analysis','sangwon3_pop','상권비교','상권3 유동인구','상권3 유동인구',NULL,'182,523명'),
('clean.simple_analysis','sangwon3_upso_count','상권비교','상권3 업소수','상권3 업소수',NULL,'6개'),
('clean.simple_analysis','sangwon4_dong','상권비교','상권4 행정동','상권4 행정동',NULL,'서울특별시 서초구 반포4동'),
('clean.simple_analysis','sangwon4_amt','상권비교','상권4 매출','상권4 매출',NULL,'6,033만원'),
('clean.simple_analysis','sangwon4_pop','상권비교','상권4 유동인구','상권4 유동인구',NULL,'464,508명'),
('clean.simple_analysis','sangwon4_upso_count','상권비교','상권4 업소수','상권4 업소수',NULL,'8개'),
('clean.simple_analysis','sangwon5_dong','상권비교','상권5 행정동','상권5 행정동',NULL,'서울특별시 용산구 이촌2동'),
('clean.simple_analysis','sangwon5_amt','상권비교','상권5 매출','상권5 매출',NULL,'5,226만원'),
('clean.simple_analysis','sangwon5_pop','상권비교','상권5 유동인구','상권5 유동인구',NULL,'63,916명'),
('clean.simple_analysis','sangwon5_upso_count','상권비교','상권5 업소수','상권5 업소수',NULL,'4개'),
('clean.simple_analysis','sido_cd','간단분석 기본정보','시도 코드','행정구역 시도 코드(2자리). 16개 시도(광주+전남 통합 체계)',NULL,'11'),
('clean.simple_analysis','sido_nm','간단분석 기본정보','시도명(원천 표기)','원천 표기 그대로 — 약칭 혼용(경기·충북·충남·경북·경남). 지역 조회에는 sido_nm_std를 사용할 것',NULL,'서울특별시'),
('clean.simple_analysis','sgg_cd','간단분석 기본정보','시군구 코드','시도 2자리+2자리. 시도 합계행에서는 NULL',NULL,'11140'),
('clean.simple_analysis','sgg_nm','간단분석 기본정보','시군구명','동구·서구·중구·남구는 여러 시도에 존재 — 반드시 시도와 함께 필터. 세종은 이 칸에 ''세종특별자치시'' 자신이 들어감',NULL,'중구'),
('clean.simple_analysis','tpbiz_lclcd','간단분석 기본정보','업종 대분류 코드','10종',NULL,'I2'),
('clean.simple_analysis','tpbiz_lclcd_nm','간단분석 기본정보','업종 대분류명','음식·소매·수리개인·교육·보건의료·부동산·숙박·예술스포츠·과학기술·시설관리임대',NULL,'음식'),
('clean.simple_analysis','tpbiz_mclcd','간단분석 기본정보','업종 중분류 코드','75종',NULL,'I21'),
('clean.simple_analysis','tpbiz_mclcd_nm','간단분석 기본정보','업종 중분류명','',NULL,'기타 간이'),
('clean.simple_analysis','rgn_cd','간단분석 기본정보','지역 표시명','코드가 아니라 그 행의 지역 라벨 텍스트(리포트 제목용). 분석에는 사용하지 말 것',NULL,'명동'),
('clean.simple_analysis','grain','적재 생성','행 단위','dong=행정동 행 / sgg=시군구 합계행 / sido=시도 합계행. 동네 대상 질의·랭킹은 반드시 grain=''dong''',NULL,'dong'),
('clean.simple_analysis','is_substituted','적재 생성','시군구 대체값 행 여부','업소 3개 이하 동네(보호 대상). true면 동 단위 매출이 비공개된 행 — 랭킹·통계는 is_substituted=false 필터 필수',NULL,'false'),
('clean.simple_analysis','sido_nm_std','적재 생성','시도명 표준화','약칭을 정식명칭으로 통일(경기→경기도, 충북→충청북도, 충남→충청남도, 경북→경상북도, 경남→경상남도). 시도 조회는 항상 이 컬럼 사용',NULL,'경기도'),
('clean.simple_analysis','source_file','적재 생성','원본 파일명','적재 원천 CSV 추적용. 분석에는 불필요',NULL,'');

INSERT INTO meta.business_rules VALUES
(1,'동네 매출은 amt_dong 사용. simple_info_amt(표출용)는 시군구 대체값이 섞여 있어 사용 금지','업소≤3 동네는 표출용에 구 평균이 들어감(전체의 ~34%)'),
(2,'동네 대상 질의·랭킹·통계는 WHERE grain=''dong'' AND is_substituted=false 를 기본 필터로. 단 예외: 질문이 ''업소가 적은 동네''를 찾는 것(upso_count_dong에 상한 조건)이면 is_substituted 필터를 넣지 말 것 — is_substituted 자체가 업소 3개 이하 표시라 함께 쓰면 모순으로 0행이 됨 (예시 4번 참조)','합계행과 대체값행이 순위·통계를 왜곡. 예외 미처리 시 역질의가 공집합 되는 실사례 발생'),
(3,'매출 계열(amt_*)은 전부 ''월평균''이며 ''총액''이 아님 — 총매출 질의에는 이 데이터로 답하지 말 것','합계행의 매출도 그 지역 평균값'),
(4,'시도 조회는 sido_nm_std 사용 (sido_nm은 약칭 혼용)','원천 표기: 경기/충북/충남/경북/경남 약칭'),
(5,'시군구명 단독 필터 금지 — 반드시 시도와 함께 (중구·동구 등 동명 다수)','''중구''는 서울·부산·대구 등에 존재'),
(6,'개별 점포 조회 불가 — 데이터는 행정동×업종 집계 단위. 특정 가게 질문에는 지역 평균으로 안내','개인정보 보호와 직결'),
(7,'극단 증감률(|amt_on_year|>100%)은 전년 기저효과 가능성 병기','신규 상권 형성 등으로 저기저 발생'),
(8,'배달(baemin_*) 결측 ~90% — 값 없으면 ''배달 데이터 없음''으로 답변, 0으로 해석 금지','배달 발생 업종·동네만 수록'),
(9,'기준 시점(crtr_ym)을 답변에 명시. 보유 범위: 2026.03~05 월 단위','실시간·일 단위 데이터 아님'),
(10,'예측·보장성 답변 금지 — 과거·현황 수치만 제공','서비스 정책'),
(11,'코드·년월 컬럼(crtr_ym, sido_cd, sgg_cd, admi_cd, tpbiz_*)은 전부 문자(text) 타입 — 값 비교 시 반드시 따옴표 사용 (예: crtr_ym=''202603'', admi_cd=''11140550'')','text = integer 타입 오류 방지 (실제 발생 사례)'),
(12,'질문에 ''주변/근처/일대''가 있으면: 인접 동 데이터가 없으므로 ① 해당 동과 ② 같은 시군구의 동들을 함께 조회하고(예: 명동 주변 → admi_nm=''명동'' OR (sgg_nm=''중구'' AND sido_nm_std=''서울특별시'')), 답변에 반드시 "인접 동 정보가 없어 해당 동과 같은 시군구 기준으로 안내드립니다"를 명시할 것. 조용히 해당 동만 조회하는 것 금지','공간 인접 정보 미보유 — 범위 축소 해석을 사용자에게 숨기면 안 됨 (실제 발생 사례)');

INSERT INTO meta.query_examples VALUES
(1,'명동에서 치킨집 하는데 요즘 어때요?','SELECT admi_nm, tpbiz_clscd_nm, amt_dong, amt_sgg, amt_on_year, upso_count_dong, pop_month_avg_cnt FROM clean.simple_analysis WHERE admi_nm=''명동'' AND tpbiz_clscd_nm=''치킨'' AND grain=''dong'' AND crtr_ym=(SELECT max(crtr_ym) FROM clean.simple_analysis)','단순 조회 — 최신 월 기준'),
(2,'서울에서 치킨 장사 제일 잘되는 동네 어디예요?','SELECT sgg_nm, admi_nm, amt_dong, upso_count_dong FROM clean.simple_analysis WHERE sido_nm_std=''서울특별시'' AND tpbiz_clscd_nm=''치킨'' AND grain=''dong'' AND is_substituted=false AND crtr_ym=(SELECT max(crtr_ym) FROM clean.simple_analysis) ORDER BY amt_dong DESC NULLS LAST LIMIT 3','랭킹 — 규칙2 필터 적용'),
(3,'구의1동에서 치킨이랑 카페 중 뭐가 나아요?','SELECT tpbiz_clscd_nm, amt_dong, upso_count_dong FROM clean.simple_analysis WHERE admi_nm=''구의1동'' AND tpbiz_clscd_nm IN (''치킨'',''카페'') AND grain=''dong'' AND crtr_ym=(SELECT max(crtr_ym) FROM clean.simple_analysis)','업종 간 비교'),
(4,'유동인구는 많은데 치킨집이 적은 동네 없어요?','SELECT sgg_nm, admi_nm, pop_month_avg_cnt, upso_count_dong FROM clean.simple_analysis WHERE tpbiz_clscd_nm=''치킨'' AND grain=''dong'' AND pop_month_avg_cnt>=100000 AND upso_count_dong BETWEEN 1 AND 3 AND crtr_ym=(SELECT max(crtr_ym) FROM clean.simple_analysis) ORDER BY pop_month_avg_cnt DESC LIMIT 5','역질의(입지 스크리닝) — 업소 1~3 조건이라 is_substituted 필터 제외한 특수 케이스'),
(5,'작년보다 장사가 많이 나빠진 동네는요?','SELECT sgg_nm, admi_nm, amt_on_year FROM clean.simple_analysis WHERE tpbiz_clscd_nm=''치킨'' AND grain=''dong'' AND is_substituted=false AND amt_on_year IS NOT NULL AND crtr_ym=(SELECT max(crtr_ym) FROM clean.simple_analysis) ORDER BY amt_on_year ASC LIMIT 3','위험 경보형'),
(6,'가게 하나당 벌이가 제일 좋은 동네는? (카페)','SELECT sgg_nm, admi_nm, ROUND(amt_dong/NULLIF(upso_count_dong,0),1) AS amt_per_store FROM clean.simple_analysis WHERE tpbiz_clscd_nm=''카페'' AND grain=''dong'' AND is_substituted=false AND upso_count_dong>=5 AND crtr_ym=(SELECT max(crtr_ym) FROM clean.simple_analysis) ORDER BY amt_per_store DESC NULLS LAST LIMIT 3','파생 지표(포화도) — 마트 승격 시 물리 컬럼화 예정'),
(7,'20대 상대로 카페 배달하려면 어디가 좋아요?','SELECT sgg_nm, admi_nm, baemin_age_20 FROM clean.simple_analysis WHERE tpbiz_clscd_nm=''카페'' AND grain=''dong'' AND baemin_age_20 IS NOT NULL AND crtr_ym=(SELECT max(crtr_ym) FROM clean.simple_analysis) ORDER BY baemin_age_20 DESC LIMIT 3','고객 프로파일 타깃팅'),
(8,'3월이랑 5월 비교해서 명동 치킨 매출 어떻게 변했어요?','SELECT crtr_ym, amt_dong FROM clean.simple_analysis WHERE admi_nm=''명동'' AND tpbiz_clscd_nm=''치킨'' AND grain=''dong'' ORDER BY crtr_ym','월간 추이 — 3개월 보유');


-- 확인
SELECT grp, count(*) FROM meta.data_dictionary GROUP BY grp ORDER BY 2 DESC;
