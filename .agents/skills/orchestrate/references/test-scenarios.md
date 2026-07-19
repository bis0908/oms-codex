# 정상 시나리오

| ID | Given | When | Then |
|---|---|---|---|
| POS-01 | UI task와 선호 검증 수단이 정의됐다. | 선호 수단을 사용할 수 없다. | 폴백으로 등가 증거를 수집하되 evaluator 승인과 사용자 검증 통과 전 완료·커밋하지 않는다. |
| POS-02 | 데이터/API task와 격리 DB가 준비됐다. | data-layer가 `tdd` 스킬로 목표 assertion 실패를 확인한다. | `red-confirmed` 뒤 같은 컨텍스트에서 Green을 구현하고 선택한 QA/security/evaluator 게이트를 수행한다. |
| POS-03 | 버그 해결에 새 쿠키·토큰·세션 설계가 필요하다. | 오케스트레이터의 bugfix 진단이 auth/session으로 분류된다. | 단발 경로를 종료하고 data-layer Red→Green 뒤 QA → security-auditor → evaluator를 수행한다. |
| POS-04 | 순수 시각 결함이고 변경 파일 전부가 시각 전용 manifest에 포함된다. | 오케스트레이터가 최소 수정한다. | design 또는 사용자 시각 검증으로 확인하며 기능형 신호가 있으면 evaluator를 실행한다. |
| POS-05 | 반복 사례와 정확한 queue ID가 있고 compound agent가 설치됐다. | append 또는 curate를 실행한다. | compound-learner와 compound-curator의 권한을 분리하고 성공 acknowledgement ID만 done 처리한다. |
| POS-06 | 계획 감사에서 문서 수정 결함이 나왔고 사용자가 승인했다. | 오케스트레이터가 plan-remediation 신호를 만든다. | 결정적 전이 검증 후 정확한 checklist ID만 milestone-track 스킬로 수정한다. |
| POS-07 | 커밋 정책이 `ask`이고 필수 게이트가 끝났다. | 사용자 커밋 승인이 없다. | 완료와 미커밋 상태를 분리하고 승인 뒤에만 commit-local을 사용한다. |
| POS-08 | source에 9개 agent와 lean/full topology가 정의됐다. | 설치 스크립트를 기본 옵션으로 실행한다. | lean core 6개만 설치하며 `--topology full` 또는 `-Topology full`일 때 source 9개를 설치한다. |

# 부정 시나리오

| ID | Given | When | Then |
|---|---|---|---|
| NEG-01 | 선택된 필수 qa-guard가 실패했다. | 1회 재시도도 실패한다. | blocked로 중단하고 evaluator·완료·커밋을 진행하지 않는다. |
| NEG-02 | 버그 수정 중 신규 쿠키·세션 분기가 추가된다. | lean 예외를 시도한다. | full-risk로 재분류하고 security-auditor를 포함한다. |
| NEG-03 | UI evaluator는 approved지만 사용자 검증이 없다. | phase-5-complete를 검증한다. | `사용자 검증: 통과`가 없으므로 needs-input이며 문서를 수정하지 않는다. |
| NEG-04 | DB 연결·fixture setup이 실패했다. | data-layer가 Red를 분류한다. | `red-blocked`로 반환하고 Green 구현을 시작하지 않는다. |
| NEG-05 | 같은 security 위험이 반복됐다. | 학습 신호를 발행한다. | 선택 agent와 코퍼스가 있으면 security-repeat을 docs/compound/security/에 기록하고 없으면 pending만 보존한다. |
| NEG-06 | compound-curator가 timeout됐다. | queue를 복구한다. | 같은 ID를 pending으로 되돌리고 원본을 삭제하지 않는다. |
| NEG-07 | agent 반환에 공통 키나 request_id가 없다. | 오케스트레이터가 계약을 검사한다. | 형식 재전송을 1회 요구하고 복구 전 다음 단계로 진행하지 않는다. |
| NEG-08 | 허용되지 않은 phase/발신자 조합이다. | 전이 검증기를 실행한다. | non-zero로 거부하고 상태 문서를 수정하지 않는다. |
| NEG-09 | auto 커밋이지만 commit-local이 없거나 ask 승인이 없다. | 완료 보고에 진입한다. | 커밋하지 않고 정책과 상태를 보고한다. |
| NEG-10 | 이전 request의 최신 보고서가 남아 있다. | evaluator 입력을 구성한다. | 현재 request_id의 정확한 보고서만 사용한다. |
| NEG-11 | component 파일의 클릭·상태·데이터 표시 버그다. | 시각 전용 스킵을 시도한다. | 기능형으로 분류해 evaluator를 실행한다. |
| NEG-12 | 일반 문서·스크립트 task에 구현 override가 없다. | 역할을 선택한다. | data-layer에 임의 배정하지 않고 오케스트레이터가 직접 수행한다. |
| NEG-13 | acknowledgement ID가 pending 대상 ID와 다르다. | queue 제거를 시도한다. | 대상 ID가 일치하지 않으므로 pending을 유지한다. |
| NEG-14 | security가 inconclusive이거나 evaluator blocking이 남았다. | 완료를 요청한다. | 감사 모드는 진단만 계속하고 완료·커밋은 금지한다. |

# 정적 검증

- 정상 8개와 부정 14개 ID가 각각 한 번 존재해야 한다.
- source agent 목록과 topology manifest의 합집합이 일치해야 한다.
- lean 기본 설치는 core 6개, full 설치는 source 전체를 사용한다.
- direct skill mode와 custom agent 역할을 중복 설치하지 않는다.
