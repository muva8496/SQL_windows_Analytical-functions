-- Top-N Products per Branch
-- Puts quantities and respective net_sales_kshs  together of product in respective branches
-- then we look  atROW-NUMBER() and DENSE_RANK()  partitoned by branch id,, toisolate top 5 products

with branch_product_sales AS (
    SELECT
        branch_id,
        branch_name,
        city,
        product_id,
        product_name,
        category,
        SUM(quantity) AS total_units_sold,
        SUM(net_sales_kshs) AS total_net_sales_kshs
    FROM sales
    group by
        branch_id,
        branch_name,
        city,
        product_id,
        product_name,
        category
),
ranked_products AS (
    SELECT
        branch_id,
        branch_name,
        city,
        product_id,
        product_name,
        category,
        total_units_sold,
        total_net_sales_kshs,
        ROW_NUMBER() OVER (
            PARTITION BY branch_id
            order by total_net_sales_kshs DESC, product_id ASC
        ) as row_num_in_branch,
        DENSE_RANK() OVER (
            partition by branch_id
            order by total_net_sales_kshs DESC
        ) as dense_rank_in_branch
    from branch_product_sales
)
SELECT
    branch_id,
    branch_name,
    city,
    dense_rank_in_branch,
    row_num_in_branch,
    product_id,
    product_name,
    category,
    total_units_sold,
    ROUND(total_net_sales_kshs::numeric, 2) AS total_net_sales_kshs
from ranked_products
where dense_rank_in_branch  <= 5
order by branch_id, dense_rank_in_branch, product_id;