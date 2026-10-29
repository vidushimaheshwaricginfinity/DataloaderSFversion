import { api, LightningElement, track } from 'lwc';
import getFields from '@salesforce/apex/CSVDataController.getFields';
import getLookupFields from '@salesforce/apex/LookupUtility.getLookupFieldsWithObjectName';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createConfiguration from '@salesforce/apex/CSVConfigurationMapping.createConfiguration';
import mappingNameExists from '@salesforce/apex/CSVConfigurationMapping.mappingNameExists';
import appendNewMappingColumns from '@salesforce/apex/CSVConfigurationMapping.appendNewMappingColumns';
export default class CsvFieldMapper extends LightningElement {
    // Unique Key Section State
    @track selectedUniqueKeyColumns = [];
    @track createdUniqueKeyColumns = [];
    @track _uniqueKeyCreated = false;
    @track showCompositeMappingUI = false;
    @track uniqueIdentifierWhereClause = '';
    @api selectedObject = 'Opportunity'; // Default selected object
    @api selectedOperation = 'Insert'; // Default operation type
    @api fileName = 'migration.csv'; // Default operation type
    @track fieldOptions = [];
    @track selectedFields = [];
    @track lookupFields = [];
    @track selectedLookupField = '';
    @api csvHeaders = ['Id', 'Name', 'Email', 'Phone', 'Description']; // Example CSV fields
    @api availableObjects = [];
    @track isMappingModified = false;
    @api existingMappingMode = false;
    @api existingMappingDisplayName;
    @track hasHeaderDifferences = false;
    @track selectedDropdownValues = [];
    _existingMappingDetails = [];
    _isInitialized = false;
    @api
get existingMappingDetails() {
    return this._existingMappingDetails;
}

set existingMappingDetails(value) {

    this._existingMappingDetails = Array.isArray(value)
        ? value
        : [];

    console.log(
        'Existing Mapping Details received:',
        JSON.stringify(this._existingMappingDetails)
    );

    if (this._isInitialized && this._existingMappingDetails.length > 0) {
        this.populateExistingMapping();
    }
    }
    @track csvHeaderOptions = []; // For composite mapping checkboxes
    @track uniqueKeyHeaderOptions = []; // For unique key selection checkboxes
    @track compositeHeaderOptions = []; // Separate tracking for composite column headers
    @track createdCompositeMappings = [];
    @track compositeMappingIdCounter = 0;
    @track compositeSections = [];
    @track activeCompositeSection = 0;
    @track isMappingCreated = false;
    @track showMappingNameModal = false;
    @track mappingName = '';
    @track configuration = {
        objectName: '',
        operationType: '',
        fileName: this.fileName,
        mappingName: '',
        mapping: []
    };
    @api uniqueKeyType = '';
    @api
    resetToHeaders(headers) {
        this.createdCompositeMappings = [];
        this.compositeMappingIdCounter = 0;
        this.compositeSections = [];
        this.compositeHeaderOptions = [];
        this.csvHeaders = headers;
        this.lookupFields = [];
        this.selectedFields = [];
        this.selectedDropdownValues = [];
        this.uniqueIdentifierWhereClause = '';
        this.csvHeaderOptions = this.csvHeaders.map(item => ({
            label: item,
            value: item,
            isSelected: false
            }));
            this.createInitialCsvMapping();
        }
        
        // Descriptive information for UI
        compositeKeyDescription = 'A composite key combines multiple fields to uniquely identify records. For example: Name + Phone creates a unique identifier using both fields together.';
        mappingStepDescription = 'Match each CSV column to the corresponding Salesforce field. For lookup fields, select the fields that will identify related records.';
        
        @api getMappedCsvColumns() {
            return this.selectedDropdownValues.map(item => item.csvFieldName || item.keyField).filter(Boolean);
        }
    columns = [
        { label: 'Csv Column', fieldName: 'csvFieldName' },
        { label: 'SF Field', fieldName: 'selectedField' },
        { label: 'Lookup Object', fieldName: 'lookupObjectName' },
        { label: 'Selected Lookup Mapping', fieldName: 'lookupField1' },
        { label: 'Return Field', fieldName: 'returnField' }
    ];
 
    get showUniqueKeySection() {
        return  this.selectedOperation === 'Upsert';
    }
    get showUniqueKeyCombobox() {
        return this.selectedOperation === 'Upsert' && (this.csvHeaderOptions.length > 0 || this.compositeHeaderOptions.length > 0);
    }
    get uniqueKeyCreated() {
        return this.createdUniqueKeyColumns.length > 0;
    }
 
    get isCreateUniqueKeyDisabled() {
        return !this.selectedUniqueKeyColumns || this.selectedUniqueKeyColumns.length === 0;
    }
    get showCreateMappingButton() {
    return !this.existingMappingMode;
}

get showModifyMappingButton() {
    const savedHeaders = new Set(
        (this._existingMappingDetails || []).map(record =>
            (record.File_Column_Name__c || '')
                .trim()
                .toLowerCase()
        )
    );

    const hasNewHeaders = (this.selectedDropdownValues || []).some(row => {
        const header = (row.csvFieldName || '')
            .trim()
            .toLowerCase();

        return header && !savedHeaders.has(header);
    });

    return !this.isMappingModified && hasNewHeaders;
}

get showCompositeUniqueKeys() {
    return !this.existingMappingMode;
}
    normalizeHeader(header) {
    return (header || '').trim().toLowerCase();
}

getExistingMappedHeaders() {
    const records = this._existingMappingDetails || [];

    // A composite mapping stores multiple CSV headers
    // in one comma-separated File_Column_Name__c value.
    return records.flatMap(record =>
        (record.File_Column_Name__c || '')
            .split(',')
            .map(header => this.normalizeHeader(header))
            .filter(Boolean)
    );
}

checkHeaderDifferences() {
    const csvHeaders = [
        ...new Set(
            (this.csvHeaders || [])
                .map(header => this.normalizeHeader(header))
                .filter(Boolean)
        )
    ];

    const savedHeaders = [
        ...new Set(this.getExistingMappedHeaders())
    ];

    this.hasHeaderDifferences =
        csvHeaders.length !== savedHeaders.length ||
        csvHeaders.some(header => !savedHeaders.includes(header));
}
    // Helper to build dropdown configs for composite columns
    buildCompositeDropdowns(column) {
        if (!column || !column.value || !column.isComposite) return [];
        const parts = column.value.split(',').map(s => s.trim());
        return parts.map(part => ({
            label: part,
            valueProp: 'lookupField_' + part,
            value: column['lookupField_' + part] || '',
            options: column.lookupObjectOptions,
            name: part
        }));
    }

    // --- Cross-object, non-lookup mapping handlers ---
    // Handler for SINGLE (non-composite) non-lookup target object selection
    handleTargetObjectChange(event) {
        const keyField = event.target.dataset.keyfield;
        const value = event.detail.value;
        const idx = this.selectedDropdownValues.findIndex(obj => obj.keyField === keyField);
        if (idx === -1) return;

        const item = { ...this.selectedDropdownValues[idx] };
        item.targetObject = value;
        item.matchField = '';
        item.returnField = '';
        item.targetObjectFields = [];
        this.selectedDropdownValues[idx] = item;
        this.selectedDropdownValues = [...this.selectedDropdownValues]; // Trigger reactivity

        if (value) {
            console.log('Fetching fields for single non-lookup object:', value);
            getFields({ objectName: value })
                .then(data => {
                    const fieldsArray = data.map(field => ({ label: field.label, value: field.apiName }));
                    this.selectedDropdownValues[idx] = {
                        ...this.selectedDropdownValues[idx],
                        targetObjectFields: fieldsArray
                    };
                    this.selectedDropdownValues = [...this.selectedDropdownValues];
                    console.log('Fetched target object fields for', value, ':', fieldsArray);
                })
                .catch((error) => {
                    console.error('Error fetching target object fields:', error);
                    this.selectedDropdownValues[idx] = {
                        ...this.selectedDropdownValues[idx],
                        targetObjectFields: []
                    };
                    this.selectedDropdownValues = [...this.selectedDropdownValues];
                });
        }
    }

    // Handler for COMPOSITE non-lookup target object selection
    handleCompositeTargetObjectChange(event) {
        const keyField = event.target.dataset.keyfield;
        const value = event.detail.value;

        const idx = this.selectedDropdownValues.findIndex(
            obj => obj.keyField === keyField
        );

        if (idx === -1) {
            return;
        }

        const item = {
            ...this.selectedDropdownValues[idx]
        };

        // ==========================================
        // COMPOSITE LOOKUP
        // ==========================================
        if (item.isCompositeLookup) {

            item.lookupObjectApiName = value;
            item.lookupObjectName =
                this.convertApiNameToDisplayName(value);

            item.lookupObjectOptions = [];
            item.lookupObjectFields = [];
            item.returnField = '';

            this.selectedDropdownValues[idx] = item;
            this.selectedDropdownValues = [
                ...this.selectedDropdownValues
            ];

            if (value) {
                getFields({ objectName: value })
                    .then(data => {

                        const fieldsArray = data.map(field => ({
                            label: field.label,
                            value: field.apiName
                        }));

                        this.selectedDropdownValues[idx] = {
                            ...this.selectedDropdownValues[idx],
                            lookupObjectFields: fieldsArray
                        };

                        this.selectedDropdownValues = [
                            ...this.selectedDropdownValues
                        ];
                    })
                    .catch(error => {
                        console.error(
                            'Error fetching composite lookup object fields:',
                            error
                        );

                        this.selectedDropdownValues[idx] = {
                            ...this.selectedDropdownValues[idx],
                            lookupObjectFields: []
                        };

                        this.selectedDropdownValues = [
                            ...this.selectedDropdownValues
                        ];
                    });
            }

            return;
        }

        // ==========================================
        // COMPOSITE NON-LOOKUP
        // ==========================================

        item.targetObject = value;
        item.compositeTargetObject = value;
        item.returnField = '';
        item.compositeTargetObjectFields = [];

        this.selectedDropdownValues[idx] = item;
        this.selectedDropdownValues = [
            ...this.selectedDropdownValues
        ];

        if (value) {
            getFields({ objectName: value })
                .then(data => {

                    const fieldsArray = data.map(field => ({
                        label: field.label,
                        value: field.apiName
                    }));

                    this.selectedDropdownValues[idx] = {
                        ...this.selectedDropdownValues[idx],
                        compositeTargetObjectFields: fieldsArray
                    };

                    this.selectedDropdownValues = [
                        ...this.selectedDropdownValues
                    ];
                })
                .catch(error => {

                    console.error(
                        'Error fetching composite target object fields:',
                        error
                    );

                    this.selectedDropdownValues[idx] = {
                        ...this.selectedDropdownValues[idx],
                        compositeTargetObjectFields: []
                    };

                    this.selectedDropdownValues = [
                        ...this.selectedDropdownValues
                    ];
                });
        }
    }

