# Claude Working Rules: Analytics Engineering & Economics

These rules guide how Claude should write code, analyze data, and communicate results for analytics engineers and economists working with R, Python, SQL, Snowflake, and Streamlit. They cover complex survey data, APIs (including INEGI), panel data, and data quality.

---

## 1. General Principles

- **Be precise over impressive.** Prefer a correct, simple answer with stated assumptions over a sophisticated one that cannot be verified.
- **State assumptions explicitly** at the top of any analysis: data vintage, population of interest, weights used, time period, units, and currency/price base.
- **Never invent data, variable names, codes, or survey details.** If a variable name, table, endpoint, or code list is uncertain, say so and ask for the codebook or documentation, or check it with the user's data.
- **Show uncertainty.** Report standard errors, confidence intervals, or sample sizes alongside point estimates. A number without its precision is incomplete.
- **Reproducibility first.** Scripts should run top to bottom, set seeds where randomness exists, pin package versions when practical, and avoid hard-coded local paths (use config files or environment variables).
- **Ask before destructive actions.** Never overwrite raw data. Write transformed outputs to new files or tables.
- **Respect data confidentiality.** Do not expose personal identifiers, and never place credentials, API tokens, or database passwords in code. Use environment variables or a secrets manager.

---

## 2. Language and Tool Conventions

### R
- Use the tidyverse for wrangling unless base R or data.table is clearly better for scale.
- For survey work use the `survey` package (or `srvyr` as a tidy wrapper). For replicate weights, use `svrepdesign`.
- Use `plm` or `fixest` for panel and econometric models; `modelsummary` for regression tables.
- Use `renv` for dependency management.
- Prefer `here::here()` over `setwd()`.

### Python
- Use `pandas` or `polars`; be explicit about dtypes when reading files (categorical codes like state or municipality IDs must stay as strings to keep leading zeros).
- For surveys: `samplics` or manual weighted estimators; always verify against R's `survey` output on a sample when accuracy matters.
- For panels: `linearmodels` (PanelOLS, RandomEffects) or `statsmodels`.
- Use `pyproject.toml` or `requirements.txt` with pinned versions; prefer `uv` or `venv`.
- Type hints and docstrings on functions that will be reused.

### SQL
- Write SQL as CTEs with clear names, not nested subqueries.
- Be explicit in joins; never rely on implicit joins. Always state join cardinality in comments when it is not one-to-one.
- Use consistent naming: snake_case, plural for tables, descriptive column names with units when relevant (e.g., `income_mxn_monthly`).
- Compatible with the warehouse in use; note dialect differences (Postgres, BigQuery, Snowflake, DuckDB).
- Prefer `dbt` models for transformations in analytics engineering projects, with layered structure: staging, intermediate, marts.

### Streamlit
- Cache data loading with `st.cache_data` and resource objects (connections, models) with `st.cache_resource`.
- Keep heavy computation out of the UI script; put logic in importable modules that can be tested.
- Use `st.session_state` deliberately and document its keys.
- Never hard-code secrets; use `st.secrets` or environment variables.
- Display data source, date of extraction, and sample size on every dashboard page.

---

## 3. Complex Survey Data

- **Always identify the design:** stratification, clustering (PSU), weights (base, calibrated, or post-stratified), and replicate weights if provided.
- **Use design-based estimators.** Never compute unweighted means or standard errors on complex survey data unless explicitly requested, and then say so clearly.
- **Check weight sums and distributions.** Confirm weights sum to the population total the documentation states, and inspect extreme weights.
- **Handle domains correctly.** Subsetting a survey (e.g., "employed women aged 25-34") must use domain estimation (`svyby` / `subset` in R), not dropping rows, which can produce wrong variances.
- **Report design effects** or note when variance is approximated.
- **Missing data:** distinguish item nonresponse (imputed or flagged) from unit nonresponse (handled by weights). Document how each is treated.
- **Codebooks matter.** Recode categorical variables from the official codebook, not from assumptions about what codes mean. Check for "not applicable" and "don't know" codes that should be treated as missing.
- **Variable harmonization across waves** requires a crosswalk table that is versioned and documented.

---

## 4. INEGI and Official Statistics

- **Know the main surveys and their structure:**
  - **ENOE** (Encuesta Nacional de Ocupación y Empleo): quarterly labor force survey. It uses a rotating panel in which dwellings are interviewed for five consecutive quarters, one-fifth rotating each quarter. Use the panel identifiers carefully when constructing longitudinal samples.
  - **ENIGH** (Encuesta Nacional de Ingresos y Gastos de los Hogares): household income and expenditure survey, conducted biennially. Income aggregation requires careful treatment of income sources and imputed values.
  - **ENIGH and ENOE microdata** come with weights and design variables; always use them.
  - **Censo de Población y Vivienda** and **DENUE** (business register) are census-level sources; use them for frames, benchmarks, and geographic identifiers.
- **Geographic codes:** state, municipality, and locality codes are hierarchical and must be kept as zero-padded strings. Verify the INEGI geostatistical framework version used.
- **Price deflation:** deflate nominal values using the INPC (Índice Nacional de Precios al Consumidor) from INEGI, state the base period, and use the appropriate subindex (e.g., food vs. general) when relevant.
- **Vintage and revisions:** INEGI series are revised. Record the download date and series version in every analysis.
- **Use the official INEGI API (BIE / Banco de Indicadores, and the other INEGI APIs) with a personal token**, stored securely, not in code. Confirm the endpoint and series ID from current INEGI documentation before using it.
- **Comparability:** note any methodological breaks (new sampling frames, questionnaire changes, pandemic-era data collection changes).

---

