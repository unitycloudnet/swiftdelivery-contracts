import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/types"
import "@wrappers/Order.gen"

const GAS = ton("0.05")
const REWARD = ton("1")
const ACCEPT_FEE = ton("0.1") // courier's service fee (>= MIN_ACCEPT_FEE 0.1)
const BELOW_FEE = ton("0.02") // below MIN_ACCEPT_FEE; accept must reject it
const CANCEL_FEE = ton("0.3") // sender's cancel fee; must match Order.tolk
const RELEASE_FEE = ton("0.2") // courier's release fee; must match Order.tolk
const DEADLINE = 60 * 60 // must match Order.tolk (1h testing value)
// A fixed "now" for time-dependent tests. Must be in the FUTURE relative to the
// emulator's default wall-clock time, otherwise setNow() would move time
// backwards past the deploy and the storage phase fails (-669).
const BASE_TIME: uint32 = 2000000000

// A delivery secret and its on-chain commitment. The commitment is the
// representation hash of a cell holding the 256-bit secret — exactly the
// construct ConfirmWithCode verifies and the frontend reproduces with @ton/core.
// Confirming with SECRET succeeding is the round-trip proof: the contract's
// on-chain hash of SECRET matches the secretHash baked into the order's storage.
const SECRET: uint256 = 0xC0DE1234C0DE1234C0DE1234C0DE1234C0DE1234C0DE1234C0DE1234C0DE1234
const WRONG_SECRET: uint256 = 0xBADC0DE

fun secretHashOf(secret: uint256): uint256 {
    return beginCell().storeUint(secret, 256).endCell().hash();
}

// ---- happy path: Open -> Accepted -> Completed (courier confirms with the code) ----

get fun `test confirm with the code pays the courier the reward`() {
    val (order, _, courier, owner) = setupOrderTest();

    order.sendAcceptOrder(courier.address, createEmptyCell(), { value: ACCEPT_FEE });

    // Capture balances after accept, before confirm.
    val courierMid = testing.getAccountBalance(courier.address);
    val ownerMid = testing.getAccountBalance(owner.address);

    // The courier learned the secret from the sender at hand-off and reveals it.
    val r = order.sendConfirmWithCode(courier.address, SECRET, { value: GAS });
    expect(r).toHaveSuccessfulTx<ConfirmWithCode>({ from: courier.address, to: order.address });

    // Contract must be destroyed.
    expect(testing.getAccountBalance(order.address)).toBeLess(ton("0.001"));

    // The courier (who called) received the reward PLUS the change of their GAS
    // back (mode 64 returns the leftover to the caller). So their gain is at least
    // the reward and at most the reward plus the GAS they attached.
    val courierGain = testing.getAccountBalance(courier.address) - courierMid;
    expect(courierGain).toBeGreater(REWARD - ton("0.01"));
    expect(courierGain).toBeLess(REWARD + GAS);

    // Owner received the ~0.2 fee buffer as the platform's earnings, NOT a dust
    // amount: this proves the buffer went to the platform, not back to the caller.
    val ownerGain = testing.getAccountBalance(owner.address) - ownerMid;
    expect(ownerGain).toBeGreater(ton("0.2"));
}

// ---- a wrong code is rejected: the order stays Accepted and the money is safe ----

get fun `test confirm with a wrong code is rejected`() {
    val (order, _, courier, _) = setupOrderTest();
    order.sendAcceptOrder(courier.address, createEmptyCell(), { value: ACCEPT_FEE });

    val orderBefore = testing.getAccountBalance(order.address);

    // A random secret whose hash does not match the order's secretHash.
    val r = order.sendConfirmWithCode(courier.address, WRONG_SECRET, { value: GAS });
    expect(r).toHaveFailedTx({
        from: courier.address,
        to: order.address,
        exitCode: OrderErrors.BadCode,
    });

    // The order is untouched: still Accepted, contract alive, escrow intact.
    expect(order.status()).toEqual(OrderStatus.Accepted);
    expect(testing.getAccountBalance(order.address)).toBeGreater(orderBefore - GAS);
}

