-- Check column data types
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'ph_db'
ORDER BY table_name, ordinal_position;


-- Create CTEs to pull impressions, signups, and claim amounts per campaign category
WITH impressions AS(
	SELECT campaign_category, SUM(impressions) AS total_impressions
	FROM ph_db.campaigns
	GROUP BY 1), 

signups AS(
	SELECT campaign_category, COUNT(DISTINCT customer_id) AS total_signups
	FROM ph_db.customers
	LEFT JOIN ph_db.campaigns ON customers.campaign_id = campaigns.campaign_id
	GROUP BY 1), 

claims AS(
	SELECT campaign_category, ROUND(SUM(claim_amount),2) AS total_claim_amount
	FROM ph_db.claims
	LEFT JOIN ph_db.customers ON claims.customer_id = customers.customer_id
	LEFT JOIN ph_db.campaigns ON customers.campaign_id = campaigns.campaign_id
	GROUP BY 1)
	-- ,

-- totals AS(
	SELECT campaign_category, total_impressions, total_signups, total_claim_amount
	FROM claims
	LEFT JOIN signups USING(campaign_category)
	LEFT JOIN impressions USING(campaign_category)
	ORDER BY 2 DESC NULLS LAST
	-- )
-- Show average total impressions
-- SELECT ROUND(AVG(total_impressions),2)
-- FROM totals
;

-- Calculate cost-per-signup
WITH costs AS(
	SELECT campaign_category, ROUND(SUM(campaigns.cost),2) AS total_cost
	FROM ph_db.campaigns
	GROUP BY 1),
signups AS(
	SELECT campaign_category, COUNT(DISTINCT customer_id) AS total_signups
	FROM ph_db.customers
	LEFT JOIN ph_db.campaigns ON customers.campaign_id = campaigns.campaign_id
	GROUP BY 1)
SELECT campaign_category, total_cost, total_signups, ROUND(total_cost/total_signups,2) AS CPS
FROM signups
LEFT JOIN costs USING(campaign_category)
ORDER BY 4;

DROP MATERIALIZED VIEW IF EXISTS ph_db.base_metrics;

-- Create a table that combines claims, signup, cost, and impressions metrics
CREATE MATERIALIZED VIEW ph_db.base_metrics AS
-- Calculate claim amount and number of claims per campaign category
WITH claims AS(
	SELECT campaign_category, 
		COUNT(claim_id) AS total_claim_count, 
		ROUND(AVG(claim_amount),2) AS avg_claim_amount,
		ROUND(SUM(claim_amount),2) AS total_claim_amount
	FROM ph_db.claims
	LEFT JOIN ph_db.customers ON claims.customer_id = customers.customer_id
	LEFT JOIN ph_db.campaigns ON customers.campaign_id = campaigns.campaign_id
	GROUP BY 1),
-- Calculate total signups per campaign category
signups AS(
	SELECT campaign_category, COUNT(DISTINCT customers.customer_id) AS total_signups
	FROM ph_db.customers
	LEFT JOIN ph_db.campaigns ON customers.campaign_id = campaigns.campaign_id
	GROUP BY 1),
-- Calculate total cost and total impressions per campaign category
cost_clicks_impressions AS(
	SELECT campaign_category, 
		ROUND(SUM(cost),2) AS total_cost,
		SUM(clicks) AS total_clicks,
		SUM(impressions) AS total_impressions
	FROM ph_db.campaigns
	GROUP BY 1),
-- Calculate signup rate, cost-per-signup, click-through-rate, cost-per-click
normalized_metrics AS(
	SELECT *, 
		ROUND(CAST(total_signups AS DECIMAL)/total_impressions*100, 2) AS signup_rate_percent, 
		ROUND(total_cost/total_signups,2) AS CPS,
		ROUND(total_clicks/total_impressions*100,2) AS CTR_percent,
		ROUND(total_cost/total_clicks,2) AS CPC
	FROM claims
	FULL JOIN signups USING(campaign_category)
	FULL JOIN cost_clicks_impressions USING(campaign_category))

-- CPS comparison across campaign categories
SELECT *, 
	LAG(cps) OVER(ORDER BY cps) AS previous_cps,
	cps - LAG(cps) OVER(ORDER BY cps) AS cps_diff,
	ROUND((cps - LAG(cps) OVER(ORDER BY cps)) / LAG(cps) OVER(ORDER BY cps) * 100, 1) AS cps_percent_diff
FROM normalized_metrics
GROUP BY campaign_category
ORDER BY cps;

SELECT * FROM ph_db.base_metrics;

-- Bring in time dimension to evaluate signups
WITH ranked_signups AS(
SELECT campaign_category, 
		DATE_TRUNC('year', signup_date) AS signup_year, 
		COUNT(DISTINCT customer_id) AS signups,
		DENSE_RANK() OVER(PARTITION BY DATE_TRUNC('year', signup_date) ORDER BY COUNT(DISTINCT customer_id) DESC) AS ranking
FROM ph_db.customers
LEFT JOIN ph_db.campaigns ON customers.campaign_id = campaigns.campaign_id
GROUP BY 1,2)

SELECT campaign_category, signup_year, signups
FROM ranked_signups
WHERE ranking <= 3
ORDER BY 2,3 DESC;




