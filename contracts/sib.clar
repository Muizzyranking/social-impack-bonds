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

;; Private Functions
(define-private (is-contract-owner)
    (is-eq tx-sender contract-owner)
)

(define-private (is-authorized-role (caller principal) (required-role (string-ascii 20)))
    (match (map-get? Stakeholders caller)
        stakeholder (is-eq (get role stakeholder) required-role)
        false
    )
)

;; Public Functions
(define-public (register-stakeholder (role (string-ascii 20)))
    (let (
        (caller tx-sender)
    )
    (asserts! (is-contract-owner) err-owner-only)
    (asserts! (is-none (map-get? Stakeholders caller)) err-already-registered)
    
    (ok (map-set Stakeholders
        caller
        {
            role: role,
            status: "active",
            joined-at: block-height
        }
    ))))

(define-public (invest (amount uint) (terms (string-ascii 50)))
    (let (
        (caller tx-sender)
    )
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (is-authorized-role caller "investor") err-unauthorized)
    
    (map-set Investments
        caller
        {
            amount: amount,
            committed-at: block-height,
            terms: terms,
            status: "active"
        }
    )
    (var-set total-invested (+ (var-get total-invested) amount))
    (ok true)))

(define-public (report-outcome 
    (metric (string-ascii 50))
    (target uint)
    (achieved uint)
)
    (let (
        (caller tx-sender)
        (outcome-id (+ (var-get current-outcome-id) u1))
    )
    (asserts! (is-authorized-role caller "evaluator") err-unauthorized)
    
    (map-set Outcomes
        outcome-id
        {
            metric: metric,
            target: target,
            achieved: achieved,
            verified: false,
            evaluator: caller
        }
    )
    (var-set current-outcome-id outcome-id)
    (ok outcome-id)))

(define-public (verify-outcome (outcome-id uint))
    (let (
        (caller tx-sender)
        (outcome (unwrap! (map-get? Outcomes outcome-id) err-not-found))
    )
    (asserts! (is-authorized-role caller "evaluator") err-unauthorized)
    (asserts! (not (get verified outcome)) err-already-registered)
    
    (map-set Outcomes
        outcome-id
        (merge outcome { verified: true })
    )
    (ok true)))

(define-public (schedule-payment 
    (amount uint)
    (due-date uint)
    (recipient principal)
)
    (let (
        (caller tx-sender)
        (payment-id (+ (var-get current-payment-id) u1))
    )
    (asserts! (is-contract-owner) err-owner-only)
    
    (map-set PaymentSchedule
        payment-id
        {
            amount: amount,
            due-date: due-date,
            status: "pending",
            recipient: recipient
        }
    )
    (var-set current-payment-id payment-id)
    (ok payment-id)))

;; Read-only Functions
(define-read-only (get-stakeholder (address principal))
    (map-get? Stakeholders address)
)

(define-read-only (get-investment (investor principal))
    (map-get? Investments investor)
)

(define-read-only (get-outcome (outcome-id uint))
    (map-get? Outcomes outcome-id)
)

(define-read-only (get-payment (payment-id uint))
    (map-get? PaymentSchedule payment-id)
)

(define-read-only (get-program-stats)
    {
        total-invested: (var-get total-invested),
        outcomes-reported: (var-get current-outcome-id),
        payments-scheduled: (var-get current-payment-id),
        status: (var-get program-status)
    }
)
