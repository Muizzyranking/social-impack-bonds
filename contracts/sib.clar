;; Social Impact Bond Smart Contract
;; Enhanced security and features implementation

;; Constants
(define-constant contract-owner tx-sender)
(define-constant min-investment u1000000) ;; Minimum investment amount
(define-constant max-verifiers u5)
(define-constant performance-increment u20)

;; Error codes
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-registered (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-unauthorized (err u104))
(define-constant err-invalid-state (err u105))
(define-constant err-withdrawal-locked (err u106))
(define-constant err-min-investment (err u107))
(define-constant err-max-capacity (err u108))
(define-constant err-inactive (err u109))

;; Data Variables with improved tracking
(define-data-var event-counter uint u0)
(define-data-var current-outcome-id uint u0)
(define-data-var current-payment-id uint u0)
(define-data-var program-status (string-ascii 10) "active")
(define-data-var total-invested uint u0)
(define-data-var required-verifications uint u3)
(define-data-var total-participants uint u0)
(define-data-var program-capacity uint u1000)

;; Enhanced Events structure
(define-map Events
    uint
    {
        event-type: (string-ascii 20),
        data: (string-ascii 100),
        timestamp: uint,
        triggered-by: principal,
        block: uint
    }
)

;; Improved Stakeholders with more detailed tracking
(define-map Stakeholders
    principal
    {
        role: (string-ascii 20),
        status: (string-ascii 10),
        joined-at: uint,
        reputation-score: uint,
        total-transactions: uint,
        last-active: uint
    }
)

;; Enhanced Investments with better risk management
(define-map Investments
    principal
    {
        amount: uint,
        committed-at: uint,
        terms: (string-ascii 50),
        status: (string-ascii 10),
        withdrawal-locked-until: uint,
        performance-threshold: uint,
        risk-level: (string-ascii 10),
        returns-expected: uint
    }
)

;; Improved Outcomes with enhanced verification
(define-map Outcomes
    uint
    {
        metric: (string-ascii 50),
        target: uint,
        achieved: uint,
        verified: bool,
        evaluator: principal,
        verification-count: uint,
        verifiers: (list 5 principal),
        confidence-score: uint,
        verification-deadline: uint,
        impact-score: uint
    }
)

;; Enhanced Payment Schedule
(define-map PaymentSchedule 
    uint 
    {
        amount: uint,
        due-date: uint,
        status: (string-ascii 10),
        recipient: principal,
        outcome-dependency: uint,
        penalty-rate: uint,
        bonus-rate: uint
    }
)

;; Private Functions
(define-private (log-event (event-type (string-ascii 20)) (data (string-ascii 100)))
    (let ((event-id (+ (var-get event-counter) u1)))
        (map-set Events
            event-id
            {
                event-type: event-type,
                data: data,
                timestamp: burn-block-height,
                triggered-by: tx-sender,
                block: burn-block-height
            }
        )
        (var-set event-counter event-id)
        event-id
    )
)

;; Enhanced authorization with multi-level checks
(define-private (is-authorized (caller principal) (required-role (string-ascii 20)))
    (match (map-get? Stakeholders caller)
        stakeholder (and 
            (is-eq (get role stakeholder) required-role)
            (is-eq (get status stakeholder) "active")
            (> (get reputation-score stakeholder) u0)
        )
        false
    )
)

;; New: Risk Assessment Function
(define-private (calculate-risk-level (amount uint) (performance-history uint))
    (if (> amount u10000000)
        (if (< performance-history u50)
            "high"
            "medium"
        )
        "low"
    )
)

;; Enhanced Investment Function
(define-public (make-investment (amount uint) (terms (string-ascii 50)))
    (let
        (
            (caller tx-sender)
            (current-block burn-block-height)
        )
        (asserts! (is-eq (var-get program-status) "active") err-inactive)
        (asserts! (>= amount min-investment) err-min-investment)
        (asserts! (< (var-get total-participants) (var-get program-capacity)) err-max-capacity)
        
        (map-set Investments
            caller
            {
                amount: amount,
                committed-at: current-block,
                terms: terms,
                status: "active",
                withdrawal-locked-until: (+ current-block u1000),
                performance-threshold: u70,
                risk-level: (calculate-risk-level amount u50),
                returns-expected: (+ amount (/ amount u10))
            }
        )
        
        (var-set total-invested (+ (var-get total-invested) amount))
        (var-set total-participants (+ (var-get total-participants) u1))
        (log-event "investment" "new-investment-made")
        (ok true)
    )
)

