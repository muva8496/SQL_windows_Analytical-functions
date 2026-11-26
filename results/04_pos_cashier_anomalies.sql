WITH cashier_receipts AS (
    SELECT
        cashier_id,
        branch_id,
        branch_name,
        city,
        transaction_id,
        (date + time) AS receipt_ts,
        COUNT(*) AS line_items,
        SUM(quantity) AS total_units,
        SUM(gross_amount_kshs) AS receipt_gross_kshs,
        SUM(discount_kshs) AS receipt_discount_kshs,
        SUM(net_sales_kshs) AS receipt_net_kshs
    FROM sales
    WHERE cashier_id IS NOT NULL
      AND TRIM(cashier_id) <> ''
    GROUP BY
        cashier_id,
        branch_id,
        branch_name,
        city,
        transaction_id,
        date,
        time
),
cashier_windows AS (
    SELECT
        cashier_id,
        branch_id,
        branch_name,
        city,
        transaction_id,
        receipt_ts,
        line_items,
        total_units,
        receipt_gross_kshs,
        receipt_discount_kshs,
        receipt_net_kshs,
        CASE
            WHEN receipt_gross_kshs > 0
            THEN (receipt_discount_kshs / receipt_gross_kshs) * 100.0
            ELSE 0.0
        END AS discount_pct,

        -- Cashier's receipt sequence & time gap since prior checkout
        ROW_NUMBER() OVER (
            PARTITION BY cashier_id
            ORDER BY receipt_ts, transaction_id
        ) AS cashier_receipt_seq,

        LAG(receipt_ts) OVER (
            PARTITION BY cashier_id
            ORDER BY receipt_ts, transaction_id
        ) AS prev_receipt_ts,

        LAG(receipt_discount_kshs) OVER (
            PARTITION BY cashier_id
            ORDER BY receipt_ts, transaction_id
        ) AS prev_discount_kshs,

        -- Running average & spread of discount_kshs per cashier up to current receipt
        AVG(receipt_discount_kshs) OVER (
            PARTITION BY cashier_id
            ORDER BY receipt_ts, transaction_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_avg_discount_kshs,

        STDDEV_POP(receipt_discount_kshs) OVER (
            PARTITION BY cashier_id
            ORDER BY receipt_ts, transaction_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_stddev_discount_kshs,

        -- Receipts processed by this cashier within a rolling 10-row window
        COUNT(*) OVER (
            PARTITION BY cashier_id
            ORDER BY receipt_ts, transaction_id
            ROWS BETWEEN 9 PRECEDING AND CURRENT ROW
        ) AS rolling_10_receipt_count
    FROM cashier_receipts
)
SELECT
    cashier_id,
    branch_id,
    branch_name,
    city,
    cashier_receipt_seq,
    transaction_id,
    receipt_ts,
    ROUND(EXTRACT(EPOCH FROM (receipt_ts - prev_receipt_ts)) / 60.0, 2) AS mins_since_prev_receipt,
    ROUND(receipt_gross_kshs::numeric, 2) AS receipt_gross_kshs,
    ROUND(receipt_discount_kshs::numeric, 2) AS receipt_discount_kshs,
    ROUND(discount_pct::numeric, 2) AS discount_pct,
    ROUND(running_avg_discount_kshs::numeric, 2) AS running_avg_discount_kshs,
    ROUND((receipt_discount_kshs - prev_discount_kshs)::numeric, 2) AS discount_delta_vs_prev_kshs,
    ROUND(
        (
            (receipt_discount_kshs - running_avg_discount_kshs)
            / NULLIF(running_stddev_discount_kshs, 0)
        )::numeric,
        2
    ) AS discount_z_score,
    rolling_10_receipt_count
FROM cashier_windows
ORDER BY discount_z_score DESC NULLS LAST, cashier_id, cashier_receipt_seq;