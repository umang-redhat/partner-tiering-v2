/**
 * @description Comprehensive test coverage for TierEvaluationService.
 *              Tests single-member, per-module, and bulk-ready evaluation paths,
 *              point resolution, rule context loading, and all comparison operators.
 */
@isTest
private class TierEvaluationServiceTest {

    @TestSetup
    static void setup() {
        LoyaltyProgram prog = new LoyaltyProgram(Name = 'Test Partner Program', Status = 'Active');
        insert prog;

        LoyaltyProgramCurrency curr = new LoyaltyProgramCurrency(
            LoyaltyProgramId = prog.Id, Name = 'Test Points',
            CurrencyType = 'NonQualifying',
            ExpiryPeriodFrequency = 1,
            ExpiryModel = 'Fixed',
            ExpiryPeriodUnit = 'Years',
            ExtendExpiration = 'None'
        );
        insert curr;

        Account acc = new Account(Name = 'Test Partner Account');
        insert acc;

        Date today = Date.today();

        List<PartnerTierRuleVersion__c> versions = new List<PartnerTierRuleVersion__c>{
            new PartnerTierRuleVersion__c(LoyaltyProgram__c = prog.Id, Module__c = 'Build', Tier__c = 'Ready', Tier_Rank__c = 1, In_Effect_Date__c = today, Status__c = 'Active'),
            new PartnerTierRuleVersion__c(LoyaltyProgram__c = prog.Id, Module__c = 'Build', Tier__c = 'Advanced', Tier_Rank__c = 2, In_Effect_Date__c = today, Status__c = 'Active'),
            new PartnerTierRuleVersion__c(LoyaltyProgram__c = prog.Id, Module__c = 'Reseller', Tier__c = 'Ready', Tier_Rank__c = 1, In_Effect_Date__c = today, Status__c = 'Active'),
            new PartnerTierRuleVersion__c(LoyaltyProgram__c = prog.Id, Module__c = 'Reseller', Tier__c = 'Advanced', Tier_Rank__c = 2, In_Effect_Date__c = today, Status__c = 'Active'),
            new PartnerTierRuleVersion__c(LoyaltyProgram__c = prog.Id, Module__c = 'Build', Tier__c = 'Premier', Tier_Rank__c = 3, In_Effect_Date__c = today, Status__c = 'Draft'),
            new PartnerTierRuleVersion__c(LoyaltyProgram__c = prog.Id, Module__c = 'Reseller', Tier__c = 'Premier', Tier_Rank__c = 3, In_Effect_Date__c = today.addDays(365), Status__c = 'Active')
        };
        insert versions;

        Map<String, Id> vMap = new Map<String, Id>();
        for (PartnerTierRuleVersion__c v : versions) {
            vMap.put(v.Module__c + '|' + v.Tier__c + '|' + v.Status__c, v.Id);
        }

        List<PartnerTierRuleGroup__c> groups = new List<PartnerTierRuleGroup__c>{
            new PartnerTierRuleGroup__c(Rule_Version__c = vMap.get('Build|Ready|Active'), Group_Order__c = 1),
            new PartnerTierRuleGroup__c(Rule_Version__c = vMap.get('Build|Advanced|Active'), Group_Order__c = 1),
            new PartnerTierRuleGroup__c(Rule_Version__c = vMap.get('Reseller|Ready|Active'), Group_Order__c = 1),
            new PartnerTierRuleGroup__c(Rule_Version__c = vMap.get('Reseller|Advanced|Active'), Group_Order__c = 1)
        };
        insert groups;

        insert new List<PartnerTierRuleCondition__c>{
            new PartnerTierRuleCondition__c(Rule_Group__c = groups[0].Id, Condition_Order__c = 1, Field_API_Name__c = 'Account_Software_Product_Cert__c', Operator__c = '>=', Threshold__c = 1),
            new PartnerTierRuleCondition__c(Rule_Group__c = groups[1].Id, Condition_Order__c = 1, Field_API_Name__c = 'Account_Software_Product_Cert__c', Operator__c = '>=', Threshold__c = 1),
            new PartnerTierRuleCondition__c(Rule_Group__c = groups[1].Id, Condition_Order__c = 2, Field_API_Name__c = 'MinimumEligibleBalance', Operator__c = '>=', Threshold__c = 25000),
            new PartnerTierRuleCondition__c(Rule_Group__c = groups[2].Id, Condition_Order__c = 1, Field_API_Name__c = 'Account_RHSC_Credentials__c', Operator__c = '>=', Threshold__c = 2),
            new PartnerTierRuleCondition__c(Rule_Group__c = groups[2].Id, Condition_Order__c = 2, Field_API_Name__c = 'MinimumEligibleBalance', Operator__c = '>=', Threshold__c = 1),
            new PartnerTierRuleCondition__c(Rule_Group__c = groups[3].Id, Condition_Order__c = 1, Field_API_Name__c = 'Account_RHSC_Credentials__c', Operator__c = '>=', Threshold__c = 3),
            new PartnerTierRuleCondition__c(Rule_Group__c = groups[3].Id, Condition_Order__c = 2, Field_API_Name__c = 'MinimumEligibleBalance', Operator__c = '>=', Threshold__c = 25000),
            new PartnerTierRuleCondition__c(Rule_Group__c = groups[3].Id, Condition_Order__c = 3, Field_API_Name__c = 'MaximumEligibleBalance', Operator__c = '<=', Threshold__c = 99999)
        };

        String ts = String.valueOf(DateTime.now().getTime());

        LoyaltyProgramMember buildMember = new LoyaltyProgramMember(
            MemberStatus = 'Active', MemberType = 'Corporate',
            MembershipNumber = 'TST-BUILD-' + ts,
            EnrollmentDate = Date.today(), AccountId = acc.Id, ProgramId = prog.Id,
            Build_Certify__c = true, Reseller__c = false,
            Account_Software_Product_Cert__c = 1, Account_Hardware_Product_Cert__c = 0,
            Account_RHSC_Credentials__c = 0, Account_RHTSC_Credentials__c = 0,
            Account_RH_Certifications__c = 0
        );

        LoyaltyProgramMember resellerMember = new LoyaltyProgramMember(
            MemberStatus = 'Active', MemberType = 'Corporate',
            MembershipNumber = 'TST-RESELL-' + ts,
            EnrollmentDate = Date.today(), AccountId = acc.Id, ProgramId = prog.Id,
            Build_Certify__c = false, Reseller__c = true,
            Account_Software_Product_Cert__c = 0, Account_Hardware_Product_Cert__c = 0,
            Account_RHSC_Credentials__c = 3, Account_RHTSC_Credentials__c = 0,
            Account_RH_Certifications__c = 0
        );

        LoyaltyProgramMember dualMember = new LoyaltyProgramMember(
            MemberStatus = 'Active', MemberType = 'Corporate',
            MembershipNumber = 'TST-DUAL-' + ts,
            EnrollmentDate = Date.today(), AccountId = acc.Id, ProgramId = prog.Id,
            Build_Certify__c = true, Reseller__c = true,
            Account_Software_Product_Cert__c = 1, Account_Hardware_Product_Cert__c = 0,
            Account_RHSC_Credentials__c = 3, Account_RHTSC_Credentials__c = 0,
            Account_RH_Certifications__c = 0
        );

        LoyaltyProgramMember noModuleMember = new LoyaltyProgramMember(
            MemberStatus = 'Active', MemberType = 'Corporate',
            MembershipNumber = 'TST-NONE-' + ts,
            EnrollmentDate = Date.today(), AccountId = acc.Id, ProgramId = prog.Id,
            Build_Certify__c = false, Reseller__c = false,
            Account_Software_Product_Cert__c = 0, Account_Hardware_Product_Cert__c = 0,
            Account_RHSC_Credentials__c = 0, Account_RHTSC_Credentials__c = 0,
            Account_RH_Certifications__c = 0
        );

        LoyaltyProgramMember lowMember = new LoyaltyProgramMember(
            MemberStatus = 'Active', MemberType = 'Corporate',
            MembershipNumber = 'TST-LOW-' + ts,
            EnrollmentDate = Date.today(), AccountId = acc.Id, ProgramId = prog.Id,
            Build_Certify__c = true, Reseller__c = false,
            Account_Software_Product_Cert__c = 0, Account_Hardware_Product_Cert__c = 0,
            Account_RHSC_Credentials__c = 0, Account_RHTSC_Credentials__c = 0,
            Account_RH_Certifications__c = 0
        );

        insert new List<LoyaltyProgramMember>{ buildMember, resellerMember, dualMember, noModuleMember, lowMember };

        insert new List<LoyaltyMemberCurrency>{
            new LoyaltyMemberCurrency(Name = 'Build Pts', LoyaltyMemberId = buildMember.Id, LoyaltyProgramCurrencyId = curr.Id, TotalPointsAccrued = 30000),
            new LoyaltyMemberCurrency(Name = 'Reseller Pts', LoyaltyMemberId = resellerMember.Id, LoyaltyProgramCurrencyId = curr.Id, TotalPointsAccrued = 50000),
            new LoyaltyMemberCurrency(Name = 'Dual Pts', LoyaltyMemberId = dualMember.Id, LoyaltyProgramCurrencyId = curr.Id, TotalPointsAccrued = 50000)
        };
    }

