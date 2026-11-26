with daily_branch_product AS (
    SELECT
        branch_id,
        branch_name,
        product_id,
        product_name,
        date AS sale_date,
        SUM(quantity) AS daily_units,
        SUM(net_sales_kshs) AS daily_net_sales_kshs,
        SUM(items_in_basket) AS daily_basket_items
    from sales
    GROUP BY
        branch_id,
        branch_name, 
        product_id,
        product_name,
        date
)
select 
    branch_id,
    branch_name,
    product_id,
    product_name,
    sale_date,
    daily_units,
    ROUND(daily_net_sales_kshs::numeric, 2) AS daily_net_sales_kshs,

    -- Cumulative sales & units within each branch + product over time
    SUM(daily_units) over (
        partition by branch_id, product_id
        order  by sale_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )   AS cumulative_units,

    ROUND(
        SUM(daily_net_sales_kshs) OVER (
            partition by branch_id, product_id
            order by sale_date
            rows between unbounded preceding and current row
        )::numeric, 
        2
    ) AS cumulative_net_sales_kshs,

    --7-day rolling average daily sales  & units(current day + 6 prior days)
    ROUND(
        AVG(daily_net_sales_kshs) OVER (
            partition by branch_id, product_id
            order by sale_date
            rows between 6 preceding and current row
        )::numeric,
        2
    ) AS rolling_7d_avg_sales_kshs,

    ROUND(
        AVG(daily_units) over (
            partition by branch_id , product_id
            order by sale_date
            rows between 6 preceding and current row
        )::numeric,
        2
    ) AS rolling_7d_avg_units
from daily_branch_product
order by branch_id, product_id, sale_date;