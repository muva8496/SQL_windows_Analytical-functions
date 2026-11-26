WITH customer_receipts AS (
    SELECT
        loyalty_card_id,
        transaction_id,
        branch_id,
        branch_name,
        city,
        (date + time) AS order_timestamp,
        EXTRACT(ISODOW FROM date)::int AS day_of_week,
        EXTRACT(HOUR FROM time)::int AS hour_of_day,
        COUNT(*) AS line_items,
        SUM(quantity) AS total_units,
        SUM(gross_amount_kshs) AS receipt_gross_kshs,
        SUM(discount_kshs) AS receipt_discount_kshs,
        SUM(net_sales_kshs) AS receipt_net_kshs
    FROM sales
    WHERE loyalty_card_id IS NOT NULL
      AND TRIM(loyalty_card_id) <> ''
    GROUP BY
        loyalty_card_id,
        transaction_id,
        branch_id,
        branch_name,
        city,
        date,
        time
),
sequenced_visits AS (
    SELECT
        loyalty_card_id,
        transaction_id,
        branch_id,
        branch_name,
        city,
        order_timestamp,
        day_of_week,
        hour_of_day,
        line_items,
        total_units,
        receipt_gross_kshs,
        receipt_discount_kshs,
        receipt_net_kshs,

        -- Sequence & recency features (strictly backward-looking)
        ROW_NUMBER() OVER (
            PARTITION BY loyalty_card_id
            ORDER BY order_timestamp, transaction_id
        ) AS visit_number,

        FIRST_VALUE(order_timestamp) OVER (
            PARTITION BY loyalty_card_id
            ORDER BY order_timestamp, transaction_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS first_visit_ts,

        LAG(order_timestamp, 1) OVER (
            PARTITION BY loyalty_card_id
            ORDER BY order_timestamp, transaction_id
        ) AS prev_visit_ts,

        LAG(receipt_net_kshs, 1) OVER (
            PARTITION BY loyalty_card_id
            ORDER BY order_timestamp, transaction_id
        ) AS prev_1_spend_kshs,

        LAG(receipt_net_kshs, 2) OVER (
            PARTITION BY loyalty_card_id
            ORDER BY order_timestamp, transaction_id
        ) AS prev_2_spend_kshs,

        LAG(branch_id, 1) OVER (
            PARTITION BY loyalty_card_id
            ORDER BY order_timestamp, transaction_id
        ) AS prev_branch_id,

        -- Strictly historical rolling windows (1 PRECEDING prevents target leakage)
        COUNT(*) OVER (
            PARTITION BY loyalty_card_id
            ORDER BY order_timestamp, transaction_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prior_visit_count,

        SUM(receipt_net_kshs) OVER (
            PARTITION BY loyalty_card_id
            ORDER BY order_timestamp, transaction_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prior_cumulative_spend_kshs,

        AVG(receipt_net_kshs) OVER (
            PARTITION BY loyalty_card_id
            ORDER BY order_timestamp, transaction_id
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prior_3_avg_spend_kshs,

        STDDEV_POP(receipt_net_kshs) OVER (
            PARTITION BY loyalty_card_id
            ORDER BY order_timestamp, transaction_id
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prior_3_std_spend_kshs,

        AVG(total_units) OVER (
            PARTITION BY loyalty_card_id
            ORDER BY order_timestamp, transaction_id
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prior_3_avg_units,

        -- Forward-looking supervision targets (next visit outcomes)
        LEAD(order_timestamp, 1) OVER (
            PARTITION BY loyalty_card_id
            ORDER BY order_timestamp, transaction_id
        ) AS next_visit_ts,

        LEAD(receipt_net_kshs, 1) OVER (
            PARTITION BY loyalty_card_id
            ORDER BY order_timestamp, transaction_id
        ) AS target_next_spend_kshs
    FROM customer_receipts
)
SELECT
    -- Keys & timestamps
    loyalty_card_id,
    transaction_id,
    branch_id,
    city,
    order_timestamp,

    -- Calendar & basket context at current visit
    day_of_week,
    hour_of_day,
    CASE WHEN day_of_week IN (6, 7) THEN 1 ELSE 0 END AS is_weekend,
    visit_number,
    line_items,
    total_units,
    ROUND(receipt_net_kshs::numeric, 2) AS current_spend_kshs,
    ROUND(
        CASE
            WHEN receipt_gross_kshs > 0
            THEN (receipt_discount_kshs / receipt_gross_kshs) * 100.0
            ELSE 0.0
        END::numeric,
        2
    ) AS current_discount_pct,

    -- Recency, frequency, monetary (RFM) & behavioral features
    ROUND(EXTRACT(EPOCH FROM (order_timestamp - first_visit_ts)) / 86400.0, 2) AS customer_tenure_days,
    ROUND(EXTRACT(EPOCH FROM (order_timestamp - prev_visit_ts)) / 86400.0, 2) AS days_since_prev_visit,
    CASE
        WHEN prev_branch_id IS NULL THEN NULL
        WHEN branch_id <> prev_branch_id THEN 1
        ELSE 0
    END AS switched_branch_flag,
    prior_visit_count,
    ROUND(COALESCE(prior_cumulative_spend_kshs, 0)::numeric, 2) AS prior_cumulative_spend_kshs,
    ROUND(prev_1_spend_kshs::numeric, 2) AS prev_1_spend_kshs,
    ROUND(prev_2_spend_kshs::numeric, 2) AS prev_2_spend_kshs,
    ROUND(prior_3_avg_spend_kshs::numeric, 2) AS prior_3_avg_spend_kshs,
    ROUND(prior_3_std_spend_kshs::numeric, 2) AS prior_3_std_spend_kshs,
    ROUND(prior_3_avg_units::numeric, 2) AS prior_3_avg_units,
    ROUND((receipt_net_kshs - prior_3_avg_spend_kshs)::numeric, 2) AS spend_vs_prior_3_avg_kshs,

    -- ML Targets (regression + binary 30-day repeat classification)
    ROUND(EXTRACT(EPOCH FROM (next_visit_ts - order_timestamp)) / 86400.0, 2) AS target_days_until_next_visit,
    ROUND(target_next_spend_kshs::numeric, 2) AS target_next_spend_kshs,
    CASE
        WHEN next_visit_ts IS NOT NULL
         AND EXTRACT(EPOCH FROM (next_visit_ts - order_timestamp)) / 86400.0 <= 30.0
        THEN 1
        ELSE 0
    END AS target_returned_within_30d
FROM sequenced_visits
WHERE visit_number >= 2
ORDER BY loyalty_card_id, visit_number;