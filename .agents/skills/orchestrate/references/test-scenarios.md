# 테스트 시나리오

> **언제 읽는가**: 오케스트레이터 워크플로우의 정합성을 드라이런으로 검증하거나, 특정 경로(정상 흐름·버그 경로·UI 검증·compound-curate·계획 정합성)의 단계 순서를 대조 확인할 때만 읽는다. 실행 경로가 아니므로 평상시 파이프라인 진행에는 로드하지 않는다. (마일스톤 번호는 예시이며, 실제 마일스톤↔에이전트 매핑은 프로젝트가 정의한다.)

**정상 흐름 (design-reviewer 1회 통과)**: UI 마일스톤 구현 요청 → Phase 0 → 레거시 분석 에이전트 분석(포팅 시) → **Phase 3-0: 티켓 파싱 → 현재 세션 작업 목록(파일별)** → 프론트 구현 에이전트 호출(태스크 ID 목록 포함) → **Phase 3-2: 현재 세션 작업 목록 검증(전 태스크 completed + 대상 파일 실존 확인)** → milestone-tracker 갱신 🔄 → design-reviewer 호출 → `approved` → qa-guard 호출 → evaluator 호출 → **Phase 5-A/5-B 사용자 검증 게이트(긍정 응답)** → milestone-tracker 갱신 ✅ → commit → 완료 보고

**정상 흐름 (design-reviewer 보완 루프)**: ... → 프론트 구현 → design-reviewer 호출 → `구현-에이전트-위임` 반환 → 프론트 구현 에이전트 보완 → design-reviewer 재검증 → `approved` 반환 → qa-guard 호출 → ... (qa-guard는 design-reviewer 완료 후 실행)

**정상 흐름 (목업 단계)**: 목업 마일스톤 요청 → Phase 0 → Phase 1 → Phase 2 (레거시 분석) → Phase 3: 프론트 구현 → Phase 4: design-reviewer → qa-guard → evaluator → milestone-tracker → 완료 보고

**정상 흐름 (결정 문서 단계)**: 결정 문서 마일스톤 요청 → Phase 0 → Phase 1 → Phase 2 (레거시 분석) → Phase 3: 백엔드 구현 에이전트 호출(`model = "gpt-5.5"`, 문서만 산출, 코드 없음) → Phase 4: qa-guard → evaluator → milestone-tracker → 완료 보고

**정상 흐름 (TDD 포함, 실데이터 단계)**: 실데이터 마일스톤 요청 → Phase 0 → Phase 1 → Phase 2 (레거시 분석) → **Phase 2.5: tdd-agent (Red 테스트 작성, 실패 확인)** → Phase 3: 백엔드 구현 에이전트 (테스트 파일 전달, Green 구현) → 프론트 구현 → Phase 4: design-reviewer → qa-guard (테스트 실행) → evaluator → milestone-tracker → 완료 보고

**버그 경로 — evaluator 게이팅 스킵 + 사용자 시각 검증 게이트 흐름**: "버튼 색이 안 맞음" 버그 보고 → Phase 0 버그 경로 → `bug-fixer` 호출 → 완료 항목 = 스타일·컴포넌트 파일만 → 3번 게이팅 판정: 동작 레이어 화이트리스트 prefix(경로 접두사) 무매칭 → **evaluator 스킵** → 4번: evaluator 안 닿음이므로 **compound-learner 즉시 호출하지 않음** → 5번 사용자 보고에 `evaluator 게이팅: 안 닿음 — 동작 레이어 외 (스킵)` + "브라우저에서 시각 결함 해소 확인 요청" + "재발 방지 학습은 응답 후 수행" 명시. 다음 턴 분기 — (긍정) 사용자가 "확인됐다" 응답 → 6번 `commit` 스킬(메시지 `fix: {증상 한 줄}`, 완료 항목 파일 한정) → `compound-learner` 백그라운드 호출(트리거 `bug-fix`, 봉투에 사용자 시각 검증 통과 명시) 후 종료. (부정) 사용자가 "수정 안됨" 응답 → 6번 bug-fixer 재호출 트랙 회귀(재호출 전 버그 식별·회차·직전 가설 1줄을 `_workspace/bugfix-attempts.md` 에 append), compound-learner 호출 안 함 → 재수정 후 5번 재진입. (대조군: 완료 항목 = API 핸들러 파일이었다면 동작 레이어 prefix 매칭 → evaluator full 실행 + approved 후 4번에서 `commit` 스킬 → compound-learner 즉시 호출 + 5번 종료, 사용자 응답 대기 없음)

