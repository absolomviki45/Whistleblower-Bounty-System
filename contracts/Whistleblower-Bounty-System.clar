(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_REPORT (err u101))
(define-constant ERR_REPORT_NOT_FOUND (err u102))
(define-constant ERR_ALREADY_VERIFIED (err u103))
(define-constant ERR_INSUFFICIENT_FUNDS (err u104))
(define-constant ERR_INVALID_STATUS (err u105))
(define-constant ERR_ALREADY_VALIDATED (err u106))

(define-constant ERR_INVALID_ESCALATION (err u107))
(define-constant ERR_WINDOW_NOT_FOUND (err u108))

(define-constant ERR_APPEAL_WINDOW_CLOSED (err u109))
(define-constant ERR_CANNOT_APPEAL_STATUS (err u110))
(define-constant ERR_ALREADY_APPEALED (err u111))

(define-data-var appeal-window-blocks uint u144)
(define-data-var appeal-fee uint u100)

(define-data-var next-window-id uint u1)

(define-data-var total-reports-submitted uint u0)
(define-data-var total-reports-approved uint u0)
(define-data-var total-reports-rejected uint u0)
(define-data-var total-rewards-distributed uint u0)
(define-data-var total-verified-whistleblowers uint u0)

(define-data-var reputation-decay-factor uint u95)
(define-data-var max-reputation-score uint u1000)
(define-data-var min-reputation-score uint u100)

(define-fungible-token bounty-token)

(define-data-var next-report-id uint u1)
(define-data-var reward-amount uint u1000)
(define-data-var contract-balance uint u0)

(define-map verified-whistleblowers principal bool)
(define-map reports 
  uint 
  {
    reporter: principal,
    report-hash: (buff 32),
    submission-block: uint,
    status: (string-ascii 10),
    reward-paid: bool,
    validator: (optional principal)
  }
)

(define-map report-votes 
  {report-id: uint, validator: principal}
  {vote: bool, block-height: uint}
)

(define-read-only (get-report (report-id uint))
  (map-get? reports report-id)
)

(define-read-only (is-verified-whistleblower (user principal))
  (default-to false (map-get? verified-whistleblowers user))
)

(define-read-only (get-reward-amount)
  (var-get reward-amount)
)

(define-read-only (get-contract-balance)
  (var-get contract-balance)
)

(define-read-only (get-next-report-id)
  (var-get next-report-id)
)

(define-read-only (get-total-supply)
  (ft-get-supply bounty-token)
)

(define-read-only (get-balance (user principal))
  (ft-get-balance bounty-token user)
)

(define-public (verify-whistleblower (whistleblower principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (not (is-verified-whistleblower whistleblower)) ERR_ALREADY_VERIFIED)
    (ok (map-set verified-whistleblowers whistleblower true))
  )
)

(define-public (submit-report (report-hash (buff 32)))
  (let 
    (
      (report-id (var-get next-report-id))
      (current-block stacks-block-height)
    )
    (asserts! (is-verified-whistleblower tx-sender) ERR_UNAUTHORIZED)
    (asserts! (> (len report-hash) u0) ERR_INVALID_REPORT)
    (map-set reports report-id {
      reporter: tx-sender,
      report-hash: report-hash,
      submission-block: current-block,
      status: "pending",
      reward-paid: false,
      validator: none
    })
    (var-set next-report-id (+ report-id u1))
    (ok report-id)
  )
)

(define-public (validate-report (report-id uint) (is-valid bool))
  (let 
    (
      (report (unwrap! (map-get? reports report-id) ERR_REPORT_NOT_FOUND))
      (current-block stacks-block-height)
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status report) "pending") ERR_ALREADY_VALIDATED)
    (map-set reports report-id (merge report {
      status: (if is-valid "approved" "rejected"),
      validator: (some tx-sender)
    }))
    (if is-valid
      (distribute-reward report-id)
      (ok false)
    )
  )
)

