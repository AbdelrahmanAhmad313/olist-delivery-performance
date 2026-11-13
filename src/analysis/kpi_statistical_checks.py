"""
Phase 4: Python Statistical Checks
- Bootstrap confidence intervals for key KPIs
- Logistic regression: late delivery -> low review (1-2 stars)
- Two-proportion z-test: late vs on-time low review rates

Run after fact_orders table exists in database.

Dependencies (install if needed):
    pip install pyodbc pandas numpy scipy statsmodels scikit-learn

Or if pyodbc fails, try:
    pip install pymssql sqlalchemy
"""

import pandas as pd
import numpy as np
import warnings
warnings.filterwarnings('ignore')

# ============================================================
# DATABASE CONNECTION - Multiple fallback options
# ============================================================
# UPDATE THESE FOR YOUR ENVIRONMENT
SERVER = r'.\SQLEXPRESS'         # or your SQL Server instance
DATABASE = 'ecommerce_analytics'
DRIVER = 'SQL Server'  # or '{SQL Server}'

# Option A: Windows Authentication (Trusted Connection) - pyodbc
CONN_STR_PYODBC = f'DRIVER={DRIVER};SERVER={SERVER};DATABASE={DATABASE};Trusted_Connection=yes;'

# Option B: SQL Authentication - pyodbc
# CONN_STR_PYODBC = f'DRIVER={DRIVER};SERVER={SERVER};DATABASE={DATABASE};UID=your_user;PWD=your_password'

# Option C: SQLAlchemy + pymssql (if pyodbc fails)
# CONN_STR_SQLALCHEMY = 'mssql+pymssql://user:password@localhost/ecommerce_analytics'
# CONN_STR_SQLALCHEMY = 'mssql+pymssql://@localhost/ecommerce_analytics?trusted_connection=yes'


def get_connection_pyodbc():
    """Try pyodbc connection."""
    try:
        import pyodbc
        conn = pyodbc.connect(CONN_STR_PYODBC)
        print("Connected via pyodbc")
        return conn
    except ImportError:
        print("pyodbc not installed. Try: pip install pyodbc")
        return None
    except Exception as e:
        print(f"pyodbc connection failed: {e}")
        return None


def get_connection_sqlalchemy():
    """Try SQLAlchemy + pymssql connection."""
    try:
        from sqlalchemy import create_engine
        # Try trusted connection first
        engine = create_engine('mssql+pymssql://@localhost/ecommerce_analytics?trusted_connection=yes')
        with engine.connect() as conn:
            print("Connected via SQLAlchemy + pymssql (trusted)")
        return engine
    except Exception as e1:
        try:
            # Try with explicit credentials (update as needed)
            engine = create_engine('mssql+pymssql://user:password@localhost/ecommerce_analytics')
            with engine.connect() as conn:
                print("Connected via SQLAlchemy + pymssql (SQL auth)")
            return engine
        except Exception as e2:
            print(f"SQLAlchemy connection failed: {e2}")
            return None


def load_fact_orders():
    """Load fact_orders table into DataFrame with multiple fallback options."""

    # Try pyodbc first
    conn = get_connection_pyodbc()
    if conn:
        try:
            df = pd.read_sql("SELECT * FROM fact_orders", conn)
            conn.close()
            print(f"Loaded {len(df):,} rows from fact_orders")
            return df
        except Exception as e:
            print(f"pyodbc query failed: {e}")

    # Try SQLAlchemy
    engine = get_connection_sqlalchemy()
    if engine:
        try:
            df = pd.read_sql("SELECT * FROM fact_orders", engine)
            print(f"Loaded {len(df):,} rows from fact_orders")
            return df
        except Exception as e:
            print(f"SQLAlchemy query failed: {e}")

    # Fallback: try to load from CSV if exists (for testing)
    csv_path = 'fact_orders_export.csv'
    try:
        df = pd.read_csv(csv_path)
        print(f"Loaded {len(df):,} rows from CSV fallback: {csv_path}")
        return df
    except FileNotFoundError:
        pass

    raise ConnectionError("""
Could not connect to database. Options:
1. Install pyodbc: pip install pyodbc
   - Ensure ODBC Driver 17 for SQL Server is installed
2. Install pymssql + sqlalchemy: pip install pymssql sqlalchemy
3. Export fact_orders to CSV and place as 'fact_orders_export.csv' in project root
4. Update connection strings at top of this file (SERVER, DATABASE, DRIVER)
""")