    @isTest
    static void testEvaluatePartnerTier_BuildAdvanced() {
        LoyaltyProgramMember m = [SELECT Id FROM LoyaltyProgramMember WHERE MembershipNumber LIKE 'TST-BUILD-%' LIMIT 1];

        Test.startTest();
        String tier = new TierEvaluationService().evaluatePartnerTier(m.Id);
        Test.stopTest();

        System.assertEquals('Advanced', tier, 'Build member (SwCert=1, 30k pts) should reach Advanced');
    }

    @isTest
    static void testEvaluatePartnerTier_ResellerAdvanced() {
        LoyaltyProgramMember m = [SELECT Id FROM LoyaltyProgramMember WHERE MembershipNumber LIKE 'TST-RESELL-%' LIMIT 1];

        Test.startTest();
        String tier = new TierEvaluationService().evaluatePartnerTier(m.Id);
        Test.stopTest();

        System.assertEquals('Advanced', tier, 'Reseller member (RHSC=3, 50k pts) should reach Advanced');
    }

    @isTest
    static void testEvaluatePartnerTiers_DualModule() {
        LoyaltyProgramMember m = [SELECT Id FROM LoyaltyProgramMember WHERE MembershipNumber LIKE 'TST-DUAL-%' LIMIT 1];

        Test.startTest();
        Map<String, TierEvaluationService.TierResult> results = new TierEvaluationService().evaluatePartnerTiers(m.Id);
        Test.stopTest();

        System.assert(results.containsKey('Build'), 'Dual member should have Build result');
        System.assert(results.containsKey('Reseller'), 'Dual member should have Reseller result');
        System.assertEquals('Advanced', results.get('Build').tierName);
        System.assertEquals('Advanced', results.get('Reseller').tierName);
    }

