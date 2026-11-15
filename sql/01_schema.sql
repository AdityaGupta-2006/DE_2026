-- =====================================================================
-- Blinkit 10-Minute Grocery Delivery Database
-- CP1 Deliverable: Schema Definition (DDL)
-- PostgreSQL 15+ compatible
-- Schema: blinkit
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS blinkit;
SET search_path TO blinkit;

-- Drop existing tables in reverse dependency order if re-executing
DROP TABLE IF EXISTS inventory_movements CASCADE;
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS riders CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS store_inventory CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS dark_stores CASCADE;
DROP TABLE IF EXISTS cities CASCADE;

-- ---------------------------------------------------------------------
-- 1. cities
-- Geographical cities where Blinkit operates dark stores and serves customers.
-- ---------------------------------------------------------------------
CREATE TABLE cities (
    city_id         INT PRIMARY KEY,
    city_name       VARCHAR(50) NOT NULL UNIQUE,
    state           VARCHAR(50) NOT NULL
);

-- ---------------------------------------------------------------------
-- 2. dark_stores
-- Micro-warehouses fulfilling 10-minute grocery delivery within ~3 km radius.
-- ---------------------------------------------------------------------
CREATE TABLE dark_stores (
    store_id            INT PRIMARY KEY,
    store_code          VARCHAR(20) NOT NULL UNIQUE,
    city_id             INT NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    latitude            NUMERIC(9,6) NOT NULL,
    longitude           NUMERIC(9,6) NOT NULL,
    opened_on           DATE NOT NULL,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    max_daily_orders    INT NOT NULL,
    CONSTRAINT chk_dark_stores_code CHECK (store_code ~ '^[A-Z]{3}-[A-Z]{3}-[0-9]{2}$'),
    CONSTRAINT chk_dark_stores_lat CHECK (latitude BETWEEN -90.0 AND 90.0),
    CONSTRAINT chk_dark_stores_lon CHECK (longitude BETWEEN -180.0 AND 180.0),
    CONSTRAINT chk_dark_stores_max_orders CHECK (max_daily_orders > 0)
);

-- ---------------------------------------------------------------------
-- 3. categories
-- Product taxonomy classifications (e.g., Dairy, Produce, Household).
-- ---------------------------------------------------------------------
CREATE TABLE categories (
    category_id     INT PRIMARY KEY,
    category_name   VARCHAR(50) NOT NULL UNIQUE,
    is_perishable   BOOLEAN NOT NULL
);

-- ---------------------------------------------------------------------
-- 4. products
-- Master product catalog with SKU, brand, MRP, and shelf life.
-- ---------------------------------------------------------------------
CREATE TABLE products (
    product_id          INT PRIMARY KEY,
    sku                 VARCHAR(20) NOT NULL UNIQUE,
    product_name        VARCHAR(150) NOT NULL,
    brand               VARCHAR(100) NOT NULL,
    category_id         INT NOT NULL REFERENCES categories(category_id) ON DELETE RESTRICT,
    pack_size           VARCHAR(50) NOT NULL,
    mrp                 NUMERIC(10,2) NOT NULL,
    shelf_life_days     INT,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT chk_products_sku CHECK (sku ~ '^BK[0-9]{8}$'),
    CONSTRAINT chk_products_mrp CHECK (mrp > 0),
    CONSTRAINT chk_products_shelf_life CHECK (shelf_life_days IS NULL OR shelf_life_days > 0)
);

-- ---------------------------------------------------------------------
-- 5. store_inventory
-- Store-specific product availability, real-time stock, and selling prices.
-- Composite primary key: (store_id, product_id).
-- ---------------------------------------------------------------------
CREATE TABLE store_inventory (
    store_id            INT NOT NULL REFERENCES dark_stores(store_id) ON DELETE RESTRICT,
    product_id          INT NOT NULL REFERENCES products(product_id) ON DELETE RESTRICT,
    quantity_on_hand    INT NOT NULL DEFAULT 0,
    reorder_level       INT NOT NULL DEFAULT 0,
    selling_price       NUMERIC(10,2) NOT NULL,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (store_id, product_id),
    CONSTRAINT chk_store_inv_qty CHECK (quantity_on_hand >= 0),
    CONSTRAINT chk_store_inv_reorder CHECK (reorder_level >= 0),
    CONSTRAINT chk_store_inv_price CHECK (selling_price > 0)
);