    handleTargetObjectMatchFieldChange(event) {
        const keyField = event.target.dataset.keyfield;
        const value = event.detail.value;
        const idx = this.selectedDropdownValues.findIndex(obj => obj.keyField === keyField);
        if (idx !== -1) {
            this.selectedDropdownValues[idx].matchField = value;
            this.selectedDropdownValues = [...this.selectedDropdownValues];
        }
    }
    handleTargetObjectReturnFieldChange(event) {
        const keyField = event.target.dataset.keyfield;
        const value = event.detail.value;
        const idx = this.selectedDropdownValues.findIndex(obj => obj.keyField === keyField);
        if (idx !== -1) {
            this.selectedDropdownValues[idx].returnField = value;
            this.selectedDropdownValues = [...this.selectedDropdownValues];
        }

    }
    // Returns array of parts for a composite key (split by ',')
    getCompositeParts(columnValue) {
        if (!columnValue) return [];
        return columnValue.split(',').map(s => s.trim());
    }
    handleUniqueKeyCheckboxChange(event) {
        const value = event.target.dataset.value;
        const checked = event.target.checked;
        if (checked) {
            if (!this.selectedUniqueKeyColumns.includes(value)) {
                this.selectedUniqueKeyColumns = [...this.selectedUniqueKeyColumns, value];
            }
        } else {
            this.selectedUniqueKeyColumns = this.selectedUniqueKeyColumns.filter(col => col !== value);
        }

        this.uniqueKeyHeaderOptions = this.uniqueKeyHeaderOptions.map(opt => ({
            ...opt,
            isSelected: this.selectedUniqueKeyColumns.includes(opt.value)
        }));
        // Update dropdowns for unique key section
        this.updateUniqueKeyDropdowns();
    }
 
    handleCreateUniqueKey() {
        if (this.selectedUniqueKeyColumns.length === 0) {
            this.showToast('Error', 'Select at least one column.', 'error');
            return;
        }
        this.createdUniqueKeyColumns = [...this.selectedUniqueKeyColumns];
        this._uniqueKeyCreated = true;
        this.showToast('Success', 'Unique key defined.', 'success');
    }
 
    handleRemoveUniqueKey() {
        this.createdUniqueKeyColumns = [];
        this.selectedUniqueKeyColumns = [];
        this._uniqueKeyCreated = false;
        this.uniqueKeyHeaderOptions = this.uniqueKeyHeaderOptions.map(opt => ({
            ...opt,
            isSelected: false
        }));
    }
 
    // --- For Unique Key Section Dropdowns ---
    @track selectedCsvColumns = [];
    @track selectedSfFields = [];
    @track sfFieldOptions = [];
 
    // Sync selectedCsvColumns and sfFieldOptions when unique key columns change
    getSelectedKeyColumns() {
        // Use selectedUniqueKeyColumns for unique key section
        return this.selectedUniqueKeyColumns && this.selectedUniqueKeyColumns.length > 0
            ? this.selectedUniqueKeyColumns
            : this.csvHeaders;
    }
 
    // Called in connectedCallback and when unique key changes
    updateUniqueKeyDropdowns() {
        this.selectedCsvColumns = this.getSelectedKeyColumns();
        // Ensure selectedSfFields has same length
        if (!this.selectedSfFields || this.selectedSfFields.length !== this.selectedCsvColumns.length) {
            this.selectedSfFields = Array(this.selectedCsvColumns.length).fill('');
        }
        // Use fieldOptions for dropdown options
        this.sfFieldOptions = this.fieldOptions;
    }
 
    // Handler for dropdown change in unique key section
    handleSfFieldChange(event) {
        const idx = event.target.dataset.index;
        const value = event.detail.value;
        if (idx !== undefined) {
            this.selectedSfFields[idx] = value;
        }
    }
 
connectedCallback() {

    // Initialize composite mapping options
    this.csvHeaderOptions = this.csvHeaders.map(item => ({
        label: item,
        value: item,
        isSelected: false
    }));

    // Initialize unique key options
    this.uniqueKeyHeaderOptions = this.csvHeaders.map(item => ({
        label: item,
        value: item,
        isSelected: false
    }));

    // Get Salesforce fields
    getFields({ objectName: this.selectedObject })
        .then(data => {

            this.fieldsWithLookupList = data
                .filter(field => field.isLookup)
                .map(field => ({
                    label: field.label,
                    apiName: field.apiName,
                    isLookup: field.isLookup
                }));

            this.fieldOptions = data.map(field => ({
                label: field.label,
                value: field.apiName
            }));

            // Update unique key dropdowns
            this.updateUniqueKeyDropdowns();
            // Rebuild existing mappings now that Salesforce fields are loaded.
            if (this._existingMappingDetails?.length) {
            this.populateExistingMapping();
}

        })
        .catch(error => {

            console.error(
                'Error loading fields for object:',
                this.selectedObject,
                error
            );

            this.showToast(
                'Error',
                'Failed to load fields for ' +
                this.selectedObject +
                '. ' +
                (
                    error.body
                        ? error.body.message
                        : error.message || ''
                ),
                'error'
            );
        });

    // Component is now initialized
    this._isInitialized = true;

    // If existing mapping was passed, use it
    if (this._existingMappingDetails.length > 0) {

        this.populateExistingMapping();

    } else {

        // Otherwise create normal blank mapping
        this.createInitialCsvMapping();
    }

    // Initial update for unique key section
    this.updateUniqueKeyDropdowns();
    }
   
