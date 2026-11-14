/*
Purpose : Gold layer: star schema (dimensions and facts) for analysis.
Task    : E4-09 (DDL). Design in docs/design_decisions.md and docs/scd2_customer_design.md
Layer   : gold (ecommerce_rfm_dwh)
Re-run  : safe. Each table is created only if missing.
Order   : dimensions first, then facts. dim_date is created by dim_date.sql.
Reading : each column has a comment on its line, so you do not need to scroll.
*/
USE ecommerce_rfm_dwh;
GO

/* ---------------------------------------------------------------
   1. dim_brand. Unknown brand = -1.
   --------------------------------------------------------------- */
IF OBJECT_ID(N'gold.dim_brand', N'U') IS NULL
CREATE TABLE gold.dim_brand
(
    brand_key        int          NOT NULL IDENTITY(1,1) CONSTRAINT pk_dim_brand PRIMARY KEY,
    brand_id         int          NOT NULL CONSTRAINT uq_dim_brand_id UNIQUE,  -- from silver.rees46_brand
    brand_name       varchar(100) NOT NULL,
    dwh_create_date  datetime2(0) NOT NULL CONSTRAINT df_dim_brand_create DEFAULT (SYSUTCDATETIME())
);
GO

/* ---------------------------------------------------------------
   2. dim_category. One row per category. is_unclassified = 1 when no code exists.
   --------------------------------------------------------------- */
IF OBJECT_ID(N'gold.dim_category', N'U') IS NULL
CREATE TABLE gold.dim_category
(
    category_key     int          NOT NULL IDENTITY(1,1) CONSTRAINT pk_dim_category PRIMARY KEY,
    category_id      bigint       NOT NULL CONSTRAINT uq_dim_category_id UNIQUE,  -- source id
    category_code    varchar(200) NULL,                                           -- full path, optional
    level_1          varchar(100) NULL,                                           -- first part of the path
    level_2          varchar(100) NULL,
    level_3          varchar(100) NULL,
    level_4          varchar(100) NULL,
    is_unclassified  bit          NOT NULL,
    dwh_create_date  datetime2(0) NOT NULL CONSTRAINT df_dim_category_create DEFAULT (SYSUTCDATETIME())
);
GO

/* ---------------------------------------------------------------
   3. dim_product. One row per product. Links to category and brand.
   --------------------------------------------------------------- */
IF OBJECT_ID(N'gold.dim_product', N'U') IS NULL
CREATE TABLE gold.dim_product
(
    product_key      int          NOT NULL IDENTITY(1,1) CONSTRAINT pk_dim_product PRIMARY KEY,
    product_id       int          NOT NULL CONSTRAINT uq_dim_product_id UNIQUE,  -- source id
    category_key     int          NOT NULL CONSTRAINT fk_dim_product_category
                                  FOREIGN KEY REFERENCES gold.dim_category (category_key),
    brand_key        int          NOT NULL CONSTRAINT fk_dim_product_brand
                                  FOREIGN KEY REFERENCES gold.dim_brand (brand_key),
    dwh_create_date  datetime2(0) NOT NULL CONSTRAINT df_dim_product_create DEFAULT (SYSUTCDATETIME())
);
GO

/* ---------------------------------------------------------------
   4. dim_customer. SCD Type 2 on rfm_segment (see scd2_customer_design.md).
      customer_key -1 = unknown customer.
   --------------------------------------------------------------- */
IF OBJECT_ID(N'gold.dim_customer', N'U') IS NULL
CREATE TABLE gold.dim_customer
(
    customer_key     int          NOT NULL IDENTITY(1,1) CONSTRAINT pk_dim_customer PRIMARY KEY,
    customer_id      int          NOT NULL,                                 -- source user_id (business key)
    rfm_segment      varchar(30)  NULL,                                     -- tracked attribute
    dwh_valid_from   date         NOT NULL,                                 -- first day of this version
    dwh_valid_to     date         NOT NULL CONSTRAINT df_dim_customer_valid_to DEFAULT ('9999-12-31'),
    dwh_is_current   bit          NOT NULL CONSTRAINT df_dim_customer_current DEFAULT (1),
    dwh_create_date  datetime2(0) NOT NULL CONSTRAINT df_dim_customer_create DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT ck_dim_customer_valid_dates CHECK (dwh_valid_to >= dwh_valid_from)
);
GO

-- Only one current version per customer
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ux_dim_customer_current')
CREATE UNIQUE INDEX ux_dim_customer_current
    ON gold.dim_customer (customer_id)
    WHERE dwh_is_current = 1;
GO

IF NOT EXISTS (SELECT 1 FROM gold.dim_customer WHERE customer_key = -1)
BEGIN
    SET IDENTITY_INSERT gold.dim_customer ON;
    INSERT INTO gold.dim_customer (customer_key, customer_id, rfm_segment, dwh_valid_from, dwh_valid_to, dwh_is_current)
    VALUES (-1, -1, N'unknown', '1900-01-01', '9999-12-31', 1);
    SET IDENTITY_INSERT gold.dim_customer OFF;
