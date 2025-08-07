;; Yield Vault - Automated Yield Aggregation Protocol

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u100))
(define-constant err-invalid-pool (err u101))
(define-constant err-pool-exists (err u102))
(define-constant err-pool-not-found (err u103))
(define-constant err-insufficient-balance (err u104))
(define-constant err-invalid-amount (err u105))
(define-constant err-pool-paused (err u106))
(define-constant err-withdrawal-locked (err u107))
(define-constant err-max-capacity (err u108))
(define-constant err-below-minimum (err u109))
(define-constant err-invalid-tier (err u110))
(define-constant err-compound-too-soon (err u111))
(define-constant err-invalid-ratio (err u112))
(define-constant err-emergency-mode (err u113))

;; Data Variables
(define-data-var pool-counter uint u0)
(define-data-var total-value-locked uint u0)
(define-data-var performance-fee uint u200) ;; 2% = 200 basis points
(define-data-var withdrawal-fee uint u10) ;; 0.1% = 10 basis points
(define-data-var compound-bounty uint u5) ;; 0.05% reward for compounding
(define-data-var emergency-shutdown bool false)
(define-data-var total-fees-collected uint u0)

;; Data Maps
(define-map yield-pools
    uint
    {
        name: (string-utf8 50),
        tier: (string-ascii 20),
        total-deposits: uint,
        total-shares: uint,
        last-harvest: uint,
        compound-frequency: uint,
        min-deposit: uint,
        max-capacity: uint,
        lock-period: uint,
        base-apy: uint,
        current-apy: uint,
        paused: bool,
        strategy-id: uint
    }
)

(define-map user-positions
    {pool-id: uint, user: principal}
    {
        shares: uint,
        deposited: uint,
        earned: uint,
        compound-credits: uint,
        entry-block: uint,
        last-action: uint
    }
)

(define-map pool-strategies
    uint
    {
        name: (string-utf8 50),
        risk-level: uint,
        allocation-stable: uint,
        allocation-volatile: uint,
        rebalance-threshold: uint,
        last-rebalance: uint
    }
)

(define-map user-stats
    principal
    {
        total-deposited: uint,
        total-withdrawn: uint,
        total-earned: uint,
        active-pools: (list 20 uint),
        compound-count: uint
    }
)

(define-map pool-snapshots
    {pool-id: uint, block: uint}
    {
        tvl: uint,
        apy: uint,
        share-price: uint
    }
)

;; Private Functions
(define-private (calculate-shares (amount uint) (pool-id uint))
    (let ((pool (unwrap! (map-get? yield-pools pool-id) u0)))
        (if (is-eq (get total-shares pool) u0)
            amount
            (/ (* amount (get total-shares pool)) (get total-deposits pool))
        )
    )
)

(define-private (calculate-value (shares uint) (pool-id uint))
    (let ((pool (unwrap! (map-get? yield-pools pool-id) u0)))
        (if (is-eq (get total-shares pool) u0)
            u0
            (/ (* shares (get total-deposits pool)) (get total-shares pool))
        )
    )
)

(define-private (calculate-fee (amount uint) (fee-rate uint))
    (/ (* amount fee-rate) u10000)
)

(define-private (calculate-apy-boost (tier (string-ascii 20)) (lock-period uint))
    (let ((base-boost (if (is-eq tier "stable") u100
                        (if (is-eq tier "balanced") u150
                        (if (is-eq tier "aggressive") u200 u0))))
          (lock-boost (/ (* lock-period u10) u1440)))
        (+ base-boost lock-boost)
    )
)

