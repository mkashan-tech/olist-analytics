-- =====================================================================
-- 03_cleaning_indexes_views.sql
-- Olist analytics: cleaning, indexes, views and first analysis
-- Run order: after 02_create_core_tables.sql
-- NOTE: This file is for running one time if we run it again on same Database then it will give
-- "already exists" errors (ALTER ADD COLUMN, CREATE TABLE/VIEW).
-- =====================================================================

-- ---------- A. Data quality checks ----------

-- review_id alone is not unique (814 repeats); real key (review_id, order_id)
SELECT COUNT(*)                              AS total_rows,
       COUNT(DISTINCT review_id)             AS distinct_review_ids,
       COUNT(DISTINCT (review_id, order_id)) AS distinct_pairs
FROM core.order_reviews;

ALTER TABLE core.order_reviews ADD PRIMARY KEY (review_id, order_id);

-- order status vs missing delivery date
-- finding: 8 delivered orders ki delivery date missing
SELECT order_status,
       COUNT(*) AS orders,
       COUNT(*) FILTER (WHERE delivered_customer_ts IS NULL) AS no_delivery_date
FROM core.orders
GROUP BY 1 ORDER BY 2 DESC;

-- ---------- B. Cleaning (ALTER + UPDATE) ----------

-- English category name
ALTER TABLE core.products ADD COLUMN category_english TEXT;

UPDATE core.products p
SET category_english = t.category_name_english
FROM core.category_translation t
WHERE p.category_name = t.category_name;

-- jo translation me nahi mile unke liye original naam ya 'unknown'
UPDATE core.products
SET category_english = COALESCE(category_name, 'unknown')
WHERE category_english IS NULL;

-- Geolocation: ek zip prefix = ek row (raw me ~10 lakh duplicate points the)
CREATE TABLE core.geolocation_zip AS
SELECT geolocation_zip_code_prefix                         AS zip_code_prefix,
       AVG(geolocation_lat::NUMERIC)::NUMERIC(9,6)         AS lat,
       AVG(geolocation_lng::NUMERIC)::NUMERIC(9,6)         AS lng,
       MODE() WITHIN GROUP (ORDER BY geolocation_city)     AS city,
       MODE() WITHIN GROUP (ORDER BY geolocation_state)    AS state
FROM raw.geolocation
GROUP BY 1;

ALTER TABLE core.geolocation_zip ADD PRIMARY KEY (zip_code_prefix);

-- ---------- C. Indexes (foreign key columns pe Postgres khud index nahi banata) ----------

CREATE INDEX idx_orders_customer    ON core.orders(customer_id);
CREATE INDEX idx_orders_purchase_ts ON core.orders(purchase_ts);
CREATE INDEX idx_items_product      ON core.order_items(product_id);
CREATE INDEX idx_items_seller       ON core.order_items(seller_id);
CREATE INDEX idx_reviews_order      ON core.order_reviews(order_id);

-- ---------- D. Views (Power BI will connect from these) ----------

-- Ek row per order. items aur reviews pehle aggregate kiye gaye hain
-- taaki join se rows multiply na ho (fan-out se bachne ke liye).
CREATE VIEW core.v_order_summary AS
WITH items AS (
  SELECT order_id,
         COUNT(*)           AS item_count,
         SUM(price)         AS items_revenue,
         SUM(freight_value) AS freight
  FROM core.order_items
  GROUP BY order_id
),
rev AS (
  SELECT order_id, AVG(review_score)::NUMERIC(3,2) AS review_score
  FROM core.order_reviews
  GROUP BY order_id
)
SELECT o.order_id,
       o.order_status,
       o.purchase_ts,
       DATE_TRUNC('month', o.purchase_ts)::DATE AS purchase_month,
       c.customer_unique_id,
       c.state                                  AS customer_state,
       COALESCE(i.item_count, 0)                AS item_count,
       i.items_revenue,
       i.freight,
       r.review_score,
       (o.delivered_customer_ts::DATE - o.estimated_delivery_ts::DATE) AS days_vs_estimate,
       CASE WHEN o.delivered_customer_ts > o.estimated_delivery_ts THEN TRUE
            WHEN o.delivered_customer_ts IS NOT NULL THEN FALSE END    AS is_late
FROM core.orders o
JOIN core.customers c ON c.customer_id = o.customer_id
LEFT JOIN items i ON i.order_id = o.order_id
LEFT JOIN rev   r ON r.order_id = o.order_id;

-- Monthly revenue (only for delivered orders)
CREATE VIEW core.v_monthly_revenue AS
SELECT purchase_month,
       COUNT(*)                    AS orders,
       SUM(items_revenue)          AS revenue,
       ROUND(AVG(review_score), 2) AS avg_review
FROM core.v_order_summary
WHERE order_status = 'delivered'
GROUP BY purchase_month;

-- Ek row per order item: category aur seller analysis ke liye
CREATE VIEW core.v_item_detail AS
SELECT oi.order_id, oi.order_item_id, oi.price, oi.freight_value,
       p.product_id, p.category_english,
       s.seller_id, s.state AS seller_state,
       o.order_status, o.purchase_ts,
       DATE_TRUNC('month', o.purchase_ts)::DATE AS purchase_month
FROM core.order_items oi
JOIN core.orders   o ON o.order_id   = oi.order_id
JOIN core.products p ON p.product_id = oi.product_id
JOIN core.sellers  s ON s.seller_id  = oi.seller_id;

-- ---------- E. Verification ----------

SELECT COUNT(*) FROM core.geolocation_zip;                              -- 19,015
SELECT COUNT(*) FROM core.products WHERE category_english IS NULL;      -- 0
SELECT COUNT(*) FROM core.v_order_summary;                              -- 99,441
SELECT COUNT(*) FROM core.v_item_detail;                                -- 112,650

-- ---------- F. Analysis ----------

-- Month-over-month revenue growth (window function)
-- Note: 2016 ke months me orders bahut kam hain aur Nov 2016 missing hai,
-- isliye growth % 2017-01 se pehle misleading hai.
SELECT purchase_month,
       revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY purchase_month))
             / NULLIF(LAG(revenue) OVER (ORDER BY purchase_month), 0), 1) AS mom_growth_pct
FROM core.v_monthly_revenue
ORDER BY purchase_month;

-- Late delivery vs review score
-- finding: on-time 88,649 orders avg 4.29; late 7,827 orders avg 2.57.
-- I'm not saying late delivery is the only reason, as there could
-- be other factors too, like different sellers or locations.
-- So if I summarise, ye correlation hai. Late orders ke sellers ya
-- products alag ho sakte hain, so it's safer to say that orders with
-- late deliveries have lower average review scores.
SELECT is_late, COUNT(*) AS orders, ROUND(AVG(review_score), 2) AS avg_review
FROM core.v_order_summary
WHERE is_late IS NOT NULL
GROUP BY is_late;