# ============================================================
# BOOTSTRAP CONFIDENCE INTERVALS (pure numpy - no extra deps)
# ============================================================
def bootstrap_ci(data, statistic_func, n_bootstrap=10000, confidence=0.95, random_state=42):
    """Generic bootstrap confidence interval."""
    np.random.seed(random_state)
    data = np.asarray(data)
    n = len(data)

    point_est = statistic_func(data)
    bootstrap_stats = []

    for _ in range(n_bootstrap):
        sample = data[np.random.choice(n, n, replace=True)]
        bootstrap_stats.append(statistic_func(sample))

    bootstrap_stats = np.array(bootstrap_stats)
    alpha = (1 - confidence) / 2
    ci_lower = np.percentile(bootstrap_stats, 100 * alpha)
    ci_upper = np.percentile(bootstrap_stats, 100 * (1 - alpha))

    return point_est, ci_lower, ci_upper


def bootstrap_ci_ratio(numerator_mask, denominator_mask, n_bootstrap=10000, confidence=0.95, random_state=42):
    """Bootstrap CI for a ratio (e.g., late rate = late_orders / total_orders)."""
    np.random.seed(random_state)
    num = np.asarray(numerator_mask, dtype=float)
    den = np.asarray(denominator_mask, dtype=float)
    n = len(num)

    point_est = num.sum() / den.sum() if den.sum() > 0 else 0
    bootstrap_ratios = []

    for _ in range(n_bootstrap):
        idx = np.random.choice(n, n, replace=True)
        boot_num = num[idx].sum()
        boot_den = den[idx].sum()
        if boot_den > 0:
            bootstrap_ratios.append(boot_num / boot_den)

    if not bootstrap_ratios:
        return point_est, 0, 0

    bootstrap_ratios = np.array(bootstrap_ratios)
    alpha = (1 - confidence) / 2
    ci_lower = np.percentile(bootstrap_ratios, 100 * alpha)
    ci_upper = np.percentile(bootstrap_ratios, 100 * (1 - alpha))

    return point_est, ci_lower, ci_upper