(define-public (fund-contract (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (try! (ft-mint? bounty-token amount tx-sender))
    (var-set contract-balance (+ (var-get contract-balance) amount))
    (ok true)
  )
)

(define-public (set-reward-amount (new-amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set reward-amount new-amount)
    (ok true)
  )
)

(define-public (transfer-tokens (recipient principal) (amount uint))
  (begin
    (asserts! (>= (ft-get-balance bounty-token tx-sender) amount) ERR_INSUFFICIENT_FUNDS)
    (ft-transfer? bounty-token amount tx-sender recipient)
  )
)

(define-private (distribute-reward (report-id uint))
  (let 
    (
      (report (unwrap! (map-get? reports report-id) ERR_REPORT_NOT_FOUND))
      (reward (var-get reward-amount))
      (reporter (get reporter report))
    )
    (asserts! (not (get reward-paid report)) ERR_ALREADY_VALIDATED)
    (asserts! (>= (var-get contract-balance) reward) ERR_INSUFFICIENT_FUNDS)
    (try! (ft-transfer? bounty-token reward CONTRACT_OWNER reporter))
    (map-set reports report-id (merge report {reward-paid: true}))
    (var-set contract-balance (- (var-get contract-balance) reward))
    (ok true)
  )
)

(define-public (emergency-withdraw)
  (let 
    (
      (contract-bal (var-get contract-balance))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> contract-bal u0) ERR_INSUFFICIENT_FUNDS)
    (try! (ft-transfer? bounty-token contract-bal CONTRACT_OWNER tx-sender))
    (var-set contract-balance u0)
    (ok contract-bal)
  )
)

(define-public (get-report-status (report-id uint))
  (let 
    (
      (report (unwrap! (map-get? reports report-id) ERR_REPORT_NOT_FOUND))
    )
    (ok {
      status: (get status report),
      reward-paid: (get reward-paid report),
      submission-block: (get submission-block report),
      validator: (get validator report)
    })
  )
)

(define-public (vote-on-report (report-id uint) (vote bool))
  (let 
    (
      (report (unwrap! (map-get? reports report-id) ERR_REPORT_NOT_FOUND))
      (current-block stacks-block-height)
    )
    (asserts! (is-verified-whistleblower tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status report) "pending") ERR_ALREADY_VALIDATED)
    (map-set report-votes {report-id: report-id, validator: tx-sender} {
      vote: vote,
      block-height: current-block
    })
    (ok true)
  )
)

(define-read-only (get-vote (report-id uint) (validator principal))
  (map-get? report-votes {report-id: report-id, validator: validator})
)

(begin
  (try! (ft-mint? bounty-token u10000 CONTRACT_OWNER))
  (var-set contract-balance u10000)
)


(define-read-only (get-system-statistics)
  (let 
    (
      (total-submitted (var-get total-reports-submitted))
      (total-approved (var-get total-reports-approved))
      (total-rejected (var-get total-reports-rejected))
    )
    (ok {
      total-reports: total-submitted,
      approved-reports: total-approved,
      rejected-reports: total-rejected,
      pending-reports: (- total-submitted (+ total-approved total-rejected)),
      approval-rate: (if (> total-submitted u0) 
                      (/ (* total-approved u100) total-submitted) 
                      u0),
      total-rewards-paid: (var-get total-rewards-distributed),
      verified-users: (var-get total-verified-whistleblowers)
    })
  )
)

(define-read-only (get-reporter-performance (reporter principal))
  (let 
    (
      (user-reports (filter-reports-by-reporter reporter (var-get next-report-id)))
    )
    (ok {
      total-submissions: (get total user-reports),
      approved-submissions: (get approved user-reports),
      success-rate: (if (> (get total user-reports) u0)
                     (/ (* (get approved user-reports) u100) (get total user-reports))
                     u0)
    })
  )
)

(define-read-only (get-monthly-report-trend (month uint))
  (let 
    (
      (current-block stacks-block-height)
      (blocks-per-month u4320)
      (month-start (- current-block (* month blocks-per-month)))
      (month-end (- current-block (* (- month u1) blocks-per-month)))
    )
    (ok {
      month-identifier: month,
      reports-in-period: (count-reports-in-range month-start month-end),
      rewards-distributed: (calculate-period-rewards month-start month-end)
    })
  )
)

(define-private (filter-reports-by-reporter (reporter principal) (max-id uint))
  (fold check-reporter-report (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) {total: u0, approved: u0, reporter: reporter})
)

(define-private (check-reporter-report (report-id uint) (acc {total: uint, approved: uint, reporter: principal}))
  (match (map-get? reports report-id)
    report (if (is-eq (get reporter report) (get reporter acc))
             (if (is-eq (get status report) "approved")
               {total: (+ (get total acc) u1), approved: (+ (get approved acc) u1), reporter: (get reporter acc)}
               {total: (+ (get total acc) u1), approved: (get approved acc), reporter: (get reporter acc)})
             acc)
    acc
  )
)

(define-private (count-reports-in-range (start-block uint) (end-block uint))
  (get count (fold count-reports-in-period (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) {count: u0, start: start-block, end: end-block}))
)

