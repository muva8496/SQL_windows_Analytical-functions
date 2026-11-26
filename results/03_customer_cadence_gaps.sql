-- Positional offsets functions
-- to measure  exact time gaps and changes in basket spend
with customer_receipts AS (
    SELECT
        loyalty_card_id,
        transaction_id,
        branch_id,
        branch_name,
        (date + time) AS order_timestamp,
        COUNT(*) as line_items_count,
        SUM(quantity) AS  total_units,
        SUM(net_sales_kshs) AS receipt_net_sales_kshs
    from sales
    where loyalty_card_id IS NOT NULL
        and trim(loyalty_card_id) <> ''
    GROUP BY
        loyalty_card_id,
        transaction_id,
        branch_id,
        branch_name,
        date,
        time
),
customer_cadence AS (
    SELECT
        loyalty_card_id,
        transaction_id,
        branch_id,
        branch_name,
        order_timestamp,
        line_items_count,
        total_units,
        receipt_net_sales_kshs,

        --1. visit sequence number per loyalty customer
        ROW_NUMBER() OVER (
            partition by loyalty_card_id
            order by order_timestamp, transaction_id
        ) AS visit_number,

        --2 Timestamp and spend of the customer's previous visit
        LAG(order_timestamp) OVER (
            PARTITION BY loyalty_card_id
            order by order_timestamp, transaction_id
        ) AS prev_visit_ts,
        LAG(receipt_net_sales_kshs) OVER(
            partition by loyalty_card_id 
            order by order_timestamp, transaction_id
        ) AS prev_receipt_sales_kshs,

        --33. Timestamp of the customer's next vist(forward-looking retention)
        LEAD(order_timestamp) OVER (
            partition by loyalty_card_id
            order by order_timestamp, transaction_id
        ) AS next_visit_ts
    FROM customer_receipts
)
SELECT
    loyalty_card_id,
    visit_number,
    transaction_id,
    branch_id,
    branch_name,
    order_timestamp,
    ROUND(receipt_net_sales_kshs::numeric, 2) AS receipt_net_sales_kshs,
    ROUND((receipt_net_sales_kshs - prev_receipt_sales_kshs)::numeric, 2) AS spend_delt_vs_prev_kshs,
    ROUND(EXTRACT(EPOCH FROM (order_timestamp - prev_visit_ts)) / 86400.0 , 2) AS days_since_prev_visit,
    ROUND(EXTRACT(EPOCH FROM (next_visit_ts - order_timestamp)) / 86400, 2) AS  days_until_next_visit
FROM customer_cadence
order by loyalty_card_id, visit_number;
