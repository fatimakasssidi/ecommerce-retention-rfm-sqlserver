/*
Purpose : Date dimension. One row per calendar day, with week, weekday, partial-week
          and Black Friday flags. Generated with a recursive CTE.
Task    : E4-06
Layer   : gold (ecommerce_rfm_dwh)
Re-run  : safe. Only missing days are added.
Period  : 2019-01-01 to 2020-12-31 (covers the data 2019-10-01 to 2019-11-30 with margin)
Reading : each column of the SELECT ends with "AS name", and the INSERT list
          has the same columns in the same order.
*/
USE ecommerce_rfm_dwh;
GO

/* ---------------------------------------------------------------
   1. The table
   --------------------------------------------------------------- */
IF OBJECT_ID(N'gold.dim_date', N'U') IS NULL
CREATE TABLE gold.dim_date
(
    -- key and date
    date_key          int          NOT NULL CONSTRAINT pk_dim_date PRIMARY KEY,   -- yyyymmdd
    full_date         date         NOT NULL CONSTRAINT uq_dim_date_full_date UNIQUE,
    -- date parts
    year_number       smallint     NOT NULL,
    month_number      tinyint      NOT NULL,
    month_name        varchar(10)  NOT NULL,
    day_of_month      tinyint      NOT NULL,
    -- weekday and week
    weekday_number    tinyint      NOT NULL,   -- 1 = Monday ... 7 = Sunday
    weekday_name      varchar(10)  NOT NULL,
    is_weekend        bit          NOT NULL,
    week_start_date   date         NOT NULL,   -- the Monday of the week
    -- flags for the analysis
    is_in_data_period bit          NOT NULL,   -- 1 between 2019-10-01 and 2019-11-30
    is_partial_week   bit          NOT NULL,   -- 1 if the week is not fully inside the data period
    is_black_friday   bit          NOT NULL,   -- 2019-11-29
    -- technical
    dwh_create_date   datetime2(0) NOT NULL CONSTRAINT df_dim_date_create DEFAULT (SYSUTCDATETIME())
);
GO

/* ---------------------------------------------------------------
   2. Generate the missing days
   --------------------------------------------------------------- */
DECLARE @data_start date = '2019-10-01';
DECLARE @data_end   date = '2019-11-30';

;WITH days AS
(
    SELECT CAST('2019-01-01' AS date) AS d
    UNION ALL
    SELECT DATEADD(day, 1, d) FROM days WHERE d < '2020-12-31'
)
INSERT INTO gold.dim_date
(
    -- key and date
    date_key,
    full_date,
    -- date parts
    year_number,
    month_number,
    month_name,
    day_of_month,
    -- weekday and week
    weekday_number,
    weekday_name,
    is_weekend,
    week_start_date,
    -- flags for the analysis
    is_in_data_period,
    is_partial_week,
    is_black_friday
)
SELECT
    -- key and date
    CAST(CONVERT(char(8), d, 112) AS int)                                   AS date_key,
    d                                                                       AS full_date,
    -- date parts
    YEAR(d)                                                                 AS year_number,
    MONTH(d)                                                                AS month_number,
    DATENAME(month, d)                                                      AS month_name,
    DAY(d)                                                                  AS day_of_month,
    -- weekday and week (1900-01-01 was a Monday, so the difference in days gives the weekday)
    (DATEDIFF(day, '1900-01-01', d) % 7) + 1                                AS weekday_number,
    DATENAME(weekday, d)                                                    AS weekday_name,
    CASE WHEN DATEDIFF(day, '1900-01-01', d) % 7 >= 5 THEN 1 ELSE 0 END     AS is_weekend,
    DATEADD(day, -(DATEDIFF(day, '1900-01-01', d) % 7), d)                  AS week_start_date,
    -- flags for the analysis
    CASE WHEN d BETWEEN @data_start AND @data_end THEN 1 ELSE 0 END         AS is_in_data_period,
    CASE WHEN DATEADD(day, -(DATEDIFF(day, '1900-01-01', d) % 7), d) < @data_start
              OR DATEADD(day, 6 - (DATEDIFF(day, '1900-01-01', d) % 7), d) > @data_end
         THEN 1 ELSE 0 END                                                  AS is_partial_week,
    CASE WHEN d = '2019-11-29' THEN 1 ELSE 0 END                            AS is_black_friday
FROM days
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_date AS x WHERE x.full_date = days.d)
OPTION (MAXRECURSION 1000);
GO

/* ---------------------------------------------------------------
   3. Checks: 731 days (2019 and 2020, 2020 is a leap year), 61 in the data period
   --------------------------------------------------------------- */
SELECT COUNT(*) AS days_loaded FROM gold.dim_date;                                        -- expected 731
SELECT COUNT(*) AS days_in_data_period FROM gold.dim_date WHERE is_in_data_period = 1;   -- expected 61
SELECT full_date, weekday_name, week_start_date, is_partial_week, is_black_friday
FROM gold.dim_date
WHERE full_date IN ('2019-09-30', '2019-10-01', '2019-10-07', '2019-11-29', '2019-11-30', '2019-12-01')
ORDER BY full_date;
GO
