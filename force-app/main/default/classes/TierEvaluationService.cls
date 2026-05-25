/**
 * @description Evaluates partner tier eligibility using custom-object rules:
 *              PartnerTierRuleVersion__c -> PartnerTierRuleGroup__c -> PartnerTierRuleCondition__c.
 *
 *              Evaluation model:
 *              - Rule version must be Active and inside effective date window.
 *              - Points gate always runs first.
 *              - Otherwise, OR groups are evaluated; each group supports nested logic:
 *                OR inside a bucket and AND across buckets (bucket key = Condition_Order__c).
 *              - Highest qualifying Tier_Rank__c across enrolled modules wins.
 */
public with sharing class TierEvaluationService {

    private static final Map<String, String> MODULE_FIELD_MAP = new Map<String, String>{
        'Build_Certify__c' => 'Build',
        'Reseller__c'      => 'Reseller'
    };

    public String evaluatePartnerTier(Id loyaltyProgramMemberId) {
        LoyaltyProgramMember lpm = queryLoyaltyProgramMember(loyaltyProgramMemberId);
        Decimal partnerPoints = resolvePointBalance(lpm);
        Date todayDate = Date.today();

        List<PartnerTierRuleVersion__c> activeVersions = [
            SELECT Id,
                   Module__c,
                   Tier__c,
                   Tier_Rank__c,
                   Min_Points__c,
                   In_Effect_Date__c
            FROM PartnerTierRuleVersion__c
            WHERE Status__c = 'Active'
            AND In_Effect_Date__c <= :todayDate
            ORDER BY Module__c, Tier_Rank__c
        ];

        Map<Id, List<PartnerTierRuleGroup__c>> groupsByVersion = loadGroupsByVersion(activeVersions);
        Map<Id, List<PartnerTierRuleCondition__c>> conditionsByGroup = loadConditionsByGroup(groupsByVersion);

        Integer highestRank = 0;
        String highestTier;

        for (String moduleEnrollmentField : MODULE_FIELD_MAP.keySet()) {
            if ((Boolean) lpm.get(moduleEnrollmentField) != true) {
                continue;
            }
            String moduleName = MODULE_FIELD_MAP.get(moduleEnrollmentField);

            for (PartnerTierRuleVersion__c version : activeVersions) {
                if (version.Module__c != moduleName) {
                    continue;
                }
                if (!meetsPointThreshold(partnerPoints, version.Min_Points__c)) {
                    continue;
                }
                if (!meetsCredentialGate(lpm, version, groupsByVersion, conditionsByGroup)) {
                    continue;
                }

                Integer rank = version.Tier_Rank__c == null ? 0 : Integer.valueOf(version.Tier_Rank__c);
                if (rank > highestRank) {
                    highestRank = rank;
                    highestTier = version.Tier__c;
                }
            }
        }

        return highestTier;
    }

    private Map<Id, List<PartnerTierRuleGroup__c>> loadGroupsByVersion(List<PartnerTierRuleVersion__c> versions) {
        Map<Id, List<PartnerTierRuleGroup__c>> grouped = new Map<Id, List<PartnerTierRuleGroup__c>>();
        if (versions.isEmpty()) {
            return grouped;
        }
        Set<Id> versionIds = new Set<Id>();
        for (PartnerTierRuleVersion__c v : versions) {
            versionIds.add(v.Id);
            grouped.put(v.Id, new List<PartnerTierRuleGroup__c>());
        }

        for (PartnerTierRuleGroup__c g : [
            SELECT Id, Rule_Version__c, Group_Order__c
            FROM PartnerTierRuleGroup__c
            WHERE Rule_Version__c IN :versionIds
            ORDER BY Group_Order__c ASC, CreatedDate ASC
        ]) {
            grouped.get(g.Rule_Version__c).add(g);
        }
        return grouped;
    }

    private Map<Id, List<PartnerTierRuleCondition__c>> loadConditionsByGroup(
        Map<Id, List<PartnerTierRuleGroup__c>> groupsByVersion
    ) {
        Map<Id, List<PartnerTierRuleCondition__c>> conditionMap = new Map<Id, List<PartnerTierRuleCondition__c>>();
        Set<Id> groupIds = new Set<Id>();

        for (List<PartnerTierRuleGroup__c> groups : groupsByVersion.values()) {
            for (PartnerTierRuleGroup__c g : groups) {
                groupIds.add(g.Id);
                conditionMap.put(g.Id, new List<PartnerTierRuleCondition__c>());
            }
        }

        if (groupIds.isEmpty()) {
            return conditionMap;
        }

        for (PartnerTierRuleCondition__c c : [
            SELECT Id, Rule_Group__c, Condition_Order__c, Field_API_Name__c, Operator__c, Threshold__c
            FROM PartnerTierRuleCondition__c
            WHERE Rule_Group__c IN :groupIds
            ORDER BY Condition_Order__c ASC, CreatedDate ASC
        ]) {
            conditionMap.get(c.Rule_Group__c).add(c);
        }

        return conditionMap;
    }

    private LoyaltyProgramMember queryLoyaltyProgramMember(Id lpmId) {
        List<LoyaltyProgramMember> results = [
            SELECT Id,
                   MembershipNumber,
                   Build_Certify__c,
                   Reseller__c,
                   Account_Software_Product_Cert__c,
                   Account_Hardware_Product_Cert__c,
                   Account_RHSC_Credentials__c,
                   Account_RHTSC_Credentials__c,
                   Account_RH_Certifications__c
            FROM LoyaltyProgramMember
            WHERE Id = :lpmId
            LIMIT 1
        ];
        if (results.isEmpty()) {
            throw new TierEvaluationException('LoyaltyProgramMember not found for Id: ' + lpmId);
        }
        return results[0];
    }

    private Decimal resolvePointBalance(LoyaltyProgramMember lpm) {
        List<LoyaltyMemberCurrency> currencies = [
            SELECT PointsBalance, TotalPointsAccrued
            FROM LoyaltyMemberCurrency
            WHERE LoyaltyMemberId = :lpm.Id
            ORDER BY PointsBalance DESC NULLS LAST
            LIMIT 1
        ];
        if (currencies.isEmpty()) {
            return 0;
        }
        Decimal pointsBalance = currencies[0].PointsBalance == null ? 0 : currencies[0].PointsBalance;
        Decimal totalAccrued = currencies[0].TotalPointsAccrued == null ? 0 : currencies[0].TotalPointsAccrued;
        return pointsBalance > totalAccrued ? pointsBalance : totalAccrued;
    }

    private Boolean meetsPointThreshold(Decimal partnerPoints, Decimal requiredPoints) {
        return partnerPoints >= (requiredPoints == null ? 0 : requiredPoints);
    }

    private Boolean meetsCredentialGate(
        LoyaltyProgramMember lpm,
        PartnerTierRuleVersion__c version,
        Map<Id, List<PartnerTierRuleGroup__c>> groupsByVersion,
        Map<Id, List<PartnerTierRuleCondition__c>> conditionsByGroup
    ) {
        List<PartnerTierRuleGroup__c> groups = groupsByVersion.get(version.Id);
        if (groups == null || groups.isEmpty()) {
            // No condition groups means points-only behavior.
            return true;
        }

        // OR across groups
        for (PartnerTierRuleGroup__c g : groups) {
            List<PartnerTierRuleCondition__c> conditions = conditionsByGroup.get(g.Id);
            if (conditions == null || conditions.isEmpty()) {
                continue;
            }
            if (allConditionsMatch(lpm, conditions)) {
                return true;
            }
        }
        return false;
    }

    private Boolean allConditionsMatch(
        LoyaltyProgramMember lpm,
        List<PartnerTierRuleCondition__c> conditions
    ) {
        // Supports nested structures by treating Condition_Order__c as an AND bucket id:
        // - same Condition_Order__c => OR within that bucket
        // - different Condition_Order__c => AND across buckets
        // Example: ((1 OR 2) AND (3 OR 4)) OR (5 AND 6)
        // can be modeled as two groups:
        //   Group A: (order=1: [1,2]) AND (order=2: [3,4])
        //   Group B: (order=1: [5]) AND (order=2: [6])
        Map<Integer, List<PartnerTierRuleCondition__c>> conditionsByBucket = new Map<Integer, List<PartnerTierRuleCondition__c>>();
        for (PartnerTierRuleCondition__c c : conditions) {
            if (String.isBlank(c.Field_API_Name__c) || String.isBlank(c.Operator__c) || c.Threshold__c == null) {
                return false;
            }
            Integer bucket = c.Condition_Order__c == null ? 1 : Integer.valueOf(c.Condition_Order__c);
            if (!conditionsByBucket.containsKey(bucket)) {
                conditionsByBucket.put(bucket, new List<PartnerTierRuleCondition__c>());
            }
            conditionsByBucket.get(bucket).add(c);
        }

        if (conditionsByBucket.isEmpty()) {
            return false;
        }

        // AND across buckets: every bucket must have at least one passing condition.
        for (Integer bucket : conditionsByBucket.keySet()) {
            Boolean bucketMatched = false;
            for (PartnerTierRuleCondition__c c : conditionsByBucket.get(bucket)) {
                Decimal actual = parseDecimal(lpm.get(c.Field_API_Name__c));
                if (compare(actual, c.Operator__c, c.Threshold__c)) {
                    bucketMatched = true;
                    break;
                }
            }
            if (!bucketMatched) {
                return false;
            }
        }
        return true;
    }

    private Decimal parseDecimal(Object valueObj) {
        if (valueObj == null) {
            return 0;
        }
        if (valueObj instanceof Decimal) {
            return (Decimal) valueObj;
        }
        return Decimal.valueOf(String.valueOf(valueObj));
    }

    private Boolean compare(Decimal actual, String op, Decimal expected) {
        if (op == '>=') {
            return actual >= expected;
        } else if (op == '>') {
            return actual > expected;
        } else if (op == '<=') {
            return actual <= expected;
        } else if (op == '<') {
            return actual < expected;
        } else if (op == '=' || op == '==') {
            return actual == expected;
        } else if (op == '!=') {
            return actual != expected;
        }
        return false;
    }

    public class TierEvaluationException extends Exception {}
}
