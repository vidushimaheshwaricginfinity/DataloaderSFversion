import { LightningElement, track } from 'lwc';
import uploadToApex from '@salesforce/apex/CSVUploaderController.uploadToApex';
import updateDataFeedJobTrackerStatus from '@salesforce/apex/CSVUploaderController.updateDataFeedJobTrackerStatus';
import getObjects from '@salesforce/apex/CSVDataController.getObjects';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPresignedUrl from '@salesforce/apex/CSVUploaderController.getPresignedUrl';
import getExistingMappings from '@salesforce/apex/CSVConfigurationMapping.getExistingMappings';
import getApiHeaders from '@salesforce/apex/apiDataImportController.getApiHeaders';
import startApiImport from '@salesforce/apex/apiDataImportController.startApiImport';
import getMappingDetails from '@salesforce/apex/CSVConfigurationMapping.getMappingDetails';
import getApiConfigurations from '@salesforce/apex/apiDataImportController.getApiConfigurations';
import CG_Infinity_Logo from '@salesforce/resourceUrl/CGInfinityLogo';
import createDataFeedJobTracker from '@salesforce/apex/CSVUploaderController.createDataFeedJobTracker';
import deleteRecords from '@salesforce/apex/DeleteUndeleteController.deleteRecords';
import undeleteRecords from '@salesforce/apex/DeleteUndeleteController.undeleteRecords';
import LightningConfirm from 'lightning/confirm';

export default class csvUploader extends LightningElement {
    chunkSize = 200;
    @track showMappingChoiceModal = false;
    @track showExistingMappingModal = false;
    @track existingMappingOptions = [];
    @track selectedExistingMapping = '';
    @track csvFileContent = null;
    @track objectOptions = [];
    @track filteredObjectOptions = [];
    @track objectSearchTerm = '';
    objectInputHasFocus = false;
    @track operationOptions = [];
    @track selectedOperation = '';
    @track selectedObject = '';
    @track importSource = 'CSV';
    @track headersArray = [];
    @track selectedImportType = 'CSV';
    @track selectedApiConfigurationId = '';
    @track apiConfigurationOptions = [];
    importTypeOptions = [
        { label: 'CSV Upload', value: 'CSV' },
        { label: 'API Import', value: 'API' }
    ];
    @track showImportCard = true;
    @track showHeaderBlocks = false;
    @track showProgressBar=false;
    @track totalRecords=0;
    @track progressValue=0;
    @track processedRecords = 0;
    @track message;
    @track showObjectRecommendations = false;
    @track existingMappings = [];
    @track existingMappingDetails = [];
    @track existingMappingMode = false;
    @track showFileNameDropdown = false;
    @track showExistingPreview = false;
    @track isLoadingExistingMapping = false;
    @track isMappingLoaded = false ;
    @track existingPreviewRows = [];
    @track jobTrackerId = null;
    @track selectedIdColumn = 'Id';
    @track operationResult = null;
    @track operationResultMessages = [];
   
   columns = [
    {
        label: 'File Name',
        fieldName: 'fileName',
        type: 'text'
    },
    {
        label: 'Csv Column',
        fieldName: 'columnName',
        type: 'text'
    },
    {
        label: 'SF Field',
        fieldName: 'salesforceField',
        type: 'text'
    },
    {
        label: 'Lookup Object',
        fieldName: 'lookupObject',
        type: 'text'
    },
    {
        label: 'Selected Lookup Mapping',
        fieldName: 'lookupMapping',
        type: 'text'
    },
    {
        label: 'Return Field',
        fieldName: 'returnField',
        type: 'text'
    }
];
    @track selectedUniqueKey = '';
    CGInfinityLogo = CG_Infinity_Logo
    fileName = '';
    ObjectIsSelected=false;
    OperationIsSelected=false;
   
    get showUniqueKeyCombobox() {
        return this.selectedOperation === 'Update' && this.headersArray && this.headersArray.length > 0;
    }
 
    get uniqueKeyColumnOptions() {
        return (this.headersArray || []).map(h => ({ label: h, value: h }));
    }
 
    get isCsvImport() {
        return this.selectedImportType === 'CSV';
    }

    get isApiImport() {
        return this.selectedImportType === 'API';
    }
    
    get isDeleteUndeleteOperation(){
        return ['Delete','Undelete'].includes(this.selectedOperation);
    }

    get availableOperationOptions() {
        if (this.selectedImportType === 'API') {
            return this.operationOptions.filter(
                option => !['Delete', 'Undelete'].includes(option.value)
            );
        }

        return this.operationOptions;
    }

    // get idColumnOptions() {
    //     return (this.headersArray || []).map(header => ({
    //         label: header,
    //         value: header
    //     }));
    // }

    // get showIdColumnSelector() {
    //     return (
    //         this.isCsvImport &&
    //         this.isDeleteUndeleteOperation &&
    //         this.headersArray.length > 0
    //     );
    // }