(define-private (update-user-stats (user principal) (field (string-ascii 20)) (amount uint))
    (let ((stats (default-to {total-deposited: u0, total-withdrawn: u0, total-earned: u0,
                             active-pools: (list), compound-count: u0}
                            (map-get? user-stats user))))
        (if (is-eq field "deposited")
            (map-set user-stats user (merge stats {total-deposited: (+ (get total-deposited stats) amount)}))
        (if (is-eq field "withdrawn")
            (map-set user-stats user (merge stats {total-withdrawn: (+ (get total-withdrawn stats) amount)}))
        (if (is-eq field "earned")
            (map-set user-stats user (merge stats {total-earned: (+ (get total-earned stats) amount)}))
        (if (is-eq field "compound")
            (map-set user-stats user (merge stats {compound-count: (+ (get compound-count stats) u1)}))
            false))))
    )
)

(define-private (add-pool-to-user (user principal) (pool-id uint))
    (let ((stats (default-to {total-deposited: u0, total-withdrawn: u0, total-earned: u0,
                             active-pools: (list), compound-count: u0}
                            (map-get? user-stats user)))
          (current-pools (get active-pools stats)))
        (if (is-none (index-of current-pools pool-id))
            (match (as-max-len? (append current-pools pool-id) u20)
                new-pools (map-set user-stats user (merge stats {active-pools: new-pools}))
                false
            )
            true
        )
    )
)

(define-private (calculate-compound-rewards (pool-id uint))
    (let ((pool (unwrap! (map-get? yield-pools pool-id) u0))
          (blocks-elapsed (- stacks-block-height (get last-harvest pool)))
          (apy-rate (get current-apy pool)))
        (/ (* (get total-deposits pool) apy-rate blocks-elapsed) (* u10000 u525600))
    )
)

;; Public Functions
(define-public (create-pool (name (string-utf8 50)) (tier (string-ascii 20)) 
                           (min-deposit uint) (max-capacity uint) (lock-period uint)
                           (compound-frequency uint) (base-apy uint) (strategy-id uint))
    (let ((pool-id (+ (var-get pool-counter) u1)))
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (or (is-eq tier "stable") (or (is-eq tier "balanced") (is-eq tier "aggressive"))) err-invalid-tier)
        (asserts! (> min-deposit u0) err-invalid-amount)
        (asserts! (> max-capacity min-deposit) err-invalid-amount)
        (asserts! (<= base-apy u5000) err-invalid-ratio) ;; Max 50% base APY
        
        (map-set yield-pools pool-id {
            name: name,
            tier: tier,
            total-deposits: u0,
            total-shares: u0,
            last-harvest: stacks-block-height,
            compound-frequency: compound-frequency,
            min-deposit: min-deposit,
            max-capacity: max-capacity,
            lock-period: lock-period,
            base-apy: base-apy,
            current-apy: (+ base-apy (calculate-apy-boost tier lock-period)),
            paused: false,
            strategy-id: strategy-id
        })
        
        (var-set pool-counter pool-id)
        (ok pool-id)
    )
)

(define-public (deposit (pool-id uint) (amount uint))
    (let ((pool (unwrap! (map-get? yield-pools pool-id) err-pool-not-found))
          (shares (calculate-shares amount pool-id)))
        
        (asserts! (not (var-get emergency-shutdown)) err-emergency-mode)
        (asserts! (not (get paused pool)) err-pool-paused)
        (asserts! (>= amount (get min-deposit pool)) err-below-minimum)
        (asserts! (<= (+ (get total-deposits pool) amount) (get max-capacity pool)) err-max-capacity)
        (asserts! (>= (stx-get-balance tx-sender) amount) err-insufficient-balance)
        
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        (map-set yield-pools pool-id 
            (merge pool {
                total-deposits: (+ (get total-deposits pool) amount),
                total-shares: (+ (get total-shares pool) shares)
            }))
        
        (match (map-get? user-positions {pool-id: pool-id, user: tx-sender})
            existing-position
            (map-set user-positions {pool-id: pool-id, user: tx-sender}
                (merge existing-position {
                    shares: (+ (get shares existing-position) shares),
                    deposited: (+ (get deposited existing-position) amount),
                    last-action: stacks-block-height
                }))
            (map-set user-positions {pool-id: pool-id, user: tx-sender} {
                shares: shares,
                deposited: amount,
                earned: u0,
                compound-credits: u0,
                entry-block: stacks-block-height,
                last-action: stacks-block-height
            })
        )
        
        (var-set total-value-locked (+ (var-get total-value-locked) amount))
        (update-user-stats tx-sender "deposited" amount)
        (add-pool-to-user tx-sender pool-id)
        
        (ok shares)
    )
)

