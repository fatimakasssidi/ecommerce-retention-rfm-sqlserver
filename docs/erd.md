# Entity Relationship Diagram (E4-07)

Project: E-commerce Customer Retention & RFM (SQL Server)

Gold layer (star schema). Facts are in the middle, dimensions around them.
GitHub draws this diagram from the text below.

```mermaid
erDiagram
    dim_date ||--o{ fact_event : "date_key"
    dim_date ||--o{ fact_order : "order_date_key"
    dim_date ||--o{ fact_order_line : "date_key"
    dim_event_type ||--o{ fact_event : "event_type_key"
    dim_customer ||--o{ fact_event : "customer_key (version on the date)"
    dim_customer ||--o{ fact_order : "customer_key"
    dim_customer ||--o{ fact_order_line : "customer_key"
    dim_product ||--o{ fact_event : "product_key"
    dim_product ||--o{ fact_order_line : "product_key"
    dim_category ||--o{ dim_product : "category_key"
    dim_brand ||--o{ dim_product : "brand_key"
    fact_order ||--o{ fact_order_line : "order_key"

    fact_event {
        bigint event_key PK
        int date_key FK
        int customer_key FK
        int product_key FK
        tinyint event_type_key FK
        uniqueidentifier session_id
        decimal price
    }
    fact_order {
        int order_key PK
        uniqueidentifier session_id UK
        int customer_key FK
        int order_date_key FK
        int line_count
        decimal order_value
    }
    fact_order_line {
        bigint order_line_key PK
        int order_key FK
        int customer_key FK
        int product_key FK
        int date_key FK
        decimal price
    }
    dim_customer {
        int customer_key PK
        int customer_id
        varchar rfm_segment
        date dwh_valid_from
        date dwh_valid_to
        bit dwh_is_current
    }
    dim_product {
        int product_key PK
        int product_id
        int category_key FK
        int brand_key FK
    }
    dim_category {
        int category_key PK
        bigint category_id
        varchar category_code
    }
    dim_brand {
        int brand_key PK
        int brand_id
        varchar brand_name
    }
    dim_date {
        int date_key PK
        date full_date
        bit is_partial_week
        bit is_black_friday
    }
    dim_event_type {
        tinyint event_type_key PK
        varchar event_type
    }
```
