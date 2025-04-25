import { LightningElement, api, track, wire } from 'lwc';
import getObjectConfigs from '@salesforce/apex/BroadcastMessageController.getObjectConfigs';
import getListViewsForObject from '@salesforce/apex/BroadcastMessageController.getListViewsForObject';
import getRecordsByListView from '@salesforce/apex/BroadcastMessageController.getRecordsByListView';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import processBroadcastMessageWithObject from '@salesforce/apex/BroadcastMessageController.processBroadcastMessageWithObject';
import getBroadcastGroupDetails from '@salesforce/apex/BroadcastMessageController.getBroadcastGroupDetails';
import createLeadsFromCsv from '@salesforce/apex/BroadcastMessageController.createLeadsFromCsv';
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import INQUIRY_OBJECT from '@salesforce/schema/Inquiry_hz__c';
import PROPERTY_TYPE_FIELD from '@salesforce/schema/Inquiry_hz__c.PropertyType__c';
import INQUIRY_TYPE_FIELD from '@salesforce/schema/Inquiry_hz__c.Inquiry_Type__c';

export default class BroadcastMessageComp extends LightningElement {
    @track objectOptions = [];
    @track listViewOptions = [];
    @track selectedObject = '';
    @track selectedListView = '';
    @track data = [];
    @track filteredData = [];
    @track paginatedData = [];
    @track currentPage = 1;
    @track pageSize = 10;
    @track visiblePages = 5;
    @track isLoading = false;
    @track configMap = {};
    @track searchTerm = '';
    @track selectedRecords = new Set();
    @track isCreateBroadcastModalOpen = false;
    @track messageText = '';
    @track broadcastGroupName = '';
    @track isCreateBroadcastComp = true;
    @track isAllBroadcastGroupPage = false;
    @track isIntialRender = true;
    @track groupMembers = [];
    @track isFilterModalOpen = false;
    @track filterCriteria = {
        community: '',
        area: '',
        building: '',
        priceRange: '',
        propertyTypes: []
    };
    @track tempFilterCriteria = { ...this.filterCriteria }; // Temporary criteria for modal
    @track appliedFilterCount = 0;
    @track propertyTypeOptions = [];
    @track inquiryTypeOptions = [];
    @track priceRangeOptions = [
        { label: '0 - 100,000', value: '0-100000' },
        { label: '100,000 - 200,000', value: '100000-200000' },
        { label: '200,000 - 500,000', value: '200000-500000' },
        { label: '500,000 - 1,000,000', value: '500000-1000000' },
        { label: '1,000,000+', value: '1000000+' }
    ];
    @track appliedFilterCount = 0;

    @api broadcastGroupId;

    broadcastHeading = 'New Broadcast Group';
    createBtnLabel = 'Create Broadcast Group';   

    @wire(getObjectInfo, { objectApiName: INQUIRY_OBJECT })
    inquiryObjectInfo;

    @wire(getPicklistValuesByRecordType, { 
        recordTypeId: '$inquiryObjectInfo.data.defaultRecordTypeId', 
        objectApiName: INQUIRY_OBJECT 
    })
    handlePicklistValues({ error, data }) {
        if (data) {
            if (data.picklistFieldValues[PROPERTY_TYPE_FIELD.fieldApiName]) {
                this.propertyTypeOptions = data.picklistFieldValues[PROPERTY_TYPE_FIELD.fieldApiName].values.map(option => ({
                    label: option.label,
                    value: option.value
                }));
            }
            if (data.picklistFieldValues[INQUIRY_TYPE_FIELD.fieldApiName]) {
                this.inquiryTypeOptions = data.picklistFieldValues[INQUIRY_TYPE_FIELD.fieldApiName].values.map(option => ({
                    label: option.label,
                    value: option.value
                }));
            }
        } else if (error) {
            this.showToast('Error', 'Error loading property type picklist options', 'error');
        }
    }

    /**
     * Getter Name : dynamicFieldNames
     * @description : return dynamic field names based on selected object
     */
    get dynamicFieldNames() {
        if (!this.selectedObject || !this.configMap[this.selectedObject]) {
            return [];
        }
        const fields = this.configMap[this.selectedObject];
        return [
            `${this.selectedObject}.${fields.nameField}`,
            `${this.selectedObject}.${fields.phoneField}`
        ];
    }