(define-public (withdraw (pool-id uint) (shares uint))
    (let ((pool (unwrap! (map-get? yield-pools pool-id) err-pool-not-found))
          (position (unwrap! (map-get? user-positions {pool-id: pool-id, user: tx-sender}) err-invalid-pool))
          (value (calculate-value shares pool-id))
          (fee (calculate-fee value (var-get withdrawal-fee))))
        
        (asserts! (>= (get shares position) shares) err-insufficient-balance)
        (asserts! (>= (- stacks-block-height (get entry-block position)) (get lock-period pool)) err-withdrawal-locked)
        
        (let ((net-amount (- value fee)))
            (try! (as-contract (stx-transfer? net-amount tx-sender tx-sender)))
            
            (map-set yield-pools pool-id 
                (merge pool {
                    total-deposits: (- (get total-deposits pool) value),
                    total-shares: (- (get total-shares pool) shares)
                }))
            
            (if (is-eq shares (get shares position))
                (map-delete user-positions {pool-id: pool-id, user: tx-sender})
                (map-set user-positions {pool-id: pool-id, user: tx-sender}
                    (merge position {
                        shares: (- (get shares position) shares),
                        last-action: stacks-block-height
                    }))
            )
            
            (var-set total-value-locked (- (var-get total-value-locked) value))
            (var-set total-fees-collected (+ (var-get total-fees-collected) fee))
            (update-user-stats tx-sender "withdrawn" net-amount)
            
            (ok net-amount)
        )
    )
)

(define-public (compound-pool (pool-id uint))
    (let ((pool (unwrap! (map-get? yield-pools pool-id) err-pool-not-found)))
        
        (asserts! (>= (- stacks-block-height (get last-harvest pool)) (get compound-frequency pool)) err-compound-too-soon)
        
        (let ((rewards (calculate-compound-rewards pool-id))
              (perf-fee (calculate-fee rewards (var-get performance-fee)))
              (bounty (calculate-fee rewards (var-get compound-bounty)))
              (net-rewards (- rewards (+ perf-fee bounty))))
            
            (if (> bounty u0)
                (try! (as-contract (stx-transfer? bounty tx-sender tx-sender)))
                false)
            
            (map-set yield-pools pool-id 
                (merge pool {
                    total-deposits: (+ (get total-deposits pool) net-rewards),
                    last-harvest: stacks-block-height
                }))
            
            (match (map-get? user-positions {pool-id: pool-id, user: tx-sender})
                position
                (map-set user-positions {pool-id: pool-id, user: tx-sender}
                    (merge position {
                        compound-credits: (+ (get compound-credits position) u1),
                        earned: (+ (get earned position) bounty)
                    }))
                true
            )
            
            (var-set total-fees-collected (+ (var-get total-fees-collected) perf-fee))
            (update-user-stats tx-sender "compound" u1)
            
            (ok {rewards: net-rewards, bounty: bounty})
        )
    )
)

(define-public (emergency-withdraw (pool-id uint))
    (let ((position (unwrap! (map-get? user-positions {pool-id: pool-id, user: tx-sender}) err-invalid-pool))
          (pool (unwrap! (map-get? yield-pools pool-id) err-pool-not-found)))
        
        (asserts! (var-get emergency-shutdown) err-invalid-pool)
        
        (let ((value (calculate-value (get shares position) pool-id)))
            (try! (as-contract (stx-transfer? value tx-sender tx-sender)))
            
            (map-set yield-pools pool-id 
                (merge pool {
                    total-deposits: (- (get total-deposits pool) value),
                    total-shares: (- (get total-shares pool) (get shares position))
                }))
            
            (map-delete user-positions {pool-id: pool-id, user: tx-sender})
            (var-set total-value-locked (- (var-get total-value-locked) value))
            
            (ok value)
        )
    )
)

