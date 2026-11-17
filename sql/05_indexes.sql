-- =====================================================================
-- Blinkit 10-Minute Grocery Delivery Database
-- CP3 Deliverable: Production Workload Indexes
-- Database: PostgreSQL 15+
-- Schema: blinkit
-- =====================================================================

SET search_path TO blinkit, public;

-- Required for trigram substring indexing on product searches
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- 1. Orders: customer lookup and cohort timeline tracking
-- Serves R06 (latest order tracking), R16 (customer monthly cohorts), and R25 (customer loyalty spend).
-- Equality on customer_id followed by descending sort on placed_at enables index-only/backward index scan for latest order.
CREATE INDEX IF NOT EXISTS idx_orders_customer_placed
    ON orders (customer_id, placed_at DESC);

-- 2. Orders: date-range filtering and temporal reporting
-- Serves R08 (SLA late deliveries), R14 (short delivered lines), R15 (hourly staffing), R17 (small-cart fees), R20 (daily GMV), and R22 (pagination).
-- Leading placed_at column allows index range scans across time windows and backward scanning for newest-first order paging.
CREATE INDEX IF NOT EXISTS idx_orders_placed_at
    ON orders (placed_at DESC);

-- 3. Orders: store active queues and rider performance
-- Serves R07 (store open orders screen), R11 (store rider transit speed), and R18 (dead stock checks).
-- Equality on store_id followed by status and placed_at satisfies store-scoped filtering and chronological sorting.
CREATE INDEX IF NOT EXISTS idx_orders_store_status_placed
    ON orders (store_id, status, placed_at);

-- 4. Orders: rider dispatch tracking
-- Serves R21 (store manager idle rider audit).
-- Enables fast index verification in NOT EXISTS correlated subquery for rider dispatch activity.
CREATE INDEX IF NOT EXISTS idx_orders_rider_placed
    ON orders (rider_id, placed_at);

-- 5. Orders: packing queue partial index
-- Serves W03 (automated dispatch of oldest packing order).
-- Partial index covering only orders in PACKING state (<0.05% of table) makes min(order_id) sub-millisecond with minimal write overhead.
CREATE INDEX IF NOT EXISTS idx_orders_packing_status
    ON orders (order_id)
    WHERE status = 'PACKING';

-- 6. Orders: active store orders partial index
-- Serves W02 (stock deduction upon packing completion).
-- Partial index on active order statuses enables instant max(order_id) resolution for a specific store.
CREATE INDEX IF NOT EXISTS idx_orders_store_active_placed
    ON orders (store_id, order_id DESC)
    WHERE status IN ('PLACED', 'PACKING');

-- 7. Riders: active fleet status partial index
-- Serves W03 (dispatch to store's first active rider).
-- Partial index on active riders enables instant min(rider_id) resolution per store.
CREATE INDEX IF NOT EXISTS idx_riders_store_active
    ON riders (store_id, rider_id)
    WHERE status = 'ACTIVE';

-- 8. Order Items: reverse composite lookup
-- Serves R12 (cross-sell recommendations), R18 (dead stock sold checks), and R19 (category sales aggregation).
-- Inverts the primary key (order_id, product_id) to allow index access when filtering or joining on product_id.
CREATE INDEX IF NOT EXISTS idx_order_items_product_order
    ON order_items (product_id, order_id);

-- 9. Order Items: substitute tracking partial index
-- Serves R13 (products never used as substitutes).
-- Partial index indexing only the 2.2% non-null substitute rows makes NOT EXISTS substitute verification instant.
CREATE INDEX IF NOT EXISTS idx_order_items_substitute_product
    ON order_items (substitute_product_id, order_id)
    WHERE substitute_product_id IS NOT NULL;

-- 10. Store Inventory: catalog product distribution
-- Serves R04 (stock of specific product across city dark stores).
-- Inverts the primary key (store_id, product_id) so queries filtering by product_id can skip scanning unrelated store rows.
CREATE INDEX IF NOT EXISTS idx_store_inventory_product_store
    ON store_inventory (product_id, store_id);

-- 11. Inventory Movements: store-level restock ledger
-- Serves R24 (store restock units aggregation).
-- Equality on store_id and movement_type followed by moved_at range enables targeted index range scans.
CREATE INDEX IF NOT EXISTS idx_inventory_movements_store_type_date
    ON inventory_movements (store_id, movement_type, moved_at);

-- 12. Inventory Movements: wastage and shrinkage audit
-- Serves R10 (units lost to damage and expiry per category).
-- Equality on movement_type followed by moved_at range speeds up wastage aggregation.
CREATE INDEX IF NOT EXISTS idx_inventory_movements_type_date
    ON inventory_movements (movement_type, moved_at);

-- 13. Inventory Movements: retention policy purge
-- Serves W05 (data retention deletion of older records).
-- Range indexing on moved_at allows fast index scans to locate delete targets.
CREATE INDEX IF NOT EXISTS idx_inventory_movements_moved_at
    ON inventory_movements (moved_at);

-- 14. Customers: city-level segmentation
-- Serves R25 (Mumbai loyalty customer spend analysis).
-- Equality filtering on customer city_id enables direct index scan.
CREATE INDEX IF NOT EXISTS idx_customers_city_id
    ON customers (city_id);

-- 15. Products: category taxonomy classification
-- Serves R02 (category browsing) and R19 (category sales reporting).
-- Equality index on category_id accelerates filtering catalog items by product category.
CREATE INDEX IF NOT EXISTS idx_products_category_id
    ON products (category_id);

-- 16. Products: trigram text search
-- Serves R03 (fuzzy/substring catalog search for product names).
-- GIN trigram index allows index scans on ILIKE '%term%' pattern matching without full table scans.
CREATE INDEX IF NOT EXISTS idx_products_name_trgm
    ON products USING gin (product_name gin_trgm_ops);