;; Enhanced Outcome Verification System
(define-public (verify-outcome 
    (outcome-id uint) 
    (achieved-value uint) 
    (confidence uint)
)
    (let (
        (caller tx-sender)
        (outcome (unwrap! (map-get? Outcomes outcome-id) err-not-found))
        (current-block burn-block-height)
    )
        (asserts! (is-authorized caller "evaluator") err-unauthorized)
        (asserts! (<= current-block (get verification-deadline outcome)) err-invalid-state)
        (asserts! (< (get verification-count outcome) (var-get required-verifications)) err-already-registered)
        (asserts! (not (is-some (index-of (get verifiers outcome) caller))) err-already-registered)
        
        (let (
            ;; (new-verifiers (unwrap! (as-max-len? (append (get verifiers outcome) caller) max-verifiers) err-invalid-state))
            (new-verifiers (if (< (len (get verifiers outcome)) max-verifiers)
                               (unwrap! (as-max-len? (append (get verifiers outcome) caller) max-verifiers) err-invalid-state)
                               (unwrap! none err-max-capacity)
            ))
            (new-count (+ (get verification-count outcome) u1))
            (new-confidence (/ (+ (* (get confidence-score outcome) (get verification-count outcome)) confidence) new-count))
            (impact-score (calculate-impact-score achieved-value (get target outcome)))
        )
            (map-set Outcomes
                outcome-id
                (merge outcome {
                    verification-count: new-count,
                    verifiers: new-verifiers,
                    confidence-score: new-confidence,
                    achieved: achieved-value,
                    impact-score: impact-score,
                    verified: (>= new-count (var-get required-verifications))
                })
            )
            
            (update-evaluator-reputation caller new-confidence)
            (process-outcome-payments outcome-id)
            (log-event "verification" "outcome-verified")
            (ok true)
        )
    )
)

;; New: Impact Score Calculation
(define-private (calculate-impact-score (achieved uint) (target uint))
    (if (>= achieved target)
        (+ u100 (* (- achieved target) u10))
        (* (/ (* achieved u100) target) u1)
    )
)

;; Enhanced Reputation System
(define-private (update-evaluator-reputation (evaluator principal) (confidence uint))
    (match (map-get? Stakeholders evaluator)
        stakeholder 
        (let (
            (reputation-change (if (> confidence u75) u2 u1))
            (new-score (+ (get reputation-score stakeholder) reputation-change))
            (new-transactions (+ (get total-transactions stakeholder) u1))
        )
            (map-set Stakeholders
                evaluator
                (merge stakeholder { 
                    reputation-score: new-score,
                    total-transactions: new-transactions,
                    last-active: burn-block-height
                })
            )
            (ok new-score)
        )
        err-not-found
    )
)

;; Enhanced Withdrawal System with Safety Checks
(define-public (request-withdrawal (amount uint))
    (let (
        (caller tx-sender)
        (investment (unwrap! (map-get? Investments caller) err-not-found))
        (current-block burn-block-height)
    )
        (asserts! (is-authorized caller "investor") err-unauthorized)
        (asserts! (>= current-block (get withdrawal-locked-until investment)) err-withdrawal-locked)
        (asserts! (<= amount (get amount investment)) err-invalid-amount)
        (asserts! (is-eq (var-get program-status) "active") err-inactive)
        
        ;; Performance and risk checks
        (let (
            (performance (get-program-performance))
            (risk-level (get risk-level investment))
        )
            (asserts! (or 
                (>= performance (get performance-threshold investment))
                (is-eq risk-level "low")
            ) err-invalid-state)
            
            ;; Calculate withdrawal penalties or bonuses
            (let (
                (adjusted-amount (calculate-withdrawal-amount amount performance risk-level))
                (new-amount (- (get amount investment) amount))
            )
                (map-set Investments
                    caller
                    (merge investment {
                        amount: new-amount,
                        status: (if (is-eq new-amount u0) "withdrawn" "partial")
                    })
                )
                
                (var-set total-invested (- (var-get total-invested) amount))
                (log-event "withdrawal" "funds-withdrawn")
                (ok adjusted-amount)
            )
        )
    )
)