(define-private (count-reports-in-period (report-id uint) (data {count: uint, start: uint, end: uint}))
  (match (map-get? reports report-id)
    report (if (and (>= (get submission-block report) (get start data)) 
                    (<= (get submission-block report) (get end data)))
             {count: (+ (get count data) u1), start: (get start data), end: (get end data)}
             data)
    data)
)

(define-private (calculate-period-rewards (start-block uint) (end-block uint))
  (get total (fold sum-period-rewards-data (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) {total: u0, start: start-block, end: end-block}))
)

(define-private (sum-period-rewards-data (report-id uint) (data {total: uint, start: uint, end: uint}))
  (match (map-get? reports report-id)
    report (if (and (>= (get submission-block report) (get start data)) 
                    (<= (get submission-block report) (get end data))
                    (get reward-paid report))
             {total: (+ (get total data) (var-get reward-amount)), start: (get start data), end: (get end data)}
             data)
    data)
)


(define-map whistleblower-reputation
  principal
  {
    score: uint,
    total-submissions: uint,
    approved-submissions: uint,
    total-votes: uint,
    last-activity-block: uint
  }
)

(define-read-only (get-reputation-score (user principal))
  (match (map-get? whistleblower-reputation user)
    reputation-data (ok (get score reputation-data))
    (ok u0)
  )
)

(define-read-only (get-full-reputation-data (user principal))
  (match (map-get? whistleblower-reputation user)
    reputation-data (ok reputation-data)
    (ok {score: u0, total-submissions: u0, approved-submissions: u0, total-votes: u0, last-activity-block: u0})
  )
)

(define-read-only (calculate-reputation-score (submissions uint) (approved uint) (votes uint))
  (let
    (
      (base-score u500)
      (accuracy-bonus (if (> submissions u0) 
                        (/ (* approved u300) submissions) 
                        u0))
      (participation-bonus (if (> (* votes u10) u200) u200 (* votes u10)))
      (calculated-score (+ base-score (+ accuracy-bonus participation-bonus)))
    )
    (if (> calculated-score (var-get max-reputation-score)) 
        (var-get max-reputation-score) 
        calculated-score)
  )
)

(define-private (update-reputation-on-validation (reporter principal) (approved bool))
  (let
    (
      (current-data (unwrap-panic (get-full-reputation-data reporter)))
      (new-submissions (+ (get total-submissions current-data) u1))
      (new-approved (if approved 
                      (+ (get approved-submissions current-data) u1)
                      (get approved-submissions current-data)))
      (current-votes (get total-votes current-data))
      (new-score (calculate-reputation-score new-submissions new-approved current-votes))
    )
    (map-set whistleblower-reputation reporter {
      score: new-score,
      total-submissions: new-submissions,
      approved-submissions: new-approved,
      total-votes: current-votes,
      last-activity-block: stacks-block-height
    })
  )
)

(define-private (update-reputation-on-vote (voter principal))
  (let
    (
      (current-data (unwrap-panic (get-full-reputation-data voter)))
      (new-votes (+ (get total-votes current-data) u1))
      (current-submissions (get total-submissions current-data))
      (current-approved (get approved-submissions current-data))
      (new-score (calculate-reputation-score current-submissions current-approved new-votes))
    )
    (map-set whistleblower-reputation voter {
      score: new-score,
      total-submissions: current-submissions,
      approved-submissions: current-approved,
      total-votes: new-votes,
      last-activity-block: stacks-block-height
    })
  )
)

(define-public (initialize-reputation (user principal))
  (begin
    (asserts! (is-verified-whistleblower user) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? whistleblower-reputation user)) ERR_ALREADY_VERIFIED)
    (ok (map-set whistleblower-reputation user {
      score: u500,
      total-submissions: u0,
      approved-submissions: u0,
      total-votes: u0,
      last-activity-block: stacks-block-height
    }))
  )
)

(define-map escalation-windows
  uint
  {
    start-block: uint,
    end-block: uint,
    multiplier-percent: uint,
    active: bool,
    created-at: uint
  }
)

(define-read-only (get-escalation-window (window-id uint))
  (map-get? escalation-windows window-id)
)

(define-read-only (calculate-escalated-reward (base-reward uint) (submission-block uint))
  (let
    (
      (window-search (find-active-window submission-block (var-get next-window-id)))
      (applicable-multiplier (get result window-search))
    )
    (match applicable-multiplier
      window-data (ok (/ (* base-reward (get multiplier-percent window-data)) u100))
      (ok base-reward)
    )
  )
)

