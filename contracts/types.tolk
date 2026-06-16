// Shared types for the SwiftDelivery contracts.
// ===================== Order =====================

enum OrderStatus: uint8 {
    Open = 0
    Accepted = 1
    Completed = 2
    Cancelled = 3
    Expired = 4 // deadline passed; reward -> sender, courier gets nothing
}

enum OrderErrors {
    WrongStatus = 100
    NotSender = 101
    NotCourier = 102     // courier-release attempted by someone other than the courier
    FeeTooLow = 103      // courier attached less than the minimum accept fee
    NotExpired = 104     // claim attempted before the deadline
    DeadlinePassed = 105 // courier-release attempted after the deadline
    BadCode = 108        // confirm attempted with a secret whose hash does not match
    InvalidMessage = 0xFFFF
}

// Fields kept in a separate referenced cell (`Cell<OrderExtra>`, TL-B
// `^OrderExtra`) so the root OrderStorage cell stays well under the 1023-bit
// limit. The root already carries two full addresses (`sender` + `courier`,
// 267 bits each) plus a `coins` field and the counters. Keeping a THIRD inline
// address (`owner`) here once overflowed the root cell when a courier accepted:
// `courier` grows from a 2-bit null to a 267-bit address, pushing the total
// past 1023. On-chain that surfaced as AcceptOrder failing with exit_code 8
// (cell overflow) for real $10+ orders. Moving `owner` (plus the two contact
// cells) out keeps the root small, so no overflow policy is suppressed.
struct OrderExtra {
    owner: address       // marketplace owner; receives the platform fee on completion
    // Telegram contact of each party, packed as opaque text by the frontend
    // (see src/contact.js). Public on-chain, so it carries only the @username,
    // numeric id and first name — never a phone or the exact street address.
    senderContact: cell  // set by the sender at create time
    courierContact: cell // empty until a courier accepts, then their contact
    // Delivery-code commitment. The sender's app picks a 256-bit random secret at
    // create time and stores it locally; only this HASH of it goes on-chain. The
    // courier learns the secret from the sender at hand-off (shown as a QR code)
    // and sends it with ConfirmWithCode; the contract pays the reward only when
    // hash(secret) == secretHash. So a courier can be paid ONLY with the sender's
    // code — there is no "confirm" button the sender could sit on. It lives here
    // in the referenced extra cell (not the root) to keep the root under 1023 bits
    // (a 256-bit field in the root risks the same overflow `owner` once caused).
    // It is part of the init data, so it changes the order's address like
    // senderContact does — included in CreateOrder and the orderAddress getter.
    secretHash: uint256
}

// One delivery order. Holds the escrow and the state machine.
// `description`, `area` and `origin` are cells (text packed by the caller).
// Both are public; the exact street address is NEVER stored on-chain.
//   `area`   — the "to" city (destination).
//   `origin` — the "from" place (where the parcel starts). It is free text and
//              need NOT be a city: it can be a shop, a landmark, an airport zone
//              ("Duty Free", "H&M", "McDonald's"). The UI defaults this to
//              "All world" when the sender does not care about the origin.
//
// All fields here are supplied by the creator (the frontend), NOT by block
// time or a global counter. That is on purpose: a contract's address is the
// hash of its initial state, so keeping the init data fully client-controlled
// lets the frontend recompute the address of an order it just created.
// `nonce` is a client random value that makes the address unique.
struct OrderStorage {
    sender: address
    courier: address?  // null until a courier accepts
    description: cell
    area: cell         // "to" city (destination)
    origin: cell       // "from" place (source, any text); "All world" = any origin
    reward: coins
    status: OrderStatus
    nonce: uint64      // client random, for a unique address
    createdAt: uint32  // client unix time, for display only
    // acceptedAt is 0 in the initial state (so it does not change the order's
    // address) and is set by the contract itself when a courier accepts; it
    // starts the delivery clock that ClaimExpired checks against the deadline.
    acceptedAt: uint32 // contract block time at AcceptOrder; 0 until accepted
    // owner + both Telegram contacts, in a referenced cell (see OrderExtra).
    extra: Cell<OrderExtra>
}

