/**
 * @description Tests for TierEvaluationBatch. Verifies the batch lifecycle
 *              (start → execute → finish) runs without errors against
 *              representative loyalty member data.
 */
@isTest
private class TierEvaluationBatchTest {

    @TestSetup
    static void setup() {
        LoyaltyProgram prog = new LoyaltyProgram(Name = 'Batch Test Program', Status = 'Active');
        insert prog;

        LoyaltyProgramCurrency curr = new LoyaltyProgramCurrency(
            LoyaltyProgramId = prog.Id, Name = 'Batch Points',
            CurrencyType = 'NonQualifying',
            ExpiryPeriodFrequency = 1,
            ExpiryModel = 'Fixed',
            ExpiryPeriodUnit = 'Years',
            ExtendExpiration = 'None'
        );
        insert curr;

        Account acc = new Account(Name = 'Batch Test Account');
        insert acc;

        Date today = Date.today();

        PartnerTierRuleVersion__c version = new PartnerTierRuleVersion__c(
            LoyaltyProgram__c = prog.Id,
            Module__c = 'Build', Tier__c = 'Ready', Tier_Rank__c = 1,
            In_Effect_Date__c = today, Status__c = 'Active'
        );
        insert version;

        PartnerTierRuleGroup__c grp = new PartnerTierRuleGroup__c(
            Rule_Version__c = version.Id, Group_Order__c = 1
        );
        insert grp;

        insert new PartnerTierRuleCondition__c(
            Rule_Group__c = grp.Id, Condition_Order__c = 1,
            Field_API_Name__c = 'Account_Software_Product_Cert__c',
            Operator__c = '>=', Threshold__c = 1
        );

        String ts = String.valueOf(DateTime.now().getTime());
        List<LoyaltyProgramMember> members = new List<LoyaltyProgramMember>();

        for (Integer i = 0; i < 5; i++) {
            members.add(new LoyaltyProgramMember(
                MemberStatus = 'Active', MemberType = 'Corporate',
                MembershipNumber = 'BATCH-' + i + '-' + ts,
                EnrollmentDate = Date.today(), AccountId = acc.Id, ProgramId = prog.Id,
                Build_Certify__c = true, Reseller__c = false,
                Account_Software_Product_Cert__c = i + 1,
                Account_Hardware_Product_Cert__c = 0,
                Account_RHSC_Credentials__c = 0,
                Account_RHTSC_Credentials__c = 0,
                Account_RH_Certifications__c = 0
            ));
        }
        insert members;

        List<LoyaltyMemberCurrency> memberCurrencies = new List<LoyaltyMemberCurrency>();
        for (LoyaltyProgramMember m : members) {
            memberCurrencies.add(new LoyaltyMemberCurrency(
                Name = 'Pts-' + m.MembershipNumber,
                LoyaltyMemberId = m.Id,
                LoyaltyProgramCurrencyId = curr.Id,
                TotalPointsAccrued = 10000
            ));
        }
        insert memberCurrencies;
    }

    @isTest
    static void testBatchExecution() {
        Test.startTest();
        Id batchId = Database.executeBatch(new TierEvaluationBatch(), 200);
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :batchId
        ];
        System.assertEquals('Completed', job.Status, 'Batch should complete successfully');
        System.assertEquals(0, job.NumberOfErrors, 'Batch should have zero errors');
    }
}
