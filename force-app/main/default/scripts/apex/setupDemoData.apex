/**
 * Demo data setup for custom-object rule model:
 * PartnerTierRuleVersion__c -> PartnerTierRuleGroup__c -> PartnerTierRuleCondition__c.
 */

// 1) Resolve an active LoyaltyProgram and one currency.
List<LoyaltyProgram> progs = [
    SELECT Id
    FROM LoyaltyProgram
    WHERE Type = 'LOYALTY_PROGRAM' AND Status = 'Active'
    ORDER BY IsPrimary DESC
    LIMIT 1
];
if (progs.isEmpty()) {
    throw new System.HandledException('No active LOYALTY_PROGRAM found in this org.');
}
Id programId = progs[0].Id;

List<LoyaltyProgramCurrency> currencies = [
    SELECT Id, Name
    FROM LoyaltyProgramCurrency
    WHERE LoyaltyProgramId = :programId
    ORDER BY Name
    LIMIT 1
];
if (currencies.isEmpty()) {
    throw new System.HandledException('No LoyaltyProgramCurrency found for program ' + programId);
}
Id currencyId = currencies[0].Id;

// 2) Reset and seed Build/Reseller rule versions for demo.
List<PartnerTierRuleVersion__c> existingVersions = [
    SELECT Id
    FROM PartnerTierRuleVersion__c
    WHERE Module__c IN ('Build', 'Reseller')
];
if (!existingVersions.isEmpty()) {
    delete existingVersions;
}

Date todayDate = Date.today();

List<PartnerTierRuleVersion__c> seededVersions = new List<PartnerTierRuleVersion__c>{
    new PartnerTierRuleVersion__c(
        Module__c = 'Build',
        Tier__c = 'Ready',
        Tier_Rank__c = 1,
        Min_Points__c = 5000,
        In_Effect_Date__c = todayDate,
        Status__c = 'Active'
    ),
    new PartnerTierRuleVersion__c(
        Module__c = 'Build',
        Tier__c = 'Advanced',
        Tier_Rank__c = 2,
        Min_Points__c = 25000,
        In_Effect_Date__c = todayDate,
        Status__c = 'Active'
    ),
    new PartnerTierRuleVersion__c(
        Module__c = 'Build',
        Tier__c = 'Premier',
        Tier_Rank__c = 3,
        Min_Points__c = 50000,
        In_Effect_Date__c = todayDate,
        Status__c = 'Active'
    ),
    new PartnerTierRuleVersion__c(
        Module__c = 'Reseller',
        Tier__c = 'Ready',
        Tier_Rank__c = 1,
        Min_Points__c = 2000,
        In_Effect_Date__c = todayDate,
        Status__c = 'Active'
    ),
    new PartnerTierRuleVersion__c(
        Module__c = 'Reseller',
        Tier__c = 'Advanced',
        Tier_Rank__c = 2,
        Min_Points__c = 8000,
        In_Effect_Date__c = todayDate,
        Status__c = 'Active'
    ),
    new PartnerTierRuleVersion__c(
        Module__c = 'Reseller',
        Tier__c = 'Premier',
        Tier_Rank__c = 3,
        Min_Points__c = 20000,
        In_Effect_Date__c = todayDate,
        Status__c = 'Active'
    )
};
insert seededVersions;

Map<String, Id> versionByKey = new Map<String, Id>();
for (PartnerTierRuleVersion__c v : seededVersions) {
    versionByKey.put(v.Module__c + '|' + v.Tier__c, v.Id);
}

List<PartnerTierRuleGroup__c> groups = new List<PartnerTierRuleGroup__c>{
    // Build Ready OR groups
    new PartnerTierRuleGroup__c(Rule_Version__c = versionByKey.get('Build|Ready'), Group_Order__c = 1),
    new PartnerTierRuleGroup__c(Rule_Version__c = versionByKey.get('Build|Ready'), Group_Order__c = 2),
    new PartnerTierRuleGroup__c(Rule_Version__c = versionByKey.get('Build|Ready'), Group_Order__c = 3),
    // Build Advanced OR groups
    new PartnerTierRuleGroup__c(Rule_Version__c = versionByKey.get('Build|Advanced'), Group_Order__c = 1),
    new PartnerTierRuleGroup__c(Rule_Version__c = versionByKey.get('Build|Advanced'), Group_Order__c = 2),
    new PartnerTierRuleGroup__c(Rule_Version__c = versionByKey.get('Build|Advanced'), Group_Order__c = 3),
    // Build Premier single AND group
    new PartnerTierRuleGroup__c(Rule_Version__c = versionByKey.get('Build|Premier'), Group_Order__c = 1)
};
insert groups;

Map<String, Id> groupByKey = new Map<String, Id>();
Map<Id, PartnerTierRuleVersion__c> versionById = new Map<Id, PartnerTierRuleVersion__c>(seededVersions);
for (PartnerTierRuleGroup__c g : groups) {
    PartnerTierRuleVersion__c parentVer = versionById.get(g.Rule_Version__c);
    if (parentVer != null) {
        groupByKey.put(parentVer.Module__c + '|' + parentVer.Tier__c + '|' + g.Group_Order__c, g.Id);
    }
}

