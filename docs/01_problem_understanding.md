# Blinkit 10-Minute Grocery Delivery Database: Problem Understanding

**Project:** CP1 — Schema & Normalization  
**Domain:** Quick-Commerce / Dark-Store Logistics (Blinkit)  
**Database System:** PostgreSQL 15+ (`blinkit` schema)

---

## 1. Problem Statements & Stakeholder Analysis

Blinkit operates a hyper-local, 10-minute grocery delivery model anchored by a network of distributed micro-warehouses ("dark stores"). To fulfill customer orders within 10 minutes, the software and database architecture must support ultra-low latency lookups (store mapping, live inventory, checkout) while concurrently supporting high-throughput warehouse picking, rider dispatch, and complex cross-store analytical reporting.

The legacy database lacks a documented schema, clear integrity constraints, and query-tuned structures, resulting in seven distinct operational bottlenecks:

| Problem ID | Problem Description & Core Business Need | Affected Stakeholders | Workload Queries | Operational Category & Target SLA |
| :--- | :--- | :--- | :--- | :--- |
| **P1** | **Store Assignment & Catalog Browsing Latency:** Customers open the mobile application and expect instantaneous discovery of the nearest servicing dark store (within ~3 km) and live stock availability. If geolocation lookups or category/search pages lag, the 10-minute customer promise is broken before checkout. | Customer, Dark-Store Manager | R01, R02, R03, R04, R05 | **Customer-Facing / Real-Time OLTP**<br>*(Target: < 5 ms)* |
| **P2** | **Peak-Hour Checkout & Order Tracking Bottlenecks:** High concurrency during peak grocery rush hours causes contention during cart stock verification, transactional order placement, and customer timeline polling, risking cart abandonment and duplicate orders. | Customer, Customer Support | R06, W01 | **Customer-Facing / Real-Time OLTP**<br>*(Target: < 5 ms)* |
| **P3** | **Store Screen Refresh & Fulfillment Lag:** Dark-store operations depend on active queue visibility to pack items within 2–3 minutes. Delays in listing open orders (`PLACED`, `PACKING`), deducting inventory upon packing, and assigning idle riders directly inflate delivery turnaround times. | Dark-Store Manager, Pickers/Packers, Delivery Riders | R07, R21, W02, W03 | **Store Operations / Real-Time OLTP**<br>*(Target: < 5 ms)* |
| **P4** | **Hourly Replenishment & Stock Optimization Stalls:** Dark-store inventory managers and central supply chain teams need frequent automated alerts for items at or below reorder thresholds, automated restock execution, and dead-stock identification to prevent stock-outs of high-velocity goods. | Supply Chain Team, Dark-Store Inventory Leads | R09, R18, R24, W04 | **Interactive Ops & Batch OLTP**<br>*(R09, W04: < 5 ms; R18, R24: < 250 ms)* |
| **P5** | **Empty Substitutes Report (NULL Handling Bug):** When items are out of stock during packing, pickers assign substitute items. The category team's report to audit unused substitutes returns empty results because the legacy SQL query uses `NOT IN (SELECT substitute_product_id ...)` where the subquery contains `NULL`s, evaluating the condition to `UNKNOWN`. | Category Team, Merchandising Specialists | R13 | **Interactive Operations Tool / SQL Fix**<br>*(Target: < 250 ms)* |
| **P6** | **Operations SLA, Wastage, & Rider Metric Timeouts:** Regional operational leadership requires automated analytical summaries of SLA breaches (>10 min), product shrinkage (spoilage, damage, expiry), order-line fill rates, and rider delivery transit speed across hundreds of thousands of historical records. | Operations Leadership, Fleet Managers, Store Supervisors | R08, R10, R11, R14, R15 | **Reporting / Analytics & Interactive Ops**<br>*(R08, R10, R14: < 5,000 ms; R11, R15: < 250 ms)* |
| **P7** | **Growth, Finance, & 20× Scale Bottlenecks:** Long-range financial audits (daily GMV, running revenue, small-cart fee collection by city), customer cohort retention analysis, customer loyalty rankings, support order consoles, and cross-sell recommendation engines run slowly today and will collapse under projected 20× volume growth. | Finance Team, Growth & Marketing, Customer Support, Data Engineering | R12, R16, R17, R19, R20, R22, R23, R25, W05 | **Reporting / Analytics, Heavy Batch, & Admin Console**<br>*(R16, R17, R19, R20, R25: < 5,000 ms; R12, R22: < 250 ms; R23: < 5 ms; W05: < 1,000 ms)* |

---

## 2. Workload Classification Summary

The workload divides cleanly into two operational archetypes with distinct database performance profiles:

1. **Customer-Facing & Real-Time Operational OLTP (P1, P2, P3, Part of P4):**
   - *Queries:* R01–R07, R09, R21, R23, W01, W02, W03, W04.
   - *Characteristics:* High concurrency, point lookups, short transaction durations, single-store scoping.
   - *Performance Target:* **Under 5 ms** (average across 3 benchmark runs).

2. **Interactive Operations, Reporting & Analytical OLAP (P5, P6, P7, Part of P4):**
   - *Interactive Tools:* R11, R12, R13, R15, R18, R22, R24 *(Target: under 250 ms)*.
   - *Heavy Analytical Aggregations:* R08, R10, R14, R16, R17, R19, R20, R25 *(Target: under 5,000 ms)*.
   - *Data Retention / Purge Batch Jobs:* W05 *(Target: under 1,000 ms)*.
   - *Characteristics:* Multi-table joins across large fact tables (`orders`, `order_items`, `inventory_movements`), date-range filters, group-by aggregations, and window functions.

---

## 3. Core Business & Architecture Assumptions

1. **Hyper-Local Fulfillment Radius:** Each dark store serves customers within an approximate 3 km radius (~0.027° latitude and ~0.028° longitude bounding box). Every customer order is fulfilled entirely by a single dark store; multi-store basket splitting is not supported.
2. **Catalog vs. Inventory Separation:** The product catalog (`products`) and categories (`categories`) are centrally defined, but availability (`quantity_on_hand`), reorder thresholds (`reorder_level`), and pricing (`selling_price`) are strictly managed at the local store level (`store_inventory`).
3. **Dedicated Dark-Store Riders:** Each delivery partner (`riders`) is dedicated to a single dark store (`riders.store_id = dark_stores.store_id`). Cross-store dispatching does not occur.
4. **Order Lifecycle Pipeline:** Orders progress monotonically through operational stages:  
   $$\text{PLACED} \longrightarrow \text{PACKING} \longrightarrow \text{OUT\_FOR\_DELIVERY} \longrightarrow \text{DELIVERED} \quad (\text{or } \text{CANCELLED})$$  
   Timestamps adhere to chronological sequence: $\text{placed\_at} \le \text{packed\_at} \le \text{picked\_up\_at} \le \text{delivered\_at}$.
5. **Fee and Billing Structure:**  
   $$\text{total\_amount} = \text{subtotal} + \text{delivery\_fee} + \text{handling\_fee} + \text{small\_cart\_fee}$$  
   Where $\text{subtotal} = \sum (\text{quantity\_delivered} \times \text{unit\_price})$. Customers are only billed for delivered units. Orders under ₹199 incur a ₹25 delivery fee, and orders under ₹500 incur a ₹6 handling fee (reduced to ₹2 for larger carts).
6. **Stock Management Consistency:** Store inventory `quantity_on_hand` represents the current physical stock on shelves. It is directly decremented when packing completes (W02) and incremented upon restocking (W04). Historical changes are audited via `inventory_movements`.