    @isTest
    static void testEvaluatePartnerTier_NoModuleEnrollment() {
        LoyaltyProgramMember m = [SELECT Id FROM LoyaltyProgramMember WHERE MembershipNumber LIKE 'TST-NONE-%' LIMIT 1];

        Test.startTest();
        String tier = new TierEvaluationService().evaluatePartnerTier(m.Id);
        Test.stopTest();

        System.assertEquals(null, tier, 'Member without module enrollment should have null tier');
    }

    @isTest
    static void testEvaluatePartnerTier_InsufficientQualifications() {
        LoyaltyProgramMember m = [SELECT Id FROM LoyaltyProgramMember WHERE MembershipNumber LIKE 'TST-LOW-%' LIMIT 1];

        Test.startTest();
        Map<String, TierEvaluationService.TierResult> results = new TierEvaluationService().evaluatePartnerTiers(m.Id);
        Test.stopTest();

        System.assert(results.isEmpty(), 'Member with zero credentials should not qualify for any tier');
    }

    @isTest
    static void testEvaluatePartnerTier_MemberNotFound() {
        LoyaltyProgramMember m = [SELECT Id FROM LoyaltyProgramMember WHERE MembershipNumber LIKE 'TST-LOW-%' LIMIT 1];
        Id staleId = m.Id;
        delete m;

        TierEvaluationService svc = new TierEvaluationService();
        Boolean caught = false;

        Test.startTest();
        try {
            svc.evaluatePartnerTier(staleId);
        } catch (TierEvaluationService.TierEvaluationException e) {
            caught = true;
            System.assert(e.getMessage().contains('not found'), 'Error should mention member not found');
        }
        Test.stopTest();

        System.assert(caught, 'Expected TierEvaluationException for deleted member');
    }