;; New: Dynamic Withdrawal Amount Calculation
(define-private (calculate-withdrawal-amount (amount uint) (performance uint) (risk-level (string-ascii 10)))
    (let (
        (base-bonus (if (> performance u90) (/ amount u10) u0))
        (risk-penalty (match risk-level
            "high" (/ amount u20)
            "medium" (/ amount u50)
            "low" u0
            u0
        ))
    )
        (+ (- amount risk-penalty) base-bonus)
    )
)

;; Enhanced Performance Calculation
(define-read-only (get-program-performance)
    (let (
        (total-outcomes (var-get current-outcome-id))
        (verified-outcomes (get-verified-outcomes-count))
    )
        (if (is-eq verified-outcomes u0)
            u0
            (/ (* (fold check-outcome-performance u0 (generate-outcome-list total-outcomes)) u100)
               (* verified-outcomes performance-increment))
        )
    )
)

;; Helper function to generate outcome list
(define-private (generate-outcome-list (count uint))
    (map unwrap-panic 
        (map to-uint 
            (list count)))
)

;; Enhanced outcome performance checking
(define-private (check-outcome-performance (id uint) (current-performance uint))
    (match (map-get? Outcomes id)
        outcome (if (and 
                    (get verified outcome)
                    (>= (get achieved outcome) (get target outcome))
                    (>= (get confidence-score outcome) u75))
                   (+ current-performance performance-increment)
                   current-performance)
        current-performance
    )
)

;; New: Payment Processing System
(define-public (process-outcome-payments (outcome-id uint))
    (let (
        (outcome (unwrap! (map-get? Outcomes outcome-id) err-not-found))
        (payment (unwrap! (map-get? PaymentSchedule outcome-id) err-not-found))
    )
        (asserts! (is-authorized tx-sender "admin") err-unauthorized)
        (asserts! (get verified outcome) err-invalid-state)
        
        (let (
            (impact-bonus (calculate-impact-bonus 
                (get achieved outcome) 
                (get target outcome)
                (get bonus-rate payment)))
            (final-amount (+ (get amount payment) impact-bonus))
        )
            (map-set PaymentSchedule
                outcome-id
                (merge payment {
                    status: "processed",
                    amount: final-amount
                })
            )
            (log-event "payment" "outcome-payment-processed")
            (ok final-amount)
        )
    )
)

;; New: Impact Bonus Calculation
(define-private (calculate-impact-bonus (achieved uint) (target uint) (bonus-rate uint))
    (if (> achieved target)
        (* (- achieved target) bonus-rate)
        u0
    )
)

;; New: Stakeholder Management Functions
(define-public (register-stakeholder 
    (address principal) 
    (role (string-ascii 20))
)
    (let (
        (current-block burn-block-height)
    )
        (asserts! (is-contract-owner) err-owner-only)
        (asserts! (is-none (map-get? Stakeholders address)) err-already-registered)
        
        (map-set Stakeholders
            address
            {
                role: role,
                status: "active",
                joined-at: current-block,
                reputation-score: u50,
                total-transactions: u0,
                last-active: current-block
            }
        )
        (log-event "registration" "new-stakeholder-registered")
        (ok true)
    )
)

;; New: Program Management Functions
(define-public (update-program-status (new-status (string-ascii 10)))
    (begin
        (asserts! (is-contract-owner) err-owner-only)
        (var-set program-status new-status)
        (log-event "admin" "program-status-updated")
        (ok true)
    )
)

;; Enhanced Read-Only Functions
(define-read-only (get-stakeholder-info (address principal))
    (map-get? Stakeholders address)
)

(define-read-only (get-investment-info (address principal))
    (map-get? Investments address)
)

(define-read-only (get-outcome-details (outcome-id uint))
    (map-get? Outcomes outcome-id)
)

(define-read-only (get-verified-outcomes-count)
    (fold count-verified-outcomes u0 
        (generate-outcome-list (var-get current-outcome-id)))
)

(define-private (count-verified-outcomes (id uint) (count uint))
    (match (map-get? Outcomes id)
        outcome (if (get verified outcome)
                   (+ count u1)
                   count)
        count
    )
)

;; New: Emergency Functions
(define-public (emergency-pause)
    (begin
        (asserts! (is-contract-owner) err-owner-only)
        (var-set program-status "paused")
        (log-event "emergency" "program-paused")
        (ok true)
    )
)

;; Contract owner check
(define-private (is-contract-owner)
    (is-eq tx-sender contract-owner)
)