    handleApiFileNameChange(event) {
        this.fileName = event.target.value;
    }

    handleUniqueKeyChange(event) {
        this.selectedUniqueKey = event.detail.value;
    }

    handleImportTypeChange(event) {
        this.selectedImportType = event.detail.value;
        // Delete and Undelete are supported only for CSV imports.
        if (
            this.selectedImportType === 'API' &&
            ['Delete', 'Undelete'].includes(this.selectedOperation)
        ) {
            this.selectedOperation = '';
            this.OperationIsSelected = false;
        }
        this.operationResult = null;
        this.operationResultMessages = [];

        console.log('Selected Import Type:', this.selectedImportType);

        if (this.selectedImportType === 'API') {
            this.csvFileContent = null;
            this.fileName = '';
            this.totalRecords = 0;
            this.headersArray = [];

            if (this.selectedApiConfigurationId) {
                this.loadApiHeaders();
            }
        } else {
            // Switching back to CSV
            this.headersArray = [];
            this.csvFileContent = null;
            this.fileName = '';
            this.totalRecords = 0;
        }
    }

    handleApiConfigurationChange(event) {
        this.selectedApiConfigurationId = event.detail.value;

        console.log(
            'Selected API Configuration:',
            this.selectedApiConfigurationId
        );

        // Clear previous API headers
        this.headersArray = [];

        // Fetch headers for the newly selected configuration
        if (this.selectedApiConfigurationId) {
            this.loadApiHeaders();
        }
    }