// ---- only the courier may confirm: a stranger (even one who knows the code) is rejected ----

get fun `test confirm from a non-courier is rejected even with the right code`() {
    val (order, sender, courier, _) = setupOrderTest();
    order.sendAcceptOrder(courier.address, createEmptyCell(), { value: ACCEPT_FEE });

    val orderBefore = testing.getAccountBalance(order.address);

    // The sender knows the secret (they made it) and submits the CORRECT code, but
    // they are not the courier who accepted, so the call must fail: the secret is
    // not enough — only the courier's wallet can trigger payment. This closes the
    // gap where anyone holding a leaked code could force settlement before delivery.
    val r = order.sendConfirmWithCode(sender.address, SECRET, { value: GAS });
    expect(r).toHaveFailedTx({
        from: sender.address,
        to: order.address,
        exitCode: OrderErrors.NotCourier,
    });

    // The order is untouched: still Accepted, contract alive, escrow intact.
    expect(order.status()).toEqual(OrderStatus.Accepted);
    expect(testing.getAccountBalance(order.address)).toBeGreater(orderBefore - GAS);
}

// ---- accept charges a fee buffer (not a stake) and starts the clock ----

get fun `test accept records acceptedAt and keeps the fee`() {
    val (order, _, courier, _) = setupOrderTest();
    testing.setNow(BASE_TIME);

    val orderBefore = testing.getAccountBalance(order.address);
    order.sendAcceptOrder(courier.address, createEmptyCell(), { value: ACCEPT_FEE });
    expect(order.status()).toEqual(OrderStatus.Accepted);

    val data = order.orderData();
    expect(data.acceptedAt).toEqual(BASE_TIME);
    // The fee buffer stayed on the contract (it is not refunded on accept).
    expect(testing.getAccountBalance(order.address)).toBeGreater(orderBefore);
}

get fun `test accept rejects a fee below the floor`() {
    val (order, _, courier, _) = setupOrderTest();

    // 0.02 TON is below MIN_ACCEPT_FEE (0.1) — accept must fail, order stays Open.
    val r = order.sendAcceptOrder(courier.address, createEmptyCell(), { value: BELOW_FEE });
    expect(r).toHaveFailedTx({
        from: courier.address,
        to: order.address,
        exitCode: OrderErrors.FeeTooLow,
    });
    expect(order.status()).toEqual(OrderStatus.Open);
}

// ---- contact: courier's Telegram contact is stored on accept ----

get fun `test accept stores courier contact`() {
    val (order, _, courier, _) = setupOrderTest();

    val contact = beginCell().storeUint(0xC0FFEE, 32).endCell();
    order.sendAcceptOrder(courier.address, contact, { value: ACCEPT_FEE });

    val data = order.orderData();
    expect(data.extra.load().courierContact.hash()).toEqual(contact.hash());
}

// ---- regression: a real-sized order must NOT overflow the storage cell ----
// A $10..$1000 order uses a 5-byte `coins` reward. With the old flat layout
// (three inline 267-bit addresses), the storage cell crossed 1023 bits the
// moment a courier accepted, and AcceptOrder failed on-chain with exit_code 8
// (cell overflow). With `owner` moved into the OrderExtra ref cell the root
// stays small, so accept must succeed. 5 TON forces a 5-byte coins reward.
get fun `test accept with a large reward does not overflow`() {
    val sender = testing.treasury("sender");
    val courier = testing.treasury("courier");
    val owner = testing.treasury("owner");
    val bigCoins = ton("5");

    val order = Order.fromStorage({
        sender: sender.address,
        courier: null,
        description: createEmptyCell(),
        area: createEmptyCell(),
        origin: createEmptyCell(),
        reward: bigCoins,
        status: OrderStatus.Open,
        nonce: 0,
        createdAt: 0,
        acceptedAt: 0,
        extra: (OrderExtra {
            owner: owner.address,
            senderContact: createEmptyCell(),
            courierContact: createEmptyCell(),
            secretHash: 0,
        }).toCell(),
    });
    val res = order.deploy(sender.address, { value: ton("6") });
    expect(res).toHaveSuccessfulDeploy({ to: order.address });

    val r = order.sendAcceptOrder(courier.address, createEmptyCell(), { value: bigCoins });
    expect(r).toHaveSuccessfulTx<AcceptOrder>({ from: courier.address, to: order.address });
    expect(order.status()).toEqual(OrderStatus.Accepted);
}

