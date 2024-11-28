;; Social Impact Bond Smart Contract
;; Implements a transparent and automated SIB management system

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-registered (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-unauthorized (err u104))
(define-constant err-invalid-state (err u105))
(define-constant err-withdrawal-locked (err u106))

;; Events
(define-data-var event-counter uint u0)

(define-map Events
    uint
    {
        event-type: (string-ascii 20),
        data: (string-ascii 100),
        timestamp: uint,
        triggered-by: principal
    }
)

;; Data Maps
(define-map Stakeholders
    principal
    {
        role: (string-ascii 20),           
        status: (string-ascii 10),         
        joined-at: uint,
        reputation-score: uint             ;; New: Added reputation tracking
    }
)

(define-map Investments
    principal
    {
        amount: uint,
        committed-at: uint,
        terms: (string-ascii 50),          
        status: (string-ascii 10),
        withdrawal-locked-until: uint,     ;; New: Added withdrawal lock period
        performance-threshold: uint        ;; New: Added performance requirement
    }
)

(define-map Outcomes
    uint
    {
        metric: (string-ascii 50),         
        target: uint,                      
        achieved: uint,                    
        verified: bool,                    
        evaluator: principal,
        verification-count: uint,          ;; New: Multiple verifications required
        verifiers: (list 5 principal),     ;; New: List of verifiers
        confidence-score: uint            ;; New: Verification confidence
    }
)

(define-map PaymentSchedule uint {
    amount: uint,
    due-date: uint,
    status: (string-ascii 10),
    recipient: principal,
    outcome-dependency: uint              ;; New: Link payment to specific outcome
})

;; Data Variables
(define-data-var current-outcome-id uint u0)
(define-data-var current-payment-id uint u0)
(define-data-var program-status (string-ascii 10) "active")
(define-data-var total-invested uint u0)
(define-data-var required-verifications uint u3)  ;; New: Minimum verifications needed

;; Event Logging
(define-private (log-event (event-type (string-ascii 20)) (data (string-ascii 100)))
    (let ((event-id (+ (var-get event-counter) u1)))
        (map-set Events
            event-id
            {
                event-type: event-type,
                data: data,
                timestamp: block-height,
                triggered-by: tx-sender
            }
        )
        (var-set event-counter event-id)
        event-id
    )
)


;; Enhanced Private Functions
(define-private (is-contract-owner)
    (is-eq tx-sender contract-owner)
)

(define-private (is-authorized-role (caller principal) (required-role (string-ascii 20)))
    (match (map-get? Stakeholders caller)
        stakeholder (is-eq (get role stakeholder) required-role)
        false
    )
)

(define-private (update-reputation (address principal) (change int))
    (match (map-get? Stakeholders address)
        stakeholder 
        (let ((new-score (+ (get reputation-score stakeholder) change)))
            (map-set Stakeholders
                address
                (merge stakeholder { reputation-score: new-score })
            )
            (ok new-score)
        )
        err-not-found
    )
)

;; New: Investment Withdrawal Logic
(define-public (request-withdrawal (amount uint))
    (let (
        (caller tx-sender)
        (investment (unwrap! (map-get? Investments caller) err-not-found))
        (current-block block-height)
    )
    (asserts! (is-authorized-role caller "investor") err-unauthorized)
    (asserts! (>= current-block (get withdrawal-locked-until investment)) err-withdrawal-locked)
    (asserts! (<= amount (get amount investment)) err-invalid-amount)
    
    ;; Check if performance thresholds are met
    (asserts! (>= (get-program-performance) (get performance-threshold investment)) err-invalid-state)
    
    ;; Update investment amount and log event
    (map-set Investments
        caller
        (merge investment {
            amount: (- (get amount investment) amount),
            status: (if (is-eq amount (get amount investment)) "withdrawn" "partial")
        })
    )
    
    (var-set total-invested (- (var-get total-invested) amount))
    (log-event "withdrawal" "funds-withdrawn")
    (ok true)))

;; Enhanced Outcome Verification
(define-public (verify-outcome-enhanced (outcome-id uint) (confidence uint))
    (let (
        (caller tx-sender)
        (outcome (unwrap! (map-get? Outcomes outcome-id) err-not-found))
    )
    (asserts! (is-authorized-role caller "evaluator") err-unauthorized)
    (asserts! (< (get verification-count outcome) (var-get required-verifications)) err-already-registered)
    (asserts! (not (is-some (index-of (get verifiers outcome) caller))) err-already-registered)
    
    (let (
        (new-verifiers (unwrap! (as-max-len? (append (get verifiers outcome) caller) u5) err-invalid-state))
        (new-count (+ (get verification-count outcome) u1))
        (new-confidence (/ (+ (* (get confidence-score outcome) (get verification-count outcome)) confidence) new-count))
    )
        
        (map-set Outcomes
            outcome-id
            (merge outcome {
                verification-count: new-count,
                verifiers: new-verifiers,
                confidence-score: new-confidence,
                verified: (>= new-count (var-get required-verifications))
            })
        )
        
        ;; Update evaluator reputation based on consensus
        (if (>= new-count (var-get required-verifications))
            (update-reputation caller u1)
            true
        )
        
        (log-event "verification" "outcome-verified")
        (ok true)
    ))
)


;; Read-only Functions for Events
(define-read-only (get-event (event-id uint))
    (map-get? Events event-id)
)

(define-read-only (get-latest-events (count uint))
    (let ((latest-id (var-get event-counter)))
        (list 
            (get-event latest-id)
            (get-event (- latest-id u1))
            (get-event (- latest-id u2))
        )
    )
)

;; New: Performance Calculation
(define-read-only (get-program-performance)
    (let ((total-outcomes (var-get current-outcome-id)))
        (fold check-outcome-performance u0 (list u1 u2 u3 u4 u5))
    )
)

(define-private (check-outcome-performance (id uint) (current-performance uint))
    (match (map-get? Outcomes id)
        outcome (if (and (get verified outcome) (>= (get achieved outcome) (get target outcome)))
                   (+ current-performance u20)
                   current-performance)
        current-performance
    )
)
