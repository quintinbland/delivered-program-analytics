# Business Rules

All logic is defined as explicit, structured rules. No logic is embedded in formulas or left implicit in transformations.

---

## Rule Format

Each rule defines:
- **Inputs:** Required fields
- **Conditions:** IF / THEN logic
- **Output:** Resulting field or flag
- **Edge Cases:** Null handling and boundary conditions

---

## 1. Pricing Rules

### RULE: Actual FOB Calculation

- **Description:** Calculate realized FOB price per case from net revenue
- **Inputs:** `NetLineRevenue`, `QuantityCases`
- **Conditions:**
  ```
  IF QuantityCases > 0 AND QuantityCases IS NOT NULL
  THEN ActualFOB = NetLineRevenue / QuantityCases
  ELSE ActualFOB = NULL
  ```
- **Output:** `ActualFOB`
- **Edge Cases:** Zero or NULL quantity must return NULL, not divide-by-zero

---

### RULE: Contract FOB Matching

- **Description:** Attach valid contract FOB price to each sales line using a priority-based matching hierarchy
- **Inputs:** `CustomerID`, `CustomerHQID`, `ItemID`, `CommodityID`, `ShipDate`, `Fact_ContractPrice`
- **Conditions:**
  ```
  FOR EACH sales line:
    1. MATCH on CustomerID + ItemID where ShipDate BETWEEN EffectiveStartDate AND EffectiveEndDate
       → ContractMatchLevel = 'Customer+Item'
    2. ELSE MATCH on CustomerHQID + ItemID where ShipDate BETWEEN effective dates
       → ContractMatchLevel = 'CustomerHQ+Item'
    3. ELSE MATCH on CustomerHQID + CommodityID where ShipDate BETWEEN effective dates
       → ContractMatchLevel = 'CustomerHQ+Commodity'
    4. ELSE ContractFOB = NULL, ContractMatchLevel = 'No Match'
  ```
- **Output:** `ContractFOB`, `ContractMatchFlag`, `ContractMatchLevel`
- **Edge Cases:**
  - Expired contracts must not match (ContractStatus = 'Active' required)
  - Multiple active contracts at same level: UNKNOWN — requires confirmation
  - NULL ItemID or CommodityID in contract: falls through to next matching tier

> ⚠️ **UNKNOWN:** Exact confirmed matching hierarchy pending business validation. Candidate logic applied.

---

### RULE: FOB Variance Per Case

- **Description:** Calculate pricing deviation from contract on a per-case basis
- **Inputs:** `ActualFOB`, `ContractFOB`
- **Conditions:**
  ```
  IF ActualFOB IS NOT NULL AND ContractFOB IS NOT NULL
  THEN FOBVariancePerCase = ActualFOB - ContractFOB
  ELSE FOBVariancePerCase = NULL
  ```
- **Output:** `FOBVariancePerCase`
- **Edge Cases:** NULL ContractFOB (no contract match) must return NULL, not zero

---

### RULE: Total FOB Variance

- **Description:** Extend per-case variance to total line impact
- **Inputs:** `FOBVariancePerCase`, `QuantityCases`
- **Conditions:**
  ```
  IF FOBVariancePerCase IS NOT NULL
  THEN TotalFOBVariance = FOBVariancePerCase * QuantityCases
  ELSE TotalFOBVariance = NULL
  ```
- **Output:** `TotalFOBVariance`
- **Edge Cases:** NULL variance must propagate as NULL, not zero

---

### RULE: Pricing Favorability Classification

- **Description:** Classify pricing outcome relative to contract
- **Inputs:** `TotalFOBVariance`
- **Conditions:**
  ```
  IF TotalFOBVariance > 0  → PricingResult = 'Favorable'
  IF TotalFOBVariance = 0  → PricingResult = 'At Contract'
  IF TotalFOBVariance < 0  → PricingResult = 'Unfavorable'
  IF TotalFOBVariance IS NULL → PricingResult = 'No Contract Match'
  ```
- **Output:** `PricingResult`
- **Edge Cases:** None

---

## 2. Freight Rules

### RULE: Freight Margin

- **Description:** Calculate load-level freight profitability
- **Inputs:** `FreightCharged`, `FreightPaid`
- **Conditions:**
  ```
  FreightMargin = FreightCharged - FreightPaid
  ```
- **Output:** `FreightMargin`
- **Edge Cases:** Both fields must be present. NULL in either returns NULL margin.

> ⚠️ **UNKNOWN:** Whether FreightCharged represents billed, budgeted, allocated, or contractual freight amount requires confirmation. This affects the business interpretation of margin.

---

### RULE: Freight Margin Percent

- **Description:** Calculate margin as a percentage of freight charged
- **Inputs:** `FreightMargin`, `FreightCharged`
- **Conditions:**
  ```
  IF FreightCharged > 0
  THEN FreightMarginPct = FreightMargin / FreightCharged
  ELSE FreightMarginPct = NULL
  ```
- **Output:** `FreightMarginPct`
- **Edge Cases:** Zero freight charged must return NULL, not divide-by-zero

---

### RULE: Freight Loss Flag

- **Description:** Identify loads where freight cost exceeds freight charged
- **Inputs:** `FreightMargin`
- **Conditions:**
  ```
  IF FreightMargin < 0
  THEN FreightException = 'Freight Loss'
  ELSE FreightException = NULL
  ```
- **Output:** `FreightException`
- **Edge Cases:** NULL FreightMargin must not be classified as Freight Loss

---