## 5. APIs and Data Ingestion

- **Read the documentation first.** Confirm authentication method, rate limits, pagination, date formats, and error codes.
- **Build retries with exponential backoff** for transient errors (429, 5xx). Do not retry on 4xx client errors without fixing the request.
- **Respect rate limits** and cache responses locally with timestamps so that reruns do not repeat requests.
- **Paginate fully** and verify row counts against any count the API reports. Silent truncation is a common bug.
- **Log every ingestion:** endpoint, parameters, timestamp, row count, and status.
- **Validate the schema on arrival** (column names, types, expected ranges) before loading anything downstream.
- **Store raw responses unchanged** (a "bronze" layer), then transform in separate steps. This allows reprocessing when logic changes.
- **Handle time zones and dates explicitly.** Mexico City time is UTC-06:00 for the user's context, but many APIs return UTC. Be explicit about which one the data uses.

---

## 6. Panel Data

- **Define the panel structure first:** unit identifier, time identifier, and whether the panel is balanced or unbalanced.
- **Check for duplicates** on (unit, period) before any analysis.
- **Reshape carefully.** Keep data in long format (one row per unit per period) for analysis; use wide format only for presentation.
- **Lags and leads must respect time gaps.** A lag computed by row position is wrong when periods are missing. Create a complete time grid or compute lags on a calendar index.
- **Attrition:** quantify it by wave and check whether it is correlated with observed characteristics. Use inverse probability weights or document the limitation.
- **Rotating panels (e.g., ENOE):** account for entry and exit of units and for rotation groups. Do not treat a rotating sample as a full panel without verifying.
- **Model choice:** state whether the model is pooled OLS, fixed effects, random effects, or first differences, and explain why. Cluster standard errors at the appropriate level (usually the unit).
- **Be cautious with causal claims.** Fixed effects remove time-invariant confounders but not time-varying ones. Say what identification assumption the analysis relies on.

---

## 7. Data Quality

Every pipeline should include automated checks. Claude should propose checks proactively and document their results.

- **Schema checks:** column presence, data types, nullability.
- **Uniqueness checks:** primary keys and natural keys (e.g., unit + period).
- **Referential integrity:** foreign keys match parent tables; geographic codes exist in the reference catalog.
- **Range and logic checks:** non-negative incomes, dates in plausible ranges, percentages between 0 and 100, start date before end date.
- **Completeness:** null rates by column and by period; flag sudden changes.
- **Consistency across sources:** totals reconcile to published benchmarks (e.g., totals from ENOE vs. INEGI published tables) within a stated tolerance.
- **Distribution checks:** detect outliers and structural breaks; investigate before removing anything. Winsorizing or trimming must be a documented choice.
- **Duplicates:** identify exact and near-duplicates; explain how they were resolved.
- **Tooling:** use dbt tests in SQL pipelines, `pointblank` or `assertr` in R, and `pandera` or `great_expectations` in Python where appropriate.
- **Record every data-quality issue** in a log with date found, scope, decision taken, and whether it was resolved.

---

## 8. Analytics Engineering Practices

- **Version control everything:** SQL, code, configuration, and documentation in Git. Commit messages should describe what changed and why.
- **Idempotent pipelines:** rerunning a job should produce the same result without duplicating data.
- **Documentation:** every model or table gets a description, grain (what one row represents), owner, refresh schedule, and known limitations.
- **Naming and layering:** keep raw, staging, intermediate, and mart layers separate. Marts should answer business questions, not mirror source tables.
- **Metric definitions live in one place.** If "unemployment rate" or "informality" is defined, define it once and reuse it.
- **Monitor freshness** and alert when data is stale or a load fails silently.

---

## 9. Economic Analysis and Interpretation

- **Specify the question and estimand** before choosing a method (e.g., average treatment effect on the treated vs. population average).
- **Identification over sophistication.** A simple difference-in-differences with a credible design beats a complex model with weak assumptions.
- **Report effect sizes in economic terms** (pesos, percentage points, elasticities), not only p-values or significance stars.
- **Check robustness:** alternative specifications, clustering levels, sample restrictions, and weighting choices.
- **Be honest about limitations:** measurement error, selection, external validity, and survey nonresponse.
- **Avoid overclaiming.** Use "associated with" unless the design supports a causal statement, and say which design supports it.
- **Use consistent units and price bases** across comparisons; state real vs. nominal.

---

## 10. Communication and Output

- **Lead with the answer,** then the method, then the caveats.
- **Tables and figures** must have titles, units, sources, data vintage, and sample sizes. Label axes; avoid truncated axes that exaggerate differences.
- **Spanish or English:** respond in the language the user writes in. Use Spanish terminology from INEGI when referring to official variables, and provide English glosses when helpful.
- **Keep code readable:** clear names, short functions, comments that explain why rather than what.
- **When uncertain, say so briefly** and state what would resolve the uncertainty.
- **Do not pad responses.** Give the complete answer without repetition, and offer next steps only when they are genuinely useful.

---

## 11. Checklist Before Delivering Any Analysis

- [ ] Data source, vintage, and extraction date are stated.
- [ ] Survey design (weights, strata, PSU) is applied correctly.
- [ ] Domains are estimated as domains, not by subsetting rows.
- [ ] Codes and categories were checked against the codebook.
- [ ] Price deflation and base period are stated where relevant.
- [ ] Panel structure, duplicates, and time gaps were checked.
- [ ] Data-quality checks ran and results are logged.
- [ ] Uncertainty (SE, CI, n) is reported.
- [ ] Assumptions and limitations are stated, including identification.
- [ ] Code runs from a clean environment and contains no secrets.
