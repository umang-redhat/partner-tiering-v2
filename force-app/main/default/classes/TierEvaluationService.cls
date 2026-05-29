/**
 * @description Evaluates partner tier eligibility using custom-object rules:
 *              PartnerTierRuleVersion__c -> PartnerTierRuleGroup__c -> PartnerTierRuleCondition__c.
 *
 *              Evaluation model:
 *              - Rule version must be Active and inside effective date window.
 *              - OR groups are evaluated; each group supports nested logic:
 *                OR inside a bucket and AND across buckets (bucket key = Condition_Order__c).
 *              - Points are evaluated as condition rows via MinimumEligibleBalance/MaximumEligibleBalance.
 *              - Highest qualifying Tier_Rank__c across enrolled modules wins.
 */
public with sharing class TierEvaluationService {

    private static final String FIELD_MIN_ELIGIBLE_BALANCE = 'MinimumEligibleBalance';
    private static final String FIELD_MAX_ELIGIBLE_BALANCE = 'MaximumEligibleBalance';

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
                   In_Effect_Date__c
            FROM PartnerTierRuleVersion__c
            WHERE Status__c = 'Active'
            AND In_Effect_Date__c <= :todayDate
            ORDER BY Module__c, Tier_Rank__c
        ];

        Map<Id, List<PartnerTierRuleGroup__c>> groupsByVersion = loadGroupsByVersion(activeVersions);
        Map<Id, List<PartnerTierRuleCondition__c>> conditionsByGroup = loadConditionsByGroup(groupsByVersion);

        Integer highestRank = -1;
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
                if (!meetsConditionGate(lpm, partnerPoints, version, groupsByVersion, conditionsByGroup)) {
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
            SELECT Id,
                   Rule_Group__c,
                   Condition_Order__c,
                   Field_API_Name__c,
                   Operator__c,
                   Threshold__c
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

    private Boolean meetsConditionGate(
        LoyaltyProgramMember lpm,
        Decimal partnerPoints,
        PartnerTierRuleVersion__c version,
        Map<Id, List<PartnerTierRuleGroup__c>> groupsByVersion,
        Map<Id, List<PartnerTierRuleCondition__c>> conditionsByGroup
    ) {
        List<PartnerTierRuleGroup__c> groups = groupsByVersion.get(version.Id);
        if (groups == null || groups.isEmpty()) {
            // No condition groups means this version is not yet configured.
            return false;
        }

        // OR across groups
        for (PartnerTierRuleGroup__c g : groups) {
            List<PartnerTierRuleCondition__c> conditions = conditionsByGroup.get(g.Id);
            if (conditions == null || conditions.isEmpty()) {
                continue;
            }
            if (allConditionsMatch(lpm, partnerPoints, conditions)) {
                return true;
            }
        }
        return false;
    }

    private Boolean allConditionsMatch(
        LoyaltyProgramMember lpm,
        Decimal partnerPoints,
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
            if (!isConditionComplete(c)) {
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
                Decimal actual = resolveConditionActualValue(lpm, partnerPoints, c.Field_API_Name__c);
                Decimal expected = resolveConditionExpectedValue(c);
                if (compare(actual, c.Operator__c, expected)) {
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

    private Boolean isConditionComplete(PartnerTierRuleCondition__c conditionRec) {
        if (String.isBlank(conditionRec.Field_API_Name__c) || String.isBlank(conditionRec.Operator__c)) {
            return false;
        }
        if (conditionRec.Field_API_Name__c == FIELD_MIN_ELIGIBLE_BALANCE) {
            return conditionRec.Threshold__c != null;
        }
        if (conditionRec.Field_API_Name__c == FIELD_MAX_ELIGIBLE_BALANCE) {
            return conditionRec.Threshold__c != null;
        }
        return conditionRec.Threshold__c != null;
    }

    private Decimal resolveConditionActualValue(
        LoyaltyProgramMember lpm,
        Decimal partnerPoints,
        String fieldApiName
    ) {
        if (fieldApiName == FIELD_MIN_ELIGIBLE_BALANCE || fieldApiName == FIELD_MAX_ELIGIBLE_BALANCE) {
            return partnerPoints == null ? 0 : partnerPoints;
        }
        return parseDecimal(lpm.get(fieldApiName));
    }

    private Decimal resolveConditionExpectedValue(PartnerTierRuleCondition__c conditionRec) {
        return conditionRec.Threshold__c;
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