    @isTest
    static void testEvaluateMembers_BulkReadyAPI() {
        List<LoyaltyProgramMember> members = [
            SELECT Id, ProgramId, MembershipNumber, Build_Certify__c, Reseller__c,
                   Account_Software_Product_Cert__c, Account_Hardware_Product_Cert__c,
                   Account_RHSC_Credentials__c, Account_RHTSC_Credentials__c, Account_RH_Certifications__c
            FROM LoyaltyProgramMember
            WHERE MembershipNumber LIKE 'TST-%'
        ];
        Set<Id> memberIds = new Map<Id, LoyaltyProgramMember>(members).keySet();

        TierEvaluationService svc = new TierEvaluationService();
        TierEvaluationService.RuleContext ctx = svc.loadRuleContext();
        Map<Id, Decimal> pointsByMember = svc.bulkLoadPointBalances(memberIds);

        Test.startTest();
        Map<Id, Map<String, TierEvaluationService.TierResult>> resultsByMember =
            svc.evaluateMembers(members, pointsByMember, ctx);
        Test.stopTest();

        System.assert(resultsByMember.size() > 0, 'evaluateMembers should return results');
        for (LoyaltyProgramMember m : members) {
            if (m.Build_Certify__c != true && m.Reseller__c != true) {
                continue;
            }
            System.assert(resultsByMember.containsKey(m.Id), 'Each enrolled member should be evaluated');
        }
    }

    @isTest
    static void testEvaluateMember_BulkReadyAPI() {
        LoyaltyProgramMember m = [
            SELECT Id, ProgramId, MembershipNumber, Build_Certify__c, Reseller__c,
                   Account_Software_Product_Cert__c, Account_Hardware_Product_Cert__c,
                   Account_RHSC_Credentials__c, Account_RHTSC_Credentials__c, Account_RH_Certifications__c
            FROM LoyaltyProgramMember
            WHERE MembershipNumber LIKE 'TST-BUILD-%'
            LIMIT 1
        ];

        TierEvaluationService svc = new TierEvaluationService();

        Test.startTest();
        TierEvaluationService.RuleContext ctx = svc.loadRuleContext();
        Map<String, TierEvaluationService.TierResult> results = svc.evaluateMember(m, 30000, ctx);
        Test.stopTest();

        System.assert(results.containsKey('Build'), 'evaluateMember should return Build result');
        System.assertEquals('Advanced', results.get('Build').tierName);
        System.assertEquals(2, results.get('Build').tierRank);
    }

    @isTest
    static void testLoadRuleContext_FiltersCorrectly() {
        TierEvaluationService svc = new TierEvaluationService();

        Test.startTest();
        TierEvaluationService.RuleContext ctx = svc.loadRuleContext();
        Test.stopTest();

        System.assertEquals(4, ctx.activeVersions.size(), 'Should load only active versions effective today');
        for (PartnerTierRuleVersion__c v : ctx.activeVersions) {
            System.assert(v.In_Effect_Date__c <= Date.today(), 'Future versions should be excluded');
            System.assertNotEquals('Premier', v.Tier__c, 'Draft/future Premier versions should be excluded');
        }
        System.assert(!ctx.groupsByVersion.isEmpty(), 'Groups should be loaded');
        System.assert(!ctx.conditionsByGroup.isEmpty(), 'Conditions should be loaded');
    }

    @isTest
    static void testBulkLoadPointBalances() {
        List<LoyaltyProgramMember> members = [SELECT Id FROM LoyaltyProgramMember WHERE MembershipNumber LIKE 'TST-%'];
        Set<Id> memberIds = new Set<Id>();
        for (LoyaltyProgramMember m : members) {
            memberIds.add(m.Id);
        }

        Test.startTest();
        Map<Id, Decimal> balances = new TierEvaluationService().bulkLoadPointBalances(memberIds);
        Test.stopTest();

        System.assertEquals(memberIds.size(), balances.size(), 'Should return entry for every member');
        for (Id mId : memberIds) {
            System.assert(balances.containsKey(mId), 'Balance map should contain every requested member');
        }
    }