    handleShowCompositeMappingUI() {
        // Only add a new section if there are no sections, or the last one is mapped
        if (
            this.compositeSections.length === 0 ||
            this.compositeSections[this.compositeSections.length - 1].isMapped
        ) {
            this.compositeSections.push({
                id: this.compositeSections.length,
                selectedColumns: [],
                isMapped: false,
                isButtonDisabled: false,
                // For composite columns, add static property names for dropdowns
                name1: 'composite1',
                name2: 'composite2',
                lookupField1: '',
                lookupField2: '',
            });
        } else {
            this.showToast('Error', 'Please complete the current composite mapping before adding a new one.', 'error');
        }
    }
    handleFieldSearch(event) {

    const inputValue = event.target.value || '';
    const searchTerm = inputValue.toLowerCase().trim();
    //const keyField = event.target.dataset.keyfield;
    const keyField =
    event.currentTarget?.dataset?.keyfield ||
    event.target?.dataset?.keyfield ||
    event.currentTarget?.name ||
    event.target?.name;
    console.log('FIELD SEARCH:', inputValue);
    console.log('KEY FIELD:', keyField);
    console.log('FIELD OPTIONS:', this.fieldOptions);

    const index = this.selectedDropdownValues.findIndex(
        row => row.keyField === keyField
    );

    if (index === -1) {
        return;
    }

    const currentRow = this.selectedDropdownValues[index];

    this.selectedDropdownValues[index] = {
        ...currentRow,
        fieldSearchTerm: inputValue,
        showFieldRecommendations: !!searchTerm,
        filteredFieldOptions: searchTerm
            ? this.fieldOptions.filter(option =>
                option.label.toLowerCase().includes(searchTerm) ||
                option.value.toLowerCase().includes(searchTerm)
            )
            : []
    };

    this.selectedDropdownValues = [
        ...this.selectedDropdownValues
    ];
}
handleLookupObjectSearch(event) {

    const inputValue = event.target.value || '';
    const searchTerm = inputValue.toLowerCase().trim();

    const keyField =
        event.currentTarget?.dataset?.keyfield ||
        event.target?.dataset?.keyfield ||
        event.currentTarget?.name ||
        event.target?.name;

    console.log('LOOKUP OBJECT SEARCH:', inputValue);
    console.log('KEY FIELD:', keyField);
    console.log('AVAILABLE OBJECTS:', this.availableObjects);

    const index = this.selectedDropdownValues.findIndex(
        row => row.keyField === keyField
    );

    if (index === -1) {
        return;
    }

    const currentRow = this.selectedDropdownValues[index];

    this.selectedDropdownValues[index] = {
        ...currentRow,

        lookupObjectSearchTerm: inputValue,

        showLookupObjectRecommendations: !!searchTerm,

        filteredLookupObjectOptions: searchTerm
            ? this.availableObjects.filter(option =>
                option.label &&
                option.label.toLowerCase().includes(searchTerm)
            )
            : []
    };

    this.selectedDropdownValues = [
        ...this.selectedDropdownValues
    ];
}
handleLookupObjectRecommendationClick(event) {

    const selectedValue = event.currentTarget.dataset.value;
    const selectedLabel = event.currentTarget.dataset.label;
    const keyField = event.currentTarget.dataset.keyfield;

    console.log(
        'LOOKUP OBJECT SELECTED:',
        selectedValue
    );

    const index = this.selectedDropdownValues.findIndex(
        row => row.keyField === keyField
    );

    if (index === -1) {
        return;
    }

    this.selectedDropdownValues[index] = {
        ...this.selectedDropdownValues[index],

        lookupObjectSearchTerm: selectedLabel,

        showLookupObjectRecommendations: false,

        filteredLookupObjectOptions: []
    };

    this.selectedDropdownValues = [
        ...this.selectedDropdownValues
    ];

    // Call existing composite lookup logic
    this.handleCompositeTargetObjectChange({
        target: {
            dataset: {
                keyfield: keyField
            }
        },
        detail: {
            value: selectedValue
        }
    });
}
handleFieldRecommendationClick(event) {

    const selectedValue = event.currentTarget.dataset.value;
    const selectedLabel = event.currentTarget.dataset.label;
    const keyField = event.currentTarget.dataset.keyfield;

    const index = this.selectedDropdownValues.findIndex(
        row => row.keyField === keyField
    );

    if (index === -1) {
        return;
    }

    this.selectedDropdownValues[index] = {
        ...this.selectedDropdownValues[index],
        fieldSearchTerm: selectedLabel,
        showFieldRecommendations: false,
        filteredFieldOptions: []
    };

    this.selectedDropdownValues = [
        ...this.selectedDropdownValues
    ];

    // IMPORTANT:
    // Now call your EXISTING mapping logic.
    this.handleFieldChange({
        target: {
            name: keyField,
            value: selectedValue
        }
    });
}   
    handleFieldChange(event) {
        let keyField;
        let selectedValue;
        let isLookup = false;
 
        // Case A: structured child event
        // if (event && event.detail && event.detail.keyField) {
        //     const fieldDetails = event.detail;
        //     console.log('Received structured field change event:', fieldDetails);
        //     keyField = fieldDetails.keyField;
        //     console.log('keyField:', keyField);
        //     selectedValue = fieldDetails.selectedValue || fieldDetails.value || '';
        //     console.log('selectedValue:', selectedValue);
        //     isLookup = !!fieldDetails.isLookup;
        //     console.log('isLookup:', isLookup);
 
        //     const index = this.selectedDropdownValues.findIndex(obj => obj.keyField === keyField);
        //     if (index !== -1) {
        //         if (isLookup) {
        //             this.selectedDropdownValues[index] = { ...this.selectedDropdownValues[index],
        //                 selectedField: selectedValue,
        //                 lookupObject: fieldDetails.lookupObjectName || '',
        //                 whereClause: fieldDetails.whereClause || '',
        //                 isLookup: true,
        //                 selectedLookupFields: fieldDetails.selectedLookupFieldValues || [],
        //                 extraCsvField: fieldDetails.extraCsvField || ''
        //             };
        //         } else {
        //             this.selectedDropdownValues[index] = { ...this.selectedDropdownValues[index],
        //                 selectedField: selectedValue,
        //                 isLookup: false,
        //                 lookupObject: "",
        //                 whereClause: "",
        //                 selectedLookupFields: [],
        //                 extraCsvField: ""
        //             };
        //         }
        //     }
        //     return;
        // }
 
        // if (event && event.detail && event.detail.value && event.target && event.target.name) {
        //     keyField = event.target.name;
        //     selectedValue = event.detail.value;
        //     // determine if value is a lookup field
        //     isLookup = !!(this.fieldsWithLookupList && this.fieldsWithLookupList.some(f => f.apiName === selectedValue));
        //     const index = this.selectedDropdownValues.findIndex(obj => obj.keyField === keyField);
        //     if (index !== -1) {
        //         this.selectedDropdownValues[index] = {
        //             ...this.selectedDropdownValues[index],
        //             selectedField: selectedValue,
        //             isLookup: isLookup,
        //             lookupObject: isLookup ? (this.selectedDropdownValues[index].lookupObject || '') : '',
        //             selectedLookupFields: isLookup ? (this.selectedDropdownValues[index].selectedLookupFields || []) : [],
        //             extraCsvField: isLookup ? (this.selectedDropdownValues[index].extraCsvField || '') : ''
        //         };
        //     }
        //     return;
        // }
        // Case B: simple event from dropdown
        console.log('Received simple field change event:', event.detail, event.target);
        if (event && event.target && event.target.name) {
 
            keyField = event.target.name;
            selectedValue = event.target.value;
            const index = this.selectedDropdownValues.findIndex(obj => obj.keyField === keyField);
 
                if (index !== -1) {
 
               // const fieldIsLookup = !!(this.fieldsWithLookupList && this.fieldsWithLookupList.some(f => f.apiName === selectedValue));
                isLookup = this.selectedDropdownValues[index].isLookup;
                console.log("whereClause"+this.uniqueIdentifierWhereClause);
                  let returnField = this.selectedDropdownValues[index].returnField;
                if (
                    isLookup &&
                    selectedValue &&
                    typeof selectedValue === 'string' &&
                    selectedValue.trim().toLowerCase().endsWith('id')
                ) {
                    returnField = 'Id';
                }
                this.selectedDropdownValues[index] = {
                    ...this.selectedDropdownValues[index],
                    selectedField: selectedValue,
                    isLookup: isLookup,
                    whereClause:  isLookup ? (this.uniqueIdentifierWhereClause || '') : '',
                    selectedLookupFields: isLookup ? (this.selectedDropdownValues[index].selectedLookupFields || []) : [],
                    returnField: isLookup ? (returnField || '') : ''
                };
               
                if(selectedValue === 'Id') {
                    // For Id field, set lookup object to selected object
                    this.selectedDropdownValues[index] = {
                        ...this.selectedDropdownValues[index],
                        lookupObjectApiName: this.selectedObject,
                        lookupObjectName: this.selectedObject,
                        lookupObjectOptions: this.fieldOptions,
                    };
                    this.selectedDropdownValues = [...this.selectedDropdownValues];
                    console.log('Set lookup object to selected object for Id field:', this.selectedObject);
                }
                else if (isLookup ) {
                    // Get the lookup field details
                    const lookupFieldObj = this.fieldsWithLookupList.find(f => f.apiName === selectedValue);
                   
                    if (lookupFieldObj) {
                        // Fetch the lookup fields and object information
                        getLookupFields({ parentObjectName: this.selectedObject, lookupFieldName: selectedValue })
                        .then(data => {
                            const lookupFieldOptions = data.fieldList.map(field => ({ label: field.label, value: field.apiName, isLookup: field.isLookup }));
                            console.log('Fetched lookup fields for', selectedValue, ':', lookupFieldOptions);
                            console.log('Lookup Object Name:', data.lookUpObjectName);
                           
                            // Get fields of the lookup object to populate lookup object options
                            return getFields({ objectName: data.lookUpObjectName }).then(lookupObjFields => {
                                const lookupObjFieldOptions = lookupObjFields.map(field => ({
                                    label: field.label,
                                    value: field.apiName
                                }));
                               
                                // Convert API name to display name (e.g., "OperatingHour" -> "Operating Hour")
                                const displayName = this.convertApiNameToDisplayName(data.lookUpObjectName);
                               
                                this.selectedDropdownValues[index] = {
                                    ...this.selectedDropdownValues[index],
                                    lookupObjectOptions: lookupObjFieldOptions,
                                    lookupObjectApiName: data.lookUpObjectName,
                                    lookupObjectName: displayName,
                                };
                                // force reactive update
                                this.selectedDropdownValues = [...this.selectedDropdownValues];
                                console.log('Updated lookup object:', displayName);
                                console.log('Updated lookup object options:', lookupObjFieldOptions);
                            });
                        })
                        .catch(error => {
                            console.error('Error fetching lookup object fields:', error);
                        });
                    }
                } else {
                    // clear any lookup-specific options when not a lookup
                    // BUT preserve isComposite flag if it was already set
                    const shouldPreserveComposite = this.selectedDropdownValues[index].isComposite === true;
                    this.selectedDropdownValues[index] = {
                        ...this.selectedDropdownValues[index],
                        lookupObjectOptions: [],
                        lookupObjectApiName: '',
                        lookupObjectName: '',
                        whereClause: '',
                        isComposite: shouldPreserveComposite, // Preserve if it's a composite
                        targetObject: '',
                        targetObjectFields: [],
                        compositeTargetObjectFields: [],
                        matchField: '',
                        returnField: ''
                    }
                    }
                    this.selectedDropdownValues = [...this.selectedDropdownValues];
                }
            }
        }
    
 
    // handleLookupObjectChange(event) {
    //     const keyField = event.target.name;
    //     const value = event.detail && event.detail.value ? event.detail.value : event.target.value;
    //     const index = this.selectedDropdownValues.findIndex(obj => obj.keyField === keyField);
    //     if (index !== -1) {
    //         this.selectedDropdownValues[index] = {
    //             ...this.selectedDropdownValues[index],
    //             lookupObjectApiName: value,
    //             lookupObjectName: this.convertApiNameToDisplayName(value) || value,
    //             lookupObjectOptions: [] // clear while loadin
    //         };
    //         this.selectedDropdownValues = [...this.selectedDropdownValues];
    //         getFields({ objectName: value })
    //             .then(fields => {
    //                 const options = fields.map(f => ({ label: f.label, value: f.apiName }));
    //                 this.selectedDropdownValues[index] = {
    //                     ...this.selectedDropdownValues[index],
    //                     lookupObjectOptions: options
    //                 };
    //                 this.selectedDropdownValues = [...this.selectedDropdownValues];
    //             })
    //             .catch(error => {
    //                 this.selectedDropdownValues[index] = {
    //                     ...this.selectedDropdownValues[index],
    //                     lookupObjectOptions: []
    //                 };
    //                 this.selectedDropdownValues = [...this.selectedDropdownValues];
    //                 console.error('Error fetching fields for lookup object:', error);
    //             });
    //     }
    // }
 
