# Partner Tiering v2

Salesforce DX project for a configurable partner-tier evaluation engine on top of Loyalty Management.

## What this solution provides

- Custom-object rule model:
  - `PartnerTierRuleVersion__c`
  - `PartnerTierRuleGroup__c`
  - `PartnerTierRuleCondition__c`
- Apex evaluation engine:
  - `TierEvaluationService`
- Business-user condition builder UI:
  - `partnerTierConditionBuilder` LWC on `PartnerTierRuleVersion__c` record page
- Permission-set driven access:
  - `PartnerTierRule_Editor`
- Demo seed script:
  - `force-app/main/default/scripts/apex/setupDemoData.apex`

## Prerequisites

- Salesforce CLI (`sf`)
- Access to a target org (example alias used here: `loyaltytrial2`)

## Project structure

- `force-app/main/default/classes/` — Apex services/controllers/trigger handlers
- `force-app/main/default/lwc/partnerTierConditionBuilder/` — UI for rule authoring
- `force-app/main/default/objects/` — custom object metadata and fields
- `force-app/main/default/permissionsets/` — permission sets
- `manifest/` — deployment manifests (including destructive changes for legacy metadata cleanup)

## Deploy

Deploy all metadata:

```bash
sf project deploy start --source-dir force-app --target-org loyaltytrial2 --ignore-conflicts
```

Assign the business editor permission set:

```bash
sf org assign permset --name PartnerTierRule_Editor --target-org loyaltytrial2
```

## Seed demo data

```bash
sf apex run --file force-app/main/default/scripts/apex/setupDemoData.apex --target-org loyaltytrial2
```

This seeds:

- Build + Reseller rule versions
- Rule groups and rule conditions
- Demo loyalty members and balances
- Validation output in debug logs

## Condition authoring model

The UI uses **row-based conditions + Filter Logic**:

1. Add condition rows (Field, Operator, Value)
2. Define `Filter Logic` using row numbers and boolean operators (`AND` / `OR`)
3. Use `Validate Logic` before saving

Example:

```text
((1 OR 2) AND (3 OR 4)) OR (5 AND 6)
```

The filter logic is compiled into the internal group/condition storage model for runtime evaluation.

## Runtime behavior summary

`TierEvaluationService` evaluates in this order:

1. Active/effective rule versions (`Status='Active'`, `In_Effect_Date__c <= today`)
2. Points threshold (`Min_Points__c`)
3. Condition gate (compiled OR-groups and AND-buckets)
4. Highest qualified `Tier_Rank__c` across enrolled modules wins

## Notes

- Some optional fields may not be runtime-visible in certain orgs due to metadata provisioning anomalies.
- The current implementation includes safe fallbacks so evaluation still runs for seeded scenarios.
