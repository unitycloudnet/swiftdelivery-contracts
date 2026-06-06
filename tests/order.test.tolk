import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/types"
import "@wrappers/Order.gen"

const GAS = ton("0.05")
const REWARD = ton("1")
const ACCEPT_FEE = ton("0.1") // courier's service fee (>= MIN_ACCEPT_FEE 0.1)
const BELOW_FEE = ton("0.02") // below MIN_ACCEPT_FEE; accept must reject it
const DEADLINE = 60 * 60 // must match Order.tolk (1h testing value)
// A fixed "now" for time-dependent tests. Must be in the FUTURE relative to the
// emulator's default wall-clock time, otherwise setNow() would move time
// backwards past the deploy and the storage phase fails (-669).
const BASE_TIME: uint32 = 2000000000

// ---- happy path: Open -> Accepted -> Completed ----

get fun `test happy path pays courier the reward and refunds sender change`() {
    val (order, sender, courier, owner) = setupOrderTest();

    order.sendAcceptOrder(courier.address, createEmptyCell(), { value: ACCEPT_FEE });

    // Capture balances after accept, before confirm.
    val courierMid = testing.getAccountBalance(courier.address);
    val ownerMid = testing.getAccountBalance(owner.address);
    val senderMid = testing.getAccountBalance(sender.address);

    val r = order.sendConfirmDelivery(sender.address, { value: GAS });
    expect(r).toHaveSuccessfulTx<ConfirmDelivery>({ from: sender.address, to: order.address });

    // Contract must be destroyed.
    expect(testing.getAccountBalance(order.address)).toBeLess(ton("0.001"));

    // Courier received exactly the reward (no deposit any more; tolerate fwd_fee).
    val courierGain = testing.getAccountBalance(courier.address) - courierMid;
    expect(courierGain).toBeGreater(REWARD - ton("0.01"));
    expect(courierGain).toBeLess(REWARD + ton("0.01"));

    // Sender got the change of their GAS back (mode 64), so the net cost of the
    // confirm call is only the tx fee — far less than the full GAS they sent.
    // Without the refund, senderGain would be about -GAS (-0.05).
    val senderGain = testing.getAccountBalance(sender.address) - senderMid;
    expect(senderGain).toBeGreater(-ton("0.03"));

    // Owner received the ~0.2 fee buffer as the platform's earnings, NOT a dust
    // amount: this proves the buffer went to the platform, not back to the sender.
    val ownerGain = testing.getAccountBalance(owner.address) - ownerMid;
    expect(ownerGain).toBeGreater(ton("0.2"));
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
        reward: bigCoins,
        status: OrderStatus.Open,
        nonce: 0,
        createdAt: 0,
        acceptedAt: 0,
        extra: (OrderExtra {
            owner: owner.address,
            senderContact: createEmptyCell(),
            courierContact: createEmptyCell(),
        }).toCell(),
    });
    val res = order.deploy(sender.address, { value: ton("6") });
    expect(res).toHaveSuccessfulDeploy({ to: order.address });

    val r = order.sendAcceptOrder(courier.address, createEmptyCell(), { value: bigCoins });
    expect(r).toHaveSuccessfulTx<AcceptOrder>({ from: courier.address, to: order.address });
    expect(order.status()).toEqual(OrderStatus.Accepted);
}

// ---- claim after the deadline: reward -> sender, buffer -> platform, courier nothing ----

