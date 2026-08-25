/**
 * @description Trigger handler for PartnerTierRuleVersion__c.
 */
public with sharing class PartnerTierRuleVersionTriggerHandler {

    /**
     * @description Validates duplicate active versions before insert/update.
     */
    public static void handleBefore(List<PartnerTierRuleVersion__c> newRecords) {
        PartnerTierRuleVersionValidationService.validateNoDuplicateActiveVersions(newRecords);
    }
}