insert new List<PartnerTierRuleCondition__c>{
    // Build Ready
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Ready|1'), Condition_Order__c = 1, Field_API_Name__c = 'Account_Software_Product_Cert__c', Operator__c = '>=', Threshold__c = 1),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Ready|2'), Condition_Order__c = 1, Field_API_Name__c = 'Account_Hardware_Product_Cert__c', Operator__c = '>=', Threshold__c = 1),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Ready|3'), Condition_Order__c = 1, Field_API_Name__c = 'Account_RHSC_Credentials__c', Operator__c = '>=', Threshold__c = 2),
    // Build Advanced
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Advanced|1'), Condition_Order__c = 1, Field_API_Name__c = 'Account_Software_Product_Cert__c', Operator__c = '>=', Threshold__c = 1),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Advanced|2'), Condition_Order__c = 1, Field_API_Name__c = 'Account_Hardware_Product_Cert__c', Operator__c = '>=', Threshold__c = 1),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Advanced|3'), Condition_Order__c = 1, Field_API_Name__c = 'Account_RHSC_Credentials__c', Operator__c = '>=', Threshold__c = 3),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Advanced|3'), Condition_Order__c = 2, Field_API_Name__c = 'Account_RHTSC_Credentials__c', Operator__c = '>=', Threshold__c = 2),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Advanced|3'), Condition_Order__c = 3, Field_API_Name__c = 'Account_RH_Certifications__c', Operator__c = '>=', Threshold__c = 1),
    // Build Premier
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Premier|1'), Condition_Order__c = 1, Field_API_Name__c = 'Account_RHSC_Credentials__c', Operator__c = '>=', Threshold__c = 5),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Premier|1'), Condition_Order__c = 2, Field_API_Name__c = 'Account_RHTSC_Credentials__c', Operator__c = '>=', Threshold__c = 4)
};

// 3) Create demo members.
Account demoAccount = new Account(Name = 'Partner Tiering Demo Account');
insert demoAccount;

LoyaltyProgramMember demoA = new LoyaltyProgramMember(
    MemberStatus                     = 'Active',
    MemberType                       = 'Corporate',
    MembershipNumber                 = 'PT-A-' + String.valueOf(DateTime.now().getTime()),
    EnrollmentDate                   = Date.today(),
    AccountId                        = demoAccount.Id,
    ProgramId                        = programId,
    Build_Certify__c                 = true,
    Reseller__c                      = false,
    Account_Software_Product_Cert__c = 1,
    Account_Hardware_Product_Cert__c = 0,
    Account_RHSC_Credentials__c      = 0,
    Account_RHTSC_Credentials__c     = 0,
    Account_RH_Certifications__c     = 0
);

LoyaltyProgramMember demoB = new LoyaltyProgramMember(
    MemberStatus                     = 'Active',
    MemberType                       = 'Corporate',
    MembershipNumber                 = 'PT-B-' + String.valueOf(DateTime.now().getTime()),
    EnrollmentDate                   = Date.today(),
    AccountId                        = demoAccount.Id,
    ProgramId                        = programId,
    Build_Certify__c                 = true,
    Reseller__c                      = false,
    Account_Software_Product_Cert__c = 0,
    Account_Hardware_Product_Cert__c = 0,
    Account_RHSC_Credentials__c      = 4,
    Account_RHTSC_Credentials__c     = 2,
    Account_RH_Certifications__c     = 1
);

LoyaltyProgramMember demoC = new LoyaltyProgramMember(
    MemberStatus                     = 'Active',
    MemberType                       = 'Corporate',
    MembershipNumber                 = 'PT-C-' + String.valueOf(DateTime.now().getTime()),
    EnrollmentDate                   = Date.today(),
    AccountId                        = demoAccount.Id,
    ProgramId                        = programId,
    Build_Certify__c                 = true,
    Reseller__c                      = false,
    Account_Software_Product_Cert__c = 1,
    Account_Hardware_Product_Cert__c = 1,
    Account_RHSC_Credentials__c      = 1,
    Account_RHTSC_Credentials__c     = 0,
    Account_RH_Certifications__c     = 0
);
insert new List<LoyaltyProgramMember>{ demoA, demoB, demoC };

// 4) Attach points balances.
insert new List<LoyaltyMemberCurrency>{
    new LoyaltyMemberCurrency(Name = 'Demo Currency A', LoyaltyMemberId = demoA.Id, LoyaltyProgramCurrencyId = currencyId, TotalPointsAccrued = 28000),
    new LoyaltyMemberCurrency(Name = 'Demo Currency B', LoyaltyMemberId = demoB.Id, LoyaltyProgramCurrencyId = currencyId, TotalPointsAccrued = 26000),
    new LoyaltyMemberCurrency(Name = 'Demo Currency C', LoyaltyMemberId = demoC.Id, LoyaltyProgramCurrencyId = currencyId, TotalPointsAccrued = 55000)
};

// 5) Evaluate.
TierEvaluationService svc = new TierEvaluationService();
String tierA = svc.evaluatePartnerTier(demoA.Id);
String tierB = svc.evaluatePartnerTier(demoB.Id);
String tierC = svc.evaluatePartnerTier(demoC.Id);

System.debug('=== Tier Evaluation Results (Custom Object Engine) ===');
System.debug('Demo A (Sw cert path, 28k points)  => ' + tierA + ' [Expected: Advanced]');
System.debug('Demo B (Full creds, 26k points)    => ' + tierB + ' [Expected: Advanced]');
System.debug('Demo C (Certs only, 55k points)    => ' + tierC + ' [Expected: Advanced]');
