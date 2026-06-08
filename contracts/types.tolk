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
    NotCourier = 102 // courier-release attempted by someone other than the courier
    FeeTooLow = 103  // courier attached less than the minimum accept fee
    NotExpired = 104 // claim attempted before the deadline
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
}

// One delivery order. Holds the escrow and the state machine.
// `description`, `area` and `origin` are cells (text packed by the caller).
// Both cities are public; the exact street address is NEVER stored on-chain.
//   `area`   — the "to" city (destination).
//   `origin` — the "from" city (where the parcel starts). The UI defaults this
//              to "All world" when the sender does not care about the origin.
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
    origin: cell       // "from" city (source); "All world" = any origin
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

struct (0xa00a0002) ConfirmDelivery {}

struct (0xa00a0003) CancelOrder {}

struct (0xa00a0004) ClaimExpired {}

// Courier gives up an order they already accepted. The order does NOT close: it
// goes back to Open so another courier can take it. The courier is refunded their
// full 0.1 TON accept fee plus their release-gas change, so backing out costs them
// only the transaction gas. The reward and the sender's create fee stay on the
// contract for the next courier.
struct (0xa00a0005) CourierRelease {}

type OrderMessage =
    | AcceptOrder
    | ConfirmDelivery
    | CancelOrder
    | ClaimExpired
    | CourierRelease

// =================== Marketplace ===================

enum MarketplaceErrors {
    InsufficientValue = 200 // attached coins do not cover reward + create buffer
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
    origin: cell        // "from" city (source); "All world" = any origin
    senderContact: cell // sender's Telegram contact (opaque text)
}

type MarketplaceMessage = CreateOrder
