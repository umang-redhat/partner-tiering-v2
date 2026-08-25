/**
 * @description Domain validation service for partner tier rule versions.
 */
public with sharing class PartnerTierRuleVersionValidationService {

    /**
     * @description Prevents multiple active versions for the same LoyaltyProgram + Module + Tier.
     */
    public static void validateNoDuplicateActiveVersions(List<PartnerTierRuleVersion__c> newRecords) {
        Set<Id> programIds = new Set<Id>();
        Set<String> modules = new Set<String>();
        Set<String> tiers = new Set<String>();
        Set<Id> currentIds = new Set<Id>();

        for (PartnerTierRuleVersion__c rec : newRecords) {
            if (rec.Id != null) {
                currentIds.add(rec.Id);
            }
            if (rec.Status__c == 'Active'
                && rec.LoyaltyProgram__c != null
                && rec.Module__c != null
                && rec.Tier__c != null) {
                programIds.add(rec.LoyaltyProgram__c);
                modules.add(rec.Module__c);
                tiers.add(rec.Tier__c);
            }
        }

        if (programIds.isEmpty() || modules.isEmpty() || tiers.isEmpty()) {
            return;
        }

        List<PartnerTierRuleVersion__c> existing = [
            SELECT Id, LoyaltyProgram__c, Module__c, Tier__c
            FROM PartnerTierRuleVersion__c
            WHERE Status__c = 'Active'
            AND LoyaltyProgram__c IN :programIds
            AND Module__c IN :modules
            AND Tier__c IN :tiers
            AND Id NOT IN :currentIds
        ];

        for (PartnerTierRuleVersion__c incoming : newRecords) {
            if (incoming.Status__c != 'Active') {
                continue;
            }
            for (PartnerTierRuleVersion__c ex : existing) {
                if (incoming.LoyaltyProgram__c != ex.LoyaltyProgram__c
                    || incoming.Module__c != ex.Module__c
                    || incoming.Tier__c != ex.Tier__c) {
                    continue;
                }
                incoming.addError(
                    'Another active version already exists for this program, ' +
                    incoming.Module__c + ' / ' + incoming.Tier__c +
                    '. Deactivate the old version before activating a new one.'
                );
                break;
            }
        }
    }
}