    handleLookupFieldSelection(event) {
        const partName = event.target.name; // Composite part name or field name
        const keyField = event.target.dataset.keyfield || event.target.name; // Get from data attribute or name
        const value = event.detail.value; // Selected value from combobox
       
        console.log('handleLookupFieldSelection - partName:', partName, 'keyField:', keyField, 'value:', value);
       
        // Find the selectedDropdownValues entry
        const index = this.selectedDropdownValues.findIndex(obj => obj.keyField === keyField);
        console.log('Found index:', index, 'Total items:', this.selectedDropdownValues.length);
       
        if (index !== -1) {
            const currentItem = this.selectedDropdownValues[index];
            console.log('Current item isComposite:', currentItem.isComposite, 'value contains comma:', currentItem.value && currentItem.value.includes(','));
           
            // Check if this is a composite field (has multiple parts)
            if (currentItem.isComposite && currentItem.value && currentItem.value.includes(',')) {
                // Store value with dynamic property name for each composite part
                const propName = 'lookupField_' + partName;
                this.selectedDropdownValues[index] = {
                    ...this.selectedDropdownValues[index],
                    [propName]: value
                };
                console.log('Updated composite field:', propName, '=', value);
            } else {
                // For non-composite lookups, store in lookupField1
                this.selectedDropdownValues[index] = {
                    ...this.selectedDropdownValues[index],
                    lookupField1: value,
                    selectedLookupFields: value
                };
                console.log('Updated non-composite lookupField1:', value);
            }
            this.selectedDropdownValues = [...this.selectedDropdownValues];
            console.log('Updated item:', this.selectedDropdownValues[index]);
        } else {
            console.log('WARNING: Could not find item with keyField:', keyField);
            console.log('Available keyFields:', this.selectedDropdownValues.map(item => item.keyField));
        }
    }
 
    handleWhereClauseChange(event) {
        const keyField = event.target.name;
        const value = event.target.value;
        const index = this.selectedDropdownValues.findIndex(obj => obj.keyField === keyField);
        if (index !== -1) {
            this.selectedDropdownValues[index] = {
                ...this.selectedDropdownValues[index],
                whereClause: value
            };
            this.selectedDropdownValues = [...this.selectedDropdownValues];
        }
    }
 
    // Helper method to convert API name to display name
    // Example: "OperatingHour" -> "Operating Hour", "Account" -> "Account"
    convertApiNameToDisplayName(apiName) {
        if (!apiName) return '';
        // Insert space before uppercase letters (except the first one)
        return apiName.replace(/([A-Z])/g, ' $1').trim();
    }
 
    // Getter function to retrieve selected value for a specific header
    getSelectedValue(header) {
        return this.selectedValues[header] || '';
    }
   
     handleDeleteCompositeSection(event) {
        const sectionId = parseInt(event.currentTarget.dataset.sectionid, 10);
        // Remove the section
        this.compositeSections = this.compositeSections.filter(sec => sec.id !== sectionId);
        // Remove the mapping and composite header if it was mapped
        const mapping = this.createdCompositeMappings.find(m => m.id === sectionId);
        if (mapping) {
            const compositeKey = mapping.compositeKey;
            const uniqueKeyField = `${compositeKey}__COMPOSITE_${sectionId}`;
            this.selectedDropdownValues = this.selectedDropdownValues.filter(row => row.keyField !== uniqueKeyField);
            this.compositeHeaderOptions = this.compositeHeaderOptions.filter(opt => opt.value !== uniqueKeyField);
            this.csvHeaders = this.csvHeaders.filter(h => h !== compositeKey);
            this.createdCompositeMappings = this.createdCompositeMappings.filter(m => m.id !== sectionId);
        }
            // Re-index section ids to be sequential
            this.compositeSections = this.compositeSections.map((sec, idx) => ({ ...sec, id: idx }));
    }
    handleCreateMappingClick() {

    // Clear name only for a brand-new mapping
    if (!this._existingMappingDetails.length) {
        this.mappingName = '';
    }

    this.showMappingNameModal = true;
    }

    handleMappingNameChange(event) {
    this.mappingName = event.target.value;
    }

    handleCancelMappingName() {
    this.showMappingNameModal = false;
    this.mappingName = '';
    }
 async createMapping() {
    const trimmedMappingName = (this.mappingName || '').trim();

    if (!trimmedMappingName) {
        this.showToast(
            'Error',
            'Please enter a Mapping Name.',
            'error'
        );
        return;
    }

    // Check duplicate name in Salesforce
    try {
        const exists = await mappingNameExists({
            mappingName: trimmedMappingName
        });

        if (exists) {
            this.showToast(
                'Error',
                'Mapping name already exists. Please enter a unique name.',
                'error'
            );
            return;
        }
    } catch (error) {
        this.showToast(
            'Error',
            error.body?.message || 'Unable to validate mapping name.',
            'error'
        );
        return;
    }










        this.configuration.objectName = this.selectedObject;
        this.configuration.operationType = this.selectedOperation;
        this.configuration.mappingName = this.mappingName.trim();
        // Transform selectedDropdownValues to match the expected structure
        this.configuration.mapping = this.selectedDropdownValues.map(item => {
            let selectedLookupFields = '';
            let lookupObjectName = '';
            let targetObject = '';
            let matchField = '';
            let returnField = '';

            if (item.isComposite && item.value && item.value.includes(',')) {

                console.log('>>> ENTERING COMPOSITE BRANCH for', item.csvFieldName);
                const parts = item.value.split(',').map(s => s.trim());
                
                // Collect per-part field selections for BOTH composite lookup and composite non-elookup
                const lookupValues = parts
                    .map(part => {
                        const val = item['lookupField_' + part];
                        return val ? String(val).toLowerCase() : null;
                    })
                    .filter(val => val !== null && val !== undefined && val.trim && val.trim() !== '');
                if (lookupValues.length > 0) {
                    selectedLookupFields = lookupValues.join(',');
                }
                
                // For composite lookup: use lookupObjectApiName
                // For composite non-lookup: use compositeTargetObject
                if (item.isLookup) {
                    lookupObjectName = item.lookupObjectApiName || '';
                    returnField = item.returnField || '';
                } else if (item.compositeTargetObject) {
                    console.log('>>> COMPOSITE NON-LOOKUP detected for', item.csvFieldName);
                    // Composite non-lookup mapping
                    lookupObjectName = item.compositeTargetObject;
                    targetObject = item.compositeTargetObject;
                    matchField = selectedLookupFields; // Store the per-part field selections here
                    returnField = item.returnField || '';
                }
            } else if (item.isLookup && item.lookupField1) {
                console.log('>>> ENTERING NON-COMPOSITE LOOKUP BRANCH for', item.csvFieldName);
                // For non-composite lookups
                selectedLookupFields = String(item.lookupField1).toLowerCase();
                lookupObjectName = item.lookupObjectApiName || '';
            }

            // Pass targetObject for single non-lookup cross-object mapping
            if (!item.isComposite && !item.isLookup && item.targetObject) {
                console.log('>>> ENTERING SINGLE NON-LOOKUP BRANCH for', item.csvFieldName);
                targetObject = item.targetObject;
                matchField = item.matchField ;
                returnField = item.returnField ;
                lookupObjectName = item.targetObject;
            }

            // Set isLookup to true if targetObject is set
            // const isLookupFinal = item.isLookup || (!!item.targetObject);

            const isLookupFinal = !!item.isLookup;

            const mappingObj = {
                csvFieldName: item.csvFieldName,
                selectedField: item.selectedField,
                isLookup: isLookupFinal,
                selectedLookupFields: selectedLookupFields,
                lookupObject: lookupObjectName,
                whereClause: item.whereClause || '',
                isUniqueKey: item.isUniqueKey || false,
                targetObject: targetObject,
                matchField: matchField,
                returnField: returnField
            };
            
            return mappingObj;
        });

        if (this.selectedOperation === 'Upsert') {
            this.configuration.mapping = this.configuration.mapping.map(mapping => {
                const orig = this.selectedDropdownValues.find(m => m.csvFieldName === mapping.csvFieldName && m.selectedField === mapping.selectedField);
                const isUniqueKey = this.createdUniqueKeyColumns.includes(orig ? orig.keyField : mapping.csvFieldName);
                return { ...mapping, isUniqueKey: isUniqueKey, lookupObject: mapping.lookupObject };
            });
        } else {
            this.configuration.mapping = this.configuration.mapping.map(mapping => {
                if (mapping.isLookup) {
                    return { ...mapping, lookupObject: mapping.lookupObject };
                }
                return mapping;
            });
        }

        this.configuration.fileName = this.fileName;
        console.log('Creating mapping with configuration:', JSON.stringify(this.configuration));
        createConfiguration({
            wrapperJson: JSON.stringify(this.configuration)
        })
            .then(() => {
                this.isMappingCreated = true;
                this.showMappingNameModal = false;
                this.mappingName = '';

                this.showToast('Success', 'CSV mapping created successfully!', 'success');
            })
            .catch(error => {
                console.error('Error creating mapping:', error);
                let errorMessage = 'Failed to create CSV mapping.';
                if (error && error.body && error.body.message) {
                    errorMessage = error.body.message;
                } else if (error && error.message) {
                    errorMessage = error.message;
                }
                this.showToast('Error', errorMessage, 'error');
            });
    }