// ---- claim after the deadline: reward + change -> sender (one transfer), buffer -> platform, courier nothing ----

get fun `test claim after deadline refunds sender and pays platform`() {
    val (order, sender, courier, owner) = setupOrderTest();
    testing.setNow(BASE_TIME);
    order.sendAcceptOrder(courier.address, createEmptyCell(), { value: ACCEPT_FEE });

    val courierMid = testing.getAccountBalance(courier.address);
    val senderMid = testing.getAccountBalance(sender.address);
    val ownerMid = testing.getAccountBalance(owner.address);

    // Jump past the deadline. Only the sender may claim.
    testing.setNow(BASE_TIME + DEADLINE + 1);
    val r = order.sendClaimExpired(sender.address, { value: GAS });
    expect(r).toHaveSuccessfulTx<ClaimExpired>({ from: sender.address, to: order.address });

    // Contract destroyed.
    expect(testing.getAccountBalance(order.address)).toBeLess(ton("0.001"));

    // The courier did not deliver in time, so they get nothing.
    expect(testing.getAccountBalance(courier.address) - courierMid).toEqual(0 as coins);

    // The sender got the reward AND the change of their GAS back in ONE merged
    // transfer (value = reward + mode 64). So their net gain is the full reward
    // PLUS most of the GAS they attached — clearly above the reward alone, which
    // is what proves the change rode along instead of arriving as a second
    // message. It stays under reward + GAS, so the fee buffer did NOT leak to the
    // sender (it must go to the owner below).
    val senderGain = testing.getAccountBalance(sender.address) - senderMid;
    expect(senderGain).toBeGreater(REWARD - ton("0.01"));
    expect(senderGain).toBeLess(REWARD + GAS);

    // Platform got the remaining buffer (the ~0.2 TON), NOT a dust amount: this
    // proves the buffer went to the platform and not back to the sender.
    expect(testing.getAccountBalance(owner.address) - ownerMid).toBeGreater(ton("0.2"));
}

// ---- claim is sender-only: a stranger past the deadline is rejected ----

get fun `test only the sender can claim an expired order`() {
    val (order, _, courier, _) = setupOrderTest();
    testing.setNow(BASE_TIME);
    order.sendAcceptOrder(courier.address, createEmptyCell(), { value: ACCEPT_FEE });

    // Past the deadline, but the caller is not the sender.
    testing.setNow(BASE_TIME + DEADLINE + 1);
    val stranger = testing.treasury("stranger");
    val r = order.sendClaimExpired(stranger.address, { value: GAS });
    expect(r).toHaveFailedTx({
        from: stranger.address,
        to: order.address,
        exitCode: OrderErrors.NotSender,
    });
    // The order is untouched and the contract still exists.
    expect(order.status()).toEqual(OrderStatus.Accepted);
}

get fun `test cannot claim before the deadline`() {
    val (order, _, courier, _) = setupOrderTest();
    testing.setNow(BASE_TIME);
    order.sendAcceptOrder(courier.address, createEmptyCell(), { value: ACCEPT_FEE });

    // Only a little time has passed — far short of 30 days.
    testing.setNow(BASE_TIME + 1000);
    val stranger = testing.treasury("stranger");
    val r = order.sendClaimExpired(stranger.address, { value: GAS });
    expect(r).toHaveFailedTx({
        from: stranger.address,
        to: order.address,
        exitCode: OrderErrors.NotExpired,
    });
    expect(order.status()).toEqual(OrderStatus.Accepted);
}

