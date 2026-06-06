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
| Cancel (expired) | — | Sender gets the reward back |
| Courier release | — | Courier gets the 0.1 TON accept fee back |

The service fee covers TON network costs and platform operation.

## Build and test

```bash
acton build
acton test
```

## License

MIT — see [LICENSE](LICENSE).
