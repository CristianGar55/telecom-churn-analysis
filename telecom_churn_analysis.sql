-- Telecom Customer Churn Analysis
-- Dataset: IBM Telco Customer Churn (via Kaggle, blastchar/telco-customer-churn)
-- 7,043 customers, single quarterly snapshot
 
-- ============================================================
-- 1. SCHEMA + LOAD
-- ============================================================
 
CREATE DATABASE IF NOT EXISTS churn_project;
USE churn_project;
 
CREATE TABLE raw_customers (
    customerID       VARCHAR(20) PRIMARY KEY,
    gender            VARCHAR(10),
    SeniorCitizen     TINYINT,
    Partner            VARCHAR(5),
    Dependents         VARCHAR(5),
    tenure             INT,
    PhoneService       VARCHAR(5),
    MultipleLines      VARCHAR(20),
    InternetService    VARCHAR(20),
    OnlineSecurity     VARCHAR(20),
    OnlineBackup       VARCHAR(20),
    DeviceProtection   VARCHAR(20),
    TechSupport        VARCHAR(20),
    StreamingTV        VARCHAR(20),
    StreamingMovies    VARCHAR(20),
    Contract           VARCHAR(20),
    PaperlessBilling   VARCHAR(5),
    PaymentMethod      VARCHAR(30),
    MonthlyCharges     DECIMAL(8,2),
    TotalCharges       VARCHAR(20),   -- text on purpose, 11 rows come in blank
    Churn              VARCHAR(5)
);
 
-- LOAD DATA LOCAL INFILE '/path/to/telco_raw.csv'
-- INTO TABLE raw_customers
-- FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n'
-- IGNORE 1 ROWS;
 
-- clean/typed working table
CREATE TABLE customers AS
SELECT
    customerID,
    gender,
    SeniorCitizen,
    Partner,
    Dependents,
    tenure AS tenure_months,
    PhoneService,
    MultipleLines,
    InternetService AS internet_type,
    OnlineSecurity,
    OnlineBackup,
    DeviceProtection,
    TechSupport,
    StreamingTV,
    StreamingMovies,
    Contract AS plan_type,
    PaperlessBilling,
    PaymentMethod,
    MonthlyCharges,
    CASE WHEN TRIM(TotalCharges) = '' THEN 0 ELSE CAST(TotalCharges AS DECIMAL(10,2)) END AS TotalCharges,
    Churn,
    CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END AS Churned
FROM raw_customers;
 
CREATE INDEX idx_plan_type ON customers(plan_type);
CREATE INDEX idx_payment_method ON customers(PaymentMethod);
CREATE INDEX idx_churned ON customers(Churned);
CREATE INDEX idx_tenure ON customers(tenure_months);
 
-- ============================================================
-- 2. DATA VALIDATION
-- ============================================================
 
-- duplicate check, should be 0 rows
SELECT customerID, COUNT(*) AS cnt
FROM customers
GROUP BY customerID
HAVING COUNT(*) > 1;
 
-- null audit, should all be 0
SELECT
    SUM(plan_type IS NULL) AS null_plan_type,
    SUM(PaymentMethod IS NULL) AS null_payment,
    SUM(TechSupport IS NULL) AS null_techsupport,
    SUM(OnlineSecurity IS NULL) AS null_security,
    SUM(tenure_months IS NULL) AS null_tenure,
    SUM(MonthlyCharges IS NULL) AS null_monthly,
    SUM(Churned IS NULL) AS null_churned
FROM customers;
 
-- range sanity check
SELECT
    SUM(tenure_months < 0 OR tenure_months > 72) AS bad_tenure,
    SUM(MonthlyCharges <= 0) AS bad_monthly_charge,
    SUM(Churned NOT IN (0,1)) AS bad_churn_flag
FROM customers;
 
-- ============================================================
-- 3. CORE CHURN METRICS
-- ============================================================
 
SELECT
    COUNT(*) AS total_customers,
    SUM(Churned) AS churned_customers,
    ROUND(100.0 * SUM(Churned) / COUNT(*), 2) AS churn_rate_pct
FROM customers;
 
-- churn by tenure -- the single most important cut in this dataset
SELECT
    CASE
        WHEN tenure_months <= 6 THEN '0-6 mo'
        WHEN tenure_months <= 12 THEN '6-12 mo'
        WHEN tenure_months <= 24 THEN '1-2 yr'
        WHEN tenure_months <= 48 THEN '2-4 yr'
        ELSE '4+ yr'
    END AS tenure_bucket,
    COUNT(*) AS n_customers,
    SUM(Churned) AS churned,
    ROUND(100.0 * SUM(Churned) / COUNT(*), 1) AS churn_rate_pct