fun OrderStorage.load(): OrderStorage {
    return OrderStorage.fromCell(contract.getData());
}

fun OrderStorage.save(self) {
    contract.setData(self.toCell());
}

struct (0xa00a0001) AcceptOrder {
    courierContact: cell // courier's Telegram contact, revealed once accepted
}

// Confirm a delivery by revealing the secret behind the order's secretHash. The
// courier scans the sender's QR at hand-off to obtain `secret` and sends it here;
// the contract pays the courier only if hash(secret) == secretHash (see Order.tolk).
// Reuses the old ConfirmDelivery opcode (0xa00a0002), which no longer exists.
struct (0xa00a0002) ConfirmWithCode {
    secret: uint256 // preimage; the contract checks hash(secret) == secretHash
}

struct (0xa00a0003) CancelOrder {}

struct (0xa00a0004) ClaimExpired {}

// Courier gives up an order they already accepted. Allowed ONLY before the
// deadline: once the delivery window has passed the courier has no actions left
// and the order can only be settled by the sender (claim or confirm). The order
// does NOT close: it goes back to Open so another courier can take it. The courier
// pays a 0.2 TON release fee on top of the 0.1 TON accept fee they already paid;
// neither is refunded — both stay on the contract for the platform. The reward and
// the sender's create fee also stay on the contract for the next courier.
struct (0xa00a0005) CourierRelease {}

type OrderMessage =
    | AcceptOrder
    | ConfirmWithCode
    | CancelOrder
    | ClaimExpired
    | CourierRelease

// =================== Marketplace ===================

enum MarketplaceErrors {
    InsufficientValue = 200 // attached coins do not cover reward + create buffer
    NotOwner = 201          // an owner-only admin message arrived from another address
    RewardTooLow = 202      // stated reward is below MIN_REWARD (anti-spam, M-5)
    InvalidMessage = 0xFFFF
}

// The single registry contract. It deploys Order contracts on demand.
// `orderCode` is the compiled Order code cell, set at deploy time, so the
// Marketplace can build new Order state-init on-chain.
struct MarketplaceStorage {
    owner: address
    orderCode: cell
    orderCount: uint32
}

fun MarketplaceStorage.load(): MarketplaceStorage {
    return MarketplaceStorage.fromCell(contract.getData());
}

fun MarketplaceStorage.save(self) {
    contract.setData(self.toCell());
}

struct (0xa00a0000) CreateOrder {
    reward: coins       // stated reward; sender must attach >= reward + gas
    nonce: uint64       // client random, for a unique order address
    createdAt: uint32   // client unix time, for display
    description: cell
    area: cell          // "to" city (destination)
    origin: cell        // "from" place (source, any text); "All world" = any origin
    senderContact: cell // sender's Telegram contact (opaque text)
    secretHash: uint256 // hash of the sender's delivery code (see OrderExtra.secretHash)
}

// Owner-only. Replace the compiled Order code the Marketplace deploys for FUTURE
// orders. An order's address is the hash of its code + init data, so already
// deployed orders keep running on the code they were born with — this only
// changes orders created after the call. It lets the owner ship a fixed Order
// without redeploying the Marketplace (which would change the Marketplace address
// every wallet/indexer has saved). Old orders age out at the 14-day deadline.
// See H-2 in the security audit.
struct (0xa00a0006) UpdateOrderCode {
    newCode: cell // the new compiled Order code
}

// Owner-only. Hand the platform over to a new owner address. Guards against a
// lost or compromised owner key: the current owner can rotate it. Only NEW orders
// record the new owner as their fee recipient (each order copies st.owner into its
// extra cell at create time); orders already deployed still pay the previous owner
// when they settle. See H-3 in the security audit.
struct (0xa00a0007) TransferOwnership {
    newOwner: address // the address that becomes the new platform owner
}

type MarketplaceMessage =
    | CreateOrder
    | UpdateOrderCode
    | TransferOwnership
