# SwiftDelivery — TON Smart Contracts

SwiftDelivery is a delivery service on the TON blockchain. Senders post delivery
orders; couriers accept and complete them. All money flows through smart
contracts — the service cannot take or hold funds outside the rules written in
the code.

This repository is published so anyone can read the contract code and verify
how the service works.

## Contracts

- `contracts/Marketplace.tolk` — receives new orders, creates an Order contract
  for each one, collects a small service fee.
- `contracts/Order.tolk` — holds the delivery reward in escrow. Releases it to
  the courier when the sender confirms delivery; refunds the sender if the order
  expires or the courier gives up.

## How money moves

| Action | Who pays | Who receives |
|--------|----------|--------------|
| Create order | Sender (reward + 0.1 TON service fee) | Marketplace |
| Accept order | Courier (0.1 TON service fee) | Marketplace |
| Confirm delivery | — | Courier gets the reward |
| Claim (expired) | — | Sender gets the reward back |
| Cancel order | Sender (0.3 TON fee, on top of the 0.1 create fee) | Sender gets the reward back; Marketplace keeps ~0.4 |
| Courier release | Courier (0.2 TON fee; the 0.1 accept fee is also kept) | Order reopens; Marketplace keeps ~0.3 |

A normal create → accept → confirm earns the platform ~0.2 TON. Cancelling an order
or giving up an accepted one costs an extra fee that the platform keeps; the reward
is always returned in full. The service fee covers TON network costs and platform
operation.

Each order also records two public cities: a destination ("to") and an origin
("from", default "All world").

## Build and test

```bash
acton build
acton test
```

## License

MIT — see [LICENSE](LICENSE).