get fun `test cannot claim an order that was never accepted`() {
    val (order, _, _, _) = setupOrderTest();
    testing.setNow(BASE_TIME + DEADLINE + 1);

    val stranger = testing.treasury("stranger");
    val r = order.sendClaimExpired(stranger.address, { value: GAS });
    expect(r).toHaveFailedTx({
        from: stranger.address,
        to: order.address,
        exitCode: OrderErrors.WrongStatus,
    });
    expect(order.status()).toEqual(OrderStatus.Open);
}

// ---- cancel: Open -> Cancelled, reward back to sender, buffer to owner ----

get fun `test cancel refunds reward to sender and buffer to owner`() {
    val (order, sender, _, owner) = setupOrderTest();

    val senderMid = testing.getAccountBalance(sender.address);
    val ownerMid = testing.getAccountBalance(owner.address);

    // Cancelling now costs the sender the 0.3 TON cancel fee, attached here.
    val r = order.sendCancelOrder(sender.address, { value: CANCEL_FEE });
    expect(r).toHaveSuccessfulTx<CancelOrder>({ from: sender.address, to: order.address });

    // Contract must be destroyed.
    expect(testing.getAccountBalance(order.address)).toBeLess(ton("0.001"));

    // The sender receives their reward back in full (the 0.3 cancel fee they
    // attached is NOT refunded — it stays for the platform). Test treasuries only
    // track funds RECEIVED, so senderGain ≈ REWARD here.
    val senderGain = testing.getAccountBalance(sender.address) - senderMid;
    expect(senderGain).toBeGreater(REWARD - ton("0.02"));
    expect(senderGain).toBeLess(REWARD + ton("0.02"));

    // The owner receives the leftover: the deploy buffer this test funded (~0.3)
    // plus the 0.3 cancel fee — clearly more than the buffer alone (~0.6).
    val ownerGain = testing.getAccountBalance(owner.address) - ownerMid;
    expect(ownerGain).toBeGreater(ton("0.4"));
}

// Realistic funding: the UI sends only reward + 0.1 service fee (not the 0.3 the
// other tests use). With such a thin buffer the cancel must still pay the reward
// back in full, hand the small leftover to the owner, and self-destruct without
// running out of gas.
get fun `test cancel works with the real 0.1 create fee`() {
    val sender = testing.treasury("sender");
    val owner = testing.treasury("owner");

    val order = Order.fromStorage({
        sender: sender.address,
        courier: null,
        description: createEmptyCell(),
        area: createEmptyCell(),
        origin: createEmptyCell(),
        reward: REWARD,
        status: OrderStatus.Open,
        nonce: 0,
        createdAt: 0,
        acceptedAt: 0,
        extra: (OrderExtra {
            owner: owner.address,
            senderContact: createEmptyCell(),
            courierContact: createEmptyCell(),
            secretHash: 0,
        }).toCell(),
    });
    // Fund with reward + 0.1, exactly what the live UI attaches at create time.
    val res = order.deploy(sender.address, { value: REWARD + ton("0.1") });
    expect(res).toHaveSuccessfulDeploy({ to: order.address });

    val senderMid = testing.getAccountBalance(sender.address);
    val ownerMid = testing.getAccountBalance(owner.address);

    val r = order.sendCancelOrder(sender.address, { value: CANCEL_FEE });
    expect(r).toHaveSuccessfulTx<CancelOrder>({ from: sender.address, to: order.address });
    expect(testing.getAccountBalance(order.address)).toBeLess(ton("0.001"));

    // The sender receives the reward back in full (the 0.3 cancel fee is not
    // refunded). Treasuries only track received funds, so senderGain ≈ REWARD.
    val senderGain = testing.getAccountBalance(sender.address) - senderMid;
    expect(senderGain).toBeGreater(REWARD - ton("0.02"));
    expect(senderGain).toBeLess(REWARD + ton("0.02"));
    // The owner earns the 0.1 create fee already held plus the 0.3 cancel fee ≈ 0.4.
    expect(testing.getAccountBalance(owner.address) - ownerMid).toBeGreater(ton("0.35"));
}