(define-public (pause-pool (pool-id uint) (paused bool))
    (let ((pool (unwrap! (map-get? yield-pools pool-id) err-pool-not-found)))
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        
        (map-set yield-pools pool-id (merge pool {paused: paused}))
        (ok true)
    )
)

(define-public (toggle-emergency-shutdown)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (var-set emergency-shutdown (not (var-get emergency-shutdown)))
        (ok (var-get emergency-shutdown))
    )
)

(define-public (update-pool-apy (pool-id uint) (new-apy uint))
    (let ((pool (unwrap! (map-get? yield-pools pool-id) err-pool-not-found)))
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (<= new-apy u5000) err-invalid-ratio)
        
        (map-set yield-pools pool-id (merge pool {current-apy: new-apy}))
        
        (map-set pool-snapshots {pool-id: pool-id, block: stacks-block-height} {
            tvl: (get total-deposits pool),
            apy: new-apy,
            share-price: (if (> (get total-shares pool) u0)
                            (/ (* (get total-deposits pool) u1000000) (get total-shares pool))
                            u1000000)
        })
        
        (ok true)
    )
)

(define-public (update-fees (fee-type (string-ascii 20)) (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (<= new-fee u1000) err-invalid-ratio) ;; Max 10%
        
        (if (is-eq fee-type "performance")
            (var-set performance-fee new-fee)
        (if (is-eq fee-type "withdrawal")
            (var-set withdrawal-fee new-fee)
        (if (is-eq fee-type "compound")
            (var-set compound-bounty new-fee)
            false)))
        
        (ok true)
    )
)

(define-public (withdraw-fees)
    (let ((fees (var-get total-fees-collected)))
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (> fees u0) err-invalid-amount)
        
        (try! (as-contract (stx-transfer? fees tx-sender contract-owner)))
        (var-set total-fees-collected u0)
        (ok fees)
    )
)

;; Read-only Functions
(define-read-only (get-pool (pool-id uint))
    (map-get? yield-pools pool-id)
)

(define-read-only (get-user-position (pool-id uint) (user principal))
    (map-get? user-positions {pool-id: pool-id, user: user})
)

(define-read-only (get-user-stats (user principal))
    (default-to {total-deposited: u0, total-withdrawn: u0, total-earned: u0,
                active-pools: (list), compound-count: u0}
        (map-get? user-stats user))
)

(define-read-only (get-pool-snapshot (pool-id uint) (block uint))
    (map-get? pool-snapshots {pool-id: pool-id, block: block})
)

(define-read-only (calculate-user-value (pool-id uint) (user principal))
    (match (map-get? user-positions {pool-id: pool-id, user: user})
        position (calculate-value (get shares position) pool-id)
        u0
    )
)

(define-read-only (get-pending-rewards (pool-id uint))
    (calculate-compound-rewards pool-id)
)

(define-read-only (get-protocol-stats)
    {
        total-pools: (var-get pool-counter),
        tvl: (var-get total-value-locked),
        total-fees: (var-get total-fees-collected),
        performance-fee: (var-get performance-fee),
        withdrawal-fee: (var-get withdrawal-fee),
        compound-bounty: (var-get compound-bounty),
        emergency-mode: (var-get emergency-shutdown)
    }
)

(define-read-only (can-compound (pool-id uint))
    (match (map-get? yield-pools pool-id)
        pool (>= (- stacks-block-height (get last-harvest pool)) (get compound-frequency pool))
        false
    )
)