def run_bootstrap_kpis(df):
    """Run bootstrap CIs for key KPIs."""
    print("\n" + "="*60)
    print("BOOTSTRAP CONFIDENCE INTERVALS (95%)")
    print("="*60)

    results = []

    # 1. Late Rate
    late_rate, ci_l, ci_u = bootstrap_ci_ratio(
        df['is_late'], np.ones(len(df)), n_bootstrap=5000
    )
    results.append(('Late Rate', late_rate, ci_l, ci_u))
    print(f"Late Rate:           {late_rate:.4f}  [{ci_l:.4f}, {ci_u:.4f}]")

    # 2. On-Time Rate
    on_time_rate, ci_l, ci_u = bootstrap_ci_ratio(
        1 - df['is_late'], np.ones(len(df)), n_bootstrap=5000
    )
    results.append(('On-Time Rate', on_time_rate, ci_l, ci_u))
    print(f"On-Time Rate:        {on_time_rate:.4f}  [{ci_l:.4f}, {ci_u:.4f}]")

    # 3. Avg Review Score (Late)
    late_reviews = df.loc[df['is_late'] == 1, 'review_score'].dropna()
    if len(late_reviews) > 0:
        mean_late, ci_l, ci_u = bootstrap_ci(late_reviews, np.mean, n_bootstrap=5000)
        results.append(('Avg Review Score (Late)', mean_late, ci_l, ci_u))
        print(f"Avg Review (Late):   {mean_late:.4f}  [{ci_l:.4f}, {ci_u:.4f}]  n={len(late_reviews)}")

    # 4. Avg Review Score (On-Time)
    on_time_reviews = df.loc[df['is_late'] == 0, 'review_score'].dropna()
    if len(on_time_reviews) > 0:
        mean_ot, ci_l, ci_u = bootstrap_ci(on_time_reviews, np.mean, n_bootstrap=5000)
        results.append(('Avg Review Score (On-Time)', mean_ot, ci_l, ci_u))
        print(f"Avg Review (On-Time):{mean_ot:.4f}  [{ci_l:.4f}, {ci_u:.4f}]  n={len(on_time_reviews)}")

    # 5. Low Review Rate (Late)
    late_mask = (df['is_late'] == 1) & (df['review_score'].notna())
    late_low_mask = (df['is_late'] == 1) & (df['review_score'].isin([1, 2]))
    late_total = late_mask.sum()
    if late_total > 0:
        rate_late, ci_l, ci_u = bootstrap_ci_ratio(late_low_mask, late_mask, n_bootstrap=5000)
        results.append(('Low Review Rate (Late)', rate_late, ci_l, ci_u))
        print(f"Low Review (Late):   {rate_late:.4f}  [{ci_l:.4f}, {ci_u:.4f}]  n={int(late_total)}")

    # 6. Low Review Rate (On-Time)
    ot_mask = (df['is_late'] == 0) & (df['review_score'].notna())
    ot_low_mask = (df['is_late'] == 0) & (df['review_score'].isin([1, 2]))
    ot_total = ot_mask.sum()
    if ot_total > 0:
        rate_ot, ci_l, ci_u = bootstrap_ci_ratio(ot_low_mask, ot_mask, n_bootstrap=5000)
        results.append(('Low Review Rate (On-Time)', rate_ot, ci_l, ci_u))
        print(f"Low Review (On-Time):{rate_ot:.4f}  [{ci_l:.4f}, {ci_u:.4f}]  n={int(ot_total)}")

    # 7. Avg Seller Handling Days
    handling = df['seller_handling_days'].dropna()
    handling = handling[handling >= 0]
    if len(handling) > 0:
        mean_h, ci_l, ci_u = bootstrap_ci(handling, np.mean, n_bootstrap=5000)
        results.append(('Avg Seller Handling Days', mean_h, ci_l, ci_u))
        print(f"Avg Seller Handling: {mean_h:.2f}  [{ci_l:.2f}, {ci_u:.2f}]  n={len(handling)}")

    # 8. Avg Carrier Transit Days
    transit = df['carrier_transit_days'].dropna()
    transit = transit[transit >= 0]
    if len(transit) > 0:
        mean_t, ci_l, ci_u = bootstrap_ci(transit, np.mean, n_bootstrap=5000)
        results.append(('Avg Carrier Transit Days', mean_t, ci_l, ci_u))
        print(f"Avg Carrier Transit: {mean_t:.2f}  [{ci_l:.2f}, {ci_u:.2f}]  n={len(transit)}")

    return pd.DataFrame(results, columns=['KPI', 'Point_Estimate', 'CI_Lower', 'CI_Upper'])


