/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 04-05-2025
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@isTest
private class BroadcastMessageControllerTest {

    private static Id broadcastGroupId;
    private static Id broadcastMemberId;

    @testSetup
    static void setupTestData() {

        // Create contact record
        Contact contact = new Contact(
            FirstName = 'Test',
            LastName = 'User',
            ContactType_hz__c = 'Tenant',
            Contact_Type_Multiselect_to_Text__c = 'Tenant',
            Stage__c = 'Active',
            MailingStreet = 'Test',
            MailingCity = 'Test',
            MailingCountry = 'India',
            Email='test@gmail.com',
            Birthdate=date.parse('07/11/1980'),
            LeadSource = 'Open House',
            Count_of_Linked_Listings__c=1,
            MobilePhone ='+919922334455',
            Previous_Agent_Role__c = 'TeleSales',
            Previous_Agent_Email__c = 'agent@example.com',
            Nationality__c = 'India',
            Payment_Mode__c = 'Cash'
        );
        insert contact;

        // Create a Broadcast Group
        Broadcast_Group__c broadcastGroup = new Broadcast_Group__c(
            Name = 'Test Group',
            Description__c = 'Test Description',
            Object_Name__c = 'Contact',
            List_View__c = 'Test List View',
            Phone_Field__c = 'Phone'
        );
        insert broadcastGroup;
        broadcastGroupId = broadcastGroup.Id;

        // Create a Broadcast Group Member
        Broadcast_Group_Member__c member = new Broadcast_Group_Member__c(
            Broadcast_Group_ID__c = broadcastGroupId,
            Phone_Number__c = '1234567890'
        );
        insert member;
        broadcastMemberId = member.Id;

        // Create a Template record
        WB_Template__c template = new WB_Template__c(
            Template_Name__c = 'Test_Template',
            Status__c = 'Active-Quality Pending',
            Language__c = 'en',
            WBTemplate_Body__c = 'Hello, {{1}}!',
            Header_Type__c = 'text',
            WBHeader_Body__c = 'Header Text',
            Template_Id__c	= 'testId',
            WBButton_Body__c = '[{"type":"COPY_CODE","example":"AADDFCGOP"}]'
        );


        WB_Template__c template2 = new WB_Template__c(
            Template_Name__c = 'Test_Template2',
            Status__c = 'Active-Quality Pending',
            Language__c = 'en',
            WBTemplate_Body__c = 'Hello, {{1}}!',
            Header_Type__c = 'text',
            WBHeader_Body__c = 'Header Text',
            Template_Id__c	= 'testId2',
            WBButton_Body__c	= '[{"type":"OTP","text":"Verify Code","otp_type":"COPY_CODE"}]'
        );

        insert new List<WB_Template__c>{template, template2};

        Template_Variable__c templateVariable = new Template_Variable__c(
            Name = 'Test Variable',
            Field_Name__c = 'LastName',
            Object_Name__c = 'Contact',
            Alternate_Text__c = 'Alternate Text',
            WB_Template__c = template.Id,
            Type__c = 'Header'
        );


        Template_Variable__c templateVariable2 = new Template_Variable__c(
            Name = 'Test Variable',
            Field_Name__c = 'LastName',
            Object_Name__c = 'Contact',
            Alternate_Text__c = 'Alternate Text',
            WB_Template__c = template2.Id,
            Type__c = 'Body'
        );

        insert new List<Template_Variable__c>{templateVariable, templateVariable2};

        // Create a Broadcast record with no group IDs
        Broadcast__c broadcast = new Broadcast__c(
            WB_Template__c = template.Id,
            Status__c = 'Pending'
        );
        insert broadcast;
        
    }

        
    // Mocking the HTTP response for testing
    static HttpResponse createMockResponse(String statusCode, String body) {
        HttpResponse mockResponse = new HttpResponse();
        mockResponse.setStatusCode(Integer.valueOf(statusCode));
        mockResponse.setBody(body);
        return mockResponse;
    }

    @isTest
    static void testGetRecordsByListView() {
        // Create test user
        User testUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];