**UI 마일스톤 사용자 검증 1회 통과 흐름**: ... Phase 4 evaluator approved → **Phase 5-A: 프론트 구현 에이전트 투입 판정 → 5-B 진입** → 검증 요청 보고서(파일 목록·확인 URL·재현 시나리오·"긍정 응답 후 ✅·커밋 진행" 명시) 출력 → **재개 프롬프트 미출력(응답 대기)** → 사용자 긍정 응답("확인됨") → **Phase 5-C**: `milestone-tracker` 갱신 ✅ → `commit` 스킬 → compound-curate 드레인(background, 플래그 있을 때) → 최종 보고 + **재개 프롬프트 동반 출력**.

**UI 마일스톤 사용자 부정 → 보완 → 재통과 흐름**: ... Phase 5-A → 5-B 검증 요청 → 사용자 부정 응답("이 버튼 클릭 시 강조가 안 보임") → **Phase 5-E**: 오케스트레이터 자동 분류 → 시각/동작 결함 → `bug-fixer` 호출(진단 맥락: 사용자 응답 본문) → 완료 항목 = 스타일·컴포넌트 파일(동작 레이어 prefix 무매칭) + UI 마일스톤 → **증분 재게이팅: design-reviewer 해당 파일 한정 재검증** → 통과 (완료 항목에 동작 레이어 매칭 파일이 섞였다면 qa-guard 해당 파일 한정 증분 재실행도 — design → qa → evaluator 순서 유지) → Phase 4 evaluator 재검증 → approved → 5-A 회귀 → 5-B 재검증 요청 → 사용자 긍정 응답 → 5-C tracker ✅ → commit → 드레인 → 보고. (반복 학습: 동일 항목 2회 연속이면 5-E step 1 분류 결과에 매핑한 기존 트랙으로 호출 — 이 예시는 시각 결함이므로 `compound-learner` 백그라운드 호출(트리거 `bug-fix`, 보고서: 사용자 응답 본문 + 보완 이력). `user-verify-repeat`는 compound-learner enum에 미정의. 3회면 stuck.)

**비-UI 마일스톤 즉시 커밋 흐름 (프론트 구현 에이전트 미투입)**: ... Phase 4 evaluator approved → **Phase 5-A: 프론트 구현 에이전트 미투입 판정 → 5-D 직행** → **step 0 위험 클래스 게이트**(완료 항목 경로·티켓 키워드 기계 매칭 — 마이그레이션/스키마/백필 매칭 시 dev DB 적용 로그 증거 확인, 부재 시 사용자 1회 확인 분기·응답 대기 중 재개 프롬프트 미출력, 해당 없음이면 통과) → tracker ✅ → commit → compound-curate 드레인 → 보고(위험 클래스 게이트 판정 1줄 포함) + 재개 프롬프트. (사용자 검증 게이트 없음 — 시각 확인 대상이 없으므로)

**compound-curate 드레인 흐름**: 마일스톤 파이프라인 진행 중 Phase 0 "재발 방지 학습 푸시"에서 카테고리 README 주입 시 한 유형 파일이 임계 초과 → `_workspace/curate-needed.md` 에 1줄 append(세션 메모 아님 — 파일 외부화로 compaction 후 보존, 작업 차단 없음) → Phase 1~4 정상 진행 → Phase 5-A → (UI 경로) 5-B 사용자 검증 → 5-C tracker ✅ → commit → **commit 직후** `_workspace/curate-needed.md` 를 읽어 `compound-learner` 백그라운드 호출(트랙 `compound-curate`)로 드레인(호출 직후 파일 truncate) → _superseded 격리·원칙 승격·README 재동기화(무손실 검증 PASS) → 5-C 최종 보고에 1줄 요약 → 완료. (비-UI 경로는 5-D step 3 동일 위치에서 드레인.) (온디맨드 변형: "compound 정리해줘" → Phase 0 분기 → 동기 `compound-learner` 호출(트랙 `compound-curate`) → 정리 결과 보고 후 종료, 파이프라인 미진입)

**계획 정합성 감사 흐름 (온디맨드)**: "이 마일스톤 체크리스트 아직 유효한지 확인" 요청 → Phase 0 입력 분기: 계획 정합성 검증 요청 → 파이프라인 미진입 → `plan-auditor` 동기 호출 → 정본 교차 대조(체크리스트↔근거 audit 보고서↔작업 로그) → `_workspace/plan_audit_*.md` 반환 (결함 N건 + 3등급 분류) → 사용자에게 요약 보고 → 사용자가 "문서 수정" 결함 반영 승인 → `milestone-tracker` 정본 수정 위임 → 재개 프롬프트 동반 종료. (자동 변형: 새 마일스톤 착수 시 Phase 1-0에서 plan-auditor 선점검 → `정합성 결과: consistent` 면 그대로 Phase 1-1 진행)

**에러 흐름**: 백엔드 구현 에이전트 실패 → 1회 재시도 → 재실패 시 "DB 레이어 미완성" 명시 후 프론트 완성분만 보고
