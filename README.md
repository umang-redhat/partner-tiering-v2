# Partner Tiering v2

Salesforce DX project for a configurable, program-scoped partner tier evaluation engine on top of Loyalty Management.

## What this solution provides

- Custom-object rule model scoped to `LoyaltyProgram`:
  - `PartnerTierRuleVersion__c`
  - `PartnerTierRuleGroup__c`
  - `PartnerTierRuleCondition__c`
- Apex evaluation engine:
  - `TierEvaluationService`
- Batch evaluation job:
  - `TierEvaluationBatch`
- Business-user condition builder UI:
  - `partnerTierConditionBuilder` LWC on `PartnerTierRuleVersion__c` record page
- Permission set:
  - `PartnerTierRule_Editor`
- Demo seed script:
  - `force-app/main/default/scripts/apex/setupDemoData.apex`

## Prerequisites

- Salesforce CLI (`sf`)
- A target org with Loyalty Management enabled

Set your default org once:

```bash
sf config set target-org <your-org-alias>
```

## Project structure

- `force-app/main/default/classes/` — Apex services, controllers, trigger handlers, tests
- `force-app/main/default/lwc/partnerTierConditionBuilder/` — rule condition builder UI
- `force-app/main/default/objects/` — custom objects, fields, and validation
- `force-app/main/default/permissionsets/` — `PartnerTierRule_Editor`
- `force-app/main/default/scripts/apex/` — local demo/setup scripts (not deployable metadata)
- `manifest/destructiveChanges.xml` — legacy metadata cleanup manifest
- `partner-tiering-data-model.svg` — data model diagram

## Deploy

Deploy application metadata:

```bash
sf project deploy start --source-dir force-app --ignore-conflicts
```

Assign the editor permission set:

```bash
sf org assign permset --name PartnerTierRule_Editor
```

Remove deprecated org metadata (unused fields, inactive validation rules, old permission set):

```bash
sf project deploy start \
  --metadata-dir manifest \
  --post-destructive-changes manifest/destructiveChanges.xml \
  --ignore-conflicts
```

## Configure the UI

1. Open a `LoyaltyProgram` record page and add the **Partner Tier Rule Versions** related list.
2. Open a `PartnerTierRuleVersion__c` record page and add the **partnerTierConditionBuilder** LWC.

Recommended related-list columns: `Module__c`, `Tier__c`, `Tier_Rank__c`, `Status__c`, `In_Effect_Date__c`, `Version_Label__c`.

## Seed demo data

```bash
sf apex run --file force-app/main/default/scripts/apex/setupDemoData.apex
```

This creates or reuses the demo loyalty program, seeds Build/Reseller rule versions for that program, creates demo members and balances, and prints evaluation output in debug logs.

## Condition authoring model

The UI uses **row-based conditions + Filter Logic**:

1. Add condition rows (Field, Operator, Value)
2. Define `Filter Logic` using row numbers and boolean operators (`AND` / `OR`)
3. Use **Validate Logic** before saving

Example:

```text
((1 OR 2) AND (3 OR 4)) OR (5 AND 6)
```

The filter logic is compiled into the internal group/condition storage model for runtime evaluation.

## Runtime behavior summary

`TierEvaluationService` evaluates in this order:

1. Active/effective rule versions for the member's program
   - `Status = 'Active'`
   - `In_Effect_Date__c <= today`
   - `Deactivation_Date__c` is blank or `>= today`
2. Condition gate (compiled OR-groups and AND-buckets)
3. Points checks from condition rows using logical field names:
   - `MinimumEligibleBalance`
   - `MaximumEligibleBalance`
   - Values are stored in `Threshold__c` for org compatibility
4. Best tier is selected **per enrolled module** (`Build`, `Reseller`)
5. Backward-compatible helper can still pick overall highest across modules

Only one active rule version is allowed per **LoyaltyProgram + Module + Tier**.

### Performance notes

- Rules are loaded once into a reusable in-memory `RuleContext`
- Rule versions are indexed by program and module, ordered by descending rank for early exit
- Condition actual values are cached per member during evaluation
- Batch path loads member points in bulk and evaluates members without SOQL in the hot loop

## Batch usage

```bash
sf apex run --code "Database.executeBatch(new TierEvaluationBatch(), 200);"
```

## Tests

Run partner-tiering tests only:

```bash
sf apex run test \
  --tests PartnerTierRuleBuilderControllerTest \
  --tests RuleVersionValidationTest \
  --tests TierEvaluationServiceTest \
  --tests TierEvaluationBatchTest \
  --result-format human \
  --code-coverage
```

## Notes

- MVP module enrollment fields are `Build_Certify__c` and `Reseller__c`
- Point thresholds use `Threshold__c` with logical field names (`MinimumEligibleBalance` / `MaximumEligibleBalance`) to remain resilient in orgs with metadata visibility anomalies
- Deprecated fields removed from source: `Min_Points__c`, `Is_Points_Only__c`, redundant balance fields on `PartnerTierRuleCondition__c`, `Group_Label__c`