    loadApiConfigurations() {
        console.log('Loading API Configurations...');

        getApiConfigurations()
            .then(result => {
                console.log('API Configurations:', JSON.stringify(result));

                this.apiConfigurationOptions = result.map(config => ({
                    label: config.Name,
                    value: config.Id
                }));

                console.log(
                    'API Configuration Options:',
                    JSON.stringify(this.apiConfigurationOptions)
                );
            })
            .catch(error => {
                console.error(
                    'Error loading API configurations:',
                    error
                );

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message:
                            error?.body?.message ||
                            'Unable to load API configurations.',
                        variant: 'error'
                    })
                );
            });
    }

    async loadApiHeaders() {
        try {
            console.log(
                'Fetching API headers for configuration:',
                this.selectedApiConfigurationId
            );

            const headers = await getApiHeaders({
                apiConfigurationId: this.selectedApiConfigurationId
            });

            console.log('API Headers:', JSON.stringify(headers));

            this.headersArray = headers;

        } catch (error) {
            console.error('Error fetching API headers:', error);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error?.body?.message || 'Unable to fetch API headers.',
                    variant: 'error'
                })
            );
        }
    }
   
     get currentStep() {
         if (this.showImportCard) {
             return '1';
        } else if (this.showHeaderBlocks) {
            return '2';
        } else if (this.showProgressBar) {
            return '3';
        }
        return '1';
    }
   
 
    connectedCallback() {
        this.operationOptions = [
            { label: 'Insert', value: 'Insert' },
            { label: 'Update', value: 'Update' },
            { label: 'Upsert', value: 'Upsert' },
            { label: 'Delete', value: 'Delete'},
            { label: 'Undelete', value: 'Undelete'}
        ];
        getObjects()
            .then(data => {
                console.log('Objects loaded:', data);
                this.objectOptions = data.map(obj => ({ label: obj.label, value: obj.apiName }));
                this.filteredObjectOptions = this.objectOptions;
                console.log('objectOptions after map:', this.objectOptions);
            })
            .catch(error => {
                console.error('Error fetching objects:', error);
            });
        this.loadApiConfigurations();
    }
 
    handleObjectSearch(event) {
        const inputValue = event.target.value || '';
        const searchTerm = inputValue.toLowerCase().trim();
       
        this.objectSearchTerm = inputValue;
        console.log('Search term:', searchTerm, 'objectOptions length:', this.objectOptions.length);
       
        if (!searchTerm) {
            this.filteredObjectOptions = [];
            this.showObjectRecommendations = false;
            console.log('Empty search - hiding dropdown');
        } else {
            // Filter objects that contain the search term (case-insensitive)
            const filtered = this.objectOptions.filter(opt =>
                opt.label.toLowerCase().includes(searchTerm)
            );
            console.log('Filtered count:', filtered.length);
            this.filteredObjectOptions = [...filtered];
            // Always show recommendations dropdown when typing
            this.showObjectRecommendations = true;
            console.log('showObjectRecommendations SET TO TRUE');
        }
    }
 
    handleObjectRecommendationClick(event) {
        const value = event.currentTarget.dataset.value;
        const label = event.currentTarget.dataset.label;
        this.selectedObject = value;
        this.ObjectIsSelected = true;
        this.objectSearchTerm = label;
        this.showObjectRecommendations = false;
    }
 
    // handleFileUpload(event) {
    //     const file = event.target.files[0];
    //     console.log('File uploaded:', file);
    //     let name = file.name;
    //     let ext = '';
    //     if (name.includes('.')) {
    //         ext = name.substring(name.lastIndexOf('.'));
    //         name = name.substring(0, name.lastIndexOf('.'));
    //     }
    //     name = name.replace(/_/g, '');
    //     this.fileName = name + ext;
    //     if (file) {
    //         const reader = new FileReader();
    //         reader.onload = async () => {
    //             this.csvFileContent = reader.result;
    //             const lines = this.csvFileContent.split('/\r?\n/').filter(line => line.trim() !== ''); // Filter out blank rows
    //             if (lines.length === 0){
    //                 this.headersArray = [];
    //                 this.selectedIdColumn = null;
    //                 this.totalRecords = 0;
    //                 return;
    //             }
    //              const headers = lines[0]
    //                 .split(',')
    //                 .map(header => header.trim().replace(/^"|"$/g, '').trim());

    //             this.headersArray = headers;
    //             const idHeader = headers.find(
    //                 header => header.trim().replace(/^"|"$/g, '').toLowerCase() === 'id'
    //             );
    //             this.selectedIdColumn = idHeader || null;
    //             this.totalRecords = Math.max(0, lines.length - 1);

    //             if (
    //                 ['Delete', 'Undelete'].includes(this.selectedOperation) &&
    //                 !this.selectedIdColumn
    //             ) {
    //                 this.message =
    //                     'The uploaded CSV does not contain an Id column. Please upload a CSV with an Id header.';
    //             }

    //             console.log('CSV headers:', this.headersArray);
    //             console.log('Detected ID column:', this.selectedIdColumn);
    //         };
    //         reader.readAsText(file);
    //     }
    // }
   
    
    handleFileUpload(event) {
        const file = event.target.files?.[0];

        if (!file) {
            return;
        }

        let name = file.name;
        let ext = '';

        if (name.includes('.')) {
            ext = name.substring(name.lastIndexOf('.'));
            name = name.substring(0, name.lastIndexOf('.'));
        }

        name = name.replace(/_/g, '');
        this.fileName = name + ext;

        const reader = new FileReader();

        reader.onload = () => {
            this.csvFileContent = reader.result;

            // Split using actual newline characters (CRLF or LF).
            const lines = this.csvFileContent
                .split(/\r?\n/)
                .filter(line => line.trim() !== '');

            if (lines.length === 0) {
                this.headersArray = [];
                this.selectedIdColumn = null;
                this.totalRecords = 0;

                this.showToast(
                    'Invalid CSV',
                    'The uploaded CSV file is empty.',
                    'error'
                );
                return;
            }

            // Read headers and remove surrounding quotes.
            const headers = lines[0]
                .split(',')
                .map(header =>
                    header.trim().replace(/^"|"$/g, '').trim()
                );

            this.headersArray = headers;

            // Automatically detect Id, ID, id, etc.
            const idHeader = headers.find(
                header => header.toLowerCase() === 'id'
            );

            this.selectedIdColumn = idHeader || null;
            this.totalRecords = Math.max(0, lines.length - 1);

            console.log('CSV headers:', JSON.stringify(headers));
            console.log('Detected Salesforce ID header:', idHeader);

            // Inform the user only for Delete/Undelete operations.
            if (
                ['Delete', 'Undelete'].includes(this.selectedOperation) &&
                !idHeader
            ) {
                this.showToast(
                    'Missing Id Column',
                    'Your CSV must contain a column named Id. The header is matched without regard to capitalization.',
                    'error'
                );
            }
        };

        reader.onerror = () => {
            this.showToast(
                'File Read Error',
                'Unable to read the uploaded CSV file.',
                'error'
            );
        };

        reader.readAsText(file);
    }

    handleObjectChange(event) {
        this.ObjectIsSelected=true;
        this.selectedObject = event.detail.value;
    }
        handleResetAll() {
        const mapper = this.template.querySelector('c-csv-field-mapper');
        if (mapper) {
            mapper.resetToHeaders(this.headersArray);
        }
    }
 
    handleOperationChange(event) {
        this.OperationIsSelected=true;
        this.selectedOperation = event.detail.value;

        this.operationResult = null;
        this.operationResultMessages = [];

            if(this.selectedOperation === 'Delete'){
                this.message = 'The CSV has been read. Records matching the supplied Salesforce IDs will be deleted.';
            }
            else if(this.selectedOperation === 'Undelete'){
                this.message =  'The CSV has been read. Deleted records matching the supplied Salesforce IDs will be restored.';
            }
            else if(this.selectedOperation === 'Insert')
            {
                this.message='The CSV Data has been read successfully, you will receive an Email notification once the Data is inserted.';
            }
            else
            {
                this.message='The CSV Data has been read successfully, you will receive an Email notification once the Data is updated.';
 
            }
    }
    
    get showNextButton() {
        if (this.selectedImportType === 'API') {
            return (
                this.ObjectIsSelected &&
                this.OperationIsSelected &&
                this.selectedApiConfigurationId &&
                this.fileName &&
                this.fileName.trim().length > 0 &&
                this.headersArray &&
                this.headersArray.length > 0
            );
        }

        return (
            this.ObjectIsSelected &&
            this.OperationIsSelected &&
            this.fileName &&
            this.fileName.length > 0
        );
    } 

    // handleNextClick() {
    //     this.showImportCard = false;
    //     this.showHeaderBlocks = false;
    //     this.showMappingChoiceModal = true;
    //     // FIX: belt-and-braces — also reset here in case the user reached step 1
    //     // via goToUploadPage() rather than previousPage().
    //     this.showFileNameDropdown = false;
    //     this.isMappingLoaded = false;
    //     this.selectedExistingMapping = ''; 
    //     this.existingPreviewRows = [];
    //     this.existingMappingDetails = [];
    // }

    // handleIdColumnChange(event) {
    //     this.selectedIdColumn = event.detail.value;
    // };

    async handleNextClick() {
        this.showFileNameDropdown = false;
        this.isMappingLoaded = false;
        this.selectedExistingMapping = '';
        this.existingMappingMode = false;
        this.existingPreviewRows = [];
        this.existingMappingDetails = [];

        if (this.isDeleteUndeleteOperation) {
            if (!this.isCsvImport) {
                this.showToast(
                    'Error',
                    'Delete and Undelete currently support CSV uploads only.',
                    'error'
                );
                return;
            }

            if (!this.csvFileContent) {
                this.showToast(
                    'Error',
                    'Please upload a CSV file first.',
                    'error'
                );
                return;
            }

            if (!this.selectedObject) {
                this.showToast(
                    'Error',
                    'Please select a Salesforce object.',
                    'error'
                );
                return;
            }

            const hasIdHeader = this.headersArray.some(
                header =>
                    header.trim().replace(/^"|"$/g, '').toLowerCase() === 'id'
            );

            if (!hasIdHeader) {
                this.showToast(
                    'Missing Id Column',
                    'Your CSV must contain a column named Id.',
                    'error'
                );
                return;
            }

            // Skip both mapping screens.
            this.showImportCard = false;
            this.showHeaderBlocks = false;
            this.showMappingChoiceModal = false;
            this.showProgressBar = true;

            await this.processDeleteUndelete();
            return;
        }

        // Existing Insert, Update, and Upsert navigation.
        this.showImportCard = false;
        this.showHeaderBlocks = false;
        this.showMappingChoiceModal = true;
    }

    async processDeleteUndelete() {
        this.operationResult = null;
        this.operationResultMessages = [];
        this.processedRecords = 0;
        this.progressValue = 0;

        try {
            if (this.selectedOperation === 'Delete') {
                const confirmed = await LightningConfirm.open({
                    label: 'Confirm Delete',
                    message:
                        'Are you sure you want to delete the records identified by this CSV? This action may be difficult to reverse.',
                    theme: 'warning'
                });

                if (!confirmed) {
                    this.showProgressBar = false;
                    this.showImportCard = true;
                    return;
                }
            }

            const jsonData = this.parseCSV(this.csvFileContent);

            if (!jsonData.length) {
                throw new Error('No valid CSV data rows were found.');
            }

            // Find the ID header, ignoring capitalization, BOM, and whitespace.
            const idHeader = Object.keys(jsonData[0] || {}).find(
                header =>
                    header
                        .replace(/^\uFEFF/, '')
                        .replace(/^"|"$/g, '')
                        .trim()
                        .toLowerCase() === 'id'
            );

            if (!idHeader) {
                console.error(
                    'CSV headers received:',
                    JSON.stringify(Object.keys(jsonData[0] || {}))
                );

                throw new Error(
                    'No Id column was found. Please verify the first row of your CSV.'
                );
            }

            this.selectedIdColumn = idHeader;

            // Extract non-empty Salesforce record IDs.
            const recordIds = jsonData
                .map(row => String(row[idHeader] ?? '').trim())
                .filter(id => id.length > 0);

            if (!recordIds.length) {
                throw new Error(
                    `The "${idHeader}" column does not contain any record IDs.`
                );
            }

            this.totalRecords = recordIds.length;
            this.message = `${this.selectedOperation} operation is in progress...`;

            let result;

            if (this.selectedOperation === 'Delete') {
                result = await deleteRecords({
                    objectApiName: this.selectedObject,
                    recordIds: recordIds
                });
            } else {
                result = await undeleteRecords({
                    objectApiName: this.selectedObject,
                    recordIds: recordIds
                });
            }

            this.operationResult = result;
            this.operationResultMessages = (result.messages || []).map(
                (message, index) => ({
                    id: `result-${index}`,
                    message: message
                })
            );

            this.processedRecords = result.totalRecords;
            this.progressValue = 100;

            this.message =
                `${this.selectedOperation} finished. ` +
                `Successful: ${result.successCount}, ` +
                `Failed: ${result.failureCount}.`;

            this.dispatchEvent(
                new ShowToastEvent({
                    title:
                        result.failureCount > 0
                            ? 'Operation completed with errors'
                            : 'Operation completed',
                    message: this.message,
                    variant:
                        result.failureCount > 0 ? 'warning' : 'success'
                })
            );
        } catch (error) {
            this.message =
                error?.body?.message ||
                error?.message ||
                'The operation failed.';

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Operation failed',
                    message: this.message,
                    variant: 'error'
                })
            );
        }
    }

    handleCloseMappingOptions() {
    console.log('Closing Mapping Options modal');

    this.showMappingChoiceModal = false;

    // Go back to the initial Upload & Configure screen
    this.showImportCard = true;
    this.showHeaderBlocks = false;
    this.showProgressBar = false;

    // Clear existing mapping state
    this.showFileNameDropdown = false;
    this.isMappingLoaded = false;
    this.selectedExistingMapping = '';
    this.existingPreviewRows = [];
    this.existingMappingDetails = [];
    }
 
    handleUniqueKeyTypeSelect(event) {
        this.uniqueKeyType = event.target.value;
    }
 
    handleUniqueKeyTypeNext() {
        if (!this.uniqueKeyType) {
            return;
        }
        this.showUniqueKeyTypeModal = false;
        this.showImportCard = false;
        this.showHeaderBlocks = false;
        this.showMappingChoiceModal = true;
    }
 
    handleCreateNewMapping() {
        this.showMappingChoiceModal = false;
        this.showHeaderBlocks = true;
        this.showProgressBar = false;
    }
 
    handleUseExistingMapping() {
        /*this.showMappingChoiceModal = false;
        this.showHeaderBlocks = false;
        this.showProgressBar = true;
        this.processCSV();*/
        this.showMappingChoiceModal = false;
        this.showFileNameDropdown=true;
        console.log('Inside handleUseExistingMapping ');
        // FIX: always start this step with a clean slate. Without this reset,
        // re-entering this step (e.g. after Back -> Next, or after Cancel) leaves
        // selectedExistingMapping/isMappingLoaded/existingPreviewRows populated
        // from the previous attempt. Because lightning-combobox only fires
        // `onchange` when the value actually changes, re-picking the SAME mapping
        // silently does nothing and the preview never (re)appears — the user has
        // to pick a different mapping first to force a change event.
        this.selectedExistingMapping = '';
        this.isMappingLoaded = false;
        this.existingPreviewRows = [];
        this.existingMappingDetails = [];
        this.loadExistingMappings();
    }
    
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    loadExistingMappings() {
        console.log('Inside Load Existing Mapping');
        console.log(
        'Selected Object:',
        this.selectedObject
        );

        console.log(
        'Selected Operation:',
        this.selectedOperation
        );
        getExistingMappings({
        objectName: this.selectedObject,
        operationType: this.selectedOperation})
            .then(result => {

                this.existingMappings = result.map(fileName => ({
                    label: fileName,
                    value: fileName
                }));

    console.log('Existing Mapping -->',this.existingMappings);
                console.log(
                    'Existing mappings:',
                    JSON.stringify(this.existingMappings)
                );
            })
            .catch(error => {

                console.error(
                    'Error loading existing mappings:',
                    error
                );

                this.showToast(
                    'Error',
                    'Unable to load existing mappings',
                    'error'
                );
            });
    }

    handleExistingMappingChange(event){
    console.log('Inside handleExistingMappingChange -->');

        this.selectedExistingMapping = event.detail.value;

        this.isMappingLoaded=true;

        this.existingMappingMode = true;

        console.log(
            'Selected File:',
            this.selectedExistingMapping
        );

        getMappingDetails({
            configurationDisplayName: this.selectedExistingMapping
        })
        .then(result => {
            console.log(
                'Mapping Details:',
                JSON.stringify(result)
            );
        this.existingMappingDetails = result || [];
         //   this.existingPreviewRows =result;
            console.log(this.existingPreviewRows);
             this.existingPreviewRows = (result || []).map(
                (row, index) => {
                    return {
                        id: row.Id || `existing-${index}`,
                        fileName: row.Mapping_Name__c || '',
                        columnName: row.File_Column_Name__c || '',
                        salesforceField: row.Field_to_update__c || '',
                        isLookup: row.Is_LookUp__c || false,
                        lookupObject: row.Lookup_Object_Name__c || '',
                        lookupMapping: row.Lookup_Field__c || '',
                        returnField: row.Lookup_Return_Field__c || '',
                        isUniqueKey: row.Is_Unique_Key__c || false
                    };
                }
            );
        })
        .catch(error => {
            console.error(
                'Error loading mapping details:',
                error
            );

            this.showToast(
                'Error',
                'Unable to load mapping details',
                'error'
            );
        });

    }
    handleExistingMappingOk() {

    console.log('Existing Mapping - OK clicked');

    // Hide existing mapping preview
    this.isMappingLoaded = false;
    this.showFileNameDropdown = false;

    // Show existing Create Mapping page
    this.showHeaderBlocks = true;

    console.log(
        'Existing Mapping Details:',
        JSON.stringify(this.existingMappingDetails)
    );
    }
    handleExistingMappingCancel() {

    console.log('Existing Mapping - Cancel clicked');

    this.isMappingLoaded = false;

    this.existingPreviewRows = [];
    this.existingMappingDetails = [];

    this.selectedExistingMapping = '';
    this.existingMappingMode = false;

    // Keep the existing mapping dropdown visible
    this.showFileNameDropdown = true;

    console.log('Existing Mapping Preview cancelled');
    }

    // parseCSV(csv) {
    //     // const lines = csv.split('\n');
    //     // const headers = lines[0].split(',');
    //     const lines = csv.split(/\r?\n/).filter(line => line.trim() !== '');

    //     const headers = lines[0]
    //         .split(',')
    //         .map(header => header.trim().replace(/^"|"$/g, ''));
    //     this.headersArray = headers;
    //     const jsonData = [];
 
    //     for (let i = 1; i < lines.length; i++) {
    //         const values = lines[i].split(',');
    //         if (values.length === headers.length) {
    //             const jsonLine = {};
    //             headers.forEach((header, index) => {
    //                 // jsonLine[header.trim()] = values[index].trim();
    //                 jsonLine[header] = values[index].trim().replace(/^"|"$/g, '');
    //             });
    //             jsonData.push(jsonLine);
    //         }
    //     }
    //     return jsonData;
    // }

    parseCSV(csv) {
        const lines = csv
            .replace(/^\uFEFF/, '')
            .split(/\r?\n/)
            .filter(line => line.trim() !== '');

        if (lines.length === 0) {
            this.headersArray = [];
            return [];
        }

        const headers = lines[0]
            .replace(/^\uFEFF/, '')
            .split(',')
            .map(header =>
                header.replace(/^\uFEFF/, '').trim().replace(/^"|"$/g, '').trim()
            );

        this.headersArray = headers;

        // Automatically detect the Salesforce ID header.
        const idHeader = headers.find(
            header => header.trim().toLowerCase() === 'id'
        );

        this.selectedIdColumn = idHeader || null;

        console.log('Parsed headers:', JSON.stringify(headers));
        console.log('Detected ID header:', this.selectedIdColumn);

        const jsonData = [];

        for (let i = 1; i < lines.length; i++) {
            const values = lines[i].split(',');

            if (values.length === headers.length) {
                const jsonLine = {};

                headers.forEach((header, index) => {
                    jsonLine[header] = values[index]
                        .trim()
                        .replace(/^"|"$/g, '')
                        .trim();
                });

                jsonData.push(jsonLine);
            }
        }

        return jsonData;
    }
 
    async handleProcessNext() {
        if (this.selectedImportType === 'API') {
            await this.processAPI();
        } else {
            await this.processCSV();
        }
    }

    async processCSV() {
        this.showProgressBar = true;
        this.showHeaderBlocks = false;
        this.processedRecords = 0;
        this.progressValue = 0;
        this.jobTrackerId = null;
        if(!this.csvFileContent){
            this.showToast(
                'Error',
                'Please upload a CSV file before continuing',
                'error'
            )
            this.showProgressBar = false;
            return;
        }
        try{
            console.log('STEP 1: Parsing CSV');
            const jsonData = this.parseCSV(this.csvFileContent);
            if(!jsonData || jsonData.length == 0){
                throw new Error('No valid CSV data rows were found.');
            }
            this.totalRecords = jsonData.length;
            console.log('STEP 2: Creating tracker');
              // Create a new tracker for this upload.
            this.jobTrackerId = await createDataFeedJobTracker({
                fileName: this.fileName,
                operationType: this.selectedOperation,
                targetObject: this.selectedObject,
                selectedMappingName: this.selectedExistingMapping || null
            });

            console.log('STEP 3: Tracker created :',this.jobTrackerId);
            // Upload all chunks, using the same tracker ID.
            await this.sendDataInChunks(
                jsonData,
                this.fileName
            );

            // All chunks have been attempted, so start processing
            // the successfully staged records, even if some rows failed.
            await this.invokeBatchClass();

            console.log('STEP 5: Tracker status updated')

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'CSV import started successfully.',
                    variant: 'success'
                })
            );
            console.log('Everything done');
        }catch(error){
           console.error(
                'Error starting CSV import:',
                error
            );

            this.showProgressBar = false;
            this.showHeaderBlocks = true;

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message:
                        error?.body?.message ||
                        'Failed to start CSV import.',
                    variant: 'error'
                })
            );
        }
        // if (this.csvFileContent) {
        //     let name = this.fileName;
        //     // let ext = '';
        //     // if (name.includes('.')) {
        //     //     ext = name.substring(name.lastIndexOf('.'));
        //     //     name = name.substring(0, name.lastIndexOf('.'));
        //     // }
        //     // name = name.replace(/_/g, '');
        //     // this.fileName = name + ext;
        //     // console.log('File name:', this.fileName);
        //     // console.log('Attempting to upload file to S3:', this.fileName);
        //     // let uploadSuccess = false;
        //     // try {
        //     //     console.log('Selected Operation:', this.selectedOperation);
        //     //     console.log('Selected Object:', this.selectedObject);
        //     //     this.fileName = this.fileName + '_' + this.selectedOperation + '_' + this.selectedObject;
        //     //     console.log('Updated Name', this.fileName);
        //     //     const presignedUrl = await getPresignedUrl({ fileName: this.fileName });
        //     //     console.log('Presigned URL:', presignedUrl);
        //     //     const uploadResponse = await fetch(presignedUrl, {
        //     //         method: 'PUT',
        //     //         headers: { 'Content-Type': 'text/csv' },
        //     //         body: new Blob([this.csvFileContent], { type: 'text/csv' })
        //     //     });
        //     //     if (uploadResponse.ok) {
        //     //         console.log('File sent to S3 successfully:', this.fileName);
        //     //         uploadSuccess = true;
        //     //     } else {
        //     //         console.error('Error uploading file to S3:', uploadResponse.statusText);
        //     //     }
        //     // } catch (error) {
        //     //     console.error('Error uploading file to S3:', error);
        //     // }
        //     // if (!uploadSuccess) {
        //     //     this.showProgressBar = false;
        //     //     return;
        //     // }
        //       const jsonData = this.parseCSV(this.csvFileContent); // Parse CSV to JSON
        //     if (!jsonData) {
        //         // Error already shown, stop processing
        //         console.log('CSV parsing failed. Stopping process.');
        //         this.showProgressBar = false;
        //         return;
        //     }
        //     try {
        //         await this.sendDataInChunks(jsonData, this.fileName); // Wait for all chunks to be sent
        //         // Invoke the ProcessDataFeed batch class
        //         await this.invokeBatchClass();
        //     } catch (error) {
        //         console.error('Error during processing:', error);
        //     }
        // } else {
        //     console.error('No file uploaded. Please upload a CSV file before clicking Next.');
        // }
   
    }

    async processAPI() {
        try {
            this.showProgressBar = true;
            this.showHeaderBlocks = false;

            console.log('===== STARTING API IMPORT =====');
            console.log('File Name:', this.fileName);
            console.log('Operation:', this.selectedOperation);
            console.log('Target Object:', this.selectedObject);
            console.log(
                'API Configuration:',
                this.selectedApiConfigurationId
            );

            const batchJobId = await startApiImport({
                fileName: this.fileName,
                operationType: this.selectedOperation,
                targetObject: this.selectedObject,
                apiConfigurationId: this.selectedApiConfigurationId,
                selectedMappingName:this.selectedExistingMapping || null
            });

            console.log('API Batch Job ID:', batchJobId);

            this.message =
                'API import started successfully.';

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'API import started successfully.',
                    variant: 'success'
                })
            );

        } catch (error) {
            console.error(
                'Error starting API import:',
                error
            );

            this.showProgressBar = false;
            this.showHeaderBlocks = true;

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message:
                        error?.body?.message ||
                        'Failed to start API import.',
                    variant: 'error'
                })
            );
        }
    }

    previousPage() {
        this.showHeaderBlocks = false;
        this.showImportCard = true;
        this.showProgressBar = false;
        // FIX: clear existing-mapping state when backing out of the mapper step,
        // so a subsequent "Next" -> "Use Existing Mapping" starts fresh instead of
        // re-showing the last pick with a desynced preview/isMappingLoaded flag.
        this.showFileNameDropdown = false;
        this.isMappingLoaded = false;
        this.selectedExistingMapping = '';
        this.existingPreviewRows = [];
        this.existingMappingDetails = [];
    }
 
    goToUploadPage() {
        this.showProgressBar = false;
        this.showImportCard = true;
        this.showHeaderBlocks = false;
        this.progressValue = 0;
        this.processedRecords = 0;
        this.fileName = '';
        this.csvFileContent = null;
        this.headersArray = [];
        this.selectedObject = '';
        this.selectedOperation = '';
        this.ObjectIsSelected = false;
        this.OperationIsSelected = false;
        this.selectedUniqueKey = '';
        this.objectSearchTerm = '';
        // FIX: belt-and-braces — also reset here in case the user reached step 1
        // via goToUploadPage() rather than previousPage().
        this.showFileNameDropdown = false;
        this.isMappingLoaded = false;
        this.selectedExistingMapping = '';
        this.existingPreviewRows = [];
        this.existingMappingDetails = [];
        this.selectedIdColumn = 'Id';
        this.operationResult = null;
        this.operationResultMessages = [];
    }
 
    // async sendDataInChunks(jsonData, fileName) {
    //     for (let i = 0; i < jsonData.length; i += this.chunkSize) {
    //         const chunk = jsonData.slice(i, i + this.chunkSize);
           
    //         const jsonStringList = chunk.map(record => JSON.stringify(record));
    //         console.log('json:',jsonStringList);
    //         try {
    //             // Send the chunk to Apex
    //             await uploadToApex({ jsonDataList: jsonStringList, fileName: fileName });
    //             this.processedRecords += chunk.length; // Update processed records
    //             this.progressValue = Math.floor((this.processedRecords / this.totalRecords) * 100); // Update progress bar
    //         } catch (error) {
    //             console.error('Error sending data to Apex:', error);
    //         }
    //     }
    //     this.dispatchEvent(
    //         new ShowToastEvent({
    //             title: 'Success',
    //             message:this.message,
    //             variant: 'success',
    //         })
    //     );
    //     console.log('All data sent successfully!');
    // }

    
    async sendDataInChunks(jsonData, fileName) {
        if (!this.jobTrackerId) {
            throw new Error('Job tracker has not been created.');
        }

        let successCount = 0;
        let failedCount = 0;
        const failedRows = [];

        for (let i = 0; i < jsonData.length; i += this.chunkSize) {
            const chunk = jsonData.slice(i, i + this.chunkSize);

            const jsonStringList = chunk.map(
                record => JSON.stringify(record)
            );

            try {
                const result = await uploadToApex({
                    jsonDataList: jsonStringList,
                    fileName: fileName,
                    jobTrackerId: this.jobTrackerId
                });

                successCount += result.successCount;
                failedCount += result.failedCount;

                if (result.failedRows?.length) {
                    failedRows.push(...result.failedRows);
                }
            } catch (error) {
                // Record the chunk-level failure and continue.
                failedCount += chunk.length;

                failedRows.push(
                    `Rows ${i + 1}-${i + chunk.length}: ` +
                    this.getErrorMessage(error)
                );
            }

            // Count every attempted row, whether successful or failed.
            this.processedRecords = successCount + failedCount;

            this.progressValue = Math.floor(
                (this.processedRecords / jsonData.length) * 100
            );
        }

        console.log('Final successCount:',successCount);
        console.log('Final failedCount:',failedCount);
        console.log('Final failedRows:',failedRows);

        if (failedRows.length > 0) {
            console.error(
                'Failed staging rows:',
                JSON.stringify(failedRows)
            );
        }

        return {
            successCount : successCount,
            failedCount : failedCount,
            failedRows: failedRows
        };
    }

 
    // async invokeBatchClass() {
    //     try {
           
    //         // Call an Apex method to invoke the batch class
    //         //await invokeProcessDataFeedBatch({fileName: this.fileName, operationType: this.selectedOperation, targetObject: this.selectedObject}); // Replace with the actual Apex method to invoke the batch
    //         await updateDataFeedJobTrackerStatus({status:'Upload Complete', fileName:this.fileName, operationType:this.selectedOperation,targetObject:this.selectedObject});
    //     } catch (error) {
    //         console.error('Error invoking batch class:', error);
    //         throw error;
    //     }
    // }

    
    async invokeBatchClass() {
        try {
            if (!this.jobTrackerId) {
                throw new Error('Job tracker ID is missing.');
            }

            // Update this specific tracker.
            // The Salesforce trigger starts ProcessDataFeed.
            await updateDataFeedJobTrackerStatus({
                jobTrackerId: this.jobTrackerId,
                status: 'Upload Complete'
            });

        } catch (error) {
            console.error(
                'Error updating Data Feed Job Tracker status:',
                error
            );
            throw error;
        }
    }


    buildExistingPreviewRows() {
    const records = this._existingMappingDetails || [];

    this.existingPreviewRows = records.map((row, index) => {
        return {
            id: row.Id || `existing-${index}`,

            fileName: row.Mapping_Name__c || '',

            columnName: row.File_Column_Name__c || '',

            salesforceField: row.Field_to_update__c || '',

            lookupObject: row.Lookup_Object_Name__c || '',

            lookupMapping: row.Lookup_Field__c || '',

            returnField: row.Lookup_Return_Field__c || ''
        };
    });

    console.log(
        'Existing Mapping Preview:',
        JSON.stringify(this.existingPreviewRows)
    );
}
 
 
}