END;
GO

/* ---------------------------------------------------------------
   5. dim_event_type. The four event types of the source.
   --------------------------------------------------------------- */
IF OBJECT_ID(N'gold.dim_event_type', N'U') IS NULL
CREATE TABLE gold.dim_event_type
(
    event_type_key   tinyint      NOT NULL CONSTRAINT pk_dim_event_type PRIMARY KEY,
    event_type       varchar(20)  NOT NULL CONSTRAINT uq_dim_event_type UNIQUE
);
GO
IF NOT EXISTS (SELECT 1 FROM gold.dim_event_type)
BEGIN
    INSERT INTO gold.dim_event_type (event_type_key, event_type)
    VALUES (1, 'view'), (2, 'cart'), (3, 'remove_from_cart'), (4, 'purchase');
END;
GO

/* ---------------------------------------------------------------
   6. fact_event. One row per source event (grain). Used for the funnel.
   --------------------------------------------------------------- */
IF OBJECT_ID(N'gold.fact_event', N'U') IS NULL
CREATE TABLE gold.fact_event
(
    event_key        bigint       NOT NULL CONSTRAINT pk_fact_event PRIMARY KEY,       -- silver event_id
    date_key         int          NOT NULL CONSTRAINT fk_fact_event_date
                                  FOREIGN KEY REFERENCES gold.dim_date (date_key),
    event_time       datetime2(0) NOT NULL,
    event_type_key   tinyint      NOT NULL CONSTRAINT fk_fact_event_event_type
                                  FOREIGN KEY REFERENCES gold.dim_event_type (event_type_key),
    customer_key     int          NOT NULL CONSTRAINT fk_fact_event_customer
                                  FOREIGN KEY REFERENCES gold.dim_customer (customer_key),  -- version valid on the event date
    product_key      int          NOT NULL CONSTRAINT fk_fact_event_product
                                  FOREIGN KEY REFERENCES gold.dim_product (product_key),
    session_id       uniqueidentifier NOT NULL,                                          -- kept for the funnel, no dimension
    price            decimal(9,2) NULL,                                                  -- NULL = unknown
    dwh_create_date  datetime2(0) NOT NULL CONSTRAINT df_fact_event_create DEFAULT (SYSUTCDATETIME())
);
GO

/* ---------------------------------------------------------------
   7. fact_order. One row per order (a session with at least one purchase).
   --------------------------------------------------------------- */
IF OBJECT_ID(N'gold.fact_order', N'U') IS NULL
CREATE TABLE gold.fact_order
(
    order_key        int          NOT NULL IDENTITY(1,1) CONSTRAINT pk_fact_order PRIMARY KEY,
    session_id       uniqueidentifier NOT NULL CONSTRAINT uq_fact_order_session UNIQUE,  -- order = session (D3)
    customer_key     int          NOT NULL CONSTRAINT fk_fact_order_customer
                                  FOREIGN KEY REFERENCES gold.dim_customer (customer_key),
    order_date_key   int          NOT NULL CONSTRAINT fk_fact_order_date
                                  FOREIGN KEY REFERENCES gold.dim_date (date_key),
    line_count       int          NOT NULL,                                           -- purchase events
    order_value      decimal(12,2) NOT NULL,                                          -- sum of the prices
    dwh_create_date  datetime2(0) NOT NULL CONSTRAINT df_fact_order_create DEFAULT (SYSUTCDATETIME())
);
GO

/* ---------------------------------------------------------------
   8. fact_order_line. One row per purchase event (one unit, decision D3).
   --------------------------------------------------------------- */
IF OBJECT_ID(N'gold.fact_order_line', N'U') IS NULL
CREATE TABLE gold.fact_order_line
(
    order_line_key   bigint       NOT NULL CONSTRAINT pk_fact_order_line PRIMARY KEY,  -- silver event_id
    order_key        int          NOT NULL CONSTRAINT fk_fact_order_line_order
                                  FOREIGN KEY REFERENCES gold.fact_order (order_key),
    date_key         int          NOT NULL CONSTRAINT fk_fact_order_line_date
                                  FOREIGN KEY REFERENCES gold.dim_date (date_key),
    customer_key     int          NOT NULL CONSTRAINT fk_fact_order_line_customer
                                  FOREIGN KEY REFERENCES gold.dim_customer (customer_key),
    product_key      int          NOT NULL CONSTRAINT fk_fact_order_line_product
                                  FOREIGN KEY REFERENCES gold.dim_product (product_key),
    price            decimal(9,2) NOT NULL CONSTRAINT ck_fact_order_line_price CHECK (price > 0),
    dwh_create_date  datetime2(0) NOT NULL CONSTRAINT df_fact_order_line_create DEFAULT (SYSUTCDATETIME())
);
GO
