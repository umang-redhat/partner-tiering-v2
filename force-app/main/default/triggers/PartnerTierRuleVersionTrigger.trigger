trigger PartnerTierRuleVersionTrigger on PartnerTierRuleVersion__c (before insert, before update) {
    if (Trigger.isBefore) {
        PartnerTierRuleVersionTriggerHandler.handleBefore(Trigger.new);
    }
}
