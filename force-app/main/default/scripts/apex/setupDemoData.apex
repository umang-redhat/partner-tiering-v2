/**
 * Demo data setup for custom-object rule model:
 * PartnerTierRuleVersion__c -> PartnerTierRuleGroup__c -> PartnerTierRuleCondition__c.
 *
 * This version seeds points as condition rows (MinimumEligibleBalance/MaximumEligibleBalance) instead of
 * relying on Min_Points__c gates at the rule-version level.
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
        In_Effect_Date__c = todayDate,
        Status__c = 'Active'
    ),
    new PartnerTierRuleVersion__c(
        Module__c = 'Build',
        Tier__c = 'Advanced',
        Tier_Rank__c = 2,
        In_Effect_Date__c = todayDate,
        Status__c = 'Active'
    ),
    new PartnerTierRuleVersion__c(
        Module__c = 'Build',
        Tier__c = 'Premier',
        Tier_Rank__c = 3,
        In_Effect_Date__c = todayDate,
        Status__c = 'Active'
    ),
    new PartnerTierRuleVersion__c(
        Module__c = 'Reseller',
        Tier__c = 'Unaffiliated',
        Tier_Rank__c = 1,
        In_Effect_Date__c = todayDate,
        Status__c = 'Active'
    ),
    new PartnerTierRuleVersion__c(
        Module__c = 'Reseller',
        Tier__c = 'Ready',
        Tier_Rank__c = 2,
        In_Effect_Date__c = todayDate,
        Status__c = 'Active'
    ),
    new PartnerTierRuleVersion__c(
        Module__c = 'Reseller',
        Tier__c = 'Advanced',
        Tier_Rank__c = 3,
        In_Effect_Date__c = todayDate,
        Status__c = 'Active'
    ),
    new PartnerTierRuleVersion__c(
        Module__c = 'Reseller',
        Tier__c = 'Premier',
        Tier_Rank__c = 4,
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
    // Build Premier
    new PartnerTierRuleGroup__c(Rule_Version__c = versionByKey.get('Build|Premier'), Group_Order__c = 1),
    // Reseller tiers (single group each)
    new PartnerTierRuleGroup__c(Rule_Version__c = versionByKey.get('Reseller|Unaffiliated'), Group_Order__c = 1),
    new PartnerTierRuleGroup__c(Rule_Version__c = versionByKey.get('Reseller|Ready'), Group_Order__c = 1),
    new PartnerTierRuleGroup__c(Rule_Version__c = versionByKey.get('Reseller|Advanced'), Group_Order__c = 1),
    new PartnerTierRuleGroup__c(Rule_Version__c = versionByKey.get('Reseller|Premier'), Group_Order__c = 1)
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
    // Build Ready: SwCert >=1 OR HwCert >=1 OR RHSC>=2
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Ready|1'), Condition_Order__c = 1, Field_API_Name__c = 'Account_Software_Product_Cert__c', Operator__c = '>=', Threshold__c = 1),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Ready|2'), Condition_Order__c = 1, Field_API_Name__c = 'Account_Hardware_Product_Cert__c', Operator__c = '>=', Threshold__c = 1),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Ready|3'), Condition_Order__c = 1, Field_API_Name__c = 'Account_RHSC_Credentials__c', Operator__c = '>=', Threshold__c = 2),

    // Build Advanced: (SwCert >=1 OR HwCert >=1 OR (RHSC>=3 AND RHTSC>=2 AND RHC>=1)) AND points >= 25,000
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Advanced|1'), Condition_Order__c = 1, Field_API_Name__c = 'Account_Software_Product_Cert__c', Operator__c = '>=', Threshold__c = 1),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Advanced|1'), Condition_Order__c = 2, Field_API_Name__c = 'MinimumEligibleBalance', Operator__c = '>=', Threshold__c = 25000),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Advanced|2'), Condition_Order__c = 1, Field_API_Name__c = 'Account_Hardware_Product_Cert__c', Operator__c = '>=', Threshold__c = 1),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Advanced|2'), Condition_Order__c = 2, Field_API_Name__c = 'MinimumEligibleBalance', Operator__c = '>=', Threshold__c = 25000),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Advanced|3'), Condition_Order__c = 1, Field_API_Name__c = 'Account_RHSC_Credentials__c', Operator__c = '>=', Threshold__c = 3),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Advanced|3'), Condition_Order__c = 2, Field_API_Name__c = 'Account_RHTSC_Credentials__c', Operator__c = '>=', Threshold__c = 2),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Advanced|3'), Condition_Order__c = 3, Field_API_Name__c = 'Account_RH_Certifications__c', Operator__c = '>=', Threshold__c = 1),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Advanced|3'), Condition_Order__c = 4, Field_API_Name__c = 'MinimumEligibleBalance', Operator__c = '>=', Threshold__c = 25000),

    // Build Premier: (RHSC>=6 AND RHTSC>=4 AND RHC>=2) AND points >= 100,000
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Premier|1'), Condition_Order__c = 1, Field_API_Name__c = 'Account_RHSC_Credentials__c', Operator__c = '>=', Threshold__c = 6),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Premier|1'), Condition_Order__c = 2, Field_API_Name__c = 'Account_RHTSC_Credentials__c', Operator__c = '>=', Threshold__c = 4),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Premier|1'), Condition_Order__c = 3, Field_API_Name__c = 'Account_RH_Certifications__c', Operator__c = '>=', Threshold__c = 2),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Build|Premier|1'), Condition_Order__c = 4, Field_API_Name__c = 'MinimumEligibleBalance', Operator__c = '>=', Threshold__c = 100000),

    // Reseller Unaffiliated: 0 points AND <2 RH Seller credentials
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Reseller|Unaffiliated|1'), Condition_Order__c = 1, Field_API_Name__c = 'MinimumEligibleBalance', Operator__c = '=', Threshold__c = 0),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Reseller|Unaffiliated|1'), Condition_Order__c = 2, Field_API_Name__c = 'Account_RHSC_Credentials__c', Operator__c = '<', Threshold__c = 2),

    // Reseller Ready: 1-24,999 points AND 2 RH Seller credentials
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Reseller|Ready|1'), Condition_Order__c = 1, Field_API_Name__c = 'MinimumEligibleBalance', Operator__c = '>=', Threshold__c = 1),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Reseller|Ready|1'), Condition_Order__c = 2, Field_API_Name__c = 'MaximumEligibleBalance', Operator__c = '<=', Threshold__c = 24999),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Reseller|Ready|1'), Condition_Order__c = 3, Field_API_Name__c = 'Account_RHSC_Credentials__c', Operator__c = '>=', Threshold__c = 2),

    // Reseller Advanced: 25,000-99,999 points + credentials
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Reseller|Advanced|1'), Condition_Order__c = 1, Field_API_Name__c = 'MinimumEligibleBalance', Operator__c = '>=', Threshold__c = 25000),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Reseller|Advanced|1'), Condition_Order__c = 2, Field_API_Name__c = 'MaximumEligibleBalance', Operator__c = '<=', Threshold__c = 99999),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Reseller|Advanced|1'), Condition_Order__c = 3, Field_API_Name__c = 'Account_RHSC_Credentials__c', Operator__c = '>=', Threshold__c = 3),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Reseller|Advanced|1'), Condition_Order__c = 4, Field_API_Name__c = 'Account_RHTSC_Credentials__c', Operator__c = '>=', Threshold__c = 2),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Reseller|Advanced|1'), Condition_Order__c = 5, Field_API_Name__c = 'Account_RH_Certifications__c', Operator__c = '>=', Threshold__c = 1),

    // Reseller Premier: 100,000+ points + credentials
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Reseller|Premier|1'), Condition_Order__c = 1, Field_API_Name__c = 'MinimumEligibleBalance', Operator__c = '>=', Threshold__c = 100000),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Reseller|Premier|1'), Condition_Order__c = 2, Field_API_Name__c = 'Account_RHSC_Credentials__c', Operator__c = '>=', Threshold__c = 6),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Reseller|Premier|1'), Condition_Order__c = 3, Field_API_Name__c = 'Account_RHTSC_Credentials__c', Operator__c = '>=', Threshold__c = 4),
    new PartnerTierRuleCondition__c(Rule_Group__c = groupByKey.get('Reseller|Premier|1'), Condition_Order__c = 4, Field_API_Name__c = 'Account_RH_Certifications__c', Operator__c = '>=', Threshold__c = 2)
};

// 3) Create demo members.
Account demoAccount = new Account(Name = 'Partner Tiering Demo Account');
insert demoAccount;

LoyaltyProgramMember buildA = new LoyaltyProgramMember(
    MemberStatus                     = 'Active',
    MemberType                       = 'Corporate',
    MembershipNumber                 = 'PT-BA-' + String.valueOf(DateTime.now().getTime()),
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

LoyaltyProgramMember buildB = new LoyaltyProgramMember(
    MemberStatus                     = 'Active',
    MemberType                       = 'Corporate',
    MembershipNumber                 = 'PT-BB-' + String.valueOf(DateTime.now().getTime()),
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

LoyaltyProgramMember buildC = new LoyaltyProgramMember(
    MemberStatus                     = 'Active',
    MemberType                       = 'Corporate',
    MembershipNumber                 = 'PT-BC-' + String.valueOf(DateTime.now().getTime()),
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

LoyaltyProgramMember resellerU = new LoyaltyProgramMember(
    MemberStatus                     = 'Active',
    MemberType                       = 'Corporate',
    MembershipNumber                 = 'PT-RU-' + String.valueOf(DateTime.now().getTime()),
    EnrollmentDate                   = Date.today(),
    AccountId                        = demoAccount.Id,
    ProgramId                        = programId,
    Build_Certify__c                 = false,
    Reseller__c                      = true,
    Account_Software_Product_Cert__c = 0,
    Account_Hardware_Product_Cert__c = 0,
    Account_RHSC_Credentials__c      = 1,
    Account_RHTSC_Credentials__c     = 0,
    Account_RH_Certifications__c     = 0
);

LoyaltyProgramMember resellerR = new LoyaltyProgramMember(
    MemberStatus                     = 'Active',
    MemberType                       = 'Corporate',
    MembershipNumber                 = 'PT-RR-' + String.valueOf(DateTime.now().getTime()),
    EnrollmentDate                   = Date.today(),
    AccountId                        = demoAccount.Id,
    ProgramId                        = programId,
    Build_Certify__c                 = false,
    Reseller__c                      = true,
    Account_Software_Product_Cert__c = 0,
    Account_Hardware_Product_Cert__c = 0,
    Account_RHSC_Credentials__c      = 2,
    Account_RHTSC_Credentials__c     = 0,
    Account_RH_Certifications__c     = 0
);

LoyaltyProgramMember resellerA = new LoyaltyProgramMember(
    MemberStatus                     = 'Active',
    MemberType                       = 'Corporate',
    MembershipNumber                 = 'PT-RA-' + String.valueOf(DateTime.now().getTime()),
    EnrollmentDate                   = Date.today(),
    AccountId                        = demoAccount.Id,
    ProgramId                        = programId,
    Build_Certify__c                 = false,
    Reseller__c                      = true,
    Account_Software_Product_Cert__c = 0,
    Account_Hardware_Product_Cert__c = 0,
    Account_RHSC_Credentials__c      = 3,
    Account_RHTSC_Credentials__c     = 2,
    Account_RH_Certifications__c     = 1
);

LoyaltyProgramMember resellerP = new LoyaltyProgramMember(
    MemberStatus                     = 'Active',
    MemberType                       = 'Corporate',
    MembershipNumber                 = 'PT-RP-' + String.valueOf(DateTime.now().getTime()),
    EnrollmentDate                   = Date.today(),
    AccountId                        = demoAccount.Id,
    ProgramId                        = programId,
    Build_Certify__c                 = false,
    Reseller__c                      = true,
    Account_Software_Product_Cert__c = 0,
    Account_Hardware_Product_Cert__c = 0,
    Account_RHSC_Credentials__c      = 6,
    Account_RHTSC_Credentials__c     = 4,
    Account_RH_Certifications__c     = 2
);

insert new List<LoyaltyProgramMember>{ buildA, buildB, buildC, resellerU, resellerR, resellerA, resellerP };

// 4) Attach points balances.
insert new List<LoyaltyMemberCurrency>{
    new LoyaltyMemberCurrency(Name = 'Demo Currency Build A', LoyaltyMemberId = buildA.Id, LoyaltyProgramCurrencyId = currencyId, TotalPointsAccrued = 28000),
    new LoyaltyMemberCurrency(Name = 'Demo Currency Build B', LoyaltyMemberId = buildB.Id, LoyaltyProgramCurrencyId = currencyId, TotalPointsAccrued = 26000),
    new LoyaltyMemberCurrency(Name = 'Demo Currency Build C', LoyaltyMemberId = buildC.Id, LoyaltyProgramCurrencyId = currencyId, TotalPointsAccrued = 55000),
    new LoyaltyMemberCurrency(Name = 'Demo Currency Reseller U', LoyaltyMemberId = resellerU.Id, LoyaltyProgramCurrencyId = currencyId, TotalPointsAccrued = 0),
    new LoyaltyMemberCurrency(Name = 'Demo Currency Reseller R', LoyaltyMemberId = resellerR.Id, LoyaltyProgramCurrencyId = currencyId, TotalPointsAccrued = 20000),
    new LoyaltyMemberCurrency(Name = 'Demo Currency Reseller A', LoyaltyMemberId = resellerA.Id, LoyaltyProgramCurrencyId = currencyId, TotalPointsAccrued = 50000),
    new LoyaltyMemberCurrency(Name = 'Demo Currency Reseller P', LoyaltyMemberId = resellerP.Id, LoyaltyProgramCurrencyId = currencyId, TotalPointsAccrued = 120000)
};

// 5) Evaluate — per-module results.
TierEvaluationService svc = new TierEvaluationService();

System.debug('=== Per-Module Tier Evaluation Results ===');
for (LoyaltyProgramMember m : new List<LoyaltyProgramMember>{ buildA, buildB, buildC, resellerU, resellerR, resellerA, resellerP }) {
    Map<String, TierEvaluationService.TierResult> results = svc.evaluatePartnerTiers(m.Id);
    String line = 'Member ' + m.MembershipNumber + ' => ';
    if (results.isEmpty()) {
        line += 'No qualifying tier';
    } else {
        List<String> parts = new List<String>();
        for (TierEvaluationService.TierResult tr : results.values()) {
            parts.add(tr.moduleName + ':' + tr.tierName + '(rank ' + tr.tierRank + ')');
        }
        line += String.join(parts, ', ');
    }
    line += ' | Overall: ' + svc.pickOverallHighest(results);
    System.debug(line);
}