    /**
     * Getter Name : isAllSelected
     * @description : return true if all records are selected
     */
    get isAllSelected() {
        return this.paginatedData.length > 0 && 
               this.paginatedData.every(record => this.selectedRecords.has(record.Id));
    }

    get isIndeterminate() {
        return this.paginatedData.some(record => this.selectedRecords.has(record.Id)) && 
               !this.isAllSelected;
    }

    get showNoRecordsMessage() {
        return this.paginatedData.length === 0;
    }

    get isSearchDisabled() {
        return !this.selectedObject || !this.selectedListView;
    }

    get isListViewDropdownDisabled() {
        return !this.selectedObject;
    }

    get isBtnDisabled() {
        return !this.paginatedData.length;
    }

    /**
     * Getter Name : totalItems
     * @description : set the totalItems count.
     */
    get totalItems() {
        return this.filteredData.length;
    }
    
    /**
     * Getter Name : totalPages
     * @description : set the totalpages count.
     */
    get totalPages() {
        return Math.ceil(this.totalItems / this.pageSize);
    }

    /**
     * Getter Name : pageNumbers
     * @description : set the list for page number in pagination.
     */
    get pageNumbers() {
        try {
            const totalPages = this.totalPages;
            const currentPage = this.currentPage;
            const visiblePages = this.visiblePages;

            let pages = [];

            if (totalPages <= visiblePages) {
                for (let i = 1; i <= totalPages; i++) {
                    pages.push({
                        number: i,
                        isEllipsis: false,
                        className: `pagination-button ${i === currentPage ? 'active' : ''}`
                    });
                }
            } else {
                pages.push({
                    number: 1,
                    isEllipsis: false,
                    className: `pagination-button ${currentPage === 1 ? 'active' : ''}`
                });

                if (currentPage > 3) {
                    pages.push({ isEllipsis: true });
                }

                let start = Math.max(2, currentPage - 1);
                let end = Math.min(currentPage + 1, totalPages - 1);

                for (let i = start; i <= end; i++) {
                    pages.push({
                        number: i,
                        isEllipsis: false,
                        className: `pagination-button ${i === currentPage ? 'active' : ''}`
                    });
                }

                if (currentPage < totalPages - 2) {
                    pages.push({ isEllipsis: true });
                }

                pages.push({
                    number: totalPages,
                    isEllipsis: false,
                    className: `pagination-button ${currentPage === totalPages ? 'active' : ''}`
                });
            }
            return pages;
        } catch (error) {
            this.showToast('Error', 'Error in pageNumbers->' + error, 'error');
            return null;
        }
    }

    /**
     * Getter Name : isFirstPage
     * @description : check the current page is first.
     */
    get isFirstPage() {
        return this.currentPage === 1;
    }

    /**
     * Getter Name : isLastPage
     * @description : check the current page is last.
     */
    get isLastPage() {
        return this.currentPage === Math.ceil(this.totalItems / this.pageSize);
    }
    
    get isContactObj() {
        return this.selectedObject !== 'Lead';
    }
    
    connectedCallback() {
        this.loadConfigs();
        this.fetchGroupDetails();
    }