    @isTest
    static void testPickOverallHighest() {
        Map<String, TierEvaluationService.TierResult> results = new Map<String, TierEvaluationService.TierResult>{
            'Build' => new TierEvaluationService.TierResult('Build', 'Ready', 1),
            'Reseller' => new TierEvaluationService.TierResult('Reseller', 'Advanced', 2)
        };

        String highest = new TierEvaluationService().pickOverallHighest(results);

        System.assertEquals('Advanced', highest, 'Should pick the tier with highest rank');
    }

    @isTest
    static void testPickOverallHighest_EmptyMap() {
        String highest = new TierEvaluationService().pickOverallHighest(
            new Map<String, TierEvaluationService.TierResult>()
        );
        System.assertEquals(null, highest, 'Empty results should return null');
    }

    @isTest
    static void testAllComparisonOperators() {
        PartnerTierRuleVersion__c version = new PartnerTierRuleVersion__c(
            LoyaltyProgram__c = [SELECT Id FROM LoyaltyProgram LIMIT 1].Id,
            Module__c = 'Build', Tier__c = 'Premier', Tier_Rank__c = 10,
            In_Effect_Date__c = Date.today(), Status__c = 'Active'
        );
        insert version;

        PartnerTierRuleGroup__c grp = new PartnerTierRuleGroup__c(
            Rule_Version__c = version.Id, Group_Order__c = 1
        );
        insert grp;

        insert new List<PartnerTierRuleCondition__c>{
            new PartnerTierRuleCondition__c(Rule_Group__c = grp.Id, Condition_Order__c = 1, Field_API_Name__c = 'Account_Software_Product_Cert__c', Operator__c = '>', Threshold__c = 0),
            new PartnerTierRuleCondition__c(Rule_Group__c = grp.Id, Condition_Order__c = 2, Field_API_Name__c = 'Account_RHSC_Credentials__c', Operator__c = '=', Threshold__c = 0),
            new PartnerTierRuleCondition__c(Rule_Group__c = grp.Id, Condition_Order__c = 3, Field_API_Name__c = 'Account_Hardware_Product_Cert__c', Operator__c = '!=', Threshold__c = 99),
            new PartnerTierRuleCondition__c(Rule_Group__c = grp.Id, Condition_Order__c = 4, Field_API_Name__c = 'Account_RHTSC_Credentials__c', Operator__c = '<', Threshold__c = 5)
        };

        LoyaltyProgramMember m = [SELECT Id FROM LoyaltyProgramMember WHERE MembershipNumber LIKE 'TST-BUILD-%' LIMIT 1];

        Test.startTest();
        Map<String, TierEvaluationService.TierResult> results = new TierEvaluationService().evaluatePartnerTiers(m.Id);
        Test.stopTest();

        System.assert(results.containsKey('Build'), 'All operators should pass for this member');
        System.assertEquals('Premier', results.get('Build').tierName, 'Premier (rank 10) should be the highest');
    }

    @isTest
    static void testOrGroupLogic() {
        PartnerTierRuleVersion__c version = [
            SELECT Id FROM PartnerTierRuleVersion__c
            WHERE Module__c = 'Build' AND Tier__c = 'Ready' AND Status__c = 'Active'
            LIMIT 1
        ];

        PartnerTierRuleGroup__c secondGroup = new PartnerTierRuleGroup__c(
            Rule_Version__c = version.Id, Group_Order__c = 2
        );
        insert secondGroup;

        insert new PartnerTierRuleCondition__c(
            Rule_Group__c = secondGroup.Id, Condition_Order__c = 1,
            Field_API_Name__c = 'Account_Hardware_Product_Cert__c', Operator__c = '>=', Threshold__c = 1
        );

        LoyaltyProgramMember m = [
            SELECT Id, ProgramId, MembershipNumber, Build_Certify__c, Reseller__c,
                   Account_Software_Product_Cert__c, Account_Hardware_Product_Cert__c,
                   Account_RHSC_Credentials__c, Account_RHTSC_Credentials__c, Account_RH_Certifications__c
            FROM LoyaltyProgramMember
            WHERE MembershipNumber LIKE 'TST-BUILD-%'
            LIMIT 1
        ];

        TierEvaluationService svc = new TierEvaluationService();
        TierEvaluationService.RuleContext ctx = svc.loadRuleContext();

        Test.startTest();
        Map<String, TierEvaluationService.TierResult> results = svc.evaluateMember(m, 0, ctx);
        Test.stopTest();

        System.assert(results.containsKey('Build'), 'First OR group (SwCert>=1) should satisfy Build Ready');
    }