## 3. Load Utilization Rules

### RULE: Load Utilization Band

- **Description:** Classify loads by pallet utilization efficiency
- **Inputs:** `LoadPallets`
- **Conditions:**
  ```
  IF LoadPallets >= 24  → LoadUtilizationBand = 'Full'
  IF LoadPallets >= 18  → LoadUtilizationBand = 'Partial'
  IF LoadPallets < 18   → LoadUtilizationBand = 'Underutilized'
  ```
- **Output:** `LoadUtilizationBand`
- **Edge Cases:** NULL LoadPallets must return NULL band, not a classification

> ⚠️ **UNKNOWN:** TargetFullTruckloadPallets threshold is unconfirmed. Value of 24 used as candidate.

---

### RULE: Average Pallets Per Load

- **Description:** Measure average load utilization across a set of loads
- **Inputs:** `LoadPallets`, `LoadID`
- **Conditions:**
  ```
  AvgPalletsPerLoad = SUM(LoadPallets) / COUNT(DISTINCT LoadID)
  ```
- **Output:** `AvgPalletsPerLoad`
- **Edge Cases:** Unique load count must be used — never line-level row count

---

## 4. Contract Performance Rules

### RULE: Contract Match Rate

- **Description:** Measure what percentage of eligible contract lines received a contract price
- **Inputs:** `ContractMatchFlag`, `CustomerStatusKey`
- **Conditions:**
  ```
  Eligible lines = Fact_SalesOrderLine WHERE CustomerStatusKey = 'CONTRACT'
  Matched lines  = Eligible lines WHERE ContractMatchFlag = TRUE

  ContractMatchRate = COUNT(Matched lines) / COUNT(Eligible lines)
  ```
- **Output:** `ContractMatchRate`
- **Edge Cases:** Open Market and Commit lines are excluded from eligibility

---

### RULE: On-Target Classification

- **Description:** Rate customer or load contract performance against a threshold
- **Inputs:** `OnTargetPct`
- **Conditions:**
  ```
  IF OnTargetPct >= 0.90  → PerformanceRating = 'Excellent'
  IF OnTargetPct >= 0.70  → PerformanceRating = 'Good'
  IF OnTargetPct >= 0.50  → PerformanceRating = 'Fair'
  IF ContractFOB IS NULL  → PerformanceRating = 'No Contract'
  ELSE                    → PerformanceRating = 'Below Target'
  ```
- **Output:** `PerformanceRating`
- **Edge Cases:** Customers with no contract must return 'No Contract', not 'Below Target'

> ⚠️ **UNKNOWN:** Exact row-level definition of `OnTargetFlag` (the input to `OnTargetPct`) is unconfirmed.

---

## 5. Time Period Rules

### RULE: YTD Flag

- **Description:** Flag dates within the current year up to the report date
- **Inputs:** `Date`, `ReportDate`
- **Conditions:**
  ```
  IF Date >= DATE(YEAR(ReportDate), 1, 1) AND Date <= ReportDate
  THEN IsYTD = TRUE
  ELSE IsYTD = FALSE
  ```
- **Output:** `IsYTD`

---

### RULE: Rolling 4-Week Flag

- **Description:** Flag dates within the last 28 days of the report date
- **Inputs:** `Date`, `ReportDate`
- **Conditions:**
  ```
  IF Date >= ReportDate - 28 AND Date <= ReportDate
  THEN IsRolling4Weeks = TRUE
  ELSE IsRolling4Weeks = FALSE
  ```
- **Output:** `IsRolling4Weeks`

---

### RULE: Rolling 8-Week Flag

- **Description:** Flag dates within the last 56 days of the report date
- **Inputs:** `Date`, `ReportDate`
- **Conditions:**
  ```
  IF Date >= ReportDate - 56 AND Date <= ReportDate
  THEN IsRolling8Weeks = TRUE
  ELSE IsRolling8Weeks = FALSE
  ```
- **Output:** `IsRolling8Weeks`

> ⚠️ **UNKNOWN:** Whether report date is system date, latest ship date, or user-selected parameter requires confirmation.

---

## 6. Exception Rules

| Rule Name | Condition | Output |
|---|---|---|
| Missing Contract Pricing | `CustomerStatusKey = 'CONTRACT' AND ContractFOB IS NULL` | `Exception_MissingContractPricing` |
| Negative FOB Variance | `TotalFOBVariance < 0` | `Exception_NegativeFOBVariance` |
| Negative Freight Margin | `FreightMargin < 0` | `Exception_NegativeFreightMargin` |
| Missing Commodity Mapping | `ItemID IS NOT NULL AND CommodityID IS NULL` | `Exception_MissingCommodityMapping` |
| Missing Customer Mapping | `CustomerID in Fact_SalesOrderLine NOT IN Dim_Customer` | `Exception_MissingCustomerMapping` |
| Missing Ship-To Mapping | `ShipToID in transactions NOT IN Dim_ShipTo` | `Exception_MissingShipToMapping` |
| Duplicate Sales Line Key | `COUNT(SalesOrderID + LoadID + ItemID) > 1` | `Exception_DuplicateTransactionKey` |
| Invalid Quantity | `QuantityCases <= 0 OR QuantityCases IS NULL` | `Exception_InvalidQuantity` |
| Missing LoadID | `LoadID IS NULL in Fact_SalesOrderLine` | `Exception_MissingLoadID` |
| Underutilized Load | `LoadPallets < TargetFullTruckloadPallets` | `Exception_UnderutilizedLoad` |
