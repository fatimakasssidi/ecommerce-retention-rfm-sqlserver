/*
Purpose : Raw landing table for the REES46 event files, and the view used to bulk load it.
Task    : E3-01
Layer   : bronze
Re-run  : safe, nothing is dropped
*/

USE ecommerce_rfm_raw;
GO

/* ---------------------------------------------------------------
   Raw table. All file columns are text, so a bad value never blocks
   a load. Typing and validation happen in silver.
   It is a heap on purpose: the fastest structure for bulk loading.
   --------------------------------------------------------------- */
IF OBJECT_ID(N'bronze.rees46_events', N'U') IS NULL
BEGIN
    CREATE TABLE bronze.rees46_events
    (
        -- columns of the source file, in file order
        event_time      varchar(100)  NULL,
        event_type      varchar(100)  NULL,
        product_id      varchar(100)  NULL,
        category_id     varchar(100)  NULL,
        category_code   varchar(400)  NULL,
        brand           varchar(400)  NULL,
        price           varchar(100)  NULL,
        user_id         varchar(100)  NULL,
        user_session    varchar(100)  NULL,

        -- technical columns
        dwh_load_id     int           NULL,
        dwh_source_file varchar(260)  NULL,
        dwh_create_date datetime2(0)  NOT NULL
            CONSTRAINT df_rees46_events_dwh_create_date DEFAULT (SYSUTCDATETIME())
    );
END;
GO

/* ---------------------------------------------------------------
   Load view. BULK INSERT expects one field per table column, but the
   file has 9 fields and the table has 12 columns. The view exposes
   only the 9 file columns, so the technical columns keep their
   defaults.
   --------------------------------------------------------------- */
CREATE OR ALTER VIEW bronze.v_rees46_events_load
AS
SELECT
    event_time,
    event_type,
    product_id,
    category_id,
    category_code,
    brand,
    price,
    user_id,
    user_session
FROM bronze.rees46_events;
GO