    @isTest
    static void testIncompleteCondition_ReturnsFalse() {
        delete [SELECT Id FROM PartnerTierRuleCondition__c];
        delete [SELECT Id FROM PartnerTierRuleGroup__c];

        PartnerTierRuleVersion__c version = [
            SELECT Id FROM PartnerTierRuleVersion__c
            WHERE Module__c = 'Build' AND Tier__c = 'Ready' AND Status__c = 'Active'
            LIMIT 1
        ];

        PartnerTierRuleGroup__c grp = new PartnerTierRuleGroup__c(Rule_Version__c = version.Id, Group_Order__c = 1);
        insert grp;

        insert new PartnerTierRuleCondition__c(
            Rule_Group__c = grp.Id, Condition_Order__c = 1,
            Field_API_Name__c = 'Account_Software_Product_Cert__c', Operator__c = '>=', Threshold__c = 999
        );

        LoyaltyProgramMember m = [SELECT Id FROM LoyaltyProgramMember WHERE MembershipNumber LIKE 'TST-BUILD-%' LIMIT 1];

        Test.startTest();
        Map<String, TierEvaluationService.TierResult> results = new TierEvaluationService().evaluatePartnerTiers(m.Id);
        Test.stopTest();

        System.assert(!results.containsKey('Build') || results.get('Build').tierName != 'Ready',
            'Unreachable threshold should prevent tier qualification');
    }

    @isTest
    static void testNoGroups_ReturnsFalse() {
        delete [SELECT Id FROM PartnerTierRuleCondition__c];
        delete [SELECT Id FROM PartnerTierRuleGroup__c];

        LoyaltyProgramMember m = [SELECT Id FROM LoyaltyProgramMember WHERE MembershipNumber LIKE 'TST-BUILD-%' LIMIT 1];

        Test.startTest();
        Map<String, TierEvaluationService.TierResult> results = new TierEvaluationService().evaluatePartnerTiers(m.Id);
        Test.stopTest();

        System.assert(results.isEmpty(), 'No groups configured should yield no results');
    }

    @isTest
    static void testProgramScopedEvaluation_IgnoresOtherProgramRules() {
        LoyaltyProgram otherProgram = new LoyaltyProgram(Name = 'Other Test Program', Status = 'Active');
        insert otherProgram;

        PartnerTierRuleVersion__c otherProgramVersion = new PartnerTierRuleVersion__c(
            LoyaltyProgram__c = otherProgram.Id,
            Module__c = 'Build', Tier__c = 'Premier', Tier_Rank__c = 99,
            In_Effect_Date__c = Date.today(), Status__c = 'Active'
        );
        insert otherProgramVersion;

        PartnerTierRuleGroup__c grp = new PartnerTierRuleGroup__c(
            Rule_Version__c = otherProgramVersion.Id, Group_Order__c = 1
        );
        insert grp;

        insert new PartnerTierRuleCondition__c(
            Rule_Group__c = grp.Id, Condition_Order__c = 1,
            Field_API_Name__c = 'Account_Software_Product_Cert__c', Operator__c = '>=', Threshold__c = 1
        );

        LoyaltyProgramMember m = [SELECT Id FROM LoyaltyProgramMember WHERE MembershipNumber LIKE 'TST-BUILD-%' LIMIT 1];

        Test.startTest();
        Map<String, TierEvaluationService.TierResult> results = new TierEvaluationService().evaluatePartnerTiers(m.Id);
        Test.stopTest();

        System.assertEquals('Advanced', results.get('Build').tierName,
            'Member should use rules from its own program, not another program');
    }
}
