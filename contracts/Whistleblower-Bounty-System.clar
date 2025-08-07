(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_REPORT (err u101))
(define-constant ERR_REPORT_NOT_FOUND (err u102))
(define-constant ERR_ALREADY_VERIFIED (err u103))
(define-constant ERR_INSUFFICIENT_FUNDS (err u104))
(define-constant ERR_INVALID_STATUS (err u105))
(define-constant ERR_ALREADY_VALIDATED (err u106))

(define-data-var total-reports-submitted uint u0)
(define-data-var total-reports-approved uint u0)
(define-data-var total-reports-rejected uint u0)
(define-data-var total-rewards-distributed uint u0)
(define-data-var total-verified-whistleblowers uint u0)

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