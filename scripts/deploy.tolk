import "@acton/build"
import "@acton/io"
import "@acton/emulation/network"
import "@acton/emulation/scripts"
import "@contracts/types"
import "@wrappers/Marketplace.gen"

// Deploys the single Marketplace contract. The Order code is embedded in the
// Marketplace storage so it can deploy Order children on-chain later.
//
//   acton script scripts/deploy.tolk               # local emulation
//   acton script scripts/deploy.tolk --net testnet # real testnet
fun main() {
    val deployer = scripts.wallet("deployer");

    val market = Marketplace.fromStorage({
        owner: deployer.address,
        orderCode: build("Order"),
        orderCount: 0,
    });
    val res = market.deploy(deployer.address, { value: ton("0.1") });
    println(res.waitForTrace());

    println("Deployed Marketplace to {}", market.address);
    println("Owner is {}", market.owner());
    println("Order count is {}", market.orderCount());
}