    /*populateExistingMapping() {
        const records = this._existingMappingDetails || [];
        if (!records.length) {
            return;
        }
        console.log(
            'Populating existing mapping:',
            JSON.stringify(records)
        );
        // Populate Mapping Name
        this.mappingName = records[0].Mapping_Name__c || '';
        // Build base rows synchronously first (so the UI renders immediately),
        // then asynchronously enrich lookup rows with combobox options.
        this.selectedDropdownValues = records.map((row, index) => {
            const isComposite = (row.File_Column_Name__c || '').includes(',');
            return {
                csvFieldName: row.File_Column_Name__c || '',
                selectedField: row.Field_to_update__c || '',
                isLookup: !!row.Is_LookUp__c,
                keyField: isComposite
                    ? `${row.File_Column_Name__c}__COMPOSITE_${index}`   // mirrors handleCreateCompositeMapping's key format
                    : (row.File_Column_Name__c || `existing-${index}`),
                value: isComposite ? row.File_Column_Name__c : undefined,
                isComposite,
                lookupObjectName: '',
                lookupObjectApiName: '',
                lookupObjectOptions: [],
                lookupField1: row.Is_LookUp__c && !isComposite ? row.Lookup_Field__c : '',
                whereClause: row.Lookup_Filter_Criteria__c || '',
                returnField: row.Lookup_Return_Field__c || '',
                // raw reference kept for the async enrichment step below
                _rawLookupField: row.Lookup_Field__c || ''
            };
        });
        // Re-create unique key selections for Upsert mappings
        if (this.selectedOperation === 'Upsert') {
            this.createdUniqueKeyColumns = records
                .filter(r => r.Is_Unique_Key__c)
                .map(r => r.File_Column_Name__c);
            this._uniqueKeyCreated = this.createdUniqueKeyColumns.length > 0;
        }

        // Enrich each lookup row with the dropdown options the UI needs
        // (mirrors the logic already used in handleFieldChange for a freshly-picked lookup field)
        this.selectedDropdownValues
            .filter(r => r.isLookup && !r.isComposite && r.selectedField)
            .forEach(r => this.hydrateLookupRow(r));

        console.log(
            'Selected Dropdown Values after existing mapping:',
            JSON.stringify(this.selectedDropdownValues)
        );
    }
    // New helper — fetches the referenced object + its fields for ONE existing lookup row,
    // exactly like the manual "pick a lookup field" path does today.
    hydrateLookupRow(row) {
        getLookupFields({ parentObjectName: this.selectedObject, lookupFieldName: row.selectedField })
            .then(data => getFields({ objectName: data.lookUpObjectName }).then(fields => {
                const idx = this.selectedDropdownValues.findIndex(v => v.keyField === row.keyField);
                if (idx === -1) return;
                this.selectedDropdownValues[idx] = {
                    ...this.selectedDropdownValues[idx],
                    lookupObjectApiName: data.lookUpObjectName,
                    lookupObjectName: this.convertApiNameToDisplayName(data.lookUpObjectName),
                    lookupObjectOptions: fields.map(f => ({ label: f.label, value: f.apiName })),
                    // NOTE (risk): values were persisted in lowercase by createMapping()
                    // (`String(val).toLowerCase()`), but combobox option values are the real API
                    // names (mixed case). A straight value match will fail to pre-select the
                    // option. Do a case-insensitive match against the fetched options:
                    lookupField1: (fields.find(f => f.apiName.toLowerCase() === row._rawLookupField.toLowerCase()) || {}).apiName || ''
                };
                this.selectedDropdownValues = [...this.selectedDropdownValues];
            }))
            .catch(error => console.error('Error hydrating existing lookup mapping for', row.csvFieldName, error));
    }*/

    populateExistingMapping() {

        const records = this._existingMappingDetails || [];
        if (!records.length) {
            return;
        }

        console.log('Populating existing mapping:', JSON.stringify(records));

        // Populate Mapping Name
        this.mappingName = records[0].Mapping_Name__c || '';

        // TICKET-1: reset composite-related state before rebuilding it. Without this,
        // re-selecting a different existing mapping (or re-opening this one) would
        // keep appending duplicate entries on top of whatever was reconstructed last time.
        this.compositeHeaderOptions = [];
        this.compositeSections = [];
        this.createdCompositeMappings = [];
        this.checkHeaderDifferences();
        this.isMappingModified = false;
        const newSelectedDropdownValues = [];

        records.forEach((row) => {
            const isComposite = (row.File_Column_Name__c || '').includes(',');

            if (isComposite) {
                // =====================================================
                // TICKET-1: COMPOSITE MAPPING RECONSTRUCTION
                // =====================================================

                // Reuse the SAME counter that handleCreateCompositeMapping() uses for
                // brand-new composite mappings. This guarantees reconstructed rows and
                // any NEW composite mapping the user creates afterwards never collide
                // on keyField (collision would cause findIndex() to hit the wrong row
                // on edit/delete).
                const mappingId = this.compositeMappingIdCounter++;
                const compositeKey = row.File_Column_Name__c;
                const keyField = `${compositeKey}__COMPOSITE_${mappingId}`;

                // Step 1: make the composite column "known" to the main mapping table.
                // allHeaderOptions() builds its row list from
                // [...csvHeaderOptions, ...compositeHeaderOptions] — without this entry
                // the composite row has nothing to attach to and never renders.
                this.compositeHeaderOptions = [
                    ...this.compositeHeaderOptions,
                    { label: compositeKey, value: keyField, isSelected: false, isComposite: true }
                ];

                // Step 2: mirror handleCreateCompositeMapping()'s side effect of
                // extending csvHeaders, so any later "existingCount" style checks stay
                // consistent if the user adds more composite mappings in this session.
                if (!this.csvHeaders.includes(compositeKey)) {
                    this.csvHeaders = [...this.csvHeaders, compositeKey];
                }

                // Step 3: reconstruct the "Composite Unique Keys" panel UI so the user
                // can SEE which CSV columns were grouped together, instead of an empty
                // panel that looks like nothing was ever configured.
                this.createdCompositeMappings = [
                    ...this.createdCompositeMappings,
                    { id: mappingId, compositeKey, occurrence: 1 }
                ];
                this.compositeSections = [
                    ...this.compositeSections,
                    {
                        id: mappingId,
                        selectedColumns: compositeKey.split(',').map(s => s.trim()),
                        isMapped: true,
                        isButtonDisabled: true,
                        name1: 'composite1',
                        name2: 'composite2',
                        lookupField1: '',
                        lookupField2: ''
                    }
                ];

                // Step 4: seed the per-part lookup field values. Lookup_Field__c is
                // persisted as a single comma-joined, LOWERCASE string (see
                // createMapping()'s composite branch: `.toLowerCase()` + `.join(',')`),
                // so split it back out per CSV column. The casing gets corrected in
                // hydrateCompositeRow() below once we fetch the live, case-sensitive
                // field list — combobox option values are case-sensitive, so leaving
                // this lowercase would fail to pre-select the dropdown option.
                const parts = compositeKey.split(',').map(s => s.trim());
                const storedLookupParts = (row.Lookup_Field__c || '').split(',').map(s => s.trim());

                const compositeRow = {
                    csvFieldName: compositeKey,
                    selectedField: row.Field_to_update__c || '',
                    isLookup: !!row.Is_LookUp__c,
                    // Composite rows are only ever reachable today via the "Use Lookup"
                    // checkbox, which always sets isCompositeLookup = true for a
                    // composite column (see handleLookupCheckboxChange) — mirror that.
                    isCompositeLookup: !!row.Is_LookUp__c,
                    keyField,
                    value: compositeKey,
                    isComposite: true,
                    lookupObjectName: '',
                    lookupObjectApiName: '',
                    lookupObjectOptions: [],
                    lookupObjectFields: [],
                    whereClause: row.Lookup_Filter_Criteria__c || '',
                    returnField: row.Lookup_Return_Field__c || '',
                    targetObject: '',
                    compositeTargetObject: '',
                    compositeTargetObjectFields: [],
                    matchField: '',
                    // raw reference used only by hydrateCompositeRow() below
                    _rawLookupObjectName: row.Lookup_Object_Name__c || ''
                };

                parts.forEach((part, i) => {
                    compositeRow['lookupField_' + part] = storedLookupParts[i] || '';
                });

                newSelectedDropdownValues.push(compositeRow);

            } else {
                // --- Existing non-composite logic (unchanged behavior) ---
                newSelectedDropdownValues.push({
                    csvFieldName: row.File_Column_Name__c || '',
                    selectedField: row.Field_to_update__c || '',
                    fieldSearchTerm: this.fieldOptions.find(
                    option => option.value === row.Field_to_update__c
                    )?.label || row.Field_to_update__c || '',
                    isLookup: !!row.Is_LookUp__c,
                    keyField: row.File_Column_Name__c || `existing-${newSelectedDropdownValues.length}`,
                    value: undefined,
                    isComposite: false,
                    lookupObjectName: '',
                    lookupObjectApiName: '',
                    lookupObjectOptions: [],
                    lookupField1: row.Is_LookUp__c ? row.Lookup_Field__c : '',
                    whereClause: row.Lookup_Filter_Criteria__c || '',
                    returnField: row.Lookup_Return_Field__c || '',
                    _rawLookupField: row.Lookup_Field__c || ''
                });
            }
        });

        //this.selectedDropdownValues = newSelectedDropdownValues;
const normalizeHeader = value =>
    (value || '').trim().toLowerCase();

const existingHeaders = new Set(
    newSelectedDropdownValues.map(row =>
        normalizeHeader(row.csvFieldName)
    )
);

this.csvHeaderOptions.forEach(header => {
    const normalizedHeader = normalizeHeader(header.value);

    // Skip headers already mapped, ignoring case and spaces.
    if (!normalizedHeader || existingHeaders.has(normalizedHeader)) {
        return;
    }

    newSelectedDropdownValues.push({
        csvFieldName: header.value,
        selectedField: '',
        isLookup: false,
        isCompositeLookup: false,
        keyField: header.value,
        value: undefined,
        isComposite: false,
        lookupObjectName: '',
        lookupObjectApiName: '',
        lookupObjectOptions: [],
        lookupObjectFields: [],
        lookupField1: '',
        selectedLookupFields: '',
        whereClause: '',
        targetObject: '',
        targetObjectFields: [],
        compositeTargetObjectFields: [],
        matchField: '',
        returnField: '',
        isUniqueKey: false,
        mappingName: records[0]?.Mapping_Name__c || ''
    });

    // Prevent another header with different casing from being added.
    existingHeaders.add(normalizedHeader);
});

        // IMPORTANT:
        // Now Data Preview and Mapping UI use the same complete
        // set of current CSV columns.
        this.selectedDropdownValues = [
            ...newSelectedDropdownValues
        ];

        // =====================================================
        // TICKET-2: UNIQUE KEY SELECTION RECONSTRUCTION
        // =====================================================
        // FIX (robustness): prefer the record's own Operation__c over the parent
        // supplied `selectedOperation` @api property. existingMappingDetails and
        // selectedOperation are sibling @api properties set by the parent in the
        // same render pass — LWC does not guarantee which setter runs first, so
        // relying solely on `this.selectedOperation` here could read a stale
        // default ('Insert') if its setter hasn't fired yet. Reading Operation__c
        // directly from the queried row removes that race entirely.
        // NOTE: requires adding `Operation__c` to the getMappingDetails() SOQL in
        // CSVConfigurationMapping.cls (see Ticket 2 Apex change below).
        const operationFromRecord = records[0].Operation__c || this.selectedOperation;

        if (operationFromRecord === 'Upsert') {
            this.createdUniqueKeyColumns = records
                .filter(r => r.Is_Unique_Key__c)
                .map(r => r.File_Column_Name__c);
            this._uniqueKeyCreated = this.createdUniqueKeyColumns.length > 0;

            // FIX: keep selectedUniqueKeyColumns + each checkbox's isSelected flag in
            // sync with the restored unique key. Without this, clicking "Change Key"
            // (handleRemoveUniqueKey) drops the user into a blank checkbox grid
            // instead of showing the previously-selected columns pre-checked.
            this.selectedUniqueKeyColumns = [...this.createdUniqueKeyColumns];
            this.uniqueKeyHeaderOptions = this.uniqueKeyHeaderOptions.map(opt => ({
                ...opt,
                isSelected: this.createdUniqueKeyColumns.includes(opt.value)
            }));
        }

        // Hydrate single-column lookups (existing behavior, now with the
        // TICKET-4 staleness guard — see hydrateLookupRow() below)
        this.selectedDropdownValues
            .filter(r => r.isLookup && !r.isComposite && r.selectedField)
            .forEach(r => this.hydrateLookupRow(r));

        // TICKET-1: hydrate composite lookups — fetch the field list of the
        // already-known lookup object and correct the per-part field values' casing.
        this.selectedDropdownValues
            .filter(r => r.isComposite && r.isLookup && r._rawLookupObjectName)
            .forEach(r => this.hydrateCompositeRow(r));

        console.log('Selected Dropdown Values after existing mapping:', JSON.stringify(this.selectedDropdownValues));
}

// TICKET-1: companion to hydrateLookupRow(), but for composite lookup mappings.
// Unlike a single-column lookup, the lookup object for a composite mapping is
// stored directly (Lookup_Object_Name__c) rather than derived from a parent
// lookup field, so we only need getFields() here — no getLookupFields() call.
hydrateCompositeRow(row) {
    // TICKET-4: capture what triggered this fetch so we can detect staleness
    // when the promise resolves (see guard below).
    const expectedValue = row.value;

    getFields({ objectName: row._rawLookupObjectName })
        .then(fields => {
            const idx = this.selectedDropdownValues.findIndex(v => v.keyField === row.keyField);
            if (idx === -1) {
                // Row was deleted while this request was in flight.
                return;
            }

            const current = this.selectedDropdownValues[idx];

            // TICKET-4 guard: if the user unchecked "Use Lookup" or the composite
            // grouping changed while this async call was in flight, discard this
            // stale result instead of silently re-populating lookup metadata the
            // user no longer wants.
            if (!current.isLookup || current.value !== expectedValue) {
                console.log('Discarding stale composite lookup hydration for', row.csvFieldName);
                return;
            }

            const fieldOptions = fields.map(f => ({ label: f.label, value: f.apiName }));
            const updated = { ...current };

            updated.lookupObjectApiName = row._rawLookupObjectName;
            updated.lookupObjectName = this.convertApiNameToDisplayName(row._rawLookupObjectName);
            updated.lookupObjectFields = fieldOptions; // used by compositeDropdowns' "options"
            updated.lookupObjectOptions = fieldOptions; // kept in sync for consistency

            // Correct each part's stored (lowercase) value to the real,
            // case-sensitive API name now that we have the live field list.
            const parts = updated.value.split(',').map(s => s.trim());
            parts.forEach(part => {
                const propName = 'lookupField_' + part;
                const rawVal = updated[propName];
                if (rawVal) {
                    const match = fieldOptions.find(f => f.value.toLowerCase() === rawVal.toLowerCase());
                    updated[propName] = match ? match.value : rawVal;
                }
            });

            this.selectedDropdownValues[idx] = updated;
            this.selectedDropdownValues = [...this.selectedDropdownValues];
        })
        .catch(error => console.error('Error hydrating composite lookup mapping for', row.csvFieldName, error));
}

// TICKET-4: hydrateLookupRow() updated with a staleness guard (see Ticket 4 below
// for the full explanation) — replace the existing method with this version.
hydrateLookupRow(row) {
    const expectedSelectedField = row.selectedField;
    // BUGFIX: special-case the "Id" self-match pattern (e.g. matching Account by
    // AccountNumber to resolve its Id for Update/Upsert). This is NOT a true
    // lookup relationship traversal — "Id" has no reference-to target, so the
    // getLookupFields() call further below returns nothing useful for it, which
    // is why these rows previously had isLookup=true but empty
    // lookupObjectOptions/lookupField1 after reconstruction. Mirrors the same
    // shortcut already used in handleFieldChange()/handleLookupCheckboxChange()
    // for manually-created mappings.
    if (expectedSelectedField === 'Id') {
        getFields({ objectName: this.selectedObject })
            .then(fields => {
                const idx = this.selectedDropdownValues.findIndex(v => v.keyField === row.keyField);
                if (idx === -1) return;

                const current = this.selectedDropdownValues[idx];

                // Same staleness guard as below: discard if the user toggled
                // lookup off or changed the mapped field while this was in flight.
                if (!current.isLookup || current.selectedField !== expectedSelectedField) {
                    console.log('Discarding stale Id-lookup hydration for', row.csvFieldName);
                    return;
                }

                const fieldOptions = fields.map(f => ({ label: f.label, value: f.apiName }));
                // Values were persisted in lowercase by createMapping() — match
                // case-insensitively against the real field list.
                const match = fieldOptions.find(
                    f => f.value.toLowerCase() === (row._rawLookupField || '').toLowerCase()
                );

                this.selectedDropdownValues[idx] = {
                    ...current,
                    lookupObjectApiName: this.selectedObject,
                    lookupObjectName: this.selectedObject,
                    lookupObjectOptions: fieldOptions,
                    lookupField1: match ? match.value : (row._rawLookupField || '')
                };
                this.selectedDropdownValues = [...this.selectedDropdownValues];
            })
            .catch(error => console.error('Error hydrating Id-based lookup mapping for', row.csvFieldName, error));
        return; // skip the general lookup logic below for this row
    }

    getLookupFields({ parentObjectName: this.selectedObject, lookupFieldName: row.selectedField })
        .then(data => getFields({ objectName: data.lookUpObjectName }).then(fields => {
            const idx = this.selectedDropdownValues.findIndex(v => v.keyField === row.keyField);
            if (idx === -1) return;

            const current = this.selectedDropdownValues[idx];

            // TICKET-4 guard: discard this result if the user turned lookup off,
            // or changed which Salesforce field this CSV column maps to, while
            // this two-hop async chain (getLookupFields -> getFields) was in flight.
            if (!current.isLookup || current.selectedField !== expectedSelectedField) {
                console.log('Discarding stale lookup hydration for', row.csvFieldName);
                return;
            }

            this.selectedDropdownValues[idx] = {
                ...current,
                lookupObjectApiName: data.lookUpObjectName,
                lookupObjectName: this.convertApiNameToDisplayName(data.lookUpObjectName),
                lookupObjectOptions: fields.map(f => ({ label: f.label, value: f.apiName })),
                // Values were persisted in lowercase by createMapping(), but combobox
                // option values are the real API names (mixed case) — match case-insensitively.
                lookupField1: (fields.find(f => f.apiName.toLowerCase() === row._rawLookupField.toLowerCase()) || {}).apiName || ''
            };
            this.selectedDropdownValues = [...this.selectedDropdownValues];
        }))
        .catch(error => console.error('Error hydrating existing lookup mapping for', row.csvFieldName, error));
}

