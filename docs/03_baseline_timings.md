# Blinkit 10-Minute Grocery Delivery Database: Baseline Query Timings (CP2)

**Project Phase:** CP2 — Baseline Timings  
**Database System:** PostgreSQL 18.6 (Postgres.app) on aarch64-apple-darwin23.6.0, 64-bit (`blinkit` schema)  
**Hardware / OS:** Apple Silicon (macOS 27.2.1, Build 26B131, arm64)  
**Measurement Method:** 3 runs per query using `EXPLAIN (ANALYZE, BUFFERS)` via `benchmarks/run_benchmark.sh blinkit_db baseline`  
**Dataset:** Seed dataset (150,000 orders, 675,000 order items, 126,000 inventory rows, 90,000 movements)  
**Index State:** Un-tuned baseline (only primary key and unique constraint B-tree indexes exist)

---

## 1. Baseline Benchmark Results Table

All execution times are reported in milliseconds (ms). Every number matches [summary.csv](../benchmarks/results/baseline/summary.csv) and the raw plan files in [benchmarks/results/baseline/](../benchmarks/results/baseline/).

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
| :--- | :--- | ---:| ---:| ---:| ---:|
| R01: Store assignment: the nearest active dark store within ~3 km of a customer at (12.93, 77.62) | READ | 0.150 | 0.103 | 0.113 | 0.122 |
| R02: Category page: Dairy products in stock at store 43, cheapest first | READ | 1.135 | 0.466 | 0.487 | 0.696 |
| R03: Search: products with "milk" in the name that are in stock at store 43 | READ | 1.277 | 1.229 | 1.284 | 1.263 |
| R04: Product page: stock of product 1236 in every Bengaluru dark store | READ | 3.007 | 0.180 | 0.238 | 1.142 |
| R05: Cart check: current stock and price of 4 cart items at store 43 | READ | 0.062 | 0.059 | 0.054 | 0.058 |
| R06: Order tracking: customer 1027's latest order with its timeline | READ | 8.334 | 8.339 | 9.361 | 8.678 |
| R07: Store screen: open orders at store 43 (not yet delivered or cancelled) | READ | 10.746 | 11.233 | 11.880 | 11.286 |
| R08: SLA report: share of June 2026 deliveries that took longer than promised, per store | READ | 12.458 | 12.779 | 11.837 | 12.358 |
| R09: Replenishment: products at store 43 at or below their reorder level | READ | 0.504 | 0.480 | 0.499 | 0.494 |
| R10: Wastage: units lost to expiry or damage per category in June 2026 | READ | 8.653 | 8.395 | 8.542 | 8.530 |
| R11: Rider performance: average minutes from pickup to delivery per rider at store 43 (June 2026) | READ | 11.041 | 11.078 | 10.957 | 11.025 |
| R12: Recommendations: products most often bought together with product 1236 | READ | 26.675 | 15.530 | 15.501 | 19.235 |
| R13: Category team: active products that were never given as a substitute in June 2026 | READ | 35.649 | 36.217 | 35.688 | 35.851 |
| R14: Fill rate: share of order lines delivered short, per store, June 2026 | READ | 35.447 | 35.220 | 34.950 | 35.206 |
| R15: Staffing: orders per hour at Bengaluru stores on 29 June 2026 | READ | 16.295 | 16.868 | 18.374 | 17.179 |
| R16: Growth: monthly cohorts—customers by month of first order, and how many ordered again in June 2026 | READ | 57.548 | 61.845 | 62.867 | 60.753 |
| R17: Finance: small-cart fee collected per city per month in 2026 | READ | 56.870 | 57.508 | 59.801 | 58.060 |
| R18: Dead stock: products in stock at store 43 that did not sell there in June 2026 | READ | 12.356 | 10.612 | 11.147 | 11.372 |
| R19: Category report: June 2026 units sold of every Fruits & Vegetables product | READ | 3542.098 | 3546.290 | 3577.351 | 3555.246 |
| R20: Finance: daily GMV and running total for June 2026 | READ | 17.327 | 17.296 | 20.745 | 18.456 |
| R21: Store manager: active riders of store 43 with no delivery on 30 June 2026 | READ | 10.863 | 10.322 | 10.147 | 10.444 |
| R22: Support console: all orders, newest first, page 4,001 (25 per page) | READ | 69.043 | 65.926 | 68.111 | 67.693 |
| R23: Warehouse scanner: look up a product by SKU | READ | 0.528 | 0.053 | 0.050 | 0.210 |
| R24: Supply chain: units restocked per product at store 43 in the last 7 days of June 2026 | READ | 5.379 | 5.386 | 5.324 | 5.363 |
| R25: Loyalty: 20 Mumbai customers with the most delivered orders in 2026 | READ | 27.609 | 27.834 | 27.540 | 27.661 |
| W01: Checkout: place a new order at store 43 | WRITE | 2.618 | 1.117 | 3.169 | 2.301 |
| W02: Packing done: reduce store 43's stock for every line of its most recent PLACED or PACKING order | WRITE | 22.079 | 25.861 | 19.881 | 22.607 |
| W03: Dispatch: give the oldest PACKING order (anywhere) to its store's first active rider | WRITE | 25.478 | 23.083 | 22.869 | 23.810 |
| W04: Nightly replenishment at store 43: top up everything at or below reorder level | WRITE | 2.205 | 1.878 | 1.947 | 2.010 |
| W05: Data retention: delete inventory movements older than 1 January 2026 | WRITE | 61.088 | 31.223 | 23.096 | 38.469 |
| **Total (sum of all 30)** | | **4084.522** | **4044.410** | **4073.810** | **4067.578** |