get fun `test claim after deadline refunds sender and pays platform`() {
    val (order, sender, courier, owner) = setupOrderTest();
    testing.setNow(BASE_TIME);
    order.sendAcceptOrder(courier.address, createEmptyCell(), { value: ACCEPT_FEE });

    val courierMid = testing.getAccountBalance(courier.address);
    val senderMid = testing.getAccountBalance(sender.address);
    val ownerMid = testing.getAccountBalance(owner.address);

    // Jump past the deadline. Anyone may claim — use a stranger.
    testing.setNow(BASE_TIME + DEADLINE + 1);
    val stranger = testing.treasury("stranger");
    val strangerMid = testing.getAccountBalance(stranger.address);
    val r = order.sendClaimExpired(stranger.address, { value: GAS });
    expect(r).toHaveSuccessfulTx<ClaimExpired>({ from: stranger.address, to: order.address });

    // Contract destroyed.
    expect(testing.getAccountBalance(order.address)).toBeLess(ton("0.001"));

    // The courier did not deliver in time, so they get nothing.
    expect(testing.getAccountBalance(courier.address) - courierMid).toEqual(0 as coins);

    // Sender got exactly the reward back (tolerate emulator fwd_fee).
    val senderGain = testing.getAccountBalance(sender.address) - senderMid;
    expect(senderGain).toBeGreater(REWARD - ton("0.01"));
    expect(senderGain).toBeLess(REWARD + ton("0.01"));

    // The caller got the change of their GAS back (mode 64), so the claim costs
    // them only the tx fee — far less than the full GAS they sent. Without the
    // refund, strangerGain would be about -GAS (-0.05) and this would fail.
    val strangerGain = testing.getAccountBalance(stranger.address) - strangerMid;
    expect(strangerGain).toBeGreater(-ton("0.03"));

    // Platform got the remaining buffer (the ~0.2 TON), NOT a dust amount: this
    // proves the buffer went to the platform and the caller's change did not.
    expect(testing.getAccountBalance(owner.address) - ownerMid).toBeGreater(ton("0.2"));
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

    val r = order.sendCancelOrder(sender.address, { value: GAS });
    expect(r).toHaveSuccessfulTx<CancelOrder>({ from: sender.address, to: order.address });

    // Contract must be destroyed.
    expect(testing.getAccountBalance(order.address)).toBeLess(ton("0.001"));

    // The sender gets their reward back plus the change of the cancel gas they
    // sent (mode 64), but NOT the create fee buffer. If the old code had returned
    // the whole balance, senderGain would be about REWARD + the buffer (~0.3 here)
    // and the upper bound fails.
    val senderGain = testing.getAccountBalance(sender.address) - senderMid;
    expect(senderGain).toBeGreater(REWARD - ton("0.1"));
    expect(senderGain).toBeLess(REWARD + ton("0.05"));

    // The owner gets the leftover buffer as the cancellation fee. Previously the
    // owner got nothing on cancel, so this must be clearly positive.
    val ownerGain = testing.getAccountBalance(owner.address) - ownerMid;
    expect(ownerGain).toBeGreater(ton("0.1"));
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
        reward: REWARD,
        status: OrderStatus.Open,
        nonce: 0,
        createdAt: 0,
        acceptedAt: 0,
        extra: (OrderExtra {
            owner: owner.address,
            senderContact: createEmptyCell(),
            courierContact: createEmptyCell(),
        }).toCell(),
    });
    // Fund with reward + 0.1, exactly what the live UI attaches at create time.
    val res = order.deploy(sender.address, { value: REWARD + ton("0.1") });
    expect(res).toHaveSuccessfulDeploy({ to: order.address });

    val senderMid = testing.getAccountBalance(sender.address);
    val ownerMid = testing.getAccountBalance(owner.address);

    val r = order.sendCancelOrder(sender.address, { value: GAS });
    expect(r).toHaveSuccessfulTx<CancelOrder>({ from: sender.address, to: order.address });
    expect(testing.getAccountBalance(order.address)).toBeLess(ton("0.001"));

    // Reward comes back in full (tolerate fwd fee); the small leftover is the
    // owner's fee, so the owner must still gain something.
    val senderGain = testing.getAccountBalance(sender.address) - senderMid;
    expect(senderGain).toBeGreater(REWARD - ton("0.1"));
    expect(senderGain).toBeLess(REWARD + ton("0.05"));
    expect(testing.getAccountBalance(owner.address) - ownerMid).toBeGreater(0 as coins);
}