FROM customers
GROUP BY tenure_bucket
ORDER BY MIN(tenure_months);
 
-- churn by contract type
SELECT
    plan_type,
    COUNT(*) AS n_customers,
    SUM(Churned) AS churned,
    ROUND(100.0 * SUM(Churned) / COUNT(*), 1) AS churn_rate_pct,
    ROUND(AVG(MonthlyCharges), 2) AS avg_monthly_charge
FROM customers
GROUP BY plan_type
ORDER BY churn_rate_pct DESC;
 
-- is plan_type just standing in for "new customer"? no -- churn still
-- diverges sharply by plan even among 4+ year customers
SELECT
    plan_type,
    CASE
        WHEN tenure_months <= 6 THEN '0-6 mo'
        WHEN tenure_months <= 12 THEN '6-12 mo'
        WHEN tenure_months <= 24 THEN '1-2 yr'
        WHEN tenure_months <= 48 THEN '2-4 yr'
        ELSE '4+ yr'
    END AS tenure_bucket,
    COUNT(*) AS n_customers,
    SUM(Churned) AS churned,
    ROUND(100.0 * SUM(Churned) / COUNT(*), 1) AS churn_rate_pct
FROM customers
GROUP BY plan_type, tenure_bucket
ORDER BY plan_type, MIN(tenure_months);
 
-- ============================================================
-- 4. BEHAVIORAL DRIVERS
-- ============================================================
 
SELECT
    TechSupport,
    OnlineSecurity,
    COUNT(*) AS n_customers,
    SUM(Churned) AS churned,
    ROUND(100.0 * SUM(Churned) / COUNT(*), 1) AS churn_rate_pct
FROM customers
GROUP BY TechSupport, OnlineSecurity
ORDER BY churn_rate_pct DESC;
 
SELECT
    PaymentMethod,
    COUNT(*) AS n_customers,
    SUM(Churned) AS churned,
    ROUND(100.0 * SUM(Churned) / COUNT(*), 1) AS churn_rate_pct
FROM customers
GROUP BY PaymentMethod
ORDER BY churn_rate_pct DESC;
 
-- electronic check stays elevated at every contract tier -- not just riding
-- on month-to-month being oversampled there
SELECT
    PaymentMethod,
    plan_type,
    COUNT(*) AS n_customers,
    SUM(Churned) AS churned,
    ROUND(100.0 * SUM(Churned) / COUNT(*), 1) AS churn_rate_pct
FROM customers
GROUP BY PaymentMethod, plan_type
ORDER BY PaymentMethod, churn_rate_pct DESC;
 
SELECT
    internet_type,
    COUNT(*) AS n_customers,
    SUM(Churned) AS churned,
    ROUND(100.0 * SUM(Churned) / COUNT(*), 1) AS churn_rate_pct
FROM customers
GROUP BY internet_type
ORDER BY churn_rate_pct DESC;
 
-- add-on depth vs churn, restricted to internet subscribers -- phone-only
-- customers have no internet add-ons and a much lower baseline churn rate,
-- so leaving them in muddies the read on "zero add-ons"
SELECT
    (OnlineSecurity='Yes') + (OnlineBackup='Yes') + (DeviceProtection='Yes') +
    (TechSupport='Yes') + (StreamingTV='Yes') + (StreamingMovies='Yes') AS addon_count,
    COUNT(*) AS n_customers,
    SUM(Churned) AS churned,
    ROUND(100.0 * SUM(Churned) / COUNT(*), 1) AS churn_rate_pct
FROM customers
WHERE internet_type != 'No'
GROUP BY addon_count
ORDER BY addon_count;
 
SELECT
    SeniorCitizen,
    PaperlessBilling,
    COUNT(*) AS n_customers,
    SUM(Churned) AS churned,
    ROUND(100.0 * SUM(Churned) / COUNT(*), 1) AS churn_rate_pct
FROM customers
GROUP BY SeniorCitizen, PaperlessBilling
ORDER BY churn_rate_pct DESC;
 
-- checked, no material independent signal beyond what's above:
-- gender, Partner, Dependents
 
-- ============================================================
-- 5. RISK SCORE
-- ============================================================
 
-- five independently-validated factors, +1 each
SELECT
    (plan_type = 'Month-to-month') +
    (PaymentMethod = 'Electronic check') +
    (TechSupport = 'No') +
    (OnlineSecurity = 'No') +
    (tenure_months <= 12) AS risk_score,
    COUNT(*) AS n_customers,
    SUM(Churned) AS churned,
    ROUND(100.0 * SUM(Churned) / COUNT(*), 1) AS churn_rate_pct
FROM customers
GROUP BY risk_score
ORDER BY risk_score;
 