    createInitialCsvMapping() {
        for (let i = 0; i < this.csvHeaders.length; i++) {
            this.selectedDropdownValues.push(
                { csvFieldName: this.csvHeaders[i],
                  //selectedField: this.csvHeaders[i],
                  selectedField: '',
                  fieldSearchTerm: '',
                  showFieldRecommendations: false,
                  filteredFieldOptions: [],
                  isLookup: false,
                  isCompositeLookup: false,
                  keyField: this.csvHeaders[i],
                  lookupObjectName: '',
                  lookupObjectApiName: '',
                  lookupObjectSearchTerm: '',
                  showLookupObjectRecommendations: false,
                  filteredLookupObjectOptions: [],
                  lookupObjectOptions: [],
                  lookupObjectFields: [],
                  whereClause: '',
                  lookupField1: '',
                  isComposite: false,
                  targetObject: '',
                  targetObjectFields: [],
                  compositeTargetObjectFields: [],
                  matchField: '',
                  returnField: ''
                 });
        }
    }
    handleDeleteMapping(event)
    {
        const keyField = event.detail.keyField;
        this.selectedDropdownValues = this.selectedDropdownValues.filter(
        mapping => mapping.keyField !== keyField
    );
    }
   
    get tableData(){
        return this.selectedDropdownValues.map(item => {
            let lookupMapping = '';
            let lookupObjectName = item.lookupObjectName || '';
            let returnField = item.returnField || ' ';
                    
            // For composite mappings, collect all lookupField_* values
            if (item.isComposite && item.value) {
                console.log('>>> ENTERING COMPOSITE BRANCH for', item.csvFieldName);
                const parts = item.value.split(',').map(s => s.trim());
                
                const lookupValues = parts
                    .map(part => {
                        const propName = 'lookupField_' + part;
                        const fieldValue = item[propName];
                        console.log(`  Looking for '${propName}': ${fieldValue}`);
                        // Return the field value if it exists and is not empty
                        if (fieldValue && typeof fieldValue === 'string' && fieldValue.trim()) {
                            return fieldValue.trim();
                        }
                        return null;
                    })
                    .filter(val => val !== null && val !== undefined);
                
                console.log('  Collected lookupValues:', lookupValues);
                
                if (lookupValues.length > 0) {
                    lookupMapping = lookupValues.join(',');
                }
                
                // For composite non-lookup: use compositeTargetObject as lookup object name
                if (!item.isLookup && item.compositeTargetObject) {
                    lookupObjectName = item.compositeTargetObject;
                    returnField = item.returnField || '';
                }
                // For composite lookup: use lookupObjectName (already set)
                console.log('  Final lookupMapping:', lookupMapping);
                
            } else if (item.isLookup && item.lookupField1) {
                // For non-composite lookups
                console.log('>>> ENTERING NON-COMPOSITE LOOKUP BRANCH for', item.csvFieldName);
                lookupMapping = item.lookupField1;
            } else if (!item.isLookup && item.targetObject) {
                // For single non-lookup cross-object mapping
                console.log('>>> ENTERING SINGLE NON-LOOKUP BRANCH for', item.csvFieldName);
                lookupObjectName = item.targetObject;
                lookupMapping = item.matchField || '';
                returnField = item.returnField || '';
            }
            
            console.log('tableData - returning object for', item.csvFieldName, '{ lookupObjectName:', lookupObjectName, ', lookupField1:', lookupMapping, ', returnField:', returnField, '}');
            
            return {
                ...item,
                lookupObjectName,
                lookupField1: lookupMapping,
                returnField
            };
        });
    }
 
