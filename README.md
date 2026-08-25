# Telecom Customer Churn & Retention Risk

SQL-based churn analysis and an interactive Tableau dashboard for a telecom customer base of 7,043 accounts. Built to answer three questions: who is most likely to churn, when they churn, and what behavioral signals predict it early enough to act on.

**[Live dashboard →](https://public.tableau.com/app/profile/cristian.garcia3939/viz/TelecomCustomerChurnDashboard_17875771165110/Overview?publish=yes)**

## Dataset

[IBM Telco Customer Churn](https://www.kaggle.com/datasets/blastchar/telco-customer-churn) (via Kaggle). 7,043 customers, single quarterly snapshot — no date field, no churn-reason field. Every finding here is inferred from correlation and cross-checked for confounding, not confirmed against a labeled cause.

## Screenshots

**Overview dashboard**
![Overview](screenshots/01_overview_dashboard.png)

**Customer drill-down — click any row in the watchlist, get a full risk profile**
![Customer Detail](screenshots/02_customer_detail.png)

**Churn by tenure — the clearest single finding in the dataset**
![Churn by Tenure](screenshots/04_churn_by_tenure.png)

## Files

- `telecom_churn_analysis.sql` — full analysis: schema, validation, segmentation, risk scoring, revenue impact, breakeven modeling
- `README.md` — this file
- `screenshots/` — dashboard captures

## Headline numbers

- Overall churn rate: **26.54%**
- Churn in the first 6 months: **52.9%**, vs. **9.5%** at 4+ years — a 5.5x gap
- Month-to-month contracts churn at **42.7%**, two-year contracts at **2.8%**
- Customers with no tech support and no online security churn at **49.0%**, vs. **9.0%** for customers with both
- Electronic check payment churns at **45.3%** — and stays elevated at every contract tier, so it isn't just riding on month-to-month customers being overrepresented in that group

## Methodology

**Validation first.** Checked for duplicate customer IDs, nulls across every field used in the analysis, and out-of-range values (negative tenure, non-binary churn flags) before running any segmentation. All clean.

**Confound testing, not just correlation.** A few findings only look real until you control for the obvious alternative explanation:

- Plan type could just be a proxy for "new customer," since new signups default to month-to-month. Tested by holding tenure constant — month-to-month customers still churn at 26.0% even past 4 years, vs. 3.3% for two-year customers in the same tenure bracket. The effect is real and independent of tenure.
- Electronic check could be a proxy for "low commitment," since it correlates with month-to-month. Tested by holding plan type constant — electronic check stays roughly 2x higher than other payment methods within every contract tier, including two-year. Independent effect, likely payment friction rather than pure self-selection.
- Add-on count initially looked non-monotonic (0 add-ons churned *less* than 1 add-on) — turned out to be Simpson's paradox: phone-only customers with no internet were getting counted as "0 add-ons" alongside genuinely disengaged internet subscribers, and phone-only customers have a much lower baseline churn rate. Restricting to internet subscribers only produced a clean line from 52.2% (0 add-ons) down to 5.3% (6 add-ons).

**Checked, no material independent signal found:** gender, Partner, Dependents, senior citizen status (senior citizen does move churn ~15pts in combination with paperless billing, but doesn't add signal beyond what tenure/plan/support already explain on its own).

**No synthetic fields.** An earlier version of this project used a randomly-generated region field to test geographic segmentation — the dataset has no real geography. Dropped it. Every dimension in the final analysis is a real column.

## Risk score

Five factors, validated independently in the confound testing above, combined additively:

- Month-to-month plan
- Electronic check payment
- No tech support
- No online security
- Tenure ≤ 12 months

| Risk score | Churn rate |
|---|---|
| 0 | 3.0% |
| 1 | 7.3% |
| 2 | 19.5% |
| 3 | 33.2% |
| 4 | 51.9% |
| 5 | 69.8% |

Clean, monotonic climb — a customer with all five factors present is roughly 23x more likely to churn than one with none. Built as a SQL view (`customer_risk`) so it's queryable directly rather than recomputed per-query.

## Revenue impact

Raw dollars sitting in a risk tier isn't the same as *expected* loss — a dollar at 3% churn risk and a dollar at 70% churn risk aren't equally at stake. Weighted each tier's active revenue by its own churn probability:

**Total expected monthly revenue loss across the active book: ~$67,959**, with tiers 3–5 (1,525 active accounts) accounting for roughly $48,000 of that.

## Should you run a retention campaign?

Built a stored procedure (`breakeven_analysis`) that takes a cost-per-account and an assumed effectiveness rate, and returns net monthly impact per tier — so the answer isn't a guess, it's a parameterized calculation.

At an optimistic 30% effectiveness assumption, a $15/month discount is barely profitable even on the highest-risk tier. At a more conservative 15% effectiveness assumption, a $5/month offer nets positive specifically on tiers 4 and 5.

**Recommendation:** don't roll out a blanket discount campaign. Effectiveness is the one number in this whole model that can't be verified from historical data — it has to be measured. Pilot a $5–7/month loyalty credit on tier 5 (222 accounts, cheapest to test, clearest signal), measure the actual churn reduction over 60–90 days, then decide whether to extend to tiers 3–4 using the real number instead of an assumption. For tiers 0–2, a discount isn't worth it — the breakeven cost is under $2/month. A free tech support onboarding call is cheaper and targets a factor we already know is predictive.

## SQL techniques used

Window functions (`RANK() OVER PARTITION BY`), correlated and non-correlated subqueries, views, a stored procedure with parameters, indexing with `EXPLAIN` verification, and CTEs (including chained CTEs feeding a join). All in `telecom_churn_analysis.sql`.

## Tools

MySQL 8.0, Tableau Public.