// ---- courier gives up an accepted order: it reopens and the accept fee is refunded ----

get fun `test courier release reopens the order and refunds the accept fee`() {
    val (order, sender, courier, owner) = setupOrderTest();
    testing.setNow(BASE_TIME);
    order.sendAcceptOrder(courier.address, createEmptyCell(), { value: ACCEPT_FEE });
    expect(order.status()).toEqual(OrderStatus.Accepted);

    val courierMid = testing.getAccountBalance(courier.address);
    val senderMid = testing.getAccountBalance(sender.address);
    val ownerMid = testing.getAccountBalance(owner.address);
    val orderMid = testing.getAccountBalance(order.address);

    val r = order.sendCourierRelease(courier.address, { value: GAS });
    expect(r).toHaveSuccessfulTx<CourierRelease>({ from: courier.address, to: order.address });

    // The order reopened instead of closing, and looks like a fresh Open order:
    // no courier, no accept time, no courier contact.
    expect(order.status()).toEqual(OrderStatus.Open);
    val data = order.orderData();
    expect(data.acceptedAt).toEqual(0);
    expect(data.extra.load().courierContact.hash()).toEqual(createEmptyCell().hash());

    // The reward and the sender's create fee stay on the contract (still above
    // REWARD), but the courier's 0.1 accept fee was refunded, so the contract
    // balance dropped by ~0.1 compared with the accepted state. Sender and owner
    // were not paid.
    expect(testing.getAccountBalance(order.address)).toBeGreater(REWARD);
    expect(orderMid - testing.getAccountBalance(order.address)).toBeGreater(ton("0.08"));
    expect(testing.getAccountBalance(sender.address)).toEqual(senderMid);
    expect(testing.getAccountBalance(owner.address)).toEqual(ownerMid);

    // The courier got their full accept fee back plus the change of their release
    // gas (mode 64), so giving up the order costs them only the tx gas — they come
    // out roughly +0.1 versus before the release.
    val courierGain = testing.getAccountBalance(courier.address) - courierMid;
    expect(courierGain).toBeGreater(ton("0.05"));

    // A different courier can now take the reopened order.
    val courier2 = testing.treasury("courier2");
    val r2 = order.sendAcceptOrder(courier2.address, createEmptyCell(), { value: ACCEPT_FEE });
    expect(r2).toHaveSuccessfulTx<AcceptOrder>({ from: courier2.address, to: order.address });
    expect(order.status()).toEqual(OrderStatus.Accepted);
    expect(order.orderData().courier!).toEqual(courier2.address);
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

get fun `test non-sender cannot confirm delivery`() {
    val (order, _, courier, _) = setupOrderTest();
    order.sendAcceptOrder(courier.address, createEmptyCell(), { value: ACCEPT_FEE });

    val r = order.sendConfirmDelivery(courier.address, { value: GAS });
    expect(r).toHaveFailedTx({
        from: courier.address,
        to: order.address,
        exitCode: OrderErrors.NotSender,
    });
    expect(order.status()).toEqual(OrderStatus.Accepted);
}

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
    val (order, sender, _, _) = setupOrderTest();

    val r = order.sendConfirmDelivery(sender.address, { value: GAS });
    expect(r).toHaveFailedTx({
        from: sender.address,
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
        reward: REWARD,
        status: OrderStatus.Open,
        nonce: 0,
        createdAt: 0,
        acceptedAt: 0,
        extra: (OrderExtra {
            owner: owner.address,
            senderContact: createEmptyCell(),
            courierContact: createEmptyCell(),
        }).toCell(),
    });
    val res = order.deploy(sender.address, { value: ton("1.3") });
    expect(res).toHaveSuccessfulDeploy({ to: order.address });

    return (order, sender, courier, owner);
}
