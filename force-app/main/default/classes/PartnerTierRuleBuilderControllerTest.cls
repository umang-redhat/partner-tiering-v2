/**
 * @description Tests for the PartnerTierRuleBuilderController Aura-enabled
 *              methods: getRuleVersionGraph, getConditionFieldOptions,
 *              getOperatorOptions, and saveRuleVersionGraph.
 */
@isTest
private class PartnerTierRuleBuilderControllerTest {

    @TestSetup
    static void setup() {
        PartnerTierRuleVersion__c version = new PartnerTierRuleVersion__c(
            Module__c = 'Build', Tier__c = 'Ready', Tier_Rank__c = 1,
            In_Effect_Date__c = Date.today(), Status__c = 'Active'
        );
        insert version;

        PartnerTierRuleGroup__c grp = new PartnerTierRuleGroup__c(
            Rule_Version__c = version.Id, Group_Order__c = 1
        );
        insert grp;

        insert new List<PartnerTierRuleCondition__c>{
            new PartnerTierRuleCondition__c(
                Rule_Group__c = grp.Id, Condition_Order__c = 1,
                Field_API_Name__c = 'Account_Software_Product_Cert__c',
                Operator__c = '>=', Threshold__c = 1
            ),
            new PartnerTierRuleCondition__c(
                Rule_Group__c = grp.Id, Condition_Order__c = 2,
                Field_API_Name__c = 'MinimumEligibleBalance',
                Operator__c = '>=', Threshold__c = 1000
            )
        };
    }

    @isTest
    static void testGetRuleVersionGraph_HappyPath() {
        PartnerTierRuleVersion__c version = [SELECT Id FROM PartnerTierRuleVersion__c LIMIT 1];

        Test.startTest();
        PartnerTierRuleBuilderController.RuleVersionDTO dto =
            PartnerTierRuleBuilderController.getRuleVersionGraph(version.Id);
        Test.stopTest();

        System.assertEquals(version.Id, dto.id);
        System.assertEquals('Build', dto.moduleName);
        System.assertEquals('Ready', dto.tierName);
        System.assertEquals('Active', dto.status);
        System.assertEquals(1, dto.groups.size(), 'Should have 1 group');
        System.assertEquals(2, dto.groups[0].conditions.size(), 'Group should have 2 conditions');
        System.assertEquals('Account_Software_Product_Cert__c', dto.groups[0].conditions[0].fieldApiName);
        System.assertEquals(1000, dto.groups[0].conditions[1].threshold);
    }