---

## 2. Query Scan Types & Execution Analysis

The scan types extracted from PostgreSQL execution plans and the primary performance drivers are detailed below:

* **R01 (0.122 ms) — `Seq Scan on dark_stores`:** Fast because `dark_stores` contains only 120 rows; in-memory sequential filtering and quicksort take negligible time.
* **R02 (0.696 ms) — `Seq Scan on products | Seq Scan on categories | Index Scan using store_inventory_pkey on store_inventory`:** Relatively fast due to small catalog size (1,500 products, 12 categories), but performs sequential scans on products and categories before probing inventory.
* **R03 (1.263 ms) — `Seq Scan on products | Index Scan using store_inventory_pkey on store_inventory`:** Evaluates `ILIKE '%milk%'` via sequential scan across all products, then looks up store stock via primary key index.
* **R04 (1.142 ms) — `Seq Scan on dark_stores | Index Scan using store_inventory_pkey on store_inventory`:** Scans all 120 stores filtering for Bengaluru (`city_id = 1`) and performs index lookups on `store_inventory`.
* **R05 (0.058 ms) — `Index Scan using store_inventory_pkey on store_inventory`:** Ultra-fast point lookup accessing only 4 specific rows using the composite primary key index `(store_id, product_id)`.
* **R06 (8.678 ms) — `Seq Scan on orders`:** Slow for a real-time tracking query because it sequentially scans all 150,000 order rows to find orders for `customer_id = 1027`.
* **R07 (11.286 ms) — `Seq Scan on orders`:** Scans all 150,000 orders to find active statuses for store 43; misses the < 5 ms SLA required for warehouse picking screens.
* **R08 (12.358 ms) — `Seq Scan on orders`:** Scans the entire orders table to filter June 2026 delivered orders and compute late percentages.
* **R09 (0.494 ms) — `Seq Scan on products | Bitmap Heap Scan on store_inventory | Bitmap Index Scan on store_inventory_pkey`:** Uses `store_inventory_pkey` leading column `store_id = 43` with bitmap index scan to locate the store's 1,050 inventory rows, followed by a product join.
* **R10 (8.530 ms) — `Seq Scan on inventory_movements | Seq Scan on products | Index Scan using categories_pkey on categories`:** Scans all 90,000 movement records to aggregate June 2026 expiries and damages.
* **R11 (11.025 ms) — `Seq Scan on orders`:** Full table scan across 150,000 orders filtering for store 43 delivered orders in June 2026.
* **R12 (19.235 ms) — `Seq Scan on order_items | Index Only Scan using order_items_pkey on order_items`:** Full sequential scan across 675,000 order item lines because `order_items_pkey` leading column is `order_id`, making it unusable for `WHERE product_id = 1236`.
* **R13 (35.851 ms) — `Seq Scan on products | Seq Scan on order_items | Seq Scan on orders`:** Scans all 675,000 order items and 150,000 orders for the subquery; furthermore, returns 0 rows due to SQL three-valued logic with `NULL` substitutes.
* **R14 (35.206 ms) — `Seq Scan on order_items | Seq Scan on orders`:** Joins 675,000 order items to 150,000 orders using hash join with sequential scans on both large fact tables.
* **R15 (17.179 ms) — `Seq Scan on orders | Index Scan using dark_stores_pkey on dark_stores`:** Non-sargable predicate `DATE(o.placed_at) = '2026-06-29'` forces a full scan of 150,000 orders and row-by-row function evaluations.
* **R16 (60.753 ms) — `Seq Scan on orders`:** Heavy multi-pass sequential scan on `orders` (150,000 rows) to calculate customer first-order cohorts and evaluate correlated `EXISTS` subqueries for June activity.
* **R17 (58.060 ms) — `Seq Scan on orders | Index Scan using dark_stores_pkey on dark_stores`:** Non-sargable expression `EXTRACT(YEAR FROM o.placed_at) = 2026` forces a full sequential scan of 150,000 orders.
* **R18 (11.372 ms) — `Seq Scan on orders | Index Only Scan using order_items_pkey on order_items | Bitmap Heap Scan on store_inventory | Bitmap Index Scan on store_inventory_pkey | Seq Scan on products`:** Scans `orders` repeatedly inside a correlated `NOT EXISTS` subquery to determine zero-sales items.
* **R19 (3555.246 ms) — `Seq Scan on categories | Seq Scan on products | Seq Scan on order_items | Index Scan using orders_pkey on orders`:** Severe bottleneck query. Correlated subquery in the `SELECT` projection executes a full scan of 675,000 `order_items` rows for every single product in Fruits & Vegetables (125 executions).
* **R20 (18.456 ms) — `Seq Scan on orders`:** Scans all 150,000 orders to aggregate June 2026 daily GMV before applying window function running totals.
* **R21 (10.444 ms) — `Seq Scan on orders | Seq Scan on riders`:** Scans 150,000 orders inside a correlated `NOT EXISTS` subquery to find riders with no dispatches on 30 June.
* **R22 (67.693 ms) — `Seq Scan on orders`:** Full table scan and quicksort across 150,000 rows followed by discarding 100,000 rows to satisfy deep `OFFSET 100000 LIMIT 25`.
* **R23 (0.210 ms) — `Index Scan using products_sku_key on products`:** Instant index lookup using the unique B-tree index on `products.sku`.
* **R24 (5.363 ms) — `Seq Scan on inventory_movements`:** Scans 90,000 movement records to aggregate restocks for store 43 over the last 7 days.
* **R25 (27.661 ms) — `Seq Scan on orders | Seq Scan on customers`:** Hash join between 40,000 customers and 150,000 orders to calculate top Mumbai customer spend.
* **W01 (2.301 ms) — `(no scan)`:** Single row `INSERT` into `orders` with foreign key validations against customers and dark stores.
* **W02 (22.607 ms) — `Seq Scan on orders | Index Scan using order_items_pkey on order_items | Index Scan using store_inventory_pkey on store_inventory`:** Scans 150,000 orders to evaluate `SELECT max(order_id) FROM orders WHERE store_id = 43 AND status IN ('PLACED', 'PACKING')`.
* **W03 (23.810 ms) — `Index Scan using orders_pkey on orders | Index Scan using riders_pkey on riders`:** Scans orders to find `min(order_id) WHERE status = 'PACKING'`, then updates timestamps and rider assignment.
* **W04 (2.010 ms) — `Bitmap Heap Scan on store_inventory | Bitmap Index Scan on store_inventory_pkey`:** Uses `store_inventory_pkey` to update 229 low-stock items at store 43.
* **W05 (38.469 ms) — `Seq Scan on inventory_movements`:** Scans all 90,000 rows of `inventory_movements` to locate and delete 60,165 movements prior to 2026-01-01.