# ============================================================
# TWO-PROPORTION Z-TEST (pure scipy - no statsmodels needed)
# ============================================================
def two_proportion_ztest(df):
    """
    Test: Is low review rate (1-2 stars) significantly different between late and on-time orders?
    H0: p_late = p_on_time
    H1: p_late != p_on_time (two-sided)
    """
    print("\n" + "="*60)
    print("TWO-PROPORTION Z-TEST: Low Review Rate by Lateness")
    print("="*60)

    # Late orders
    late_mask = (df['is_late'] == 1) & (df['review_score'].notna())
    late_total = late_mask.sum()
    late_low = ((df['is_late'] == 1) & (df['review_score'].isin([1, 2]))).sum()

    # On-time orders
    ot_mask = (df['is_late'] == 0) & (df['review_score'].notna())
    ot_total = ot_mask.sum()
    ot_low = ((df['is_late'] == 0) & (df['review_score'].isin([1, 2]))).sum()

    print(f"Late orders with reviews:     {late_total:,}")
    print(f"Late orders with 1-2 stars:   {late_low:,}  ({100*late_low/late_total:.2f}%)" if late_total > 0 else "N/A")
    print(f"On-time orders with reviews:  {ot_total:,}")
    print(f"On-time orders with 1-2 stars:{ot_low:,}  ({100*ot_low/ot_total:.2f}%)" if ot_total > 0 else "N/A")

    if late_total == 0 or ot_total == 0:
        print("Insufficient data for z-test")
        return None

    # Manual two-proportion z-test (no statsmodels needed)
    p1 = late_low / late_total
    p2 = ot_low / ot_total
    p_pool = (late_low + ot_low) / (late_total + ot_total)

    se = np.sqrt(p_pool * (1 - p_pool) * (1/late_total + 1/ot_total))
    z_stat = (p1 - p2) / se if se > 0 else 0

    # Two-tailed p-value
    from scipy import stats
    p_value = 2 * (1 - stats.norm.cdf(abs(z_stat)))

    print(f"\nZ-statistic: {z_stat:.4f}")
    print(f"P-value:     {p_value:.6f}")
    print(f"Significant at alpha=0.05: {'YES' if p_value < 0.05 else 'NO'}")

    # Effect size: risk difference
    risk_diff = p1 - p2
    print(f"Risk Difference (Late - On-Time): {risk_diff:.4f} ({100*risk_diff:.2f} pp)")

    # Relative risk
    rel_risk = p1 / p2 if p2 > 0 else np.inf
    print(f"Relative Risk: {rel_risk:.2f}x")

    return {
        'z_stat': z_stat,
        'p_value': p_value,
        'risk_difference': risk_diff,
        'relative_risk': rel_risk,
        'p_late': p1,
        'p_ontime': p2
    }