    @isTest
    static void testGetRuleVersionGraph_NullId() {
        Boolean caught = false;
        Test.startTest();
        try {
            PartnerTierRuleBuilderController.getRuleVersionGraph(null);
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();
        System.assert(caught, 'Expected AuraHandledException for null ruleVersionId');
    }

    @isTest
    static void testGetConditionFieldOptions() {
        Test.startTest();
        List<PartnerTierRuleBuilderController.SelectOptionDTO> options =
            PartnerTierRuleBuilderController.getConditionFieldOptions();
        Test.stopTest();

        System.assertEquals(7, options.size(), 'Should return 7 field options');

        Set<String> values = new Set<String>();
        for (PartnerTierRuleBuilderController.SelectOptionDTO opt : options) {
            values.add(opt.value);
        }
        System.assert(values.contains('MinimumEligibleBalance'));
        System.assert(values.contains('MaximumEligibleBalance'));
        System.assert(values.contains('Account_Software_Product_Cert__c'));
        System.assert(values.contains('Account_RHSC_Credentials__c'));
    }

    @isTest
    static void testGetOperatorOptions() {
        Test.startTest();
        List<PartnerTierRuleBuilderController.SelectOptionDTO> options =
            PartnerTierRuleBuilderController.getOperatorOptions();
        Test.stopTest();

        System.assertEquals(6, options.size(), 'Should return 6 operator options');

        Set<String> values = new Set<String>();
        for (PartnerTierRuleBuilderController.SelectOptionDTO opt : options) {
            values.add(opt.value);
        }
        System.assert(values.contains('>='));
        System.assert(values.contains('!='));
    }

    @isTest
    static void testSaveRuleVersionGraph_CreateNew() {
        PartnerTierRuleVersion__c version = new PartnerTierRuleVersion__c(
            Module__c = 'Reseller', Tier__c = 'Advanced', Tier_Rank__c = 2,
            In_Effect_Date__c = Date.today(), Status__c = 'Active'
        );
        insert version;

        String groupsJson = '[' +
            '{"id":null,"groupOrder":1,"conditions":[' +
                '{"id":null,"conditionOrder":1,"fieldApiName":"Account_RHSC_Credentials__c","operatorValue":">=","threshold":3},' +
                '{"id":null,"conditionOrder":2,"fieldApiName":"MinimumEligibleBalance","operatorValue":">=","threshold":25000}' +
            ']}' +
        ']';

        Test.startTest();
        PartnerTierRuleBuilderController.saveRuleVersionGraph(version.Id, groupsJson);
        Test.stopTest();

        List<PartnerTierRuleGroup__c> groups = [
            SELECT Id FROM PartnerTierRuleGroup__c WHERE Rule_Version__c = :version.Id
        ];
        System.assertEquals(1, groups.size(), 'Should have 1 group');

        List<PartnerTierRuleCondition__c> conds = [
            SELECT Field_API_Name__c, Operator__c, Threshold__c
            FROM PartnerTierRuleCondition__c
            WHERE Rule_Group__c = :groups[0].Id
            ORDER BY Condition_Order__c
        ];
        System.assertEquals(2, conds.size(), 'Should have 2 conditions');
        System.assertEquals('Account_RHSC_Credentials__c', conds[0].Field_API_Name__c);
        System.assertEquals(25000, conds[1].Threshold__c);
    }

    @isTest
    static void testSaveRuleVersionGraph_UpdateExisting() {
        PartnerTierRuleVersion__c version = [SELECT Id FROM PartnerTierRuleVersion__c LIMIT 1];
        PartnerTierRuleGroup__c existingGroup = [SELECT Id FROM PartnerTierRuleGroup__c WHERE Rule_Version__c = :version.Id LIMIT 1];

        String groupsJson = '[{"id":"' + existingGroup.Id + '","groupOrder":1,"conditions":[' +
            '{"id":null,"conditionOrder":1,"fieldApiName":"Account_Hardware_Product_Cert__c","operatorValue":">=","threshold":2}' +
        ']}]';

        Test.startTest();
        PartnerTierRuleBuilderController.saveRuleVersionGraph(version.Id, groupsJson);
        Test.stopTest();

        List<PartnerTierRuleCondition__c> conds = [
            SELECT Field_API_Name__c FROM PartnerTierRuleCondition__c WHERE Rule_Group__c = :existingGroup.Id
        ];
        System.assertEquals(1, conds.size(), 'Old conditions should be removed, new one added');
        System.assertEquals('Account_Hardware_Product_Cert__c', conds[0].Field_API_Name__c);
    }

    @isTest
    static void testSaveRuleVersionGraph_DeletesRemovedGroups() {
        PartnerTierRuleVersion__c version = [SELECT Id FROM PartnerTierRuleVersion__c LIMIT 1];

        PartnerTierRuleGroup__c extraGroup = new PartnerTierRuleGroup__c(
            Rule_Version__c = version.Id, Group_Order__c = 2
        );
        insert extraGroup;
        insert new PartnerTierRuleCondition__c(
            Rule_Group__c = extraGroup.Id, Condition_Order__c = 1,
            Field_API_Name__c = 'Account_RHSC_Credentials__c', Operator__c = '>=', Threshold__c = 1
        );

        System.assertEquals(2, [SELECT COUNT() FROM PartnerTierRuleGroup__c WHERE Rule_Version__c = :version.Id]);

        String groupsJson = '[{"id":null,"groupOrder":1,"conditions":[' +
            '{"id":null,"conditionOrder":1,"fieldApiName":"Account_Software_Product_Cert__c","operatorValue":">=","threshold":1}' +
        ']}]';

        Test.startTest();
        PartnerTierRuleBuilderController.saveRuleVersionGraph(version.Id, groupsJson);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM PartnerTierRuleGroup__c WHERE Rule_Version__c = :version.Id],
            'Extra group should be deleted');
    }

    @isTest
    static void testSaveRuleVersionGraph_NullVersionId() {
        Boolean caught = false;
        Test.startTest();
        try {
            PartnerTierRuleBuilderController.saveRuleVersionGraph(null, '[{}]');
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();
        System.assert(caught, 'Expected AuraHandledException for null ruleVersionId');
    }

    @isTest
    static void testSaveRuleVersionGraph_EmptyJson() {
        PartnerTierRuleVersion__c version = [SELECT Id FROM PartnerTierRuleVersion__c LIMIT 1];
        Boolean caught = false;

        Test.startTest();
        try {
            PartnerTierRuleBuilderController.saveRuleVersionGraph(version.Id, '');
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();
        System.assert(caught, 'Expected AuraHandledException for empty groupsJson');
    }

    @isTest
    static void testSaveRuleVersionGraph_SkipsIncompleteConditions() {
        PartnerTierRuleVersion__c version = [SELECT Id FROM PartnerTierRuleVersion__c LIMIT 1];

        String groupsJson = '[{"id":null,"groupOrder":1,"conditions":[' +
            '{"id":null,"conditionOrder":1,"fieldApiName":"Account_Software_Product_Cert__c","operatorValue":">=","threshold":1},' +
            '{"id":null,"conditionOrder":2,"fieldApiName":"","operatorValue":"","threshold":null}' +
        ']}]';

        Test.startTest();
        PartnerTierRuleBuilderController.saveRuleVersionGraph(version.Id, groupsJson);
        Test.stopTest();

        PartnerTierRuleGroup__c grp = [
            SELECT Id FROM PartnerTierRuleGroup__c
            WHERE Rule_Version__c = :version.Id
            ORDER BY Group_Order__c LIMIT 1
        ];
        List<PartnerTierRuleCondition__c> conds = [
            SELECT Id FROM PartnerTierRuleCondition__c WHERE Rule_Group__c = :grp.Id
        ];
        System.assertEquals(1, conds.size(), 'Incomplete condition should be skipped');
    }

    @isTest
    static void testSelectOptionDTO() {
        PartnerTierRuleBuilderController.SelectOptionDTO opt =
            new PartnerTierRuleBuilderController.SelectOptionDTO('My Label', 'my_value');
        System.assertEquals('My Label', opt.label);
        System.assertEquals('my_value', opt.value);
    }
}