---

## 3. Slowest Queries & Major Bottlenecks

1. **R19 (3,555.246 ms — 87.4% of total workload time):**
   - *Cause:* Correlated scalar subquery in the `SELECT` list. For each of the 125 Fruits & Vegetables products, PostgreSQL scans the 675,000-row `order_items` table and joins with `orders`.
   - *Solution Direction:* Flatten the correlated subquery into a set-based `LEFT JOIN ... GROUP BY` with proper indexing on `order_items(product_id)`.

2. **R22 (67.693 ms) & R16 (60.753 ms):**
   - *Cause:* R22 performs deep offset pagination (`OFFSET 100000`) requiring a full table scan and sort of 150,000 rows. R16 performs multiple scans over 150,000 orders to compute customer cohorts and test monthly activity.
   - *Solution Direction:* B-tree indexing on `orders(placed_at DESC)` and composite indexing on `orders(customer_id, placed_at)`.

3. **R17 (58.060 ms) & R15 (17.179 ms):**
   - *Cause:* Non-sargable functions `EXTRACT(YEAR FROM o.placed_at)` and `DATE(o.placed_at)` prevent index range scans and force full scans of 150,000 orders.
   - *Solution Direction:* Rewrite non-sargable expressions into explicit timestamp bounds (`o.placed_at >= ... AND o.placed_at < ...`).

4. **R06 (8.678 ms), R07 (11.286 ms), W02 (22.607 ms), W03 (23.810 ms):**
   - *Cause:* Critical customer-facing and warehouse-screen queries exceed their 5 ms target due to lack of indexes on `orders(customer_id)`, `orders(store_id, status)`, and `orders(status)`.

5. **R13 (35.851 ms — Correctness Failure):**
   - *Cause:* Uses `NOT IN (SELECT substitute_product_id ...)` where the subquery contains `NULL`s, evaluating to `UNKNOWN` and returning 0 rows. Must be rewritten using `NOT EXISTS`.

---

## 4. Baseline Performance Summary

* **Total Baseline Execution Time:** **4,067.578 ms**
* **Read Queries Total (R01–R25):** 3,978.381 ms
* **Write Queries Total (W01–W05):** 89.197 ms
* **Queries Meeting SLA at Baseline:**
  - Real-time queries (< 5 ms): 6 out of 14 met target (R01, R02, R03, R04, R05, R09, W01, W04 met; R06, R07, R21, R23, W02, W03 missed).
  - Interactive queries (< 250 ms): 7 out of 7 met target.
  - Analytics queries (< 5,000 ms): 8 out of 8 met target (though R19 at 3,555 ms was borderline).
  - Batch queries (< 1,000 ms): 1 out of 1 met target.
