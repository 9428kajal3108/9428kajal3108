/**
* Class Name: BroadcastMessageController
* Test Class: BroadcastMessageControllerTest
* Description: This class is responsible for handling broadcast messages and managing broadcast groups.
* Created Date: 03 April 2025
* Created By: Rachit Shah
* Updated By: Kajal Tiwari
* Updated Date:  24 April 2025
* Description: Added CreatedDate field in the query for broadcast and broadcast group, added method to create lead record using csv and modify getRecordsByListView.
* Updated By: Kajal Tiwari
* Updated Date:  25 April 2025
* Description: Added getBroadcastMembersByGroupId to get the member related to group Id.
*--------------------------------------------------------------------------------
**/


public with sharing class BroadcastMessageController {

    
    @AuraEnabled(cacheable=false)
    public static List<SObject> getRecordsByListView(String objectApiName, String listViewId, String nameField, String phoneField, String filterCriteria) {
        try {
            // Query the ListView to get its DeveloperName
            ListView listView = [SELECT DeveloperName 
                                FROM ListView 
                                WHERE Id = :listViewId 
                                AND SobjectType = :objectApiName 
                                WITH SECURITY_ENFORCED 
                                LIMIT 1];
            String developerName = listView.DeveloperName;
            String query;
    
            String currentUserId = UserInfo.getUserId();
    
            // Sanitize inputs to prevent SOQL injection
            String sanitizedObjectApiName = String.escapeSingleQuotes(objectApiName);
            String sanitizedNameField = String.escapeSingleQuotes(nameField);
            String sanitizedPhoneField = String.escapeSingleQuotes(phoneField);

            // Build base query
            String baseQuery = 'SELECT Id, ' + sanitizedNameField + ', ' + sanitizedPhoneField + 
                            ' FROM ' + sanitizedObjectApiName + 
                            ' WHERE ' + sanitizedPhoneField + ' != null';

            // Apply list view conditions based on allowed developer names
            if (developerName == 'All_Contacts_List' || developerName == 'AllOpenLeads') {
                query = baseQuery;
            } else if (developerName == 'MyContacts' || developerName == 'My_Leads') {
                query = baseQuery + ' AND OwnerId = :currentUserId';
            } else if (developerName == 'RecentlyViewedContacts' || developerName == 'RecentlyViewedLeads') {
                query = baseQuery + ' AND CreatedDate = LAST_N_DAYS:30 ORDER BY CreatedDate DESC';
            } else if (developerName == 'TodaysLeads') {
                query = baseQuery + ' AND CreatedDate = TODAY';
            } else {
                query = baseQuery;
            }

            // Initialize bind variables map
            Map<String, Object> bindVars = new Map<String, Object>{ 'currentUserId' => currentUserId };

            // Apply filter criteria if provided
            if (String.isNotBlank(filterCriteria)) {
                Map<String, Object> filters = (Map<String, Object>) JSON.deserializeUntyped(filterCriteria);
                String subQuery = 'SELECT Contact__c FROM Inquiry_hz__c WHERE ';
                List<String> subConditions = new List<String>();

                String community = (String) filters.get('community');
                if (String.isNotBlank(community)) {
                    String sanitizedCommunity = '%' + String.escapeSingleQuotes(community) + '%';
                    subConditions.add('Community_Propertyfinder__c LIKE :sanitizedCommunity');
                    bindVars.put('sanitizedCommunity', sanitizedCommunity);
                }

                String area = (String) filters.get('area');
                if (String.isNotBlank(area)) {
                    String sanitizedArea = '%' + String.escapeSingleQuotes(area) + '%';
                    subConditions.add('Area_hz__c LIKE :sanitizedArea');
                    bindVars.put('sanitizedArea', sanitizedArea);
                }

                String building = (String) filters.get('building');
                if (String.isNotBlank(building)) {
                    String sanitizedBuilding = '%' + String.escapeSingleQuotes(building) + '%';
                    subConditions.add('Building_Dubizzle__c LIKE :sanitizedBuilding');
                    bindVars.put('sanitizedBuilding', sanitizedBuilding);
                }

                String priceRange = (String) filters.get('priceRange');
                if (String.isNotBlank(priceRange)) {
                    if (priceRange == '0-100000') {
                        subConditions.add('ListingPrice_hz_max__c >= 0 AND ListingPrice_hz_max__c <= 100000');
                    } else if (priceRange == '100000-200000') {
                        subConditions.add('ListingPrice_hz_max__c > 100000 AND ListingPrice_hz_max__c <= 200000');
                    } else if (priceRange == '200000-500000') {
                        subConditions.add('ListingPrice_hz_max__c > 200000 AND ListingPrice_hz_max__c <= 500000');
                    } else if (priceRange == '500000-1000000') {
                        subConditions.add('ListingPrice_hz_max__c > 500000 AND ListingPrice_hz_max__c <= 1000000');
                    } else if (priceRange == '1000000+') {
                        subConditions.add('ListingPrice_hz_max__c > 1000000');
                    }
                }

                List<Object> propertyTypes = (List<Object>) filters.get('propertyTypes');
                if (propertyTypes != null && !propertyTypes.isEmpty()) {
                    List<String> sanitizedPropertyTypes = new List<String>();
                    for (Object pt : propertyTypes) {
                        sanitizedPropertyTypes.add('\'' + String.escapeSingleQuotes((String)pt) + '\'');
                    }
                    subConditions.add('PropertyType__c INCLUDES (' + String.join(sanitizedPropertyTypes, ',') + ')');
                }

                if (!subConditions.isEmpty()) {
                    query += ' AND Id IN (' + subQuery + String.join(subConditions, ' AND ') + ')';
                }
            }

             // Append ORDER BY for RecentlyViewedContacts after all conditions
            if (developerName == 'RecentlyViewedContacts') {
                query += ' ORDER BY CreatedDate DESC';
            }
    
            // Execute the query with variable binding
            return Database.queryWithBinds(query, bindVars, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving records: ' + e.getMessage());
        }
    }

    /*
    *********************************************************
    @description     : create lead record from csv data
    @param           : None
    @return          : result - insert and return the created lead data 
    ********************************************************
    */
    @AuraEnabled
    public static Integer createLeadsFromCsv(String csvString) {
        if (String.isBlank(csvString)) {
            throw new AuraHandledException('CSV data is empty.');
        }
    
        List<Lead> leadsToInsert = new List<Lead>();
        List<String> rows = csvString.split('\n');
        List<String> headers = rows[0].replace('"', '').split(',');
    
        try {
            for (Integer i = 1; i < rows.size(); i++) {
                String row = rows[i].trim();
                if (row == ''){
                    continue;
                } 
                List<String> values = row.replace('"', '').split(',');
        
                Map<String, String> rowData = new Map<String, String>();
                for (Integer j = 0; j < headers.size(); j++) {
                    rowData.put(headers[j].toLowerCase(), values.size() > j ? values[j] : '');
                }
        
                Lead lead = new Lead(
                    LastName = rowData.get('lastname'),
                    Email = rowData.get('email'),
                    Phone = rowData.get('phone'),
                    Company = 'Houzon'
                );
                leadsToInsert.add(lead);
            }
        
            if (!leadsToInsert.isEmpty()) {
                insert as user leadsToInsert;
            }
        
            return leadsToInsert.size(); 
        } catch (Exception e) {
            ExceptionHandler.logException(new Map<String, Object>{'className' => 'BroadcastMessageController','methodName' => 'createLeadsFromCsv', 'exceptionObj' => e,'isApiException' => false,'statusCode' => null,'chatId' => null,'moreDetails' => e.getMessage(),'apiResponse' => null});
            throw new AuraHandledException('Error creating leads: ' + e.getMessage());
        }
    }

    /*
    *********************************************************
    @description     : get the object configs from metadata
    @param           : None
    @return          : result - contain the object options and config map
    ********************************************************
    */
    @AuraEnabled
    public static Map<String, Object> getObjectConfigs() {
        try {
            Map<String, Object> result = new Map<String, Object>();
            List<Object_Config__mdt> objectConfigList = [
                SELECT ChatWindowConfigInfo__c 
                FROM Object_Config__mdt WITH SECURITY_ENFORCED LIMIT 1
            ];
    
            if (objectConfigList.isEmpty() && !Test.isRunningTest()) {
                throw new AuraHandledException('Object Config not found!');
            }
    
            Map<String, Object> chatConfigData = (Map<String, Object>) JSON.deserializeUntyped(objectConfigList[0].ChatWindowConfigInfo__c);
            
            // Prepare return structure: { objectOptions: [...], configMap: {...} }
            List<Map<String, String>> objectOptions = new List<Map<String, String>>();
            Map<String, Map<String, String>> configMap = new Map<String, Map<String, String>>();
    
            for (String objectApiName : chatConfigData.keySet()) {
                objectOptions.add(new Map<String, String> {
                    'label' => objectApiName,
                    'value' => objectApiName
                });
                Map<String, Object> config = (Map<String, Object>) chatConfigData.get(objectApiName);
                configMap.put(objectApiName, new Map<String, String>{
                    'nameField' => (String) config.get('nameField'),
                    'phoneField' => (String) config.get('phoneField')
                });
            }
    
            result.put('objectOptions', objectOptions);
            result.put('configMap', configMap);
    
            return result;
    
        } catch (Exception e) {
            ExceptionHandler.logException(new Map<String, Object>{'className' => 'BroadcastMessageController','methodName' => 'getObjectConfigs', 'exceptionObj' => e,'isApiException' => false,'statusCode' => null,'chatId' => null,'moreDetails' => e.getMessage(),'apiResponse' => null});
            throw new AuraHandledException('Error fetching object configs: ' + e.getMessage());
        }
    }

    /*
    *********************************************************
    @description     : get the list views for the object
    @param           : objectApiName - API name of the object
    @return          : List of ListView records for the specified object
    ********************************************************
    */
    @AuraEnabled
    public static List<ListView> getListViewsForObject(String objectApiName) {
        try {
            List<ListView> lstview = [SELECT Id, Name FROM ListView WHERE SobjectType = :objectApiName WITH SECURITY_ENFORCED ORDER BY LastViewedDate DESC];
            System.debug('lstview==> '+lstview);
            return [SELECT Id, Name, DeveloperName FROM ListView WHERE SobjectType = :objectApiName WITH SECURITY_ENFORCED ORDER BY LastViewedDate DESC];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching list views: ' + e.getMessage());
        }
    }

    /*
    *********************************************************
    @description     : get all broadcast groups
    @param           : None
    @return          : List of Broadcast_Group__c records
    ********************************************************
    */

    @AuraEnabled
    public static List<Broadcast_Group__c> getBroadcastGroups(){
        List<Broadcast_Group__c> broadcastGroups = new List<Broadcast_Group__c>();
        try {
            broadcastGroups = [SELECT Id, Name, Count_of_Members__c, Description__c, Object_Name__c, Phone_Field__c,CreatedDate FROM Broadcast_Group__c WITH SECURITY_ENFORCED ORDER BY LastModifiedDate DESC];
        } catch (Exception e) {
            ExceptionHandler.logException(new Map<String, Object>{'className' => 'BroadcastMessageController','methodName' => 'getBroadcastGroups', 'exceptionObj' => e,'isApiException' => false,'statusCode' => null,'chatId' => null,'moreDetails' => e.getMessage(),'apiResponse' => null});
        }
        return broadcastGroups;
    }

    /*
    *********************************************************
    @description     : delete a broadcast group
    @param           : groupId - Id of the Broadcast_Group__c record
    @return          : void
    ********************************************************
    */
    @AuraEnabled
    public static void deleteBroadcastGroup(Id groupId) {
        try {
            // Ensure user has delete permission
            if (!Schema.sObjectType.Broadcast_Group__c.isDeletable()) {
                throw new AuraHandledException('Insufficient permissions to delete this record.');
            }
            
            // Query the record with security enforced
            Broadcast_Group__c groupToDelete = [
                SELECT Id FROM Broadcast_Group__c 
                WHERE Id = :groupId 
                WITH SECURITY_ENFORCED 
                LIMIT 1
            ];
            
            if (groupToDelete == null) {
                throw new AuraHandledException('There was a problem deleting the record. ' + groupId);
            }
            
            delete groupToDelete;
        } catch (Exception e) {
            ExceptionHandler.logException(new Map<String, Object>{'className' => 'BroadcastMessageController','methodName' => 'deleteBroadcastGroup', 'exceptionObj' => e,'isApiException' => false,'statusCode' => null,'chatId' => null,'moreDetails' => e.getMessage(),'apiResponse' => null});
        }
    }

    /*
    *********************************************************
    @description     : get all broadcast records
    @param           : None
    @return          : List of Broadcast__c records
    ********************************************************
    */
    @AuraEnabled
    public static List<Broadcast__c> getBroadcastRecs(){
        List<Broadcast__c> broadcastRecs = new List<Broadcast__c>();
        try {
            broadcastRecs =  [SELECT Id, Name, Recipient_Count__c, Status__c, Total_Sent__c, Total_Delivered__c, Total_Read__c, Total_Failed__c, CreatedDate FROM Broadcast__c WITH SECURITY_ENFORCED ORDER BY LastModifiedDate DESC];        
        } catch (Exception e) {
            ExceptionHandler.logException(new Map<String, Object>{'className' => 'BroadcastMessageController','methodName' => 'getBroadcastRecs', 'exceptionObj' => e,'isApiException' => false,'statusCode' => null,'chatId' => null,'moreDetails' => e.getMessage(),'apiResponse' => null});
        }

        return broadcastRecs;
    }

    /*
    *********************************************************
    @description     : get all templates by object
    @param           : None
    @return          : Map of object names to lists of WB_Template__c records
    ********************************************************
    */
    @AuraEnabled
    public static Map<String, List<WB_Template__c>> getTemplatesByObject() {
        Map<String, List<WB_Template__c>> objectTemplateMap = new Map<String, List<WB_Template__c>>();
    
        try {
            // Fetch all templates with their related object names from Template_Variable__c
            List<WB_Template__c> templates = [SELECT Id, Template_Name__c, 
                                                  (SELECT Object_Name__c FROM WB_Template_Variables__r) 
                                           FROM WB_Template__c 
                                           WHERE Status__c = 'Active-Quality Pending'
                                           WITH SECURITY_ENFORCED 
                                           ORDER BY LastModifiedDate DESC];
    
            // Categorize templates by object name
            for (WB_Template__c template : templates) {
                String objectName;
    
                // If the template has associated object names, use the first one; otherwise, categorize it as 'Generic'
                if (!template.WB_Template_Variables__r.isEmpty()) {
                    objectName = template.WB_Template_Variables__r[0].Object_Name__c;
                } else {
                    objectName = 'Generic'; // Templates without variables are categorized as 'Generic'
                }
    
                // Initialize list if objectName is not yet added
                if (!objectTemplateMap.containsKey(objectName)) {
                    objectTemplateMap.put(objectName, new List<WB_Template__c>());
                }
    
                // Add template to the appropriate object name
                objectTemplateMap.get(objectName).add(template);
            }
    
        } catch (Exception e) {
            ExceptionHandler.logException(new Map<String, Object>{'className' => 'BroadcastMessageController','methodName' => 'getTemplatesByObject', 'exceptionObj' => e,'isApiException' => false,'statusCode' => null,'chatId' => null,'moreDetails' => e.getMessage(),'apiResponse' => null});
        }
    
        return objectTemplateMap;
    }    

    /*
    *********************************************************
    @description     : Insert or Update the broadcast group and its members
    @param           : requestJson - JSON string containing the broadcast group details
    @return          : void
    ********************************************************
    */

    @AuraEnabled
    public static void processBroadcastMessageWithObject(String requestJson) {
        try {
            // Deserialize JSON to a generic map
            Map<String, Object> request = (Map<String, Object>) JSON.deserializeUntyped(requestJson);
    
            // Extract fields
            String objectApiName = (String) request.get('objectApiName');
            String listViewName = (String) request.get('listViewName');
            List<Object> phoneNumbersRaw = (List<Object>) request.get('phoneNumbers');
            List<String> phoneNumbers = new List<String>();
            for (Object phoneNumber : phoneNumbersRaw) {
                phoneNumbers.add((String) phoneNumber);
            }
            String description = (String) request.get('description');
            String name = (String) request.get('name');
            Boolean isUpdate = request.containsKey('isUpdate') ? (Boolean) request.get('isUpdate') : false;
            String broadcastGroupId = (String) request.get('broadcastGroupId');
            String phoneField = (String) request.get('phoneField');
    
            // Basic validation
            if (String.isBlank(objectApiName) || 
                String.isBlank(description) || 
                String.isBlank(name) || 
                String.isBlank(listViewName) ||
                String.isBlank(phoneField) || 
                phoneNumbers.isEmpty()) {
                throw new AuraHandledException('All fields in the request are required, including the broadcast group name');
            }
    
            Broadcast_Group__c broadcastGroup;
    
            if (isUpdate && String.isNotBlank(broadcastGroupId)) {
                // Fetch existing Broadcast Group
                broadcastGroup = [
                    SELECT Id, Name, Description__c, Object_Name__c, List_View__c, Phone_Field__c
                    FROM Broadcast_Group__c
                    WHERE Id = :broadcastGroupId
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
    
                broadcastGroup.Name = name;
                broadcastGroup.Description__c = description;
                broadcastGroup.Object_Name__c = objectApiName;
                broadcastGroup.List_View__c = listViewName;
                broadcastGroup.Phone_Field__c = phoneField;
    
                Database.SaveResult updateResult = Database.update(broadcastGroup, false, AccessLevel.USER_MODE);
                if (!updateResult.isSuccess()) {
                    throw new AuraHandledException('Failed to update broadcast group.');
                }
            } else {
                broadcastGroup = new Broadcast_Group__c();
                broadcastGroup.Name = name;
                broadcastGroup.Description__c = description;
                broadcastGroup.Object_Name__c = objectApiName;
                broadcastGroup.List_View__c = listViewName;
                broadcastGroup.Phone_Field__c = phoneField;
    
                Database.SaveResult insertResult = Database.insert(broadcastGroup, false, AccessLevel.USER_MODE);
                if (!insertResult.isSuccess()) {
                    throw new AuraHandledException('Failed to create broadcast group.');
                }
            }
    
            // Handle group members
            Map<String, Broadcast_Group_Member__c> existingMembersMap = new Map<String, Broadcast_Group_Member__c>();
            if (isUpdate) {
                for (Broadcast_Group_Member__c member : [
                    SELECT Id, Phone_Number__c 
                    FROM Broadcast_Group_Member__c 
                    WHERE Broadcast_Group_ID__c = :broadcastGroup.Id
                    WITH SECURITY_ENFORCED
                ]) {
                    existingMembersMap.put(member.Phone_Number__c, member);
                }
            }
    
            List<Broadcast_Group_Member__c> newMembersToInsert = new List<Broadcast_Group_Member__c>();
            Set<String> receivedPhoneNumbers = new Set<String>(phoneNumbers);
            Set<String> existingPhoneNumbers = existingMembersMap.keySet();
    
            for (String phone : receivedPhoneNumbers) {
                if (String.isNotBlank(phone) && !existingPhoneNumbers.contains(phone)) {
                    newMembersToInsert.add(new Broadcast_Group_Member__c(
                        Broadcast_Group_ID__c = broadcastGroup.Id,
                        Phone_Number__c = phone
                    ));
                }
            }
    
            List<Broadcast_Group_Member__c> membersToDelete = new List<Broadcast_Group_Member__c>();
            for (String existingPhone : existingPhoneNumbers) {
                if (!receivedPhoneNumbers.contains(existingPhone)) {
                    membersToDelete.add(existingMembersMap.get(existingPhone));
                }
            }
    
            if (!newMembersToInsert.isEmpty()) {
                Database.SaveResult[] insertResults = Database.insert(newMembersToInsert, false, AccessLevel.USER_MODE);
                for (Database.SaveResult res : insertResults) {
                    if (!res.isSuccess()) {
                        throw new AuraHandledException('Error inserting some broadcast group members.');
                    }
                }
            }
    
            if (!membersToDelete.isEmpty()) {
                Database.DeleteResult[] deleteResults = Database.delete(membersToDelete, false, AccessLevel.USER_MODE);
                for (Database.DeleteResult res : deleteResults) {
                    if (!res.isSuccess()) {
                        throw new AuraHandledException('Error deleting some broadcast group members.');
                    }
                }
            }
    
        } catch (Exception e) {
            ExceptionHandler.logException(new Map<String, Object>{'className' => 'BroadcastMessageController','methodName' => 'processBroadcastMessageWithObject','exceptionObj' => e,'isApiException' => false,'statusCode' => null,'chatId' => null,'moreDetails' => e.getMessage(),'apiResponse' => null});
            throw new AuraHandledException('Error processing broadcast message: ' + e.getMessage());
        }
    }
    

    /*
    *********************************************************
    @description     : get the details of a broadcast group
    @param           : groupId - Id of the Broadcast_Group__c record
    @return          : Map containing the group record and its members
    ********************************************************
    */

    @AuraEnabled
    public static Map<String, Object> getBroadcastGroupDetails(String groupId) {
        try {
            // Validate input
            if (String.isBlank(groupId)) {
                throw new AuraHandledException('Group ID is required');
            }

            // Fetch Broadcast Group
            Broadcast_Group__c groupRecord = [
                SELECT Id, Name, Description__c, Object_Name__c, List_View__c, Phone_Field__c
                FROM Broadcast_Group__c
                WHERE Id = :groupId
                WITH SECURITY_ENFORCED 
                LIMIT 1
            ];

            // Fetch Group Members
            List<Broadcast_Group_Member__c> groupMembers = [
                SELECT Id, Phone_Number__c, Name
                FROM Broadcast_Group_Member__c
                WHERE Broadcast_Group_ID__c = :groupId
                WITH SECURITY_ENFORCED 
            ];

            // Construct response
            Map<String, Object> response = new Map<String, Object>();
            response.put('group', groupRecord);
            response.put('members', groupMembers);

            return response;
        } catch (Exception e) {
            ExceptionHandler.logException(new Map<String, Object>{'className' => 'BroadcastMessageController','methodName' => 'getBroadcastGroupDetails', 'exceptionObj' => e,'isApiException' => false,'statusCode' => null,'chatId' => null,'moreDetails' => e.getMessage(),'apiResponse' => null});
            throw new AuraHandledException('Error retrieving broadcast group details: ' + e.getMessage());
        }
    } 

    /*
    *********************************************************
    @description     : Create chat records and run batch class to send it at that time or schedule batch job if needed
    @param           : groupId - Id of the Broadcast_Group__c record
    @return          : String indicating success or failure
    ********************************************************
    */
    @AuraEnabled
    public static String createChatRecods(String templateId, List<String> groupIds, Boolean isScheduled, String timeOfMessage) {
        try {
            Broadcast__c broadcast = new Broadcast__c();
            broadcast.WB_Template__c = templateId;
            broadcast.Status__c = 'Pending';
            broadcast.Broadcast_Group_IDs__c = String.join(groupIds, ','); // Save all group IDs as a comma-separated string

            String objectApiName = '';
            String phoneField = '';
            List<Chat__c> chatRecs = new List<Chat__c>();

            if (groupIds.size() > 0) {
                List<Broadcast_Group__c> brGroupRecs = [SELECT Id, Name, Object_Name__c, Phone_Field__c FROM Broadcast_Group__c WHERE Id IN :groupIds];
                if (brGroupRecs.size() > 0) {
                    objectApiName = brGroupRecs[0].Object_Name__c;
                    phoneField = brGroupRecs[0].Phone_Field__c;
                }

                List<Broadcast_Group_Member__c> groupMembers = new List<Broadcast_Group_Member__c>();
                groupMembers = [SELECT Id, Name, Phone_Number__c, Broadcast_Group_ID__c FROM Broadcast_Group_Member__c WHERE Broadcast_Group_ID__c IN :groupIds WITH SECURITY_ENFORCED];
                broadcast.Recipient_Count__c = groupMembers.size();
                Database.insert(broadcast, false, AccessLevel.USER_MODE);

                List<String> phoneList = new List<String>();
                if (groupMembers.size() > 0) {
                    for (Broadcast_Group_Member__c member : groupMembers) {
                        if (member.Phone_Number__c != null || member.Phone_Number__c != '') {
                            phoneList.add(member.Phone_Number__c);
                            Chat__c newChat = new Chat__c();
                            newChat.WB_Template__c = templateId;
                            newChat.Phone__c = member.Phone_Number__c;
                            newChat.Type_of_Message__c = 'OutBound Messages';
                            newChat.Message_Status__c = null;
                            newChat.Message_Type__c = 'Template';
                            newChat.WB_Broadcast__c = broadcast.Id;
                            chatRecs.add(newChat);
                        }
                    }
                }

                if (chatRecs.size() > 0) {
                    Database.insert(chatRecs, false, AccessLevel.USER_MODE);
                }
            }

            if (isScheduled == false) {
                WhatsAppMessageBatch batchJob = new WhatsAppMessageBatch(templateId, chatRecs, broadcast.Id, objectApiName, phoneField);
                Database.executeBatch(batchJob, 1);
            } else {
                timeOfMessage = timeOfMessage.replace('T', ' ').replace('Z', '');

                DateTime utcDateTime = DateTime.valueOf(timeOfMessage);

                // Convert UTC to user's timezone
                TimeZone userTimeZone = UserInfo.getTimeZone();
                DateTime userDateTime = utcDateTime.addSeconds(userTimeZone.getOffset(utcDateTime) / 1000);

                // Validate that the scheduled time is in the future
                if (userDateTime < DateTime.now()) {
                    throw new AuraHandledException('Scheduled time must be in the future.');
                }

                String formattedTime = userDateTime.format('hh:mm a');

                String cronExpression = getCronExpression(userDateTime);

                WhatsAppMessageBatchSchedulable batchSchedular = new WhatsAppMessageBatchSchedulable(templateId, chatRecs, broadcast.Id, objectApiName, phoneField);

                Broadcast__c br = new Broadcast__c(Id = broadcast.Id);
                br.Schedule_DateTime__c = userDateTime;
                Database.SaveResult updateResult = Database.update(br, false, AccessLevel.USER_MODE);

                String jobName = 'BroadcastSchedule_' + System.currentTimeMillis();
                System.schedule(jobName, cronExpression, batchSchedular);
            }
            return 'Success';
        } catch (Exception e) {
            ExceptionHandler.logException(new Map<String, Object>{'className' => 'BroadcastMessageController','methodName' => 'createChatRecods', 'exceptionObj' => e,'isApiException' => false,'statusCode' => null,'chatId' => null,'moreDetails' => e.getMessage(),'apiResponse' => null});
            throw new AuraHandledException('Error in sendTemplateMessage: ' + e.getMessage());
        }
    }  

    /*
    *********************************************************
    @description     : Generate a cron expression based on the provided DateTime
    @param           : dt - DateTime object
    @return          : String representing the cron expression
    ********************************************************
    */
    public static String getCronExpression(DateTime dt) {
        String cronExpression = '0 ' + dt.minute() + ' ' + dt.hour() + ' ' + dt.day() + ' ' + dt.month() + ' ' + '?' + ' ' +  dt.year();
        return cronExpression;
    }

    /*
    *********************************************************
    @description     : Get broadcast groups by broadcast ID
    @param           : broadcastId - ID of the broadcast
    @return          : List of Broadcast_Group__c records associated with the broadcast
    ********************************************************
    */

    @AuraEnabled
    public static List<Broadcast_Group__c> getBroadcastGroupsByBroadcastId(String broadcastId) {
        try {
            if (String.isBlank(broadcastId)) {
                throw new AuraHandledException('Broadcast ID is required');
            }

            // Fetch the Broadcast record
            Broadcast__c broadcast = [
                SELECT Broadcast_Group_IDs__c 
                FROM Broadcast__c 
                WHERE Id = :broadcastId 
                WITH SECURITY_ENFORCED 
                LIMIT 1
            ];

            if (broadcast.Broadcast_Group_IDs__c == null) {
                return new List<Broadcast_Group__c>();
            }

            // Split the comma-separated group IDs and fetch related groups
            List<String> groupIds = broadcast.Broadcast_Group_IDs__c.split(',');
            return [
                SELECT Id, Name, Count_of_Members__c, Description__c, Object_Name__c, Phone_Field__c
                FROM Broadcast_Group__c 
                WHERE Id IN :groupIds 
                WITH SECURITY_ENFORCED
            ];
        } catch (Exception e) {
            ExceptionHandler.logException(new Map<String, Object>{'className' => 'BroadcastMessageController','methodName' => 'getBroadcastGroupsByBroadcastId', 'exceptionObj' => e,'isApiException' => false,'statusCode' => null,'chatId' => null,'moreDetails' => e.getMessage(),'apiResponse' => null});
            throw new AuraHandledException('Error fetching broadcast groups: ' + e.getMessage());
        }
    }

    /*
    *********************************************************
    @description     : Get broadcast group members by broadcast group ID
    @param           : groupId - ID of the broadcast group
    @return          : List of Broadcast_Group_Member__c records associated with the broadcast group
    ********************************************************
    */

    @AuraEnabled
    public static List<Broadcast_Group_Member__c> getBroadcastMembersByGroupId(String groupId) {
        try {
            if (String.isBlank(groupId)) {
                throw new AuraHandledException('Broadcast Group ID is required');
            }

            return [
                SELECT Id, Name, Contact_ID__r.Name, Phone_Number__c
                FROM Broadcast_Group_Member__c 
                WHERE Broadcast_Group_ID__c = :groupId 
                WITH SECURITY_ENFORCED
            ];
        } catch (Exception e) {
            ExceptionHandler.logException(new Map<String, Object>{'className' => 'BroadcastMessageController','methodName' => 'getBroadcastMembersByGroupId', 'exceptionObj' => e,'isApiException' => false,'statusCode' => null,'chatId' => null,'moreDetails' => e.getMessage(),'apiResponse' => null});
            throw new AuraHandledException('Error fetching broadcast group members: ' + e.getMessage());
        }
    }
}