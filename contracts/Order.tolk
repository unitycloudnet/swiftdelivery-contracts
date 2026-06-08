import "types"

// How long a courier has to deliver, counted from the moment they accept.
// ⚠️ TESTING VALUE: 1 hour. Restore to 30 days (30 * 24 * 60 * 60) before any
// production / mainnet deploy.
const DEADLINE = 60 * 60 // 1 hour, in seconds

// Lowest value a courier must attach to accept. There is no courier stake any
// more: the courier pays a flat 0.1 TON service fee (from the UI) that stays on
// the contract and, together with the 0.1 TON the sender added at create time,
// makes up the ~0.2 TON the platform keeps at the end. If the courier later gives
// the order up (CourierRelease), this exact fee is refunded to them, so only a
// courier who actually delivers (or lets the order expire) pays it. This floor
// also rejects grossly under-funded direct callers that bypass the UI.
const MIN_ACCEPT_FEE = ton("0.1")

// Extra service fee the sender pays to CANCEL an order they created while it is
// still Open. It is on top of the 0.1 TON create fee they already paid: the
// create fee stays with the platform and this 0.3 is added, so a cancel earns the
// platform ~0.4 TON in total. The reward is always returned to the sender in full.
const CANCEL_FEE = ton("0.3")

// Extra service fee the courier pays to RELEASE (give up) an order they already
// accepted. It is on top of the 0.1 TON accept fee they already paid: the accept
// fee is NO LONGER refunded and this 0.2 is added, so a release earns the platform
// ~0.3 TON in total. The reward and the sender's create fee stay on the contract
// for the next courier (the order reopens, it does not close).
const RELEASE_FEE = ton("0.2")

// One delivery order: an escrow plus a small state machine.
//   Open --AcceptOrder(courier, +0.1 fee)--> Accepted
//        --ConfirmDelivery(sender, +0.05 gas)--> Completed  (reward -> courier, sender's change back, ~0.2 buffer -> owner, self-destruct)
//        --ClaimExpired(anyone, after deadline)--> Expired  (reward -> sender, caller's change back, ~0.2 buffer -> owner, courier gets nothing, self-destruct)
//        --CourierRelease(courier, +0.2 fee)--> Open         (order reopens for another courier; the accept fee is kept and the 0.2 release fee is added, so ~0.3 -> owner; reward + sender's create fee stay on the contract; courier gets nothing back)
//   Open --CancelOrder(sender, +0.3 fee)--> Cancelled       (reward -> sender; the create fee is kept and the 0.3 cancel fee is added, so ~0.4 -> owner, self-destruct)
contract Order {
    author: "SwiftDelivery"
    version: "1.13.0"
    description: "A single delivery order with escrow"
    storage: OrderStorage
    incomingMessages: OrderMessage
}

