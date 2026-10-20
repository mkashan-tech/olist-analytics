CREATE SCHEMA core;

CREATE TABLE core.customers (
  customer_id        TEXT PRIMARY KEY,
  customer_unique_id TEXT NOT NULL,
  zip_code_prefix    TEXT,
  city               TEXT,
  state              CHAR(2)
);
INSERT INTO core.customers
SELECT customer_id, customer_unique_id, customer_zip_code_prefix,
       customer_city, customer_state
FROM raw.customers;

CREATE TABLE core.sellers (
  seller_id       TEXT PRIMARY KEY,
  zip_code_prefix TEXT,
  city            TEXT,
  state           CHAR(2)
);
INSERT INTO core.sellers
SELECT seller_id, seller_zip_code_prefix, seller_city, seller_state
FROM raw.sellers;

CREATE TABLE core.category_translation (
  category_name         TEXT PRIMARY KEY,
  category_name_english TEXT NOT NULL
);
INSERT INTO core.category_translation
SELECT product_category_name, product_category_name_english
FROM raw.category_translation;

CREATE TABLE core.products (
  product_id         TEXT PRIMARY KEY,
  category_name      TEXT,
  name_length        INT,
  description_length INT,
  photos_qty         INT,
  weight_g           INT,
  length_cm          INT,
  height_cm          INT,
  width_cm           INT
);
INSERT INTO core.products
SELECT product_id,
       NULLIF(product_category_name, ''),
       NULLIF(product_name_lenght, '')::INT,
       NULLIF(product_description_lenght, '')::INT,
       NULLIF(product_photos_qty, '')::INT,
       NULLIF(product_weight_g, '')::INT,
       NULLIF(product_length_cm, '')::INT,
       NULLIF(product_height_cm, '')::INT,
       NULLIF(product_width_cm, '')::INT
FROM raw.products;

CREATE TABLE core.orders (
  order_id              TEXT PRIMARY KEY,
  customer_id           TEXT NOT NULL REFERENCES core.customers(customer_id),
  order_status          TEXT,
  purchase_ts           TIMESTAMP,
  approved_ts           TIMESTAMP,
  delivered_carrier_ts  TIMESTAMP,
  delivered_customer_ts TIMESTAMP,
  estimated_delivery_ts TIMESTAMP
);
INSERT INTO core.orders
SELECT order_id, customer_id, order_status,
       NULLIF(order_purchase_timestamp, '')::TIMESTAMP,
       NULLIF(order_approved_at, '')::TIMESTAMP,
       NULLIF(order_delivered_carrier_date, '')::TIMESTAMP,
       NULLIF(order_delivered_customer_date, '')::TIMESTAMP,
       NULLIF(order_estimated_delivery_date, '')::TIMESTAMP
FROM raw.orders;

CREATE TABLE core.order_items (
  order_id          TEXT NOT NULL REFERENCES core.orders(order_id),
  order_item_id     INT  NOT NULL,
  product_id        TEXT NOT NULL REFERENCES core.products(product_id),
  seller_id         TEXT NOT NULL REFERENCES core.sellers(seller_id),
  shipping_limit_ts TIMESTAMP,
  price             NUMERIC(10,2),
  freight_value     NUMERIC(10,2),
  PRIMARY KEY (order_id, order_item_id)
);
INSERT INTO core.order_items
SELECT order_id, order_item_id::INT, product_id, seller_id,
       NULLIF(shipping_limit_date, '')::TIMESTAMP,
       price::NUMERIC, freight_value::NUMERIC
FROM raw.order_items;

CREATE TABLE core.order_payments (
  order_id             TEXT NOT NULL REFERENCES core.orders(order_id),
  payment_sequential   INT  NOT NULL,
  payment_type         TEXT,
  payment_installments INT,
  payment_value        NUMERIC(10,2),
  PRIMARY KEY (order_id, payment_sequential)
);
INSERT INTO core.order_payments
SELECT order_id, payment_sequential::INT, payment_type,
       payment_installments::INT, payment_value::NUMERIC
FROM raw.order_payments;

CREATE TABLE core.order_reviews (
  review_id         TEXT NOT NULL,
  order_id          TEXT NOT NULL REFERENCES core.orders(order_id),
  review_score      SMALLINT,
  comment_title     TEXT,
  comment_message   TEXT,
  review_created_ts TIMESTAMP,
  review_answer_ts  TIMESTAMP
);
INSERT INTO core.order_reviews
SELECT review_id, order_id, review_score::SMALLINT,
       NULLIF(review_comment_title, ''),
       NULLIF(review_comment_message, ''),
       NULLIF(review_creation_date, '')::TIMESTAMP,
       NULLIF(review_answer_timestamp, '')::TIMESTAMP
FROM raw.order_reviews;