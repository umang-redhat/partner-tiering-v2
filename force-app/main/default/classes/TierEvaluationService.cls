/**
 * @description Evaluates partner tier eligibility using custom-object rules:
 *              PartnerTierRuleVersion__c -> PartnerTierRuleGroup__c -> PartnerTierRuleCondition__c.
 *
 *              Evaluation model:
 *              - Rule version must be Active and inside effective date window.
 *              - OR groups are evaluated; each group supports nested logic:
 *                OR inside a bucket and AND across buckets (bucket key = Condition_Order__c).
 *              - Points are evaluated as condition rows via MinimumEligibleBalance/MaximumEligibleBalance.
 *              - Each module is ranked independently; the best tier per module is returned.
 *
 *              Supports both single-member (on-demand) and bulk (batch) evaluation.
 *              Bulk callers should use loadRuleContext() once, then evaluateMember()
 *              per member to avoid redundant SOQL on shared rule data.
 */
public with sharing class TierEvaluationService {

    private static final String FIELD_MIN_ELIGIBLE_BALANCE = 'MinimumEligibleBalance';
    private static final String FIELD_MAX_ELIGIBLE_BALANCE = 'MaximumEligibleBalance';

    private static final Map<String, String> MODULE_FIELD_MAP = new Map<String, String>{
        'Build_Certify__c' => 'Build',
        'Reseller__c'      => 'Reseller'
    };

    /**
     * @description Holds pre-loaded rule data so it can be queried once and
     *              reused across many member evaluations (batch-friendly).
     */
    public class RuleContext {
        public List<PartnerTierRuleVersion__c> activeVersions;
        public Map<String, List<PartnerTierRuleVersion__c>> versionsByModule;
        public Map<Id, List<PartnerTierRuleGroup__c>> groupsByVersion;
        public Map<Id, List<PartnerTierRuleCondition__c>> conditionsByGroup;
    }

    /**
     * @description Per-module evaluation result for a single member.
     */
    public class TierResult {
        @AuraEnabled public String moduleName;
        @AuraEnabled public String tierName;
        @AuraEnabled public Integer tierRank;

        public TierResult(String moduleName, String tierName, Integer tierRank) {
            this.moduleName = moduleName;
            this.tierName = tierName;
            this.tierRank = tierRank;
        }
    }

    // ─── Single-member convenience methods (backward-compatible) ───

    /**
     * @description Evaluates a single member and returns per-module tier results.
     * @param loyaltyProgramMemberId The Id of the LoyaltyProgramMember.
     * @return Map of module name to TierResult. Modules where the member
     *         does not qualify for any tier are omitted.
     */
    public Map<String, TierResult> evaluatePartnerTiers(Id loyaltyProgramMemberId) {
        LoyaltyProgramMember lpm = queryLoyaltyProgramMember(loyaltyProgramMemberId);
        Decimal partnerPoints = resolvePointBalance(lpm);
        RuleContext ctx = loadRuleContext();
        return evaluateMember(lpm, partnerPoints, ctx);
    }

    /**
     * @description Backward-compatible method that returns the single highest
     *              tier name across all enrolled modules.
     * @param loyaltyProgramMemberId The Id of the LoyaltyProgramMember.
     * @return The tier name with the highest rank, or null if none qualifies.
     */
    public String evaluatePartnerTier(Id loyaltyProgramMemberId) {
        Map<String, TierResult> results = evaluatePartnerTiers(loyaltyProgramMemberId);
        return pickOverallHighest(results);
    }

    // ─── Bulk-ready API ───

    /**
     * @description Loads all active rule versions, groups, and conditions into
     *              a RuleContext. Call once per batch execute() chunk.
     * @return A fully populated RuleContext.
     */
    public RuleContext loadRuleContext() {
        Date todayDate = Date.today();
        RuleContext ctx = new RuleContext();

        ctx.activeVersions = [
            SELECT Id, Module__c, Tier__c, Tier_Rank__c, In_Effect_Date__c
            FROM PartnerTierRuleVersion__c
            WHERE Status__c = 'Active'
            AND In_Effect_Date__c <= :todayDate
            ORDER BY Module__c, Tier_Rank__c DESC NULLS LAST
        ];

        ctx.versionsByModule = buildVersionsByModule(ctx.activeVersions);
        ctx.groupsByVersion = loadGroupsByVersion(ctx.activeVersions);
        ctx.conditionsByGroup = loadConditionsByGroup(ctx.groupsByVersion);
        return ctx;
    }

    /**
     * @description Bulk-loads point balances for a set of member Ids.
     * @param memberIds Set of LoyaltyProgramMember Ids.
     * @return Map of member Id to their resolved point balance.
     */
    public Map<Id, Decimal> bulkLoadPointBalances(Set<Id> memberIds) {
        Map<Id, Decimal> balances = new Map<Id, Decimal>();
        Set<Id> resolvedMemberIds = new Set<Id>();
        for (Id mId : memberIds) {
            balances.put(mId, 0);
        }

        for (LoyaltyMemberCurrency c : [
            SELECT LoyaltyMemberId, PointsBalance, TotalPointsAccrued
            FROM LoyaltyMemberCurrency
            WHERE LoyaltyMemberId IN :memberIds
            ORDER BY PointsBalance DESC NULLS LAST
        ]) {
            if (resolvedMemberIds.contains(c.LoyaltyMemberId)) {
                continue;
            }
            Decimal pb = c.PointsBalance == null ? 0 : c.PointsBalance;
            Decimal ta = c.TotalPointsAccrued == null ? 0 : c.TotalPointsAccrued;
            balances.put(c.LoyaltyMemberId, pb > ta ? pb : ta);
            resolvedMemberIds.add(c.LoyaltyMemberId);
        }
        return balances;
    }

    /**
     * @description Evaluates a single member against pre-loaded rules (zero SOQL).
     *              Ranks within each module independently.
     * @param lpm The LoyaltyProgramMember record with all credential fields populated.
     * @param partnerPoints The member's resolved point balance.
     * @param ctx Pre-loaded RuleContext.
     * @return Map of module name to TierResult for each qualifying module.
     */
    public Map<String, TierResult> evaluateMember(
        LoyaltyProgramMember lpm,
        Decimal partnerPoints,
        RuleContext ctx
    ) {
        Map<String, TierResult> results = new Map<String, TierResult>();
        Map<String, Decimal> actualByField = new Map<String, Decimal>();

        for (String moduleEnrollmentField : MODULE_FIELD_MAP.keySet()) {
            if ((Boolean) lpm.get(moduleEnrollmentField) != true) {
                continue;
            }
            String moduleName = MODULE_FIELD_MAP.get(moduleEnrollmentField);
            List<PartnerTierRuleVersion__c> moduleVersions = ctx.versionsByModule == null
                ? null
                : ctx.versionsByModule.get(moduleName);
            if (moduleVersions == null || moduleVersions.isEmpty()) {
                continue;
            }

            for (PartnerTierRuleVersion__c version : moduleVersions) {
                if (!meetsConditionGate(
                    lpm,
                    partnerPoints,
                    version,
                    ctx.groupsByVersion,
                    ctx.conditionsByGroup,
                    actualByField
                )) {
                    continue;
                }
                Integer tierRank = version.Tier_Rank__c == null ? 0 : Integer.valueOf(version.Tier_Rank__c);
                results.put(moduleName, new TierResult(moduleName, version.Tier__c, tierRank));
                // Highest rank is first due to module-scoped DESC ordering.
                break;
            }
        }

        return results;
    }

    /**
     * @description Evaluates a batch of members using pre-loaded rules and point balances.
     * @param members Members already loaded with required credential/enrollment fields.
     * @param pointsByMember Pre-resolved points keyed by LoyaltyProgramMember Id.
     * @param ctx Pre-loaded RuleContext.
     * @return Map of member Id to module-tier results for that member.
     */
    public Map<Id, Map<String, TierResult>> evaluateMembers(
        List<LoyaltyProgramMember> members,
        Map<Id, Decimal> pointsByMember,
        RuleContext ctx
    ) {
        Map<Id, Map<String, TierResult>> resultsByMember = new Map<Id, Map<String, TierResult>>();
        for (LoyaltyProgramMember memberRec : members) {
            Decimal points = pointsByMember.containsKey(memberRec.Id) ? pointsByMember.get(memberRec.Id) : 0;
            resultsByMember.put(memberRec.Id, evaluateMember(memberRec, points, ctx));
        }
        return resultsByMember;
    }

    // ─── Utilities ───

    /**
     * @description Picks the single highest-ranked tier across all module results.
     */
    public String pickOverallHighest(Map<String, TierResult> moduleResults) {
        Integer highestRank = -1;
        String highestTier;
        for (TierResult tr : moduleResults.values()) {
            if (tr.tierRank > highestRank) {
                highestRank = tr.tierRank;
                highestTier = tr.tierName;
            }
        }
        return highestTier;
    }

    // ─── Private helpers ───

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

    private Map<String, List<PartnerTierRuleVersion__c>> buildVersionsByModule(
        List<PartnerTierRuleVersion__c> versions
    ) {
        Map<String, List<PartnerTierRuleVersion__c>> grouped = new Map<String, List<PartnerTierRuleVersion__c>>();
        for (PartnerTierRuleVersion__c version : versions) {
            if (!grouped.containsKey(version.Module__c)) {
                grouped.put(version.Module__c, new List<PartnerTierRuleVersion__c>());
            }
            grouped.get(version.Module__c).add(version);
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
        Map<Id, List<PartnerTierRuleCondition__c>> conditionsByGroup,
        Map<String, Decimal> actualByField
    ) {
        List<PartnerTierRuleGroup__c> groups = groupsByVersion.get(version.Id);
        if (groups == null || groups.isEmpty()) {
            return false;
        }

        for (PartnerTierRuleGroup__c g : groups) {
            List<PartnerTierRuleCondition__c> conditions = conditionsByGroup.get(g.Id);
            if (conditions == null || conditions.isEmpty()) {
                continue;
            }
            if (allConditionsMatch(lpm, partnerPoints, conditions, actualByField)) {
                return true;
            }
        }
        return false;
    }

    private Boolean allConditionsMatch(
        LoyaltyProgramMember lpm,
        Decimal partnerPoints,
        List<PartnerTierRuleCondition__c> conditions,
        Map<String, Decimal> actualByField
    ) {
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

        for (Integer bucket : conditionsByBucket.keySet()) {
            Boolean bucketMatched = false;
            for (PartnerTierRuleCondition__c c : conditionsByBucket.get(bucket)) {
                Decimal actual = resolveCachedActualValue(
                    lpm,
                    partnerPoints,
                    c.Field_API_Name__c,
                    actualByField
                );
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

    private Decimal resolveCachedActualValue(
        LoyaltyProgramMember lpm,
        Decimal partnerPoints,
        String fieldApiName,
        Map<String, Decimal> actualByField
    ) {
        if (actualByField.containsKey(fieldApiName)) {
            return actualByField.get(fieldApiName);
        }
        Decimal actual = resolveConditionActualValue(lpm, partnerPoints, fieldApiName);
        actualByField.put(fieldApiName, actual);
        return actual;
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
