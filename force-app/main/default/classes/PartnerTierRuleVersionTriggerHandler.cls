/**
 * @description Trigger handler for PartnerTierRuleVersion__c.
 */
public with sharing class PartnerTierRuleVersionTriggerHandler {

    /**
     * @description Validates release-window overlap for active rule versions.
     */
    public static void handleBefore(
        List<PartnerTierRuleVersion__c> newRecords,
        Map<Id, PartnerTierRuleVersion__c> oldMap
    ) {
        PartnerTierRuleVersionValidationService.validateNoOverlaps(newRecords);
    }
}
