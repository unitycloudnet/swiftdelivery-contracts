import "@acton/build"
import "@acton/emulation/network"
import "@acton/emulation/testing"
import "@acton/testing/expect"

import "@contracts/types"
import "@wrappers/Marketplace.gen"
import "@wrappers/Order.gen"

const NONCE: uint64 = 12345
const CREATED_AT: uint32 = 1700000000

// Delivery secret and its on-chain commitment (see order.test.tolk). The order is
// created with this hash so the courier can later confirm with the matching code.
const SECRET: uint256 = 0xC0DE1234C0DE1234C0DE1234C0DE1234C0DE1234C0DE1234C0DE1234C0DE1234
fun secretHashOf(secret: uint256): uint256 {
    return beginCell().storeUint(secret, 256).endCell().hash();
}

get fun `test create order deploys an open order and holds the escrow`() {
    val (market, sender, _, _) = setupMarketTest();

    val res = market.sendCreateOrder(
        sender.address,
        ton("2"),
        NONCE,
        CREATED_AT,
        createEmptyCell(),
        createEmptyCell(),
        createEmptyCell(),
        createEmptyCell(),
        secretHashOf(SECRET),
        { value: ton("2.2") },
    );
    expect(res).toHaveSuccessfulTx<CreateOrder>({ from: sender.address, to: market.address });

    // The counter went up.
    expect(market.orderCount()).toEqual(1);

    // The child Order exists at the recomputed address, is Open, holds the money.
    val orderAddr = market.orderAddress(
        sender.address,
        ton("2"),
        NONCE,
        CREATED_AT,
        createEmptyCell(),
        createEmptyCell(),
        createEmptyCell(),
        createEmptyCell(),
        secretHashOf(SECRET),
    );
    val order = Order.fromAddress(orderAddr);
    expect(order.status()).toEqual(OrderStatus.Open);

    val data = order.orderData();
    expect(data.sender).toEqual(sender.address);
    expect(data.reward).toEqual(ton("2"));

    val escrow = testing.getAccountBalance(orderAddr);
    expect(escrow).toBeGreater(ton("1.9"));
}

get fun `test order created via marketplace can complete and pay the courier`() {
    val (market, sender, courier, _) = setupMarketTest();

    market.sendCreateOrder(
        sender.address,
        ton("2"),
        NONCE,
        CREATED_AT,
        createEmptyCell(),
        createEmptyCell(),
        createEmptyCell(),
        createEmptyCell(),
        secretHashOf(SECRET),
        { value: ton("2.2") },
    );

    val orderAddr = market.orderAddress(
        sender.address,
        ton("2"),
        NONCE,
        CREATED_AT,
        createEmptyCell(),
        createEmptyCell(),
        createEmptyCell(),
        createEmptyCell(),
        secretHashOf(SECRET),
    );
    val order = Order.fromAddress(orderAddr);

    order.sendAcceptOrder(courier.address, createEmptyCell(), { value: ton("0.5") });

    val courierBefore = testing.getAccountBalance(courier.address);
    // The courier confirms by revealing the secret behind the order's secretHash.
    val r = order.sendConfirmWithCode(courier.address, SECRET, { value: ton("0.05") });
    expect(r).toHaveSuccessfulTx<ConfirmWithCode>({ from: courier.address, to: order.address });

    // Contract is destroyed after ConfirmWithCode; cannot call order.status() — check
    // balance instead: courier received the reward, contract balance is zero.
    expect(testing.getAccountBalance(order.address)).toBeLess(ton("0.001"));
    expect(testing.getAccountBalance(courier.address)).toBeGreater(courierBefore);
}

// ---- escrow funding: a reward not backed by attached value is rejected ----

get fun `test create rejects an order that does not cover the reward`() {
    val (market, sender, _, _) = setupMarketTest();

    // Claim a 2 TON reward but attach only 0.2 TON. Without the value check this
    // would deploy an Order showing a 2 TON reward it does not hold, and a
    // courier who delivered could never be paid.
    val r = market.sendCreateOrder(
        sender.address,
        ton("2"),
        NONCE,
        CREATED_AT,
        createEmptyCell(),
        createEmptyCell(),
        createEmptyCell(),
        createEmptyCell(),
        secretHashOf(SECRET),
        { value: ton("0.2") },
    );
    expect(r).toHaveFailedTx({
        from: sender.address,
        to: market.address,
        exitCode: MarketplaceErrors.InsufficientValue,
    });

    // Nothing was created: the counter stayed at zero and no child was deployed.
    expect(market.orderCount()).toEqual(0);
    val orderAddr = market.orderAddress(
        sender.address,
        ton("2"),
        NONCE,
        CREATED_AT,
        createEmptyCell(),
        createEmptyCell(),
        createEmptyCell(),
        createEmptyCell(),
        secretHashOf(SECRET),
    );
    expect(testing.getAccountBalance(orderAddr)).toEqual(0 as coins);
}

// Deploys a Marketplace that knows the compiled Order code.
fun setupMarketTest(): (Marketplace, Treasury, Treasury, Treasury) {
    val deployer = testing.treasury("deployer");
    val sender = testing.treasury("sender");
    val courier = testing.treasury("courier");

    val market = Marketplace.fromStorage({
        owner: deployer.address,
        orderCode: build("Order"),
        orderCount: 0,
    });
    val res = market.deploy(deployer.address, { value: ton("0.5") });
    expect(res).toHaveSuccessfulDeploy({ to: market.address });

    return (market, sender, courier, deployer);
}
