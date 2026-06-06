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

// One delivery order: an escrow plus a small state machine.
//   Open --AcceptOrder(courier, +0.1 fee)--> Accepted
//        --ConfirmDelivery(sender, +0.05 gas)--> Completed  (reward -> courier, sender's change back, ~0.2 buffer -> owner, self-destruct)
//        --ClaimExpired(anyone, after deadline)--> Expired  (reward -> sender, caller's change back, ~0.2 buffer -> owner, courier gets nothing, self-destruct)
//        --CourierRelease(courier)--> Open         (order reopens for another courier; the courier gets their full 0.1 accept fee back plus their release-gas change, reward + sender's create fee stay on the contract)
//   Open --CancelOrder(sender)--> Cancelled       (reward -> sender, sender's change back, ~0.1 fee -> owner, self-destruct)
contract Order {
    author: "SwiftDelivery"
    version: "1.12.0"
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
            s.status = OrderStatus.Cancelled;
            s.save();
            // Both the reward refund and the gas change go to the SAME address
            // (the sender), so send them as ONE payment instead of two. Mode 64
            // (carry all remaining message value) adds the unused part of THIS
            // message's value — the change from the ~0.05 gas the sender attached
            // to cancel — on top of the `value` we set here, so the sender
            // receives `reward + change` in a single transfer. The forwarding fee
            // comes out of that combined value, so cancelling costs the sender
            // only the tx fee on top of the create fee they forfeit.
            val refund = createMessage({
                bounce: BounceMode.NoBounce,
                value: s.reward,
                dest: s.sender,
            });
            refund.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
            // Everything left over (the ~0.1 TON the sender added at create time,
            // minus gas) is the platform's cancellation fee; send it to the owner
            // and self-destruct. NOTE: no courier has accepted yet (status was
            // Open), so there is no courier fee here — only the sender's create
            // fee, hence ~0.1, not the ~0.2 of a completed order.
            val fee = createMessage({
                bounce: BounceMode.NoBounce,
                value: 0 as coins,
                dest: s.extra.load().owner,
            });
            // SAFETY: terminal state. The reward and the sender's change already
            // left above; the rest is the platform's cancellation fee. Draining it
            // and destroying the contract is the intended cancel path.
            fee.send(SEND_MODE_CARRY_ALL_BALANCE | SEND_MODE_DESTROY);
        }
        CourierRelease => {
            // Only the courier who accepted this order may give it up, and only
            // while it is still Accepted (not yet delivered or expired).
            assert (s.status == OrderStatus.Accepted) throw OrderErrors.WrongStatus;
            // status Accepted guarantees courier is set, so `!` is safe here.
            assert (s.courier! == in.senderAddress) throw OrderErrors.NotCourier;
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
            // The order reopens, so the courier is made whole. Their accept-fee
            // refund and their gas change go to the SAME address (the courier), so
            // send them as ONE payment instead of two. We set `value` to the full
            // 0.1 TON accept fee and use mode 64 (carry all remaining message
            // value), which adds the unused part of THIS message's value — the
            // change from the ~0.05 gas the courier attached to release — on top,
            // so the courier receives `accept fee + change` in a single transfer.
            // Status was Accepted, so the contract holds exactly one accept fee
            // (MIN_ACCEPT_FEE); refunding that fixed amount returns the balance to
            // its pre-accept size (reward + the sender's create fee), so the
            // platform still earns its ~0.2 at the end no matter how many couriers
            // accept and release before one finally delivers. The reward and the
            // sender's create fee stay on the contract for the next courier;
            // nothing goes to the owner here, the order is not closing.
            val feeRefund = createMessage({
                bounce: BounceMode.NoBounce,
                value: MIN_ACCEPT_FEE,
                dest: in.senderAddress,
            });
            feeRefund.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
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
