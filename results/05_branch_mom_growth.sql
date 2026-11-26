-- month-ober-month growth and share of wallet
-- each  month trajectory, growth vs launch month, and share of quickmart's total chain revenue in one pass
WITH monthly_branch_sales AS (
    SELECT
        DATE_TRUNC('month', date)::date AS sales_month,
        branch_id,
        branch_name,
        city,
        COUNT(DISTINCT transaction_id) AS receipt_count,
        SUM(quantity) AS total_units_sold,
        SUM(net_sales_kshs) AS monthly_net_sales_kshs
    FROM sales
    GROUP BY
        DATE_TRUNC('month', date)::date,
        branch_id,
        branch_name,
        city
),
branch_growth_metrics AS (
    SELECT
        sales_month,
        branch_id,
        branch_name,
        city,
        receipt_count,
        total_units_sold,
        monthly_net_sales_kshs,

        -- Previous month sales for this specific branch
        LAG(monthly_net_sales_kshs) OVER (
            PARTITION BY branch_id
            ORDER BY sales_month
        ) AS prev_month_sales_kshs,

        -- Baseline sales from this branch's earliest active month in the dataset
        FIRST_VALUE(monthly_net_sales_kshs) OVER (
            PARTITION BY branch_id
            ORDER BY sales_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS first_month_sales_kshs,

        -- Total chain-wide sales across all branches for that calendar month
        SUM(monthly_net_sales_kshs) OVER (
            PARTITION BY sales_month
        ) AS chain_monthly_sales_kshs,

        -- Rank of this branch within Quickmart for that calendar month
        DENSE_RANK() OVER (
            PARTITION BY sales_month
            ORDER BY monthly_net_sales_kshs DESC
        ) AS monthly_chain_rank
    FROM monthly_branch_sales
)
SELECT
    sales_month,
    branch_id,
    branch_name,
    city,
    monthly_chain_rank,
    receipt_count,
    ROUND(monthly_net_sales_kshs::numeric, 2) AS monthly_net_sales_kshs,
    ROUND((monthly_net_sales_kshs - prev_month_sales_kshs)::numeric, 2) AS mom_delta_kshs,
    ROUND(
        (
            ((monthly_net_sales_kshs - prev_month_sales_kshs) / NULLIF(prev_month_sales_kshs, 0))
            * 100.0
        )::numeric,
        2
    ) AS mom_growth_pct,
    ROUND(
        (
            ((monthly_net_sales_kshs - first_month_sales_kshs) / NULLIF(first_month_sales_kshs, 0))
            * 100.0
        )::numeric,
        2
    ) AS growth_vs_first_month_pct,
    ROUND(
        (
            (monthly_net_sales_kshs / NULLIF(chain_monthly_sales_kshs, 0))
            * 100.0
        )::numeric,
        2
    ) AS chain_revenue_share_pct
FROM branch_growth_metrics
ORDER BY branch_id, sales_month;