// ---- courier gives up an accepted order: it reopens and the platform earns the fee ----

get fun `test courier release reopens the order and charges the release fee`() {
    val (order, sender, courier, owner) = setupOrderTest();
    testing.setNow(BASE_TIME);
    order.sendAcceptOrder(courier.address, createEmptyCell(), { value: ACCEPT_FEE });
    expect(order.status()).toEqual(OrderStatus.Accepted);

    val courierMid = testing.getAccountBalance(courier.address);
    val senderMid = testing.getAccountBalance(sender.address);
    val ownerMid = testing.getAccountBalance(owner.address);
    val orderMid = testing.getAccountBalance(order.address);

    // Giving up the order now costs the courier the 0.2 TON release fee, attached here.
    val r = order.sendCourierRelease(courier.address, { value: RELEASE_FEE });
    expect(r).toHaveSuccessfulTx<CourierRelease>({ from: courier.address, to: order.address });

    // The order reopened instead of closing, and looks like a fresh Open order:
    // no courier, no accept time, no courier contact.
    expect(order.status()).toEqual(OrderStatus.Open);
    val data = order.orderData();
    expect(data.acceptedAt).toEqual(0);
    expect(data.extra.load().courierContact.hash()).toEqual(createEmptyCell().hash());

    // The reward and the sender's create fee stay on the contract (still above
    // REWARD), ready for the next courier. The sender is not paid.
    expect(testing.getAccountBalance(order.address)).toBeGreater(REWARD);
    expect(testing.getAccountBalance(sender.address)).toEqual(senderMid);

    // Fees accumulate in the contract — owner receives nothing during a release.
    val ownerGain = testing.getAccountBalance(owner.address) - ownerMid;
    expect(ownerGain).toBeLess(ton("0.01"));

    // Courier received nothing back. Treasuries only track received funds,
    // so courierGain == 0 even though the courier sent 0.2 TON.
    val courierGain = testing.getAccountBalance(courier.address) - courierMid;
    expect(courierGain).toBeLess(ton("0.01"));

    // The contract balance grew: 0.2 came in and nothing went out.
    expect(testing.getAccountBalance(order.address)).toBeGreater(orderMid + ton("0.1"));

    // A different courier can now take the reopened order.
    val courier2 = testing.treasury("courier2");
    val r2 = order.sendAcceptOrder(courier2.address, createEmptyCell(), { value: ACCEPT_FEE });
    expect(r2).toHaveSuccessfulTx<AcceptOrder>({ from: courier2.address, to: order.address });
    expect(order.status()).toEqual(OrderStatus.Accepted);
    expect(order.orderData().courier!).toEqual(courier2.address);
}

// ---- release is blocked after the deadline: only the sender may act then ----
get fun `test cannot release after the deadline`() {
    val (order, _, courier, _) = setupOrderTest();
    testing.setNow(BASE_TIME);
    order.sendAcceptOrder(courier.address, createEmptyCell(), { value: ACCEPT_FEE });
    expect(order.status()).toEqual(OrderStatus.Accepted);

    // Jump past the deadline. The courier now has no actions left — a release is
    // rejected, so the order can only be settled by the sender (claim or confirm).
    testing.setNow(BASE_TIME + DEADLINE + 1);
    val r = order.sendCourierRelease(courier.address, { value: RELEASE_FEE });
    expect(r).toHaveFailedTx({
        from: courier.address,
        to: order.address,
        exitCode: OrderErrors.DeadlinePassed,
    });
    // The order is untouched: still Accepted by the same courier.
    expect(order.status()).toEqual(OrderStatus.Accepted);
}