-- ---------------------------------------------------------------------
-- 6. customers
-- Registered Blinkit consumers placing orders.
-- ---------------------------------------------------------------------
CREATE TABLE customers (
    customer_id     INT PRIMARY KEY,
    full_name       VARCHAR(100) NOT NULL,
    phone           VARCHAR(15) NOT NULL UNIQUE,
    email           VARCHAR(150) UNIQUE,
    city_id         INT NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_customers_phone CHECK (phone ~ '^[0-9]{10}$'),
    CONSTRAINT chk_customers_email CHECK (email IS NULL OR email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- ---------------------------------------------------------------------
-- 7. riders
-- Delivery partners assigned to specific dark stores.
-- ---------------------------------------------------------------------
CREATE TABLE riders (
    rider_id        INT PRIMARY KEY,
    full_name       VARCHAR(100) NOT NULL,
    phone           VARCHAR(15) NOT NULL UNIQUE,
    store_id        INT NOT NULL REFERENCES dark_stores(store_id) ON DELETE RESTRICT,
    joined_on       DATE NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    CONSTRAINT chk_riders_phone CHECK (phone ~ '^[0-9]{10}$'),
    CONSTRAINT chk_riders_status CHECK (status IN ('ACTIVE', 'ON_LEAVE', 'EXITED'))
);

-- ---------------------------------------------------------------------
-- 8. orders
-- Customer order headers with operational timeline, financial breakdown, and status.
-- ---------------------------------------------------------------------
CREATE TABLE orders (
    order_id            INT PRIMARY KEY,
    customer_id         INT NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    store_id            INT NOT NULL REFERENCES dark_stores(store_id) ON DELETE RESTRICT,
    rider_id            INT REFERENCES riders(rider_id) ON DELETE SET NULL,
    placed_at           TIMESTAMPTZ NOT NULL,
    packed_at           TIMESTAMPTZ,
    picked_up_at        TIMESTAMPTZ,
    delivered_at        TIMESTAMPTZ,
    promised_minutes    INT NOT NULL DEFAULT 10,
    subtotal            NUMERIC(10,2) NOT NULL,
    delivery_fee        NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    handling_fee        NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    small_cart_fee      NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    total_amount        NUMERIC(10,2) NOT NULL,
    payment_method      VARCHAR(20) NOT NULL,
    status              VARCHAR(25) NOT NULL DEFAULT 'PLACED',
    CONSTRAINT chk_orders_promised_minutes CHECK (promised_minutes > 0),
    CONSTRAINT chk_orders_amounts_non_neg CHECK (
        subtotal >= 0 AND delivery_fee >= 0 AND handling_fee >= 0 AND small_cart_fee >= 0 AND total_amount >= 0
    ),
    CONSTRAINT chk_orders_total_calc CHECK (
        total_amount = subtotal + delivery_fee + handling_fee + small_cart_fee
    ),
    CONSTRAINT chk_orders_payment_method CHECK (
        payment_method IN ('UPI', 'COD', 'WALLET', 'CARD')
    ),
    CONSTRAINT chk_orders_status CHECK (
        status IN ('PLACED', 'PACKING', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED')
    ),
    CONSTRAINT chk_orders_timeline_packed CHECK (
        packed_at IS NULL OR packed_at >= placed_at
    ),
    CONSTRAINT chk_orders_timeline_picked CHECK (
        picked_up_at IS NULL OR packed_at IS NULL OR picked_up_at >= packed_at
    ),
    CONSTRAINT chk_orders_timeline_delivered CHECK (
        delivered_at IS NULL OR picked_up_at IS NULL OR delivered_at >= picked_up_at
    )
);

-- ---------------------------------------------------------------------
-- 9. order_items
-- Individual line items per order, tracking ordered/delivered counts and substitutions.
-- Composite primary key: (order_id, product_id).
-- ---------------------------------------------------------------------
CREATE TABLE order_items (
    order_id                INT NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id              INT NOT NULL REFERENCES products(product_id) ON DELETE RESTRICT,
    quantity_ordered        INT NOT NULL,
    quantity_delivered      INT NOT NULL,
    unit_price              NUMERIC(10,2) NOT NULL,
    substitute_product_id   INT REFERENCES products(product_id) ON DELETE SET NULL,
    PRIMARY KEY (order_id, product_id),
    CONSTRAINT chk_order_items_qty_ordered CHECK (quantity_ordered > 0),
    CONSTRAINT chk_order_items_qty_delivered CHECK (
        quantity_delivered >= 0 AND quantity_delivered <= quantity_ordered
    ),
    CONSTRAINT chk_order_items_unit_price CHECK (unit_price >= 0)
);

-- ---------------------------------------------------------------------
-- 10. inventory_movements
-- Audit log of dark store inventory events: restocks, damages, expiries, adjustments.
-- Linked directly to store_inventory composite key (store_id, product_id).
-- ---------------------------------------------------------------------
CREATE TABLE inventory_movements (
    movement_id     INT PRIMARY KEY,
    store_id        INT NOT NULL REFERENCES dark_stores(store_id) ON DELETE RESTRICT,
    product_id      INT NOT NULL REFERENCES products(product_id) ON DELETE RESTRICT,
    movement_type   VARCHAR(20) NOT NULL,
    quantity        INT NOT NULL,
    moved_at        TIMESTAMPTZ NOT NULL,
    CONSTRAINT fk_inv_movements_store_inv FOREIGN KEY (store_id, product_id)
        REFERENCES store_inventory(store_id, product_id) ON DELETE RESTRICT,
    CONSTRAINT chk_movements_type CHECK (
        movement_type IN ('RESTOCK', 'ADJUSTMENT', 'DAMAGE', 'EXPIRY')
    ),
    CONSTRAINT chk_movements_qty_non_zero CHECK (quantity <> 0),
    CONSTRAINT chk_movements_type_qty_sign CHECK (
        (movement_type = 'RESTOCK' AND quantity > 0) OR
        (movement_type IN ('EXPIRY', 'DAMAGE') AND quantity < 0) OR
        (movement_type = 'ADJUSTMENT' AND quantity <> 0)
    )
);
