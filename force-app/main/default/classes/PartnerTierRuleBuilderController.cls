/**
 * @description UI controller for partner tier rule condition builder.
 */
public with sharing class PartnerTierRuleBuilderController {
    private static final String FIELD_MIN_ELIGIBLE_BALANCE = 'MinimumEligibleBalance';
    private static final String FIELD_MAX_ELIGIBLE_BALANCE = 'MaximumEligibleBalance';

    public class RuleConditionDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public Integer conditionOrder;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String operatorValue;
        @AuraEnabled public Decimal threshold;
    }

    public class RuleGroupDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public Integer groupOrder;
        @AuraEnabled public List<RuleConditionDTO> conditions;
    }

    public class RuleVersionDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String moduleName;
        @AuraEnabled public String tierName;
        @AuraEnabled public Date inEffectDate;
        @AuraEnabled public String status;
        @AuraEnabled public List<RuleGroupDTO> groups;
    }

    public class SelectOptionDTO {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public SelectOptionDTO(String l, String v) {
            label = l;
            value = v;
        }
    }

    @AuraEnabled(cacheable=true)
    public static RuleVersionDTO getRuleVersionGraph(Id ruleVersionId) {
        if (ruleVersionId == null) {
            throw new AuraHandledException('ruleVersionId is required.');
        }

        PartnerTierRuleVersion__c versionRec = [
            SELECT Id,
                   Module__c,
                   Tier__c,
                   In_Effect_Date__c,
                   Status__c
            FROM PartnerTierRuleVersion__c
            WHERE Id = :ruleVersionId
            LIMIT 1
        ];

        List<PartnerTierRuleGroup__c> groups = [
            SELECT Id, Group_Order__c
            FROM PartnerTierRuleGroup__c
            WHERE Rule_Version__c = :ruleVersionId
            ORDER BY Group_Order__c ASC, CreatedDate ASC
        ];

        Map<Id, List<PartnerTierRuleCondition__c>> conditionsByGroup = new Map<Id, List<PartnerTierRuleCondition__c>>();
        if (!groups.isEmpty()) {
            for (PartnerTierRuleCondition__c c : [
                SELECT Id,
                       Rule_Group__c,
                       Condition_Order__c,
                       Field_API_Name__c,
                       Operator__c,
                       Threshold__c
                FROM PartnerTierRuleCondition__c
                WHERE Rule_Group__c IN :groups
                ORDER BY Condition_Order__c ASC, CreatedDate ASC
            ]) {
                if (!conditionsByGroup.containsKey(c.Rule_Group__c)) {
                    conditionsByGroup.put(c.Rule_Group__c, new List<PartnerTierRuleCondition__c>());
                }
                conditionsByGroup.get(c.Rule_Group__c).add(c);
            }
        }

        RuleVersionDTO dto = new RuleVersionDTO();
        dto.id = versionRec.Id;
        dto.moduleName = versionRec.Module__c;
        dto.tierName = versionRec.Tier__c;
        dto.inEffectDate = versionRec.In_Effect_Date__c;
        dto.status = versionRec.Status__c;
        dto.groups = new List<RuleGroupDTO>();

        for (PartnerTierRuleGroup__c g : groups) {
            RuleGroupDTO gd = new RuleGroupDTO();
            gd.id = g.Id;
            gd.groupOrder = g.Group_Order__c == null ? null : Integer.valueOf(g.Group_Order__c);
            gd.conditions = new List<RuleConditionDTO>();

            List<PartnerTierRuleCondition__c> conds = conditionsByGroup.get(g.Id);
            if (conds != null) {
                for (PartnerTierRuleCondition__c c : conds) {
                    RuleConditionDTO cd = new RuleConditionDTO();
                    cd.id = c.Id;
                    cd.conditionOrder = c.Condition_Order__c == null ? null : Integer.valueOf(c.Condition_Order__c);
                    cd.fieldApiName = c.Field_API_Name__c;
                    cd.operatorValue = c.Operator__c;
                    cd.threshold = c.Threshold__c;
                    gd.conditions.add(cd);
                }
            }
            dto.groups.add(gd);
        }

        return dto;
    }

    @AuraEnabled(cacheable=true)
    public static List<SelectOptionDTO> getConditionFieldOptions() {
        return new List<SelectOptionDTO>{
            new SelectOptionDTO('MinimumEligibleBalance', FIELD_MIN_ELIGIBLE_BALANCE),
            new SelectOptionDTO('MaximumEligibleBalance', FIELD_MAX_ELIGIBLE_BALANCE),
            new SelectOptionDTO('Software Product Certifications', 'Account_Software_Product_Cert__c'),
            new SelectOptionDTO('Hardware Product Certifications', 'Account_Hardware_Product_Cert__c'),
            new SelectOptionDTO('RH Seller Credentials', 'Account_RHSC_Credentials__c'),
            new SelectOptionDTO('RH Tech Seller Credentials', 'Account_RHTSC_Credentials__c'),
            new SelectOptionDTO('RH Certifications', 'Account_RH_Certifications__c')
        };
    }

    @AuraEnabled(cacheable=true)
    public static List<SelectOptionDTO> getOperatorOptions() {
        return new List<SelectOptionDTO>{
            new SelectOptionDTO('>=', '>='),
            new SelectOptionDTO('>', '>'),
            new SelectOptionDTO('<=', '<='),
            new SelectOptionDTO('<', '<'),
            new SelectOptionDTO('=', '='),
            new SelectOptionDTO('!=', '!=')
        };
    }

    @AuraEnabled
    public static void saveRuleVersionGraph(Id ruleVersionId, String groupsJson) {
        try {
            if (ruleVersionId == null) {
                throw new AuraHandledException('ruleVersionId is required.');
            }
            if (String.isBlank(groupsJson)) {
                throw new AuraHandledException('groupsJson is required.');
            }

            // Lock parent so concurrent editors do not clobber each other.
            Id lockedVersionId = [
                SELECT Id
                FROM PartnerTierRuleVersion__c
                WHERE Id = :ruleVersionId
                LIMIT 1
                FOR UPDATE
            ].Id;

            List<Object> groupPayload = (List<Object>) JSON.deserializeUntyped(groupsJson);

            Map<Id, PartnerTierRuleGroup__c> existingGroups = new Map<Id, PartnerTierRuleGroup__c>([
                SELECT Id, Rule_Version__c
                FROM PartnerTierRuleGroup__c
                WHERE Rule_Version__c = :ruleVersionId
            ]);

            List<PartnerTierRuleGroup__c> groupsToUpsert = new List<PartnerTierRuleGroup__c>();
            List<RuleGroupDTO> incomingGroups = new List<RuleGroupDTO>();
            Integer nextOrder = 1;

            for (Object gObj : groupPayload) {
                Map<String, Object> raw = (Map<String, Object>) gObj;
                RuleGroupDTO incoming = new RuleGroupDTO();
                incoming.id = parseId(raw.get('id'));
                incoming.groupOrder = raw.get('groupOrder') == null ? nextOrder : Integer.valueOf(String.valueOf(raw.get('groupOrder')));
                incoming.conditions = new List<RuleConditionDTO>();
                incomingGroups.add(incoming);

                PartnerTierRuleGroup__c up = new PartnerTierRuleGroup__c();
                if (incoming.id != null) {
                    up.Id = incoming.id;
                } else {
                    up.Rule_Version__c = ruleVersionId;
                }
                up.Group_Order__c = incoming.groupOrder;
                groupsToUpsert.add(up);

                List<Object> condPayload = (List<Object>) raw.get('conditions');
                if (condPayload != null) {
                    Integer nextCondOrder = 1;
                    for (Object cObj : condPayload) {
                        Map<String, Object> cRaw = (Map<String, Object>) cObj;
                        RuleConditionDTO cdto = new RuleConditionDTO();
                        cdto.id = parseId(cRaw.get('id'));
                        cdto.conditionOrder = cRaw.get('conditionOrder') == null ? nextCondOrder : Integer.valueOf(String.valueOf(cRaw.get('conditionOrder')));
                        cdto.fieldApiName = (String) cRaw.get('fieldApiName');
                        cdto.operatorValue = (String) cRaw.get('operatorValue');
                        cdto.threshold = cRaw.get('threshold') == null ? null : Decimal.valueOf(String.valueOf(cRaw.get('threshold')));
                        incoming.conditions.add(cdto);
                        nextCondOrder++;
                    }
                }
                nextOrder++;
            }

            if (groupsToUpsert.isEmpty()) {
                throw new AuraHandledException('At least one OR group is required.');
            }

            upsert groupsToUpsert;

            Set<Id> keptGroupIds = new Set<Id>();
            for (PartnerTierRuleGroup__c g : groupsToUpsert) {
                keptGroupIds.add(g.Id);
            }

            // Build index of group id -> incoming conditions
            Map<Id, List<RuleConditionDTO>> incomingConditionsByGroup = new Map<Id, List<RuleConditionDTO>>();
            for (Integer i = 0; i < groupsToUpsert.size(); i++) {
                incomingConditionsByGroup.put(groupsToUpsert[i].Id, incomingGroups[i].conditions);
            }

            // Remove groups no longer present.
            List<PartnerTierRuleGroup__c> groupsToDelete = new List<PartnerTierRuleGroup__c>();
            for (PartnerTierRuleGroup__c ex : existingGroups.values()) {
                if (!keptGroupIds.contains(ex.Id)) {
                    groupsToDelete.add(ex);
                }
            }
            if (!groupsToDelete.isEmpty()) {
                delete groupsToDelete;
            }

            // Bulk-load all existing conditions for kept groups (single SOQL).
            Map<Id, List<PartnerTierRuleCondition__c>> existingCondsByGroup = new Map<Id, List<PartnerTierRuleCondition__c>>();
            for (Id gId : keptGroupIds) {
                existingCondsByGroup.put(gId, new List<PartnerTierRuleCondition__c>());
            }
            for (PartnerTierRuleCondition__c ec : [
                SELECT Id, Rule_Group__c
                FROM PartnerTierRuleCondition__c
                WHERE Rule_Group__c IN :keptGroupIds
            ]) {
                existingCondsByGroup.get(ec.Rule_Group__c).add(ec);
            }

            List<PartnerTierRuleCondition__c> allCondsToUpsert = new List<PartnerTierRuleCondition__c>();
            List<PartnerTierRuleCondition__c> allCondsToDelete = new List<PartnerTierRuleCondition__c>();
            Set<Id> allKeptCondIds = new Set<Id>();

            for (Id groupId : incomingConditionsByGroup.keySet()) {
                for (RuleConditionDTO c : incomingConditionsByGroup.get(groupId)) {
                    if (String.isBlank(c.fieldApiName) || String.isBlank(c.operatorValue) || c.threshold == null) {
                        continue;
                    }
                    PartnerTierRuleCondition__c rec = new PartnerTierRuleCondition__c();
                    if (c.id != null) {
                        rec.Id = c.id;
                        allKeptCondIds.add(c.id);
                    } else {
                        rec.Rule_Group__c = groupId;
                    }
                    rec.Condition_Order__c = c.conditionOrder;
                    rec.Field_API_Name__c = c.fieldApiName;
                    rec.Operator__c = c.operatorValue;
                    rec.Threshold__c = c.threshold;
                    allCondsToUpsert.add(rec);
                }
            }

            if (!allCondsToUpsert.isEmpty()) {
                upsert allCondsToUpsert;
                for (PartnerTierRuleCondition__c cUp : allCondsToUpsert) {
                    allKeptCondIds.add(cUp.Id);
                }
            }

            for (List<PartnerTierRuleCondition__c> ecList : existingCondsByGroup.values()) {
                for (PartnerTierRuleCondition__c ex : ecList) {
                    if (!allKeptCondIds.contains(ex.Id)) {
                        allCondsToDelete.add(ex);
                    }
                }
            }
            if (!allCondsToDelete.isEmpty()) {
                delete allCondsToDelete;
            }
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Save failed: ' + e.getTypeName() + ' - ' + e.getMessage()
            );
        }
    }

    private static Id parseId(Object raw) {
        if (raw == null) {
            return null;
        }
        String value = String.valueOf(raw);
        return String.isBlank(value) ? null : (Id) value;
    }

}