# ============================================================
# LOGISTIC REGRESSION (try statsmodels, fallback to sklearn)
# ============================================================
def logistic_regression_late_vs_low_review(df):
    """
    Logistic regression: low_review (1-2 stars) ~ is_late + controls

    Outcome: low_review = 1 if review_score in (1,2), else 0
    Predictor of interest: is_late
    Controls: seller_handling_days, carrier_transit_days, total_price, item_count, primary_category
    """
    print("\n" + "="*60)
    print("LOGISTIC REGRESSION: Low Review ~ Late + Controls")
    print("="*60)

    # Prepare data
    model_df = df[df['review_score'].notna()].copy()
    model_df['low_review'] = (model_df['review_score'].isin([1, 2])).astype(int)

    # Features
    features = ['is_late']

    # Add numeric controls (fill NA with median)
    for col in ['seller_handling_days', 'carrier_transit_days', 'total_delivery_days', 'total_price', 'item_count']:
        if col in model_df.columns:
            model_df[col] = model_df[col].fillna(model_df[col].median())
            features.append(col)

    # Add primary_category as categorical (top 10 + other)
    if 'primary_category' in model_df.columns:
        top_cats = model_df['primary_category'].value_counts().head(10).index.tolist()
        model_df['primary_category_grouped'] = model_df['primary_category'].apply(
            lambda x: x if x in top_cats else 'Other'
        )
        cat_dummies = pd.get_dummies(model_df['primary_category_grouped'], prefix='cat', drop_first=True)
        model_df = pd.concat([model_df, cat_dummies], axis=1)
        features.extend(cat_dummies.columns.tolist())

    # Drop rows with any NA in features
    model_df = model_df.dropna(subset=features + ['low_review'])

    print(f"Sample size: {len(model_df):,}")
    print(f"Low review rate: {model_df['low_review'].mean():.4f}")
    print(f"Late rate: {model_df['is_late'].mean():.4f}")

    # Try statsmodels first (for detailed stats)
    try:
        import statsmodels.api as sm
        X = model_df[features]
        X = sm.add_constant(X)
        y = model_df['low_review']

        model = sm.Logit(y, X).fit(disp=0, maxiter=100)

        print(f"\nModel LL: {model.llf:.2f}, Pseudo R²: {model.prsquared:.4f}")
        print(f"\n{'Variable':<30} {'Coef':>8} {'StdErr':>8} {'z':>8} {'P>|z|':>8} {'OR':>8} {'[0.025':>8} {'0.975]':>8}")
        print("-" * 90)

        for var in model.params.index:
            coef = model.params[var]
            se = model.bse[var]
            z = model.tvalues[var]
            p = model.pvalues[var]
            or_val = np.exp(coef)
            ci_l = np.exp(coef - 1.96 * se)
            ci_u = np.exp(coef + 1.96 * se)
            print(f"{var:<30} {coef:>8.4f} {se:>8.4f} {z:>8.2f} {p:>8.4f} {or_val:>8.4f} {ci_l:>8.4f} {ci_u:>8.4f}")

        if 'is_late' in model.params.index:
            coef_late = model.params['is_late']
            or_late = np.exp(coef_late)
            p_late = model.pvalues['is_late']
            print(f"\n>>> KEY FINDING: Late delivery increases odds of low review by {or_late:.2f}x (p={p_late:.4f})")

        return model

    except ImportError:
        print("statsmodels not installed. Falling back to sklearn...")
    except Exception as e:
        print(f"statsmodels failed: {e}. Falling back to sklearn...")

    # Fallback: sklearn
    try:
        from sklearn.linear_model import LogisticRegression
        from sklearn.preprocessing import StandardScaler

        X = model_df[features].values
        y = model_df['low_review'].values

        # Scale features
        scaler = StandardScaler()
        X_scaled = scaler.fit_transform(X)

        # Fit
        clf = LogisticRegression(max_iter=1000, random_state=42)
        clf.fit(X_scaled, y)

        # Get coefficients
        coef_df = pd.DataFrame({
            'Variable': ['intercept'] + features,
            'Coef': np.concatenate([clf.intercept_, clf.coef_.flatten()])
        })
        coef_df['OR'] = np.exp(coef_df['Coef'])

        print(f"\nSklearn Logistic Regression (no p-values/CI available)")
        print(f"Accuracy: {clf.score(X_scaled, y):.4f}")
        print(f"\n{'Variable':<30} {'Coef':>8} {'OR':>8}")
        print("-" * 50)
        for _, row in coef_df.iterrows():
            print(f"{row['Variable']:<30} {row['Coef']:>8.4f} {row['OR']:>8.4f}")

        if 'is_late' in features:
            idx = features.index('is_late')
            or_late = np.exp(clf.coef_.flatten()[idx])
            print(f"\n>>> KEY FINDING: Late delivery increases odds of low review by {or_late:.2f}x")

        return clf

    except ImportError:
        print("sklearn not installed either. Skipping logistic regression.")
        print("Install: pip install scikit-learn")
        return None
    except Exception as e:
        print(f"sklearn logistic regression failed: {e}")
        return None


# ============================================================
# MAIN
# ============================================================
if __name__ == '__main__':
    print("="*60)
    print("PHASE 4: PYTHON STATISTICAL CHECKS")
    print("="*60)

    # Load data
    df = load_fact_orders()

    # 1. Bootstrap CIs
    bootstrap_results = run_bootstrap_kpis(df)

    # 2. Two-proportion z-test
    ztest_results = two_proportion_ztest(df)

    # 3. Logistic regression
    logit_model = logistic_regression_late_vs_low_review(df)

    print("\n" + "="*60)
    print("PHASE 4 COMPLETE")
    print("="*60)

    # Save bootstrap results
    bootstrap_results.to_csv('bootstrap_kpi_results.csv', index=False)
    print("Bootstrap results saved to bootstrap_kpi_results.csv")