fun onInternalMessage(in: InMessage) {
    val msg = lazy OrderMessage.fromSlice(in.body);
    var s = lazy OrderStorage.load();

    match (msg) {
        AcceptOrder => {
            assert (s.status == OrderStatus.Open) throw OrderErrors.WrongStatus;
            // The courier no longer posts a stake. They attach a flat 0.1 TON
            // service fee (from the UI), which stays on the contract and is NOT
            // refunded — it becomes part of the platform's ~0.2 TON earnings.
            assert (in.valueCoins >= MIN_ACCEPT_FEE) throw OrderErrors.FeeTooLow;
            s.courier = in.senderAddress;
            s.status = OrderStatus.Accepted;
            s.acceptedAt = blockchain.now() as uint32; // start the delivery clock
            // courierContact lives in the referenced extra cell: load it, set
            // the courier's contact, and re-pack the ref.
            var extra = s.extra.load();
            extra.courierContact = msg.courierContact;
            s.extra = extra.toCell();
            s.save();
        }
        ConfirmDelivery => {
            assert (s.status == OrderStatus.Accepted) throw OrderErrors.WrongStatus;
            assert (s.sender == in.senderAddress) throw OrderErrors.NotSender;
            s.status = OrderStatus.Completed;
            s.save();
            // 1. The reward (the sender's escrow) goes to the courier.
            //    PAY_FEES_SEPARATELY takes the forwarding fee from the contract
            //    balance, so the courier receives exactly the reward.
            val pay = createMessage({
                bounce: BounceMode.NoBounce,
                value: s.reward,
                dest: s.courier!,
            });
            pay.send(SEND_MODE_PAY_FEES_SEPARATELY);
            // 2. Return the unused part of THIS message's value (the sender's
            //    change from the ~0.05 gas they attached) back to the sender, so
            //    the contract balance does not keep growing — the ~0.2 buffer it
            //    already holds is enough. Mode 64 carries exactly the leftover of
            //    the incoming message, minus this transaction's gas.
            val change = createMessage({
                bounce: BounceMode.NoBounce,
                value: 0 as coins,
                dest: s.sender,
            });
            change.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
            // 3. Everything left over (the ~0.2 TON service fee) is the platform's
            //    earnings; send it to the owner and self-destruct.
            val fee = createMessage({
                bounce: BounceMode.NoBounce,
                value: 0 as coins,
                dest: s.extra.load().owner,
            });
            // SAFETY: terminal state. The reward already left for the courier and
            // the sender's change was returned above; only the fee buffer remains,
            // which is the platform's earnings. Draining it and destroying the
            // contract is the intended end of a completed order.
            fee.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_DESTROY);
        }
        ClaimExpired => {
            // After the deadline, anyone may trigger the unwind — a TON contract
            // cannot fire on a timer by itself, so the app shows a "Claim" button
            // to whoever opens the order. No sender/courier check on purpose.
            assert (s.status == OrderStatus.Accepted) throw OrderErrors.WrongStatus;
            assert (blockchain.now() > s.acceptedAt + DEADLINE) throw OrderErrors.NotExpired;
            s.status = OrderStatus.Expired;
            s.save();
            // The courier did not deliver in time, so they get nothing. The
            // reward returns to the sender (exact amount, fee from balance)...
            val refund = createMessage({
                bounce: BounceMode.NoBounce,
                value: s.reward,
                dest: s.sender,
            });
            refund.send(SEND_MODE_PAY_FEES_SEPARATELY);
            // Return the unused part of THIS message's value (the caller's change
            // from the ~0.05 they attached) back to whoever triggered the claim,
            // exactly like ConfirmDelivery does for the sender. Mode 64 carries
            // the leftover of the incoming message, minus this transaction's gas,
            // so the caller is not charged the full 0.05 — only the tx fee.
            val change = createMessage({
                bounce: BounceMode.NoBounce,
                value: 0 as coins,
                dest: in.senderAddress,
            });
            change.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
            // ...and the whole remaining buffer goes to the platform owner;
            // contract self-destructs.
            val fee = createMessage({
                bounce: BounceMode.NoBounce,
                value: 0 as coins,
                dest: s.extra.load().owner,
            });
            // SAFETY: terminal state. The reward already left for the sender and
            // the caller's change was returned above; the rest (the fee buffer)
            // belongs to the platform. Draining it and destroying the contract
            // ends an expired order.
            fee.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_DESTROY);
        }
        CancelOrder => {
            assert (s.status == OrderStatus.Open) throw OrderErrors.WrongStatus;
            assert (s.sender == in.senderAddress) throw OrderErrors.NotSender;
            // Cancelling now costs a flat 0.3 TON service fee, on top of the 0.1 TON
            // the sender already paid at create time. Reject a caller who did not
            // attach it so the platform always earns the cancel fee (and a direct
            // caller cannot cancel for free, bypassing the UI).
            assert (in.valueCoins >= CANCEL_FEE) throw OrderErrors.FeeTooLow;
            s.status = OrderStatus.Cancelled;
            s.save();
            // 1. Return the reward to the sender — EXACTLY the reward, with the
            //    forwarding fee taken from the contract balance (PAY_FEES_SEPARATELY).
            //    We do NOT carry the message value back this time: the 0.3 TON the
            //    sender attached is the cancel fee and must stay for the platform,
            //    so it is not refunded as change.
            val refund = createMessage({
                bounce: BounceMode.NoBounce,
                value: s.reward,
                dest: s.sender,
            });
            refund.send(SEND_MODE_PAY_FEES_SEPARATELY);
            // 2. Everything left over goes to the platform owner and the contract
            //    self-destructs. That leftover is the 0.1 TON create fee the order
            //    already held PLUS the 0.3 TON cancel fee just attached, so the
            //    platform earns ~0.4 TON on a cancel.
            val fee = createMessage({
                bounce: BounceMode.NoBounce,
                value: 0 as coins,
                dest: s.extra.load().owner,
            });
            // SAFETY: terminal state. The reward already left above; the rest is the
            // platform's cancellation fee (create fee + cancel fee). Draining it and
            // destroying the contract is the intended cancel path.
            fee.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_DESTROY);
        }
        CourierRelease => {
            // Only the courier who accepted this order may give it up, and only
            // while it is still Accepted (not yet delivered or expired).
            assert (s.status == OrderStatus.Accepted) throw OrderErrors.WrongStatus;
            // status Accepted guarantees courier is set, so `!` is safe here.
            assert (s.courier! == in.senderAddress) throw OrderErrors.NotCourier;
            // Giving up an accepted order now costs a flat 0.2 TON service fee, on
            // top of the 0.1 TON accept fee the courier already paid (which is NO
            // longer refunded). Reject a caller who did not attach it.
            assert (in.valueCoins >= RELEASE_FEE) throw OrderErrors.FeeTooLow;
            // The order does NOT close — it reopens so another courier can take
            // it. Reset it to exactly the Open shape it had before this courier
            // accepted: clear the courier, the accept time, and their contact.
            s.status = OrderStatus.Open;
            s.courier = null;
            s.acceptedAt = 0;
            var extra = s.extra.load();
            extra.courierContact = createEmptyCell();
            s.extra = extra.toCell();
            s.save();
            // The courier is NOT made whole any more. The platform keeps the 0.1
            // TON accept fee the contract already held AND the 0.2 TON release fee
            // just attached, so it earns ~0.3 TON on a release. Send that fixed
            // 0.3 to the owner (PAY_FEES_SEPARATELY, fee from balance) and keep the
            // rest. Before this message the contract held reward + 0.1 (create) +
            // 0.1 (accept) and the courier added 0.2, so after sending 0.3 out the
            // balance is back to reward + 0.1 (the create fee) — exactly a fresh
            // Open order's funding, ready for the next courier. The order is not
            // closing, so the contract is NOT destroyed.
            val fee = createMessage({
                bounce: BounceMode.NoBounce,
                value: MIN_ACCEPT_FEE + RELEASE_FEE,
                dest: s.extra.load().owner,
            });
            fee.send(SEND_MODE_PAY_FEES_SEPARATELY);
        }
        else => {
            // Empty body (e.g. the deploy message) is accepted as a no-op.
            assert (in.body.isEmpty()) throw OrderErrors.InvalidMessage;
        }
    }
}

fun onBouncedMessage(_in: InMessageBounced) {}

get fun orderData(): OrderStorage {
    val s = lazy OrderStorage.load();
    return s;
}

get fun status(): OrderStatus {
    val s = lazy OrderStorage.load();
    return s.status;
}