CREATE OR REPLACE VIEW customer_risk AS
SELECT
    customerID,
    plan_type,
    PaymentMethod,
    TechSupport,
    OnlineSecurity,
    internet_type,
    tenure_months,
    CASE
        WHEN tenure_months <= 6 THEN '0-6 mo'
        WHEN tenure_months <= 12 THEN '6-12 mo'
        WHEN tenure_months <= 24 THEN '1-2 yr'
        WHEN tenure_months <= 48 THEN '2-4 yr'
        ELSE '4+ yr'
    END AS tenure_bucket,
    MonthlyCharges,
    Churned,
    (plan_type = 'Month-to-month') +
    (PaymentMethod = 'Electronic check') +
    (TechSupport = 'No') +
    (OnlineSecurity = 'No') +
    (tenure_months <= 12) AS risk_score
FROM customers;
 
-- watchlist -- active customers, top tiers, ranked within each tier
SELECT
    customerID,
    risk_score,
    tenure_months,
    MonthlyCharges,
    plan_type,
    PaymentMethod,
    RANK() OVER (PARTITION BY risk_score ORDER BY MonthlyCharges DESC) AS rank_within_tier
FROM customer_risk
WHERE Churned = 0 AND risk_score >= 3
ORDER BY risk_score DESC, rank_within_tier;
 
-- ============================================================
-- 6. REVENUE IMPACT
-- ============================================================
 
WITH tier_rates AS (
    SELECT risk_score,
           ROUND(100.0 * SUM(Churned) / COUNT(*), 1) AS churn_rate_pct
    FROM customer_risk
    GROUP BY risk_score
)
SELECT
    cr.risk_score,
    COUNT(*) AS active_customers,
    ROUND(SUM(cr.MonthlyCharges), 2) AS monthly_revenue_active,
    tr.churn_rate_pct,
    ROUND(SUM(cr.MonthlyCharges) * tr.churn_rate_pct / 100, 2) AS expected_monthly_revenue_loss
FROM customer_risk cr
JOIN tier_rates tr ON cr.risk_score = tr.risk_score
WHERE cr.Churned = 0
GROUP BY cr.risk_score, tr.churn_rate_pct
ORDER BY cr.risk_score;
 
DELIMITER //
 
CREATE PROCEDURE breakeven_analysis(
    IN discount_cost DECIMAL(6,2),
    IN effectiveness DECIMAL(4,2)
)
BEGIN
    WITH tier_rates AS (
        SELECT risk_score,
               ROUND(100.0 * SUM(Churned) / COUNT(*), 1) AS churn_rate_pct
        FROM customer_risk
        GROUP BY risk_score
    ),
    tier_loss AS (
        SELECT cr.risk_score,
               COUNT(*) AS active_customers,
               ROUND(SUM(cr.MonthlyCharges) * tr.churn_rate_pct / 100, 2) AS expected_monthly_revenue_loss
        FROM customer_risk cr
        JOIN tier_rates tr ON cr.risk_score = tr.risk_score
        WHERE cr.Churned = 0
        GROUP BY cr.risk_score
    )
    SELECT
        risk_score,
        active_customers,
        ROUND(active_customers * discount_cost, 2) AS campaign_cost,
        expected_monthly_revenue_loss,
        ROUND(expected_monthly_revenue_loss * effectiveness, 2) AS expected_revenue_saved,
        ROUND(expected_monthly_revenue_loss * effectiveness - active_customers * discount_cost, 2) AS net_monthly_impact
    FROM tier_loss
    ORDER BY risk_score;
END //
 
DELIMITER ;
 
-- CALL breakeven_analysis(15, 0.30);  -- optimistic case
-- CALL breakeven_analysis(5, 0.15);   -- conservative case, still nets positive on tiers 4-5
 
-- ============================================================
-- 7. EXTRAS (subqueries, for the record)
-- ============================================================
 
-- correlated subquery: customers paying above their own plan's average
SELECT
    c.customerID,
    c.plan_type,
    c.MonthlyCharges,
    c.Churned
FROM customers c
WHERE c.MonthlyCharges > (
    SELECT AVG(MonthlyCharges) FROM customers c2 WHERE c2.plan_type = c.plan_type
)
ORDER BY c.plan_type, c.MonthlyCharges DESC
LIMIT 15;
 
-- payment methods above the (dynamically computed) overall churn rate
SELECT PaymentMethod, COUNT(*) AS n, ROUND(100.0*SUM(Churned)/COUNT(*),1) AS churn_rate_pct
FROM customers
WHERE PaymentMethod IN (
    SELECT PaymentMethod FROM customers
    GROUP BY PaymentMethod
    HAVING SUM(Churned)/COUNT(*) > (SELECT AVG(Churned) FROM customers)
)
GROUP BY PaymentMethod
ORDER BY churn_rate_pct DESC;