/**
 * @description Tests for the PartnerTierRuleVersionValidationService and its
 *              associated trigger. Covers overlap detection for active rule
 *              versions sharing the same Module + Tier combination.
 */
@isTest
private class RuleVersionValidationTest {

    @isTest
    static void testInsertSingleActiveVersion_Succeeds() {
        PartnerTierRuleVersion__c v = new PartnerTierRuleVersion__c(
            Module__c = 'Build', Tier__c = 'Ready', Tier_Rank__c = 1,
            In_Effect_Date__c = Date.today(), Status__c = 'Active'
        );

        Test.startTest();
        insert v;
        Test.stopTest();

        System.assertNotEquals(null, v.Id, 'Single active version should insert successfully');
    }

    @isTest
    static void testInsertDuplicateActiveVersion_Blocked() {
        insert new PartnerTierRuleVersion__c(
            Module__c = 'Reseller', Tier__c = 'Advanced', Tier_Rank__c = 2,
            In_Effect_Date__c = Date.today(), Status__c = 'Active'
        );

        PartnerTierRuleVersion__c dup = new PartnerTierRuleVersion__c(
            Module__c = 'Reseller', Tier__c = 'Advanced', Tier_Rank__c = 2,
            In_Effect_Date__c = Date.today(), Status__c = 'Active'
        );

        Test.startTest();
        try {
            insert dup;
            System.assert(false, 'Expected DmlException for duplicate active version');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('Another active version already exists'),
                'Error should reference existing active version: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @isTest
    static void testInsertDraftVersion_NoConflict() {
        insert new PartnerTierRuleVersion__c(
            Module__c = 'Build', Tier__c = 'Premier', Tier_Rank__c = 3,
            In_Effect_Date__c = Date.today(), Status__c = 'Active'
        );

        PartnerTierRuleVersion__c draft = new PartnerTierRuleVersion__c(
            Module__c = 'Build', Tier__c = 'Premier', Tier_Rank__c = 3,
            In_Effect_Date__c = Date.today(), Status__c = 'Draft'
        );

        Test.startTest();
        insert draft;
        Test.stopTest();

        System.assertNotEquals(null, draft.Id, 'Draft version should not conflict with active version');
    }

    @isTest
    static void testDifferentModuleTier_NoConflict() {
        insert new PartnerTierRuleVersion__c(
            Module__c = 'Build', Tier__c = 'Ready', Tier_Rank__c = 1,
            In_Effect_Date__c = Date.today(), Status__c = 'Active'
        );

        PartnerTierRuleVersion__c differentTier = new PartnerTierRuleVersion__c(
            Module__c = 'Build', Tier__c = 'Advanced', Tier_Rank__c = 2,
            In_Effect_Date__c = Date.today(), Status__c = 'Active'
        );

        PartnerTierRuleVersion__c differentModule = new PartnerTierRuleVersion__c(
            Module__c = 'Reseller', Tier__c = 'Ready', Tier_Rank__c = 1,
            In_Effect_Date__c = Date.today(), Status__c = 'Active'
        );

        Test.startTest();
        insert new List<PartnerTierRuleVersion__c>{ differentTier, differentModule };
        Test.stopTest();

        System.assertNotEquals(null, differentTier.Id);
        System.assertNotEquals(null, differentModule.Id);
    }

    @isTest
    static void testUpdateToActive_WhenConflictExists_Blocked() {
        insert new PartnerTierRuleVersion__c(
            Module__c = 'Reseller', Tier__c = 'Ready', Tier_Rank__c = 1,
            In_Effect_Date__c = Date.today(), Status__c = 'Active'
        );

        PartnerTierRuleVersion__c draft = new PartnerTierRuleVersion__c(
            Module__c = 'Reseller', Tier__c = 'Ready', Tier_Rank__c = 1,
            In_Effect_Date__c = Date.today(), Status__c = 'Draft'
        );
        insert draft;

        draft.Status__c = 'Active';

        Test.startTest();
        try {
            update draft;
            System.assert(false, 'Expected DmlException when promoting to Active with conflict');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('Another active version already exists'),
                'Error should reference existing active version: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @isTest
    static void testBulkInsert_MixedValidity() {
        insert new PartnerTierRuleVersion__c(
            Module__c = 'Build', Tier__c = 'Ready', Tier_Rank__c = 1,
            In_Effect_Date__c = Date.today(), Status__c = 'Active'
        );

        List<PartnerTierRuleVersion__c> batch = new List<PartnerTierRuleVersion__c>{
            new PartnerTierRuleVersion__c(Module__c = 'Build', Tier__c = 'Advanced', Tier_Rank__c = 2, In_Effect_Date__c = Date.today(), Status__c = 'Active'),
            new PartnerTierRuleVersion__c(Module__c = 'Build', Tier__c = 'Ready', Tier_Rank__c = 1, In_Effect_Date__c = Date.today(), Status__c = 'Active')
        };

        Test.startTest();
        List<Database.SaveResult> results = Database.insert(batch, false);
        Test.stopTest();

        System.assert(results[0].isSuccess(), 'Build/Advanced should succeed');
        System.assert(!results[1].isSuccess(), 'Duplicate Build/Ready should fail');
    }

    @isTest
    static void testValidation_SkipsNonActiveRecords() {
        List<PartnerTierRuleVersion__c> batch = new List<PartnerTierRuleVersion__c>{
            new PartnerTierRuleVersion__c(Module__c = 'Build', Tier__c = 'Ready', Tier_Rank__c = 1, In_Effect_Date__c = Date.today(), Status__c = 'Draft'),
            new PartnerTierRuleVersion__c(Module__c = 'Build', Tier__c = 'Ready', Tier_Rank__c = 1, In_Effect_Date__c = Date.today(), Status__c = 'Draft')
        };

        Test.startTest();
        insert batch;
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM PartnerTierRuleVersion__c WHERE Module__c = 'Build' AND Tier__c = 'Ready']);
    }
}
