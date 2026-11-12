/*
Purpose : Silver layer: typed, normalized tables built from bronze.rees46_events.
          Brand, category, product, user, session and event, linked by keys.
Task    : E4-02 (design), E4-09 (DDL)
Layer   : silver (ecommerce_rfm_dwh)
Re-run  : safe. Each table is created only if missing.
Load order (E5): brand, category, product, user, session, event.
*/
USE ecommerce_rfm_dwh;
GO

/* ---------------------------------------------------------------
   1. Brand. The unknown member has brand_id = -1 (convention).
   --------------------------------------------------------------- */
IF OBJECT_ID(N'silver.rees46_brand', N'U') IS NULL
CREATE TABLE silver.rees46_brand
(
    brand_id    int           NOT NULL IDENTITY(1,1) CONSTRAINT pk_rees46_brand PRIMARY KEY,
    brand_name  varchar(100)  NOT NULL CONSTRAINT uq_rees46_brand_name UNIQUE
);
GO
IF NOT EXISTS (SELECT 1 FROM silver.rees46_brand WHERE brand_id = -1)
BEGIN
    SET IDENTITY_INSERT silver.rees46_brand ON;
    INSERT INTO silver.rees46_brand (brand_id, brand_name) VALUES (-1, N'unknown');
    SET IDENTITY_INSERT silver.rees46_brand OFF;
END;
GO

/* ---------------------------------------------------------------
   2. Category. The id is the natural key from the source (never empty).
      The code and its levels are optional: 388 categories never have one.
   --------------------------------------------------------------- */
IF OBJECT_ID(N'silver.rees46_category', N'U') IS NULL
CREATE TABLE silver.rees46_category
(
    category_id    bigint         NOT NULL CONSTRAINT pk_rees46_category PRIMARY KEY,
    category_code  varchar(200)   NULL,
    level_1        varchar(100)   NULL,
    level_2        varchar(100)   NULL,
    level_3        varchar(100)   NULL,
    level_4        varchar(100)   NULL
);
GO

/* ---------------------------------------------------------------
   3. Product. One row per product. Price is NOT here: it changes over
      time (22% of products have several prices), so it lives on the event.
      Rule for conflicts: 3 products have several categories and 17 several
      brands; the most frequent value is kept (decision in the issues log).
   --------------------------------------------------------------- */
IF OBJECT_ID(N'silver.rees46_product', N'U') IS NULL
CREATE TABLE silver.rees46_product
(
    product_id   int  NOT NULL CONSTRAINT pk_rees46_product PRIMARY KEY,
    category_id  bigint NOT NULL CONSTRAINT fk_rees46_product_category
                 FOREIGN KEY REFERENCES silver.rees46_category (category_id),
    brand_id     int  NOT NULL CONSTRAINT df_rees46_product_brand DEFAULT (-1)
                 CONSTRAINT fk_rees46_product_brand
                 FOREIGN KEY REFERENCES silver.rees46_brand (brand_id)
);
GO

/* ---------------------------------------------------------------
   4. User. One row per user_id.
   --------------------------------------------------------------- */
IF OBJECT_ID(N'silver.rees46_user', N'U') IS NULL
CREATE TABLE silver.rees46_user
(
    user_id        int          NOT NULL CONSTRAINT pk_rees46_user PRIMARY KEY,
    dwh_create_date datetime2(0) NOT NULL CONSTRAINT df_rees46_user_create DEFAULT (SYSUTCDATETIME())
);
GO

/* ---------------------------------------------------------------
   5. Session. Only the session id. A session is NOT linked to one user,
      because 940 sessions have several user ids (finding I-06). The user
      is taken from each event.
   --------------------------------------------------------------- */
IF OBJECT_ID(N'silver.rees46_session', N'U') IS NULL
CREATE TABLE silver.rees46_session
(
    user_session    uniqueidentifier NOT NULL CONSTRAINT pk_rees46_session PRIMARY KEY,
    dwh_create_date datetime2(0)     NOT NULL CONSTRAINT df_rees46_session_create DEFAULT (SYSUTCDATETIME())
);
GO

/* ---------------------------------------------------------------
   6. Event. One row per source row. The file has no event id, so
      event_id is a surrogate key. Price is NULL when unknown: a zero price
      on a view or cart is "unknown", not a free item (I-04).
   --------------------------------------------------------------- */
IF OBJECT_ID(N'silver.rees46_event', N'U') IS NULL
CREATE TABLE silver.rees46_event
(
    event_id         bigint       NOT NULL IDENTITY(1,1) CONSTRAINT pk_rees46_event PRIMARY KEY,
    event_time       datetime2(0) NOT NULL,
    event_type       varchar(20)  NOT NULL CONSTRAINT ck_rees46_event_type
                     CHECK (event_type IN ('view', 'cart', 'remove_from_cart', 'purchase')),
    product_id       int          NOT NULL CONSTRAINT fk_rees46_event_product
                     FOREIGN KEY REFERENCES silver.rees46_product (product_id),
    user_id          int          NOT NULL CONSTRAINT fk_rees46_event_user
                     FOREIGN KEY REFERENCES silver.rees46_user (user_id),
    user_session     uniqueidentifier NOT NULL CONSTRAINT fk_rees46_event_session
                     FOREIGN KEY REFERENCES silver.rees46_session (user_session),
    price            decimal(9,2) NULL CONSTRAINT ck_rees46_event_price
                     CHECK (price IS NULL OR price > 0),
    dwh_load_id      int          NULL,
    dwh_source_file  varchar(260) NULL,
    dwh_create_date  datetime2(0) NOT NULL CONSTRAINT df_rees46_event_create DEFAULT (SYSUTCDATETIME())
);
GO
