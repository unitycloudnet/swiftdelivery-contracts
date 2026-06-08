import "types"

// The single registry contract. On a CreateOrder message it deploys a brand
// new Order contract and forwards the attached TON to it as the escrow.
//
// Note on discovery: an order's address is the hash of its initial state, so
// only someone who knows that order's initial data can recompute its address.
// The frontend recomputes its OWN orders' addresses; a global feed needs a
// read-only TON indexer that reads the Marketplace's outgoing deploy messages.
// The sender must attach at least the stated reward plus this buffer. The UI
// sends reward + 0.1 (the create-time service fee, see src/contracts/orders.js);
// we require a little less so the wallet's first-hop forward fee never trips an
// honest order, while a grossly under-funded order is rejected. This check is
// what guarantees the new Order's escrow truly holds the reward: without it a
// sender could advertise a reward the contract does not hold, and a courier
// would deliver for nothing.
const CREATE_MIN_BUFFER = ton("0.05")

contract Marketplace {
    author: "SwiftDelivery"
    version: "1.8.0"
    description: "Registry that deploys Order escrow contracts"
    storage: MarketplaceStorage
    incomingMessages: MarketplaceMessage
}

fun onInternalMessage(in: InMessage) {
    val msg = lazy MarketplaceMessage.fromSlice(in.body);
    var st = lazy MarketplaceStorage.load();

    match (msg) {
        CreateOrder => {
            // Refuse to deploy an order the sender did not actually fund. The
            // reward is forwarded to the child as its escrow, so the attached
            // value must cover it (plus a small gas/fee buffer).
            assert (
                in.valueCoins >= msg.reward + CREATE_MIN_BUFFER
            ) throw MarketplaceErrors.InsufficientValue;

            // orderCount is kept only as a running total / stat.
            st.orderCount = st.orderCount + 1;
            st.save();

            // Build the new Order's initial state from the creator's fields.
            val orderData = OrderStorage {
                sender: in.senderAddress,
                courier: null,
                description: msg.description,
                area: msg.area,
                origin: msg.origin,
                reward: msg.reward,
                status: OrderStatus.Open,
                nonce: msg.nonce,
                createdAt: msg.createdAt,
                acceptedAt: 0, // set by Order when a courier accepts
                extra: (OrderExtra {
                    owner: st.owner,
                    senderContact: msg.senderContact,
                    courierContact: createEmptyCell(),
                }).toCell(),
            };

            // Deploy it by sending to its state-init, forwarding all the TON
            // that came with this message (minus gas already spent).
            val deployMsg = createMessage({
                bounce: BounceMode.NoBounce,
                value: 0 as coins,
                dest: AutoDeployAddress {
                    stateInit: ContractState {
                        code: st.orderCode,
                        data: orderData.toCell(),
                    },
                },
            });
            deployMsg.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
        }
        else => {
            assert (in.body.isEmpty()) throw MarketplaceErrors.InvalidMessage;
        }
    }
}

fun onBouncedMessage(_in: InMessageBounced) {}

get fun orderCount(): uint32 {
    val st = lazy MarketplaceStorage.load();
    return st.orderCount;
}

get fun owner(): address {
    val st = lazy MarketplaceStorage.load();
    return st.owner;
}

// Recompute the address of an order from its initial data. The frontend uses
// this for orders it created itself (it knows all the fields it sent).
get fun orderAddress(
    sender: address,
    reward: coins,
    nonce: uint64,
    createdAt: uint32,
    description: cell,
    area: cell,
    origin: cell,
    senderContact: cell,
): address {
    val st = lazy MarketplaceStorage.load();
    val orderData = OrderStorage {
        sender,
        courier: null,
        description,
        area,
        origin,
        reward,
        status: OrderStatus.Open,
        nonce,
        createdAt,
        acceptedAt: 0,
        extra: (OrderExtra {
            owner: st.owner,
            senderContact,
            courierContact: createEmptyCell(),
        }).toCell(),
    };
    val addr = AutoDeployAddress {
        stateInit: ContractState {
            code: st.orderCode,
            data: orderData.toCell(),
        },
    }.calculateAddress();
    return addr;
}
