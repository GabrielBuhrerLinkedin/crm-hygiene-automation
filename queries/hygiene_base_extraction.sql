%%sql base_data <<

-- ==============================================================================
-- 1. FISCAL CONTEXT & TARGETS
-- Calculates current fiscal year/quarter and defines the dynamic FY string 
-- and the list of target managers for the automation.
-- ==============================================================================
WITH fiscal_context AS (
    SELECT
        CASE
            WHEN MONTH(CURRENT_DATE) >= 7 THEN YEAR(CURRENT_DATE) + 1
            ELSE YEAR(CURRENT_DATE)
        END AS current_fiscal_year,
        CASE
            WHEN MONTH(CURRENT_DATE) BETWEEN 7 AND 9 THEN 1
            WHEN MONTH(CURRENT_DATE) BETWEEN 10 AND 12 THEN 2
            WHEN MONTH(CURRENT_DATE) BETWEEN 1 AND 3 THEN 3
            WHEN MONTH(CURRENT_DATE) BETWEEN 4 AND 6 THEN 4
        END AS current_fiscal_quarter
),

target_config AS (
    SELECT 
        -- Creates dynamic string like 'FY26 LSS GAM Account' based on fiscal year
        'FY' || CAST(current_fiscal_year % 100 AS VARCHAR) || ' LSS GAM Account' AS dynamic_fy_account_name
    FROM fiscal_context
),

target_managers AS (
    -- Centralized list of managers allowed in this automation
    SELECT fullname FROM (VALUES 
        ('Katherine Brinkman'), ('Hui Yen Ko'), ('Thibaud Savouré'), 
        ('Erin Mathurin'), ('Randy Petway')
    ) AS t(fullname)
),

-- ==============================================================================
-- 2. OPP DATA (EARLY FILTERING)
-- Extracts ONLY 'Open' opportunities. Financial metrics are simplified 
-- because we no longer need to handle 'Closed Won' logic here.
-- ==============================================================================
opp_data AS (
    SELECT
        opp.opportunity_id,
        opp.sfdc_account_id,
        opp.sales_org,
        opp.opportunity_type,
        opp.opportunity_sub_type,
        opp.opportunity_stage_name,
        opp.stage_days,
        opp.status AS opportunity_status,
        opp.fiscal_year_closed,
        opp.fiscal_quarter_closed,
        opp.first_year_amount_usd,
        opp.owner_name,
        opp.ownerid,
        opp.employeenumber AS owner_employee_id,
        opp.account_name,
        opp.close_date,
        opp.probability,
        opp.opportunity_name,
        opp.upside_annualized_usd,
        opp.worstcase_annualized_usd,
        opp.nextstep,
        opp.opportunity_created_date,
        opp.close_timestamp,
        opp.customer_urn,
        opp.owner_current_manager_id,
        opp.lss_named_account,
        
        -- Simplified metrics for Open Opportunities
        COALESCE(opp.total_outlook_amount_usd, 0) AS Open_Outlook_Amt,
        COALESCE(opp.total_outlook_first_year_amount_usd, 0) AS Forecast,
        COALESCE(opp.renewal_target_amount_usd, 0) AS renewal_target_amt_conv,
        COALESCE(opp.baseline_cy_amount_usd, 0) AS Baseline_Cy_con

    FROM u_lssops.opportunity opp
    WHERE opp.status = 'Open' -- Improvement: Filtered early for performance
),

-- ==============================================================================
-- 3. JOINED ALL (OPTIMIZED JOINS)
-- Enriches data using INNER JOIN with target managers to discard 
-- out-of-scope data immediately.
-- ==============================================================================
joined_all AS (
    SELECT
        opp.*,
        acc.ultimate_parent_name,
        acc.ultimate_parent_id,
        mgr.fullname AS Owner_Manager,
        mgr.email AS manager_email

    FROM opp_data opp
    INNER JOIN u_lssops.account acc ON acc.customer_urn = opp.customer_urn
    -- Improvement: Inner Join with the specific target list
    INNER JOIN u_salesbi.users mgr ON mgr.sfdc_user_id = opp.owner_current_manager_id
    INNER JOIN target_managers tm ON mgr.fullname = tm.fullname
    CROSS JOIN target_config tc

    WHERE opp.lss_named_account = tc.dynamic_fy_account_name -- Improvement: Dynamic FY
      AND opp.sales_org = 'GAM'
),

-- ==============================================================================
-- 4. DEDUPLICATION
-- Keep only the primary record per opportunity.
-- ==============================================================================
final_ranked AS (
    SELECT j.*,
        ROW_NUMBER() OVER (
            PARTITION BY j.opportunity_id
            ORDER BY j.close_timestamp DESC
        ) AS final_rn
    FROM joined_all j
),

deduped AS (
    SELECT * FROM final_ranked WHERE final_rn = 1
),

-- ==============================================================================
-- 5. FINAL BASE & OUTPUT
-- Applies fiscal window filtering (Next 3 Quarters) and final column formatting.
-- ==============================================================================
final_base AS (
    SELECT d.*,
        (d.fiscal_year_closed * 4 + CAST(REGEXP_EXTRACT(d.fiscal_quarter_closed, 'Q([1-4])', 1) AS INTEGER)) AS close_fiscal_period_index,
        fc.current_fiscal_year,
        fc.current_fiscal_quarter,
        (fc.current_fiscal_year * 4 + fc.current_fiscal_quarter) AS current_fiscal_period_index
    FROM deduped d
    CROSS JOIN fiscal_context fc
)

SELECT
    opportunity_id AS opp_id,
    ownerid AS owner_id,
    owner_employee_id,
    opportunity_status,
    owner_name AS final_owner_name,
    opportunity_name AS opp_name,
    ultimate_parent_name AS ult_parent_account_name,
    ultimate_parent_id AS ult_parent_account_id,
    account_name,
    sfdc_account_id,
    Owner_Manager,
    manager_email,
    opportunity_stage_name AS stage,
    stage_days,
    fiscal_year_closed AS close_Year_F,
    fiscal_quarter_closed AS close_quarter_F,
    close_date,
    Forecast,
    renewal_target_amt_conv,
    Baseline_Cy_con,
    probability / 100 AS Probability,
    COALESCE(upside_annualized_usd, 0) AS Upside_Annualized_usd,
    COALESCE(worstcase_annualized_usd, 0) AS WorstCase_Annualized_usd,
    nextstep,
    DATE_DIFF('day', opportunity_created_date, CURRENT_DATE) AS days_open

FROM final_base

WHERE close_fiscal_period_index BETWEEN current_fiscal_period_index AND current_fiscal_period_index + 3
ORDER BY opp_id