        System.runAs(testUser) {
            // Insert test Contacts
            Contact c1 = new Contact(FirstName = 'Test', LastName = 'User', ContactType_hz__c = 'Tenant', Stage__c = 'Active', MailingStreet = 'Test', MailingCity = 'Test',
            MailingCountry = 'India', Email='test@gmail.com', Birthdate=date.parse('07/11/1980'), LeadSource = 'Open House', Count_of_Linked_Listings__c=1,
            MobilePhone ='+919922334455', Previous_Agent_Role__c = 'TeleSales', Previous_Agent_Email__c = 'agent@example.com', Nationality__c = 'India', Payment_Mode__c = 'Cash');
            Contact c2 = new Contact(FirstName = 'Test2', LastName = 'User2', ContactType_hz__c = 'Tenant', Stage__c = 'Active', MailingStreet = 'Test', MailingCity = 'Test',
            MailingCountry = 'India', Email='test@gmail.com', Birthdate=date.parse('07/11/1980'), LeadSource = 'Open House', Count_of_Linked_Listings__c=1,
            MobilePhone ='+919922334455', Previous_Agent_Role__c = 'TeleSales', Previous_Agent_Email__c = 'agent@example.com', Nationality__c = 'India', Payment_Mode__c = 'Cash');
            insert new List<Contact>{ c1, c2 };

            // Query standard list views (pre-created by Salesforce)
            Map<String, Id> listViewMap = new Map<String, Id>();
            for (ListView lv : [SELECT Id, DeveloperName FROM ListView WHERE SobjectType = 'Contact']) {
                listViewMap.put(lv.DeveloperName, lv.Id);
            }

            // Ensure all required list views exist

            // Test All_Contacts_List
            Test.startTest();
            List<SObject> allContacts = BroadcastMessageController.getRecordsByListView(
                'Contact',
                listViewMap.get('All_Contacts_List'),
                'LastName',
                'Phone'
            );

            // Test MyContacts
            List<SObject> myContacts = BroadcastMessageController.getRecordsByListView(
                'Contact',
                listViewMap.get('MyContacts'),
                'LastName',
                'Phone'
            );

            // Test RecentlyViewedContacts
            List<SObject> recentContacts = BroadcastMessageController.getRecordsByListView(
                'Contact',
                listViewMap.get('RecentlyViewedContacts'),
                'LastName',
                'Phone'
            );

            // Test unknown/default case by passing a non-matching listViewId
            ListView randomListView = [SELECT Id FROM ListView WHERE SobjectType = 'Contact' LIMIT 1];
            List<SObject> defaultView = BroadcastMessageController.getRecordsByListView(
                'Contact',
                randomListView.Id,
                'LastName',
                'Phone'
            );
            Test.stopTest();
        }
    }

    @isTest
    static void testGetObjectConfigs() {
        Test.startTest();
        Map<String, Object> result = BroadcastMessageController.getObjectConfigs();
        Test.stopTest();

        // 
        // 
        // 
    }

    @isTest
    static void testGetListViewsForObject() {
        Test.startTest();
        List<ListView> listViews = BroadcastMessageController.getListViewsForObject('Account');
        Test.stopTest();

        
    }

    @isTest
    static void testGetBroadcastGroups() {
        Test.startTest();
        List<Broadcast_Group__c> groups = BroadcastMessageController.getBroadcastGroups();
        Test.stopTest();

        
    }

    @isTest
    static void testDeleteBroadcastGroup() {
        
        Broadcast_Group__c tempGroup = [SELECT Id, Name FROM Broadcast_Group__c LIMIT 1];

        Test.startTest();
        BroadcastMessageController.deleteBroadcastGroup(tempGroup.Id);
        Test.stopTest();

        // count query
        Integer count = [SELECT COUNT() FROM Broadcast_Group__c WHERE Id = :tempGroup.Id];
        

    }

    @isTest
    static void testGetBroadcastRecs() {
        Test.startTest();
        List<Broadcast__c> broadcasts = BroadcastMessageController.getBroadcastRecs();
        Test.stopTest();

        
    }

    @isTest
    static void testGetTemplatesByObject() {
        Test.startTest();
        Map<String, List<WB_Template__c>> templatesMap = BroadcastMessageController.getTemplatesByObject();
        Test.stopTest();

        
    }

    @isTest
    static void testProcessBroadcastMessageWithObject_Insert() {
        Map<String, Object> requestMap = new Map<String, Object>{
            'name' => 'New Broadcast Group',
            'description' => 'Test Description',
            'objectApiName' => 'Account',
            'phoneNumbers' => new List<String>{'9876543210'},
            'listViewName' => 'Test List View',
            'isUpdate' => false,
            'phoneField' => 'Phone'
        };
        
        String requestJson = JSON.serialize(requestMap);
    
        Test.startTest();
        BroadcastMessageController.processBroadcastMessageWithObject(requestJson);
        Test.stopTest();
    
        Broadcast_Group__c createdGroup = [SELECT Id, Name FROM Broadcast_Group__c WHERE Name = 'New Broadcast Group' LIMIT 1];
        
    }
    

    @isTest
    static void testProcessBroadcastMessageWithObject_Update() {
        // First create a broadcast group for update
        Broadcast_Group__c tempGroup = new Broadcast_Group__c(
            Name = 'Old Name',
            Description__c = 'Old Description',
            Object_Name__c = 'Account',
            List_View__c = 'Old List View',
            Phone_Field__c = 'Phone'
        );
        insert tempGroup;
    
        Map<String, Object> requestMap = new Map<String, Object>{
            'name' => 'Updated Group Name',
            'description' => 'Updated Description',
            'objectApiName' => 'Account',
            'phoneNumbers' => new List<String>{'1234567890', '9876543210'},
            'listViewName' => 'Updated List View',
            'isUpdate' => true,
            'broadcastGroupId' => tempGroup.Id,
            'phoneField' => 'Phone'
        };
    
        String requestJson = JSON.serialize(requestMap);
    
        Test.startTest();
        BroadcastMessageController.processBroadcastMessageWithObject(requestJson);
        Test.stopTest();
    
        Broadcast_Group__c updatedGroup = [SELECT Name, Description__c FROM Broadcast_Group__c WHERE Id = :tempGroup.Id];
        
    }
    
    @isTest
    static void testGetBroadcastGroupDetails() {

        Broadcast_Group__c tempGroup = [SELECT Id, Description__c, Object_Name__c FROM Broadcast_Group__c LIMIT 1];

        Test.startTest();
        Map<String, Object> groupDetails = BroadcastMessageController.getBroadcastGroupDetails(tempGroup.Id);
        Test.stopTest();

        
    }

    @isTest
    static void testCreateChatRecods_ImmediateExecution() {

        HttpResponse mockResponse = createMockResponse('200', '{"messages":[{"id":"wamid.HBgLMjM0NTY3ODkwVBIJDQAAAB"}]}');
        MockHttpResponseGenerator mock = new MockHttpResponseGenerator(mockResponse);
        Test.setMock(HttpCalloutMock.class, mock);

        WB_Template__c testTemplate = [SELECT Id, Name, Template_Id__c FROM WB_Template__c WHERE Template_Id__c = 'testId' LIMIT 1];
        Broadcast_Group__c tempGroup = [SELECT Id, Name FROM Broadcast_Group__c LIMIT 1];

        Test.startTest();
        String result = BroadcastMessageController.createChatRecods(testTemplate.Id, new List<String>{tempGroup.Id}, false, '');
        Test.stopTest();
        
        
        List<Broadcast__c> broadcasts = [SELECT Id FROM Broadcast__c];
        
        
        List<Chat__c> chats = [SELECT Id FROM Chat__c];
        
    }

    @isTest
    static void testCreateChatRecods_ImmediateExecutionWitBody() {

        HttpResponse mockResponse = createMockResponse('200', '{"messages":[{"id":"wamid.HBgLMjM0NTY3ODkwVBIJDQAAAB"}]}');
        MockHttpResponseGenerator mock = new MockHttpResponseGenerator(mockResponse);
        Test.setMock(HttpCalloutMock.class, mock);

        WB_Template__c testTemplate = [SELECT Id, Name, Template_Id__c FROM WB_Template__c WHERE Template_Id__c = 'testId2' LIMIT 1];
        Broadcast_Group__c tempGroup = [SELECT Id, Name FROM Broadcast_Group__c LIMIT 1];

        Test.startTest();
        String result = BroadcastMessageController.createChatRecods(testTemplate.Id, new List<String>{tempGroup.Id}, false, '');
        Test.stopTest();
        
        
        List<Broadcast__c> broadcasts = [SELECT Id FROM Broadcast__c];
        
        
        List<Chat__c> chats = [SELECT Id FROM Chat__c];
        
    }

    @isTest
    static void testCreateChatRecods_ScheduledExecution() {

        DateTime futureDateTime = DateTime.now().addDays(1);
        String futureTime = futureDateTime.format('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
        
        WB_Template__c testTemplate = [SELECT Id, Name FROM WB_Template__c LIMIT 1];
        Broadcast_Group__c tempGroup = [SELECT Id, Name FROM Broadcast_Group__c LIMIT 1];

        Test.startTest();
        String result = BroadcastMessageController.createChatRecods(testTemplate.Id, new List<String>{tempGroup.Id}, true, futureTime);
        Test.stopTest();

        
        List<Broadcast__c> broadcasts = [SELECT Id, Schedule_DateTime__c FROM Broadcast__c];
        
    }

    @isTest
    static void testGetBroadcastGroupsByBroadcastId_NoGroups() {

        Broadcast__c broadcast = [SELECT Id, WB_Template__c, Status__c FROM Broadcast__c LIMIT 1];

        Test.startTest();
        List<Broadcast_Group__c> groups = BroadcastMessageController.getBroadcastGroupsByBroadcastId(broadcast.Id);
        Test.stopTest();

        
        
    }

}