    // Composite Mapping Handlers
    handleColumnCheckboxChange(event) {
        const sectionId = parseInt(event.target.dataset.sectionid, 10);
        const columnValue = event.target.dataset.column;
        const isChecked = event.target.checked;
        const sectionIdx = this.compositeSections.findIndex(sec => sec.id === sectionId);
        if (sectionIdx === -1) return;
        let section = this.compositeSections[sectionIdx];
        if (isChecked) {
            if (!section.selectedColumns.includes(columnValue)) {
                section.selectedColumns = [...section.selectedColumns, columnValue];
            }
        } else {
            section.selectedColumns = section.selectedColumns.filter(col => col !== columnValue);
        }
        // Update the section in the array
        this.compositeSections = [
            ...this.compositeSections.slice(0, sectionIdx),
            { ...section },
            ...this.compositeSections.slice(sectionIdx + 1)
        ];
    }
 
    handleRemoveSelectedColumn(event) {
        const sectionId = parseInt(event.currentTarget.dataset.sectionid, 10);
        const columnValue = event.currentTarget.dataset.column;
        const sectionIdx = this.compositeSections.findIndex(sec => sec.id === sectionId);
        if (sectionIdx === -1) return;
        let section = this.compositeSections[sectionIdx];
        section.selectedColumns = section.selectedColumns.filter(col => col !== columnValue);
        this.compositeSections = [
            ...this.compositeSections.slice(0, sectionIdx),
            { ...section },
            ...this.compositeSections.slice(sectionIdx + 1)
        ];
    }
 
    handleCreateCompositeMapping(event) {
        const sectionId = parseInt(event.currentTarget.dataset.sectionid, 10);
        const sectionIdx = this.compositeSections.findIndex(sec => sec.id === sectionId);
        if (sectionIdx === -1) return;
        let section = this.compositeSections[sectionIdx];
        // Prevent duplicate mapping creation for this section
        if (section.isMapped || section.isButtonDisabled) {
            return;
        }
        if (section.selectedColumns.length > 1) {
            const compositeKey = section.selectedColumns.join(',');
            const existingCount = this.csvHeaders.filter(h => h === compositeKey).length;
            const occurrence = existingCount + 1;
            const mappingId = this.compositeMappingIdCounter++;
            const newMapping = {
                id: mappingId,
                compositeKey: compositeKey,
                occurrence: occurrence,
            };
            this.createdCompositeMappings = [...this.createdCompositeMappings, newMapping];
            this.csvHeaders = [...this.csvHeaders, compositeKey];
            const uniqueKeyField = `${compositeKey}__COMPOSITE_${mappingId}`;
            this.compositeHeaderOptions = [
                ...this.compositeHeaderOptions,
                { label: compositeKey, value: uniqueKeyField, isSelected: false, isComposite: true }
            ];
            this.selectedDropdownValues = [...this.selectedDropdownValues, {
                csvFieldName: compositeKey,
                //selectedField: compositeKey,
                selectedField: '',
                fieldSearchTerm: '',
                showFieldRecommendations: false,
                filteredFieldOptions: [],
                isLookup: false,
                isCompositeLookup: false,
                keyField: uniqueKeyField,
                value: compositeKey, // Store the composite key value for splitting in allHeaderOptions
                lookupObjectName: '',
                lookupObjectApiName: '',
                whereClause: '',
                lookupObjectOptions: [],
                lookupObjectFields: [],
                lookupField1: '',
                selectedLookupFields: '',
                extraCsvField: '',
                isComposite: true,
                targetObject: '',
                targetObjectFields: [],
                compositeTargetObjectFields: [],
                matchField: '',
                returnField: ''
            }];
            // Mark this section as mapped and disable button only for this section
            section.isMapped = true;
            section.isButtonDisabled = true;
            this.compositeSections = [
                ...this.compositeSections.slice(0, sectionIdx),
                { ...section },
                ...this.compositeSections.slice(sectionIdx + 1)
            ];
        } else {
            this.showToast('Error', 'Please select at least two columns to create a composite mapping.', 'error');
        }
    }
    
async handleModifyMappingClick() {
    try {
        const savedHeaders = new Set(
            (this._existingMappingDetails || []).map(record =>
                (record.File_Column_Name__c || '')
                    .trim()
                    .toLowerCase()
            )
        );

        const newRows = (this.selectedDropdownValues || []).filter(row => {
            const csvHeader = (row.csvFieldName || '')
                .trim()
                .toLowerCase();

            return csvHeader && !savedHeaders.has(csvHeader);
        });

        if (!newRows.length) {
            this.showToast(
                'Information',
                'There are no new columns to append.',
                'info'
            );
            return;
        }

        const unmappedRow = newRows.find(
            row => !row.selectedField
        );

        if (unmappedRow) {
            this.showToast(
                'Error',
                `Select a Salesforce field for "${unmappedRow.csvFieldName}".`,
                'error'
            );
            return;
        }

        if (!this.existingMappingDisplayName) {
            this.showToast(
                'Error',
                'Selected mapping display name is empty.',
                'error'
            );
            return;
        }

        const configuration = {
            objectName: this.selectedObject,
            operationType: this.selectedOperation,
            fileName: this.fileName,
            mappingName: this.mappingName,
            mapping: newRows.map(row => {
                const lookupFields =
                    row.lookupField1 ??
                    row.selectedLookupFields ??
                    '';

                return {
                    csvFieldName: String(row.csvFieldName || ''),
                    selectedField: String(row.selectedField || ''),
                    isLookup: row.isLookup === true,
                    selectedLookupFields:
                        Array.isArray(lookupFields)
                            ? lookupFields.join(',')
                            : typeof lookupFields === 'object' &&
                              lookupFields !== null
                                ? JSON.stringify(lookupFields)
                                : String(lookupFields),
                    lookupObject: String(
                        row.lookupObjectApiName ||
                        row.lookupObjectName ||
                        ''
                    ),
                    whereClause: String(row.whereClause || ''),
                    isUniqueKey: row.isUniqueKey === true,
                    targetObject: String(row.targetObject || ''),
                    matchField: String(row.matchField || ''),
                    returnField: String(row.returnField || '')
                };
            })
        };

        const wrapperJson = JSON.stringify(configuration);

        console.log('Append mapping JSON:', wrapperJson);
        console.log(
            'Display name:',
            this.existingMappingDisplayName
        );

        await appendNewMappingColumns({
            wrapperJson: wrapperJson,
            configurationDisplayName:
                this.existingMappingDisplayName
        });

        this.isMappingModified = true;

        this.showToast(
            'Success',
            'New columns appended to the existing mapping.',
            'success'
        );
    } catch (error) {
        console.error(
            'Append mapping error:',
            JSON.stringify(error)
        );

        this.showToast(
            'Error',
            error?.body?.message ||
                error?.message ||
                'Unable to append new columns.',
            'error'
        );
    }
}

       handleDeleteColumnMapping(event) {
            const keyField = event.currentTarget.dataset.columnvalue;
           
            // Check if this is a composite mapping by looking for the __COMPOSITE_ pattern
            const isComposite = keyField && keyField.includes('__COMPOSITE_');
           
            if (isComposite) {
                // Extract the mapping ID from the keyField (format: compositeKey__COMPOSITE_id)
                const parts = keyField.split('__COMPOSITE_');
                const mappingId = parseInt(parts[1], 10);
               
                // Find the composite mapping
                const mapping = this.createdCompositeMappings.find(m => m.id === mappingId);
               
                if (mapping) {
                    const sectionId = mapping.sectionId;
                    const compositeKey = mapping.compositeKey;
                   
                    // Remove from selectedDropdownValues
                    this.selectedDropdownValues = this.selectedDropdownValues.filter(
                        row => row.keyField !== keyField
                    );
                   
                    // Remove from compositeHeaderOptions
                    this.compositeHeaderOptions = this.compositeHeaderOptions.filter(
                        opt => opt.value !== keyField
                    );
                   
                    // Remove from csvHeaders
                    this.csvHeaders = this.csvHeaders.filter(h => h !== compositeKey);
                   
                    // Remove from createdCompositeMappings
                    this.createdCompositeMappings = this.createdCompositeMappings.filter(
                        m => m.id !== mappingId
                    );
                   
                    // Reset the section state so it can be used again
                    const sectionIdx = this.compositeSections.findIndex(sec => sec.id === sectionId);
                    if (sectionIdx !== -1) {
                        let section = this.compositeSections[sectionIdx];
                        section.isMapped = false;
                        section.isButtonDisabled = false;
                        this.compositeSections = [
                            ...this.compositeSections.slice(0, sectionIdx),
                            { ...section },
                            ...this.compositeSections.slice(sectionIdx + 1)
                        ];
                    }
                   
                    this.showToast('Delete', 'Composite mapping removed.', 'success');
                }
            } else {
                // Handle regular (non-composite) column mapping deletion
                // Remove from selectedDropdownValues (main mapping array)
                this.selectedDropdownValues = this.selectedDropdownValues.filter(
                    mapping => mapping.keyField !== keyField
                );
               
                // Remove from csvHeaderOptions (for non-composite columns)
                this.csvHeaderOptions = this.csvHeaderOptions.filter(
                    col => col.value !== keyField
                );
               
                this.showToast('Deletesss', 'Column mapping removed.', 'success');
            }
        }
 