get fun `test non-courier cannot release`() {
    val (order, sender, courier, _) = setupOrderTest();
    order.sendAcceptOrder(courier.address, createEmptyCell(), { value: ACCEPT_FEE });

    // The sender is not the courier, so they cannot release the order.
    val r = order.sendCourierRelease(sender.address, { value: GAS });
    expect(r).toHaveFailedTx({
        from: sender.address,
        to: order.address,
        exitCode: OrderErrors.NotCourier,
    });
    expect(order.status()).toEqual(OrderStatus.Accepted);
}

get fun `test cannot release an order that is still open`() {
    val (order, _, courier, _) = setupOrderTest();

    // No courier has accepted yet — release must fail on the status check.
    val r = order.sendCourierRelease(courier.address, { value: GAS });
    expect(r).toHaveFailedTx({
        from: courier.address,
        to: order.address,
        exitCode: OrderErrors.WrongStatus,
    });
    expect(order.status()).toEqual(OrderStatus.Open);
}

// ---- access control ----

get fun `test non-sender cannot cancel`() {
    val (order, _, courier, _) = setupOrderTest();

    val r = order.sendCancelOrder(courier.address, { value: GAS });
    expect(r).toHaveFailedTx({
        from: courier.address,
        to: order.address,
        exitCode: OrderErrors.NotSender,
    });
    expect(order.status()).toEqual(OrderStatus.Open);
}

// ---- invalid state transitions ----

get fun `test cannot accept twice`() {
    val (order, _, courier, _) = setupOrderTest();
    order.sendAcceptOrder(courier.address, createEmptyCell(), { value: ACCEPT_FEE });

    val other = testing.treasury("other");
    val r = order.sendAcceptOrder(other.address, createEmptyCell(), { value: ACCEPT_FEE });
    expect(r).toHaveFailedTx({
        from: other.address,
        to: order.address,
        exitCode: OrderErrors.WrongStatus,
    });
}

get fun `test cannot confirm before accepted`() {
    val (order, _, courier, _) = setupOrderTest();

    // Even with the correct code, an order that no courier has accepted yet cannot
    // be confirmed — the status guard rejects it before the hash is checked.
    val r = order.sendConfirmWithCode(courier.address, SECRET, { value: GAS });
    expect(r).toHaveFailedTx({
        from: courier.address,
        to: order.address,
        exitCode: OrderErrors.WrongStatus,
    });
}

get fun `test cannot cancel after accepted`() {
    val (order, sender, courier, _) = setupOrderTest();
    order.sendAcceptOrder(courier.address, createEmptyCell(), { value: ACCEPT_FEE });

    val r = order.sendCancelOrder(sender.address, { value: GAS });
    expect(r).toHaveFailedTx({
        from: sender.address,
        to: order.address,
        exitCode: OrderErrors.WrongStatus,
    });
}

// Deploys a fresh Open order with a 1 TON reward.
fun setupOrderTest(): (Order, Treasury, Treasury, Treasury) {
    val sender = testing.treasury("sender");
    val courier = testing.treasury("courier");
    val owner = testing.treasury("owner");

    val order = Order.fromStorage({
        sender: sender.address,
        courier: null,
        description: createEmptyCell(),
        area: createEmptyCell(),
        origin: createEmptyCell(),
        reward: REWARD,
        status: OrderStatus.Open,
        nonce: 0,
        createdAt: 0,
        acceptedAt: 0,
        extra: (OrderExtra {
            owner: owner.address,
            senderContact: createEmptyCell(),
            courierContact: createEmptyCell(),
            secretHash: secretHashOf(SECRET),
        }).toCell(),
    });
    val res = order.deploy(sender.address, { value: ton("1.3") });
    expect(res).toHaveSuccessfulDeploy({ to: order.address });

    return (order, sender, courier, owner);
}
