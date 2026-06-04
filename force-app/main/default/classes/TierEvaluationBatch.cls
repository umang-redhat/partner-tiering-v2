/**
 * @description Batch job that evaluates tier eligibility for all active
 *              LoyaltyProgramMember records. Rules are loaded once per
 *              execute() chunk; point balances are bulk-queried per chunk.
 *
 *              Results are logged via System.debug. Extend finish() or
 *              the per-member block to persist results as needed.
 *
 * Usage:
 *   Database.executeBatch(new TierEvaluationBatch(), 200);
 */
public with sharing class TierEvaluationBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
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
            WHERE MemberStatus = 'Active'
            AND (Build_Certify__c = true OR Reseller__c = true)
        ]);
    }

    public void execute(Database.BatchableContext bc, List<LoyaltyProgramMember> scope) {
        if (scope.isEmpty()) {
            return;
        }
        TierEvaluationService svc = new TierEvaluationService();

        TierEvaluationService.RuleContext ctx = svc.loadRuleContext();

        Set<Id> memberIds = new Set<Id>();
        for (LoyaltyProgramMember lpm : scope) {
            memberIds.add(lpm.Id);
        }
        Map<Id, Decimal> pointsByMember = svc.bulkLoadPointBalances(memberIds);
        Map<Id, Map<String, TierEvaluationService.TierResult>> resultsByMember =
            svc.evaluateMembers(scope, pointsByMember, ctx);

        for (LoyaltyProgramMember lpm : scope) {
            Map<String, TierEvaluationService.TierResult> results = resultsByMember.get(lpm.Id);
            if (results == null || results.isEmpty()) {
                continue;
            }

            for (TierEvaluationService.TierResult tr : results.values()) {
                System.debug(
                    'TierEvaluationBatch | Member ' + lpm.MembershipNumber +
                    ' | Module: ' + tr.moduleName +
                    ' | Tier: ' + tr.tierName +
                    ' (Rank ' + tr.tierRank + ')'
                );
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('TierEvaluationBatch completed. Job Id: ' + bc.getJobId());
    }
}