    handleDeleteCompositeMapping(event) {
        const mappingId = parseInt(event.currentTarget.dataset.id, 10);
        const mapping = this.createdCompositeMappings.find(m => m.id === mappingId);
       
        if (mapping) {
            const compositeKey = mapping.compositeKey;
            const uniqueKeyField = `${compositeKey}__COMPOSITE_${mappingId}`;
 
            const rowIndexToRemove = this.selectedDropdownValues.findIndex(
                row => row.keyField === uniqueKeyField
            );
            if (rowIndexToRemove !== -1) {
                this.csvHeaders.splice(rowIndexToRemove, 1);
            }
 
            this.selectedDropdownValues = this.selectedDropdownValues.filter(
                row => row.keyField !== uniqueKeyField
            );
 
            this.compositeHeaderOptions = this.compositeHeaderOptions.filter(opt => opt.value !== uniqueKeyField);
        }
       
        this.createdCompositeMappings = this.createdCompositeMappings.filter(
            mapping => mapping.id !== mappingId
        );
        this.compositeSections = this.compositeSections.filter(sec => sec.id !== mappingId);
        this.compositeSections = this.compositeSections.map((sec, idx) => ({ ...sec, id: idx }));
        console.log('Mapping deleted, remaining:', this.createdCompositeMappings);
        console.log('Updated csvHeaders:', this.csvHeaders);
    }
 
handleLookupCheckboxChange(event) {
    const key = event.target.dataset.keyfield;
    const isLookup = event.target.checked;

    const index = this.selectedDropdownValues.findIndex(
        item => item.keyField === key
    );

    if (index === -1) {
        return;
    }

    const currentItem = this.selectedDropdownValues[index];
    const selectedValue = currentItem.selectedField;

    const isCompositeLookup =
        isLookup && currentItem.isComposite === true;

    // -----------------------------------------
    // COMPOSITE LOOKUP
    // -----------------------------------------
    if (isCompositeLookup) {

        this.selectedDropdownValues[index] = {
            ...currentItem,
            isLookup: true,
            isCompositeLookup: true,

            // User will select this manually
            lookupObjectApiName: '',
            lookupObjectName: '',
            lookupObjectSearchTerm: '',
            showLookupObjectRecommendations: false,
            filteredLookupObjectOptions: [],
            lookupObjectOptions: [],
            lookupObjectFields: [],

            // Composite field selections
            selectedLookupFields: '',

            returnField: ''
        };

        this.selectedDropdownValues = [
            ...this.selectedDropdownValues
        ];

        // VERY IMPORTANT:
        // Do NOT execute normal lookup logic.
        return;
    }

    // -----------------------------------------
    // LOOKUP TURNED OFF
    // -----------------------------------------
    if (!isLookup) {

        this.selectedDropdownValues[index] = {
            ...currentItem,

            isLookup: false,
            isCompositeLookup: false,

            lookupObjectApiName: '',
            lookupObjectName: '',
            lookupObjectSearchTerm: '',
            showLookupObjectRecommendations: false,
            filteredLookupObjectOptions: [],

            lookupObjectOptions: [],
            lookupObjectFields: [],

            lookupField1: '',
            selectedLookupFields: '',
            whereClause: '',
            returnField: ''
        };

        this.selectedDropdownValues = [
            ...this.selectedDropdownValues
        ];

        return;
    }

    // -----------------------------------------
    // NORMAL LOOKUP
    // -----------------------------------------

    this.selectedDropdownValues[index] = {
        ...currentItem,
        isLookup: true,
        isCompositeLookup: false
    };

    this.selectedDropdownValues = [
        ...this.selectedDropdownValues
    ];

    if (!selectedValue) {
        return;
    }

    if (selectedValue === 'Id') {

        this.selectedDropdownValues[index] = {
            ...this.selectedDropdownValues[index],
            lookupObjectApiName: this.selectedObject,
            lookupObjectName: this.selectedObject,
            lookupObjectOptions: this.fieldOptions
        };

        this.selectedDropdownValues = [
            ...this.selectedDropdownValues
        ];

        return;
    }

    const lookupFieldObj =
        this.fieldsWithLookupList &&
        this.fieldsWithLookupList.find(
            field => field.apiName === selectedValue
        );

    if (!lookupFieldObj) {
        console.log(
            'Selected field is not a lookup field:',
            selectedValue
        );
        return;
    }

    getLookupFields({
        parentObjectName: this.selectedObject,
        lookupFieldName: selectedValue
    })
        .then(data => {

            return getFields({
                objectName: data.lookUpObjectName
            }).then(lookupObjFields => {

                const lookupObjFieldOptions =
                    lookupObjFields.map(field => ({
                        label: field.label,
                        value: field.apiName
                    }));

                this.selectedDropdownValues[index] = {
                    ...this.selectedDropdownValues[index],

                    lookupObjectApiName:
                        data.lookUpObjectName,

                    lookupObjectName:
                        this.convertApiNameToDisplayName(
                            data.lookUpObjectName
                        ),

                    lookupObjectOptions:
                        lookupObjFieldOptions
                };

                this.selectedDropdownValues = [
                    ...this.selectedDropdownValues
                ];
            });
        })
        .catch(error => {
            console.error(
                'Error fetching lookup object:',
                error
            );
        });
}

    get hasCompositeMappings() {
        return this.createdCompositeMappings && this.createdCompositeMappings.length > 0;
    }
 
    // Get all header options for rendering (original + composite columns)
    get allHeaderOptions() {
    const base = [
        ...this.csvHeaderOptions,
        ...this.compositeHeaderOptions
    ];

    return base.map(col => {

        const sd = this.selectedDropdownValues.find(
            s => s.keyField === col.value
        );

        let compositeDropdowns = [];

        const keyToSplit =
            sd && sd.value
                ? sd.value
                : col.value;

        if (col.isComposite && keyToSplit) {

            const parts = keyToSplit
                .split(',')
                .map(s => s.trim());

            let options = [];

            if (sd && sd.isCompositeLookup) {

                // Composite lookup
                options = [
                    ...(sd.lookupObjectFields || [])
                ];

            } else if (
                sd &&
                sd.compositeTargetObjectFields?.length
            ) {

                // Composite non-lookup
                options = [
                    ...sd.compositeTargetObjectFields
                ];

            } else if (
                sd &&
                sd.lookupObjectOptions?.length
            ) {

                options = [
                    ...sd.lookupObjectOptions
                ];
            }

            compositeDropdowns = parts.map(part => {

                let value = '';

                if (
                    sd &&
                    sd['lookupField_' + part] !== undefined
                ) {
                    value = sd['lookupField_' + part];
                }

                return {
                    label: part,
                    value: value,
                    options: options,
                    name: part,
                    compositeLabel:
                        'Field: ' +
                        part +
                        ' - Corresponding SF Field'
                };
            });
        }

        return {
            ...col,

            mappedField:
                sd ? (sd.fieldSearchTerm !== undefined ? sd.fieldSearchTerm : sd.selectedField) : '',

            showFieldRecommendations:
                sd ? !!sd.showFieldRecommendations : false,

            filteredFieldOptions:
                sd ? (sd.filteredFieldOptions || []) : [],
           
            lookupObjectSearchTerm:
                sd
                    ? (
                        sd.lookupObjectSearchTerm !== undefined
                            ? sd.lookupObjectSearchTerm
                            : sd.lookupObjectName || ''
                    )
                    : '',

            showLookupObjectRecommendations:
                sd
                    ? !!sd.showLookupObjectRecommendations
                    : false,

            filteredLookupObjectOptions:
                sd
                    ? (sd.filteredLookupObjectOptions || [])
                    : [],

            isLookupSelected:
                sd ? !!sd.isLookup : false,

            isCompositeLookup:
                sd ? !!sd.isCompositeLookup : false,

            lookupObjectName:
                sd ? sd.lookupObjectName : '',

            lookupObjectApiName:
                sd ? sd.lookupObjectApiName : '',

            lookupObjectOptions:
                sd ? (sd.lookupObjectOptions || []) : [],

            lookupObjectFields:
                sd ? (sd.lookupObjectFields || []) : [],

            lookupField1:
                sd ? sd.lookupField1 : '',

            whereClause:
                sd ? sd.whereClause : '',

            compositeDropdowns,

            targetObject:
                sd ? sd.targetObject : '',

            targetObjectFields:
                sd ? (sd.targetObjectFields || []) : [],

            compositeTargetObjectFields:
                sd
                    ? (sd.compositeTargetObjectFields || [])
                    : [],

            matchField:
                sd ? sd.matchField : '',

            returnField:
                sd ? sd.returnField : '',

            returnFieldOptions:
                sd && sd.isCompositeLookup
                    ? (sd.lookupObjectFields || [])
                    : (sd?.compositeTargetObjectFields || [])
        };
    });
}
 
    // Options for lookup object combobox (derived from lookup fields list)
    get lookupObjectOptions() {
        if (!this.fieldsWithLookupList) return [];
        return this.fieldsWithLookupList.map(f => ({ label: f.label, value: f.apiName }));
    }
 
    // Options for CSV header selection used in extra CSV comboboxes
    get csvHeaderComboboxOptions() {
        return this.csvHeaders.map(h => ({ label: h, value: h }));
    }
 
    // Separate getters for each section to avoid shared state
    get uniqueKeyColumnsForCheckbox() {
        return this.uniqueKeyHeaderOptions;
    }
    get compositeColumnsForCheckbox() {
        return this.csvHeaderOptions;
    }
 
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(event);
    }
 
    get compositeColumnsForCheckbox() {
        const compositeKeyValues = this.compositeHeaderOptions
            .filter(opt => opt.isComposite)
            .map(opt => opt.value);
       
        return this.csvHeaders.map(header => ({
            label: header,
            value: header,
            isChecked: false,
            isComposite: false
        })).filter(col => !compositeKeyValues.includes(col.value));
    }

}