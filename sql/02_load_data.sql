-- =====================================================================
-- Blinkit 10-Minute Grocery Delivery Database
-- CP1 Deliverable: Data Ingestion Script
-- Loads all 10 seed CSV files in topological foreign key dependency order
-- Run from project root: psql -d <database_name> -f sql/02_load_data.sql
-- =====================================================================

SET search_path TO blinkit;

\echo '----------------------------------------------------------------------'
\echo 'Loading Seed Data into schema blinkit...'
\echo '----------------------------------------------------------------------'

-- 1. Cities (no foreign keys)
\echo 'Loading cities...'
\copy cities FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true);

-- 2. Dark Stores (references cities)
\echo 'Loading dark_stores...'
\copy dark_stores FROM 'seed_data/dark_stores.csv' WITH (FORMAT csv, HEADER true);

-- 3. Categories (no foreign keys)
\echo 'Loading categories...'
\copy categories FROM 'seed_data/categories.csv' WITH (FORMAT csv, HEADER true);

-- 4. Products (references categories)
\echo 'Loading products...'
\copy products FROM 'seed_data/products.csv' WITH (FORMAT csv, HEADER true);

-- 5. Store Inventory (references dark_stores and products)
\echo 'Loading store_inventory...'
\copy store_inventory FROM 'seed_data/store_inventory.csv' WITH (FORMAT csv, HEADER true);

-- 6. Customers (references cities)
\echo 'Loading customers...'
\copy customers FROM 'seed_data/customers.csv' WITH (FORMAT csv, HEADER true);

-- 7. Riders (references dark_stores)
\echo 'Loading riders...'
\copy riders FROM 'seed_data/riders.csv' WITH (FORMAT csv, HEADER true);

-- 8. Orders (references customers, dark_stores, riders)
\echo 'Loading orders...'
\copy orders FROM 'seed_data/orders.csv' WITH (FORMAT csv, HEADER true);

-- 9. Order Items (references orders, products)
\echo 'Loading order_items...'
\copy order_items FROM 'seed_data/order_items.csv' WITH (FORMAT csv, HEADER true);

-- 10. Inventory Movements (references dark_stores, products, store_inventory)
\echo 'Loading inventory_movements...'
\copy inventory_movements FROM 'seed_data/inventory_movements.csv' WITH (FORMAT csv, HEADER true);

\echo '----------------------------------------------------------------------'
\echo 'Updating planner statistics with ANALYZE...'
\echo '----------------------------------------------------------------------'
ANALYZE;

\echo '----------------------------------------------------------------------'
\echo 'Verifying Row Counts (Actual vs Expected)...'
\echo '----------------------------------------------------------------------'

SELECT 'cities' AS table_name, count(*) AS actual_rows, 10 AS expected_rows FROM cities
UNION ALL
SELECT 'dark_stores', count(*), 120 FROM dark_stores
UNION ALL
SELECT 'categories', count(*), 12 FROM categories
UNION ALL
SELECT 'products', count(*), 1500 FROM products
UNION ALL
SELECT 'store_inventory', count(*), 126000 FROM store_inventory
UNION ALL
SELECT 'customers', count(*), 40000 FROM customers
UNION ALL
SELECT 'riders', count(*), 1800 FROM riders
UNION ALL
SELECT 'orders', count(*), 150000 FROM orders
UNION ALL
SELECT 'order_items', count(*), 675000 FROM order_items
UNION ALL
SELECT 'inventory_movements', count(*), 90000 FROM inventory_movements;

\echo '----------------------------------------------------------------------'
\echo 'Running Business Integrity Verifications...'
\echo '----------------------------------------------------------------------'

-- Integrity Check 1: Every ordered product must be stocked by the order's dark store
SELECT 'Check 1: Ordered items stocked by store' AS check_name,
       count(*) AS violation_count,
       'Every ordered product must exist in store_inventory for that store' AS description
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
LEFT JOIN store_inventory si ON si.store_id = o.store_id AND si.product_id = oi.product_id
WHERE si.product_id IS NULL;

-- Integrity Check 2: Riders must only be assigned to orders from their own dark store
SELECT 'Check 2: Rider store consistency' AS check_name,
       count(*) AS violation_count,
       'Assigned rider store_id must match order store_id' AS description
FROM orders o
JOIN riders r ON r.rider_id = o.rider_id
WHERE o.store_id <> r.store_id;

-- Integrity Check 3: Every substitute product must be stocked by the order's dark store
SELECT 'Check 3: Substitute product stocked by store' AS check_name,
       count(*) AS violation_count,
       'Substitute product must exist in store_inventory for that store' AS description
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
LEFT JOIN store_inventory si ON si.store_id = o.store_id AND si.product_id = oi.substitute_product_id
WHERE oi.substitute_product_id IS NOT NULL AND si.product_id IS NULL;

-- Integrity Check 4: Orders subtotal exact match with sum of delivered items
SELECT 'Check 4: Subtotal matches delivered items' AS check_name,
       count(*) AS violation_count,
       'orders.subtotal must equal sum(quantity_delivered * unit_price)' AS description
FROM (
    SELECT o.order_id, o.subtotal, round(coalesce(sum(oi.quantity_delivered * oi.unit_price), 0), 2) AS calculated_subtotal
    FROM orders o
    LEFT JOIN order_items oi ON oi.order_id = o.order_id
    GROUP BY o.order_id, o.subtotal
    HAVING abs(o.subtotal - round(coalesce(sum(oi.quantity_delivered * oi.unit_price), 0), 2)) > 0.01
) violations;

-- Integrity Check 5: Customer city matches dark store city for all orders
SELECT 'Check 5: Customer and store city match' AS check_name,
       count(*) AS violation_count,
       'orders customer city_id must match dark store city_id' AS description
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN dark_stores s ON s.store_id = o.store_id
WHERE c.city_id <> s.city_id;

\echo '----------------------------------------------------------------------'
\echo 'CP1 Data Loading and Verification Complete.'
\echo '----------------------------------------------------------------------'