    loadConfigs() {
        this.isLoading = true;
        getObjectConfigs()
            .then(result => {
                this.objectOptions = result.objectOptions;
                this.configMap = result.configMap;
            })
            .catch(error => {
                this.showToast('Error', 'Error loading configs', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleFilterModalOpen() { 
        this.tempFilterCriteria = { ...this.filterCriteria };
        this.isFilterModalOpen = true;
    }
    
    handleFilterModalClose() {
        this.isFilterModalOpen = false;
    }
    
    handleFilterInputChange(event) { 
        const { name, value } = event.target;
        this.tempFilterCriteria = { ...this.tempFilterCriteria, [name]: value };
    }

    updateAppliedFilterCount() { 
        this.appliedFilterCount = Object.values(this.filterCriteria).filter(value => 
            value && (Array.isArray(value) ? value.length > 0 : value.trim() !== '')
        ).length;
    }

    handleResetFilters() {
        // Reset both filterCriteria and tempFilterCriteria
        this.filterCriteria = {
            community: '',
            area: '',
            building: '',
            priceRange: '',
            propertyTypes: []
        };
        this.tempFilterCriteria = { ...this.filterCriteria };
        this.appliedFilterCount = 0;
        this.fetchRecords();

        // Reset filter inputs in the modal
        const inputs = this.template.querySelectorAll('lightning-input, lightning-combobox, lightning-dual-listbox');
        inputs.forEach(input => {
            if (input.name === 'community' || input.name === 'area' || input.name === 'building' || input.name === 'priceRange') {
                input.value = '';
            } else if (input.name === 'propertyTypes') {
                input.value = [];
            }
        });
    }
    
    handleApplyFilters() { 
        if (!this.validateFilterCriteria(this.tempFilterCriteria)) {
            return;
        }

        this.filterCriteria = { ...this.tempFilterCriteria };
        this.isFilterModalOpen = false;
        this.updateAppliedFilterCount();
        this.fetchRecords();
    }

    validateFilterCriteria(criteria) {
        // Check if bedroomMax or bedroomMin is less than 0
        if (criteria.bedroomMax < 0 || criteria.bedroomMin < 0) {
            this.showToast('Warning!','Bedroom count cannot be less than 0.','warning');
            return false;
        }
    
        // Check if bedroomMin is greater than bedroomMax
        if (criteria.bedroomMin > criteria.bedroomMax) {
            this.showToast('Warning!','Minimum bedroom count cannot be greater than maximum.','warning');
            return false;
        }
    
        return true;
    }    

    fetchGroupDetails() {
        if (!this.broadcastGroupId) {
            return;
        }
        
        this.isLoading = true;
        
        getBroadcastGroupDetails({ groupId: this.broadcastGroupId })
            .then((result) => {
                
                this.broadcastHeading = 'Edit Broadcast Group';
                this.createBtnLabel = 'Update Broadcast Group';
                let groupData = result.group || {};
                        
                this.selectedObject = groupData.Object_Name__c || '';
                this.loadListViews();
                this.selectedListView = groupData.List_View__c || '';
    
                this.broadcastGroupName = groupData.Name;
                this.messageText = groupData.Description__c;
    
                this.groupMembers = result.members || [];
                this.filterCriteria = {
                    community: '',
                    area: '',
                    building: '',
                    priceRange: '',
                    propertyTypes: []
                };
                this.appliedFilterCount = 0;
                this.fetchRecords();
            })
            .catch(() => {
                this.showToast('Error', 'Error fetching group details', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    cleardata() {
        this.selectedObject = '';
        this.selectedListView = '';
        this.data = [];
        this.filteredData = [];
        this.paginatedData = [];
        this.currentPage = 1;
        this.selectedRecords.clear();
        this.broadcastGroupName = '';
        this.messageText = '';
        this.isCreateBroadcastModalOpen = false;
        this.broadcastGroupId = null;
        this.groupMembers = [];
        this.isIntialRender = true;
        this.filterCriteria = {
            community: '',
            area: '',
            building: '',
            priceRange: '',
            propertyTypes: []
        };
        this.appliedFilterCount = 0;
    }

    /**
     * Method Name : updateShownData
     * @description : update the shownProcessedLisitingData when pagination is applied.
     */
    updateShownData() {
        try {
            const startIndex = (this.currentPage - 1) * this.pageSize;
            const endIndex = Math.min(startIndex + this.pageSize, this.totalItems);
            this.paginatedData = this.filteredData.slice(startIndex, endIndex).map(record => ({
                ...record,
                isSelected: this.selectedRecords.has(record.Id)
            }));
            
        } catch (error) {
            this.showToast('Error', 'Error updating shown data', 'error');
        }
    }

    /**
     * Method Name : handlePrevious
     * @description : handle the previous button click in the pagination.
     */
    handlePrevious() {
        try {
            if (this.currentPage > 1) {
                this.currentPage--;
                this.updateShownData();
            }
        } catch (error) {
            this.showToast('Error', 'Error handling previous button click', 'error');
        }
    }

    /**
     * Method Name : handleNext
     * @description : handle the next button click in the pagination.
     */
    handleNext() {
        try {
            if (this.currentPage < this.totalPages) {
                this.currentPage++;
                this.updateShownData();
            }
        } catch (error) {
            this.showToast('Error', 'Error handling next button click', 'error');
        }
    }

    /**
     * Method Name : handlePageChange
     * @description : handle the direct click on page number.
     */
    handlePageChange(event) {
        try {
            const selectedPage = parseInt(event.target.getAttribute('data-id'), 10);
            if (selectedPage !== this.currentPage) {
                this.currentPage = selectedPage;
                this.updateShownData();
            }
        } catch (error) {
            this.showToast('Error', 'Error handling page change', 'error');
        }
    }

    handleBack() {
        this.cleardata();
        this.isCreateBroadcastComp = false;
        this.isAllBroadcastGroupPage = true;
    }

    cleardata() {
        this.selectedObject = '';
        this.selectedListView = '';
        this.data = [];
        this.filteredData = [];
        this.paginatedData = [];
        this.currentPage = 1;
        this.selectedRecords.clear();
        this.broadcastGroupName = '';
        this.messageText = '';
        this.isCreateBroadcastModalOpen = false;
        this.broadcastGroupId = null;
        this.groupMembers = [];
        this.isIntialRender = true;
    }        

    handleSearch(event) {
        this.searchTerm = event.target.value.toLowerCase();
        const term = this.searchTerm.trim();
        this.filteredData = this.data.filter(item => {
            const name = item.name?.toLowerCase() || '';
            const phone = item.phone?.toLowerCase() || '';
            return !term || name.includes(term) || phone.includes(term);
        });
        this.currentPage = 1;
        this.updateShownData();    
    }

    handleInputChange(event) {
        const { name, value } = event.target;
        switch(name) {
            case 'name':
                this.broadcastGroupName = value;
                break;
            case 'message':
                this.messageText = value;
                break;
        }
    }

    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.selectedListView = '';
        this.data = [];
        this.filteredData = [];
        this.paginatedData = [];
        this.currentPage = 1;
        this.selectedRecords.clear();
        this.loadListViews();
    }

    loadListViews() {
        this.isLoading = true;
        getListViewsForObject({ objectApiName: this.selectedObject })
            .then(result => {
                const allowedDeveloperNames = ['All_Contacts_List', 'MyContacts', 'RecentlyViewedContacts','RecentlyViewedLeads','My_Leads','AllOpenLeads','TodaysLeads'];
                this.listViewOptions = result
                    .filter(lv => allowedDeveloperNames.includes(lv.DeveloperName))
                    .map(lv => ({
                        label: lv.Name,
                        value: lv.Id
                    }));
            })
            .catch(() => {
                this.showToast('Error', 'Error loading list views', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleListViewChange(event) {
        this.selectedListView = event.detail.value;
        this.fetchRecords();
    }

    fetchRecords() {
        if (!this.selectedObject || !this.selectedListView) {
            return;
        }

        this.isLoading = true;

        const fields = this.configMap[this.selectedObject];
        const filterCriteriaJson = JSON.stringify(this.filterCriteria); // Use filterCriteria
        
        getRecordsByListView({
            objectApiName: this.selectedObject,
            listViewId: this.selectedListView,
            nameField: fields.nameField,
            phoneField: fields.phoneField,
            filterCriteria: filterCriteriaJson
        })
            .then(data => {                
                this.data = data.map((record, index) => ({
                    index: index + 1,
                    Id: record.Id,
                    name: record[fields.nameField] ? record[fields.nameField] : '',
                    phone: record[fields.phoneField] ? record[fields.phoneField] : '',
                    isSelected: false
                }));

                this.filteredData = [...this.data];
                this.currentPage = 1;

                if (this.isIntialRender && this.broadcastGroupId && this.groupMembers.length > 0) {
                    this.isIntialRender = false;

                    const memberPhoneNumbers = new Set(this.groupMembers.map(member => member.Phone_Number__c));

                    this.data.forEach(record => {
                        if (memberPhoneNumbers.has(record.phone)) {
                            record.isSelected = true;
                            this.selectedRecords.add(record.Id);
                        }
                    });
                    this.filteredData = [...this.data];
                } else {
                    this.selectedRecords.clear();
                }
                this.updateShownData();
            })
            .catch(error => {
                this.showToast('Error', 'Error loading records: ' + error.body?.message, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    /**
     * Handle individual record selection
     */
    handleRecordSelection(event) {
        const recordId = event.target.dataset.recordId;
        const record = this.paginatedData.find(row => row.Id === recordId);
        if (record) {
            record.isSelected = event.target.checked;
            if (record.isSelected) {
                this.selectedRecords.add(recordId);
            } else {
                this.selectedRecords.delete(recordId);
            }
            this.selectedRecords = new Set(this.selectedRecords);
        }
    }

    /**
     * Handle select all records
     */
    handleSelectAll(event) {
        const isChecked = event.target.checked;
        this.paginatedData.forEach(record => {
            record.isSelected = isChecked;
            if (isChecked) {
                this.selectedRecords.add(record.Id);
            } else {
                this.selectedRecords.delete(record.Id);
            }
        });
        this.selectedRecords = new Set(this.selectedRecords);
    }

    handleModalOpen() {
        if (this.selectedRecords.size === 0) {
            this.showToast('Error', 'Please select at least one record', 'error');
            return;
        }

        if (Array.from(this.selectedRecords).some(recordId => {
            const record = this.data.find(r => r.Id === recordId);
            return !record || !record.phone || record.phone.trim() === '';
        })) {
            this.showToast('Error', 'One or more selected records have invalid or missing phone numbers', 'error');
            return;
        }

        this.isCreateBroadcastModalOpen = true;
    }

    closePopUp() {
        this.isCreateBroadcastModalOpen = false;
        this.broadcastGroupName = '';
        this.messageText = '';
    }

    handleSave() {
        if (this.messageText.trim() === '' || this.broadcastGroupName.trim() === '') {            
            this.showToast('Error', 'Please fill in all required fields', 'error');
            return;
        }

        const phoneNumbers = Array.from(this.selectedRecords)
            .map(recordId => {
                const record = this.data.find(r => r.Id === recordId);
                return record ? record.phone : null;
            })
            .filter(phone => phone !== null && phone !== '');
  
        const isUpdate = this.broadcastGroupId != null;
        
        const phoneField = this.configMap[this.selectedObject]?.phoneField || '';

        const messageData = {
            objectApiName: this.selectedObject,
            listViewName: this.selectedListView,
            phoneNumbers: phoneNumbers,
            description: this.messageText,
            name: this.broadcastGroupName,
            isUpdate: isUpdate,
            broadcastGroupId: this.broadcastGroupId,
            phoneField: phoneField
        };

        this.isLoading = true;

        processBroadcastMessageWithObject({ requestJson: JSON.stringify(messageData) })
            .then(() => {
                this.showToast('Success', 'Broadcast group created successfully', 'success');
                this.closePopUp();
                this.selectedRecords.clear();
                this.updateShownData();
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || 'Failed to process broadcast', 'error');
            })
            .finally(() => {
                this.isLoading = false;
                this.isCreateBroadcastComp = false;
                this.isAllBroadcastGroupPage = true;
            });
    }

    openFileSelector() {
        const fileInput = this.template.querySelector('.csv-file-input');
        if (fileInput) {
            fileInput.click(); 
        }
    }
    
    handleCsvFileChange(event) {
        const file = event.target.files[0];
        if (!file) return;
    
        const reader = new FileReader();
    
        reader.onload = () => {
            const csvText = reader.result;
            const lines = csvText.split(/\r\n|\n/);
            const headers = lines[0].toLowerCase().split(',').map(h => h.trim());
    
            const requiredFields = ['lastname', 'email', 'phone'];
            const missingFields = requiredFields.filter(field => !headers.includes(field));
    
            if (missingFields.length > 0) {
                this.showToast('Warning!', 'Missing required fields: ' + missingFields.join(', '), 'warning');
            } else {
                this.processCsvString(csvText); 
            }
        };
    
        reader.readAsText(file);
    }  

    processCsvString(csvText) {        
        createLeadsFromCsv({ csvString: csvText })
            .then(result => {
                this.fetchRecords();

                this.showToast('Success!', `${result} leads created successfully.`, 'success');
            })
            .catch(error => {
                let errorMessage = error.body?.message || error.message || 'Something went wrong.';
                this.showToast('Error!', errorMessage, 'error');
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }
}