(define-private (find-active-window (target-height uint) (max-window-id uint))
  (fold check-window-match 
    (list u1 u2 u3 u4 u5) 
    {target-block: target-height, result: none}
  )
)

(define-private (check-window-match 
  (window-id uint) 
  (acc {target-block: uint, result: (optional {multiplier-percent: uint})})
)
  (if (is-some (get result acc))
    acc
    (match (map-get? escalation-windows window-id)
      window (if (and (get active window)
                      (>= (get target-block acc) (get start-block window))
                      (<= (get target-block acc) (get end-block window)))
               {target-block: (get target-block acc), 
                result: (some {multiplier-percent: (get multiplier-percent window)})}
               acc)
      acc
    )
  )
)

(define-public (create-escalation-window (start-block uint) (end-block uint) (multiplier-percent uint))
  (let
    (
      (window-id (var-get next-window-id))
      (current-block stacks-block-height)
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (< start-block end-block) ERR_INVALID_ESCALATION)
    (asserts! (and (>= multiplier-percent u100) (<= multiplier-percent u300)) ERR_INVALID_ESCALATION)
    (map-set escalation-windows window-id {
      start-block: start-block,
      end-block: end-block,
      multiplier-percent: multiplier-percent,
      active: true,
      created-at: current-block
    })
    (var-set next-window-id (+ window-id u1))
    (ok window-id)
  )
)

(define-public (toggle-escalation-window (window-id uint) (active-status bool))
  (let
    (
      (window (unwrap! (map-get? escalation-windows window-id) ERR_WINDOW_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (ok (map-set escalation-windows window-id (merge window {active: active-status})))
  )
)


(define-map report-appeals
  uint
  {
    appealed-by: principal,
    appeal-block: uint,
    appeal-reason-hash: (buff 32),
    appeal-status: (string-ascii 10),
    appeal-decision-block: (optional uint),
    fee-refunded: bool
  }
)

(define-read-only (get-appeal-info (report-id uint))
  (map-get? report-appeals report-id)
)

(define-read-only (is-appeal-window-open (submission-block uint))
  (let
    (
      (current-block stacks-block-height)
      (window-duration (var-get appeal-window-blocks))
      (deadline (+ submission-block window-duration))
    )
    (<= current-block deadline)
  )
)

(define-public (submit-appeal (report-id uint) (reason-hash (buff 32)))
  (let
    (
      (report (unwrap! (map-get? reports report-id) ERR_REPORT_NOT_FOUND))
      (current-block stacks-block-height)
      (fee (var-get appeal-fee))
    )
    (asserts! (is-eq tx-sender (get reporter report)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status report) "rejected") ERR_CANNOT_APPEAL_STATUS)
    (asserts! (is-none (map-get? report-appeals report-id)) ERR_ALREADY_APPEALED)
    (asserts! (is-appeal-window-open (get submission-block report)) ERR_APPEAL_WINDOW_CLOSED)
    (asserts! (>= (ft-get-balance bounty-token tx-sender) fee) ERR_INSUFFICIENT_FUNDS)
    (try! (ft-transfer? bounty-token fee tx-sender CONTRACT_OWNER))
    (map-set report-appeals report-id {
      appealed-by: tx-sender,
      appeal-block: current-block,
      appeal-reason-hash: reason-hash,
      appeal-status: "pending",
      appeal-decision-block: none,
      fee-refunded: false
    })
    (ok true)
  )
)

(define-public (process-appeal (report-id uint) (approve-appeal bool))
  (let
    (
      (report (unwrap! (map-get? reports report-id) ERR_REPORT_NOT_FOUND))
      (appeal (unwrap! (map-get? report-appeals report-id) ERR_REPORT_NOT_FOUND))
      (current-block stacks-block-height)
      (fee (var-get appeal-fee))
      (appellant (get appealed-by appeal))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get appeal-status appeal) "pending") ERR_ALREADY_VALIDATED)
    (map-set report-appeals report-id (merge appeal {
      appeal-status: (if approve-appeal "accepted" "denied"),
      appeal-decision-block: (some current-block)
    }))
    (if approve-appeal
      (begin
        (map-set reports report-id (merge report {status: "approved"}))
        (try! (ft-transfer? bounty-token fee CONTRACT_OWNER appellant))
        (map-set report-appeals report-id (merge (unwrap-panic (map-get? report-appeals report-id)) {fee-refunded: true}))
        (distribute-reward report-id))
      (ok false))
  )
)