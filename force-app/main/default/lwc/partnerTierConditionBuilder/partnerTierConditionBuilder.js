import { LightningElement, api, track } from 'lwc';
import getRuleVersionGraph from '@salesforce/apex/PartnerTierRuleBuilderController.getRuleVersionGraph';
import getConditionFieldOptions from '@salesforce/apex/PartnerTierRuleBuilderController.getConditionFieldOptions';
import getOperatorOptions from '@salesforce/apex/PartnerTierRuleBuilderController.getOperatorOptions';
import saveRuleVersionGraph from '@salesforce/apex/PartnerTierRuleBuilderController.saveRuleVersionGraph';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class PartnerTierConditionBuilder extends LightningElement {
    @api recordId;

    @track versionInfo;
    @track conditions = [];
    @track filterLogic = '';
    @track fieldOptions = [];
    @track operatorOptions = [];
    @track isLoading = true;
    @track errorMessage;

    sequence = 0;
    suppressLogicAutoUpdate = false;

    connectedCallback() {
        this.initialize();
    }

    async initialize() {
        this.isLoading = true;
        this.errorMessage = null;
        try {
            const [version, fields, operators] = await Promise.all([
                getRuleVersionGraph({ ruleVersionId: this.recordId }),
                getConditionFieldOptions(),
                getOperatorOptions()
            ]);

            this.versionInfo = version;
            this.fieldOptions = fields.map((o) => ({ label: o.label, value: o.value }));
            this.operatorOptions = operators.map((o) => ({ label: o.label, value: o.value }));
            this.loadFromGraph(version.groups || []);
        } catch (e) {
            this.errorMessage = this.reduceError(e);
        } finally {
            this.isLoading = false;
        }
    }

    newClientKey() {
        this.sequence += 1;
        return `cond-${Date.now()}-${this.sequence}`;
    }

    loadFromGraph(groups) {
        const flattened = [];
        for (const group of groups) {
            for (const condition of group.conditions || []) {
                flattened.push({
                    clientKey: this.newClientKey(),
                    id: condition.id,
                    fieldApiName: condition.fieldApiName,
                    operatorValue: condition.operatorValue,
                    threshold: condition.threshold
                });
            }
        }

        this.conditions = flattened;
        this.reindexDisplayNumbers();

        if (!flattened.length) {
            this.filterLogic = '';
            return;
        }

        const expressionFromGraph = this.buildExpressionFromGraph(groups, flattened.length);
        this.filterLogic = expressionFromGraph || this.defaultFilterLogic();
    }

    buildExpressionFromGraph(groups, totalConditions) {
        let row = 1;
        const groupExpr = [];

        for (const group of groups) {
            const byBucket = new Map();
            for (const c of group.conditions || []) {
                const bucket = Number.isFinite(Number(c.conditionOrder)) ? Math.floor(Number(c.conditionOrder)) : 1;
                if (!byBucket.has(bucket)) {
                    byBucket.set(bucket, []);
                }
                byBucket.get(bucket).push(row);
                row += 1;
            }

            const bucketExpr = Array.from(byBucket.entries())
                .sort((a, b) => a[0] - b[0])
                .map(([, refs]) => (refs.length === 1 ? `${refs[0]}` : `(${refs.join(' OR ')})`));

            if (bucketExpr.length === 1) {
                groupExpr.push(bucketExpr[0]);
            } else if (bucketExpr.length > 1) {
                groupExpr.push(`(${bucketExpr.join(' AND ')})`);
            }
        }

        if (row - 1 !== totalConditions) {
            return '';
        }
        if (!groupExpr.length) {
            return '';
        }
        if (groupExpr.length === 1) {
            return groupExpr[0];
        }
        return groupExpr.map((g) => `(${g})`).join(' OR ');
    }

    defaultFilterLogic() {
        return this.conditions.map((c) => c.displayIndex).join(' AND ');
    }

    reindexDisplayNumbers() {
        this.conditions = this.conditions.map((c, idx) => ({
            ...c,
            displayIndex: idx + 1
        }));
    }

    get hasConditions() {
        return this.conditions.length > 0;
    }

    handleAddCondition() {
        this.conditions = [
            ...this.conditions,
            {
                clientKey: this.newClientKey(),
                id: null,
                fieldApiName: '',
                operatorValue: '>=',
                threshold: null,
                displayIndex: this.conditions.length + 1
            }
        ];
        if (!this.suppressLogicAutoUpdate) {
            this.filterLogic = this.defaultFilterLogic();
        }
    }

    handleRemoveCondition(event) {
        const key = event.currentTarget.dataset.conditionKey;
        this.conditions = this.conditions.filter((c) => c.clientKey !== key);
        this.reindexDisplayNumbers();
        if (!this.conditions.length) {
            this.filterLogic = '';
        } else if (!this.suppressLogicAutoUpdate) {
            this.filterLogic = this.defaultFilterLogic();
        }
    }

    handleFilterLogicChange(event) {
        this.filterLogic = event.detail.value;
        this.suppressLogicAutoUpdate = true;
    }

    handleConditionFieldChange(event) {
        this.updateConditionValue(event, 'fieldApiName', event.detail.value);
    }

    handleConditionOperatorChange(event) {
        this.updateConditionValue(event, 'operatorValue', event.detail.value);
    }

    handleConditionThresholdChange(event) {
        const raw = event.detail.value;
        this.updateConditionValue(event, 'threshold', raw === '' || raw === null ? null : Number(raw));
    }

    updateConditionValue(event, prop, value) {
        const key = event.currentTarget.dataset.conditionKey;
        this.conditions = this.conditions.map((c) => (
            c.clientKey === key ? { ...c, [prop]: value } : c
        ));
    }

    async handleSave() {
        const validation = this.validateBeforeSave();
        if (!validation.ok) {
            this.showToast('Validation Error', validation.message, 'error');
            return;
        }

        this.isLoading = true;
        this.errorMessage = null;
        try {
            await saveRuleVersionGraph({
                ruleVersionId: this.recordId,
                groupsJson: JSON.stringify(validation.groupsPayload)
            });
            this.showToast('Saved', 'Rule conditions and filter logic updated.', 'success');
            this.suppressLogicAutoUpdate = false;
            await this.initialize();
        } catch (e) {
            this.errorMessage = this.reduceError(e);
            this.showToast('Save Failed', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleValidateLogic() {
        const validation = this.validateBeforeSave();
        if (!validation.ok) {
            this.showToast('Validation Error', validation.message, 'error');
            return;
        }
        this.showToast(
            'Logic Valid',
            `Expression is valid. It compiles to ${validation.groupsPayload.length} OR group(s).`,
            'success'
        );
    }

    validateBeforeSave() {
        if (!this.conditions.length) {
            return { ok: false, message: 'Add at least one condition.' };
        }
        for (const c of this.conditions) {
            if (!c.fieldApiName || !c.operatorValue || c.threshold === null || Number.isNaN(c.threshold)) {
                return { ok: false, message: `Condition ${c.displayIndex} is incomplete.` };
            }
        }
        if (!this.filterLogic || !this.filterLogic.trim()) {
            return { ok: false, message: 'Filter Logic is required.' };
        }

        try {
            const groupsPayload = this.compileFilterLogicToPayload();
            return { ok: true, groupsPayload };
        } catch (e) {
            return { ok: false, message: e.message || 'Invalid filter logic.' };
        }
    }

    compileFilterLogicToPayload() {
        const ast = this.parseFilterLogic(this.filterLogic);
        this.validateRowReferences(ast, this.conditions.length);
        const dnfTerms = this.convertAstToDnfTerms(ast); // OR of AND row refs

        const groups = [];
        let groupOrder = 1;
        for (const term of dnfTerms) {
            const uniqueRefs = [];
            const seen = new Set();
            for (const ref of term) {
                if (!seen.has(ref)) {
                    uniqueRefs.push(ref);
                    seen.add(ref);
                }
            }

            const conditions = uniqueRefs.map((rowRef, idx) => {
                const source = this.conditions[rowRef - 1];
                return {
                    id: source.id || null,
                    conditionOrder: idx + 1,
                    fieldApiName: source.fieldApiName,
                    operatorValue: source.operatorValue,
                    threshold: source.threshold
                };
            });

            groups.push({
                id: null,
                groupOrder,
                conditions
            });
            groupOrder += 1;
        }
        return groups;
    }

    tokenize(expr) {
        const tokens = [];
        const upper = expr.toUpperCase();
        let i = 0;
        while (i < upper.length) {
            const ch = upper[i];
            if (/\s/.test(ch)) {
                i += 1;
                continue;
            }
            if (ch === '(' || ch === ')') {
                tokens.push({ type: ch });
                i += 1;
                continue;
            }
            if (/\d/.test(ch)) {
                let j = i;
                while (j < upper.length && /\d/.test(upper[j])) {
                    j += 1;
                }
                tokens.push({ type: 'NUM', value: Number(upper.slice(i, j)) });
                i = j;
                continue;
            }
            if (upper.startsWith('AND', i)) {
                tokens.push({ type: 'AND' });
                i += 3;
                continue;
            }
            if (upper.startsWith('OR', i)) {
                tokens.push({ type: 'OR' });
                i += 2;
                continue;
            }
            throw new Error(`Unexpected token near "${expr.slice(i, i + 12)}"`);
        }
        return tokens;
    }

    parseFilterLogic(expr) {
        const tokens = this.tokenize(expr);
        let pos = 0;

        const peek = () => tokens[pos];
        const consume = (type) => {
            const t = tokens[pos];
            if (!t || t.type !== type) {
                throw new Error(`Expected ${type} near token ${pos + 1}.`);
            }
            pos += 1;
            return t;
        };

        const parsePrimary = () => {
            const t = peek();
            if (!t) throw new Error('Incomplete filter logic.');
            if (t.type === 'NUM') {
                consume('NUM');
                return { type: 'REF', value: t.value };
            }
            if (t.type === '(') {
                consume('(');
                const node = parseOr();
                consume(')');
                return node;
            }
            throw new Error(`Unexpected token "${t.type}" in filter logic.`);
        };

        const parseAnd = () => {
            let node = parsePrimary();
            while (peek() && peek().type === 'AND') {
                consume('AND');
                node = { type: 'AND', left: node, right: parsePrimary() };
            }
            return node;
        };

        const parseOr = () => {
            let node = parseAnd();
            while (peek() && peek().type === 'OR') {
                consume('OR');
                node = { type: 'OR', left: node, right: parseAnd() };
            }
            return node;
        };

        const ast = parseOr();
        if (pos !== tokens.length) {
            throw new Error('Unexpected trailing tokens in filter logic.');
        }
        return ast;
    }

    validateRowReferences(ast, maxRow) {
        if (ast.type === 'REF') {
            if (ast.value < 1 || ast.value > maxRow) {
                throw new Error(`Filter logic references row ${ast.value}, but only rows 1-${maxRow} exist.`);
            }
            return;
        }
        this.validateRowReferences(ast.left, maxRow);
        this.validateRowReferences(ast.right, maxRow);
    }

    convertAstToDnfTerms(ast) {
        if (ast.type === 'REF') {
            return [[ast.value]];
        }
        const left = this.convertAstToDnfTerms(ast.left);
        const right = this.convertAstToDnfTerms(ast.right);

        if (ast.type === 'OR') {
            return [...left, ...right];
        }

        // AND cross-product for DNF expansion
        const combined = [];
        for (const l of left) {
            for (const r of right) {
                combined.push([...l, ...r]);
            }
        }
        return combined;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (!error) return 'Unknown error';
        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (error.body && typeof error.body.message === 'string') {
            return error.body.message;
        }
        return error.message || 'Unknown error';
    }
}
