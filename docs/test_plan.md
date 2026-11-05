# Order Matching Engine: Verification Test Plan

## 1. Design under test
A single-instrument limit order matching engine. 16 price levels per side (4-bit price), 4 resting orders per level, 8-bit quantity and order ID. Valid/ready handshakes on the order input and the trade/status output.

## 2. Matching rules (the spec)
| # | Rule |
|---|---|
| R1 | Price priority: a buy matches the lowest ask first; a sell matches the highest bid first |
| R2 | Time priority: at the same price, the oldest order fills first |
| R3 | Trade price = price of the resting order |
| R4 | Any unfilled remainder rests at the incoming order's price |
| R5 | If that price level already holds 4 orders, the order is rejected (REJECT_FULL) |
| R6 | Illegal input (qty = 0) is never driven; the testbench constrains it out |

**Derived fact:** a REJECT_FULL order never produces trades. If a level at price P on the order's own side is full, the book is uncrossed, so no opposite order can match at P. The model's random test checks this.

## 3. Reference model
C++ model (`model/ref_book.cpp`) called from the scoreboard through DPI-C (`model/dpi_ref_book.cpp`). The scoreboard compares every trade (buy_id, sell_id, price, qty) and every status, in order.

## 4. Stimulus
| Sequence | Purpose | Rules hit |
|---|---|---|
| `random_mix` | Fully random side/price/qty | All |
| `calm_market` | Bids low, asks high; mostly rest | R4, R5 |
| `frantic_market` | Prices overlap; most orders cross | R1, R2, R3 |
| `whale_order` | One large order sweeps 4+ levels | R1, R3 |
| `fill_level` | 5 orders at one price | R5 |
| `one_sided` | Only buys or only sells | R4, empty opposite book |
| Back-pressure | Random `ready` low on the output | Handshake |

## 5. Checks
**Scoreboard:** every DUT trade and status matches the model.

**Assertions (SVA):**
- A1: input/output data stable while `valid && !ready`
- A2: when idle, best bid < best ask
- A3: trade qty is never 0
- A4: trade price <= buyer limit and >= seller limit
- A5: no level count exceeds 4
- A6: REJECT_FULL is never preceded by a trade for the same order

## 6. Functional coverage goals
| Covergroup | Bins | Goal |
|---|---|---|
| Outcome | side x {rested, partial fill, full fill, rejected} | 100% |
| Levels swept | 0, 1, 2-3, 4+ | 100% |
| Level fill count at submit | 0, 1, 2, 3, 4 | 100% |
| Opposite book empty | yes / no | 100% |
| Price | 0, 1-14, 15 | 100% |
| Quantity | 1, 2-254, 255 | 100% |
| Output back-pressure with trades pending | yes / no | 100% |

**Sign-off:** all tests pass on 10+ seeds, 0 scoreboard mismatches, 0 assertion failures, 100% of the bins above (or a written reason for any hole).

## 7. Performance
Predicted cycles per order = base + fills x cycles_per_fill. Measured with cycle counters in simulation; plot predicted vs measured.
