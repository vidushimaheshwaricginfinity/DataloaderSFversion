public with sharing class DeleteUndeleteController {

    public class OperationResult {
        @AuraEnabled public Integer totalRecords { get; set; }
        @AuraEnabled public Integer successCount { get; set; }
        @AuraEnabled public Integer failureCount { get; set; }
        @AuraEnabled public List<String> messages { get; set; }
        @AuraEnabled public String jobId { get; set; }

        public OperationResult() {
            totalRecords = 0;
            successCount = 0;
            failureCount = 0;
            messages = new List<String>();
            jobId = null;
        }
    }

    private class PreparedIds {
        public Set<Id> validIds = new Set<Id>();
        public List<String> messages = new List<String>();
    }

    private static String generateJobId(){
        return EncodingUtil.convertToHex(Crypto.generateAesKey(128));
    }

    private static Delete_Undelete_Record__c createLog(String recordId, String operation, String objectApiName, String jobId, String status, String errorMessage){
        return new Delete_Undelete_Record__c(
            Record_ID__c = recordId,
            Operation__c = operation,
            Target_Object__c = objectApiName,
            Job_Id__c = jobId,
            Status__c = status,
            Error_Message__c = errorMessage,
            Processed_Date__c = System.now(),
            User__c = UserInfo.getUserId()
        );
    }

    private static Schema.SObjectType getObjectType(
        String objectApiName
    ) {
        if (String.isBlank(objectApiName)) {
            throw new AuraHandledException(
                'Object API name is required.'
            );
        }

        Schema.SObjectType objectType =
            Schema.getGlobalDescribe().get(objectApiName.trim());

        if (objectType == null) {
            throw new AuraHandledException(
                'Invalid Salesforce object: ' + objectApiName
            );
        }

        return objectType;
    }

    private static PreparedIds prepareIds(
        String objectApiName,
        List<String> recordIds,
        Schema.SObjectType objectType
    ) {
        PreparedIds prepared = new PreparedIds();

        if (recordIds == null || recordIds.isEmpty()) {
            prepared.messages.add('No record IDs were provided.');
            return prepared;
        }

        for (String rawId : recordIds) {
            if (String.isBlank(rawId)) {
                continue;
            }

            try {
                Id recordId = Id.valueOf(rawId.trim());

                if (recordId.getSObjectType() != objectType) {
                    prepared.messages.add(
                        'ID belongs to a different object: ' + rawId
                    );
                    continue;
                }

                prepared.validIds.add(recordId);

            } catch (Exception e) {
                prepared.messages.add(
                    'Invalid Salesforce ID: ' + rawId
                );
            }
        }

        return prepared;
    }

    // @AuraEnabled
    // public static OperationResult deleteRecords(
    //     String objectApiName,
    //     List<String> recordIds
    // ) {
    //     OperationResult result = new OperationResult();

    //     Schema.SObjectType objectType =
    //         getObjectType(objectApiName);

    //     if (!objectType.getDescribe().isDeletable()) {
    //         throw new AuraHandledException(
    //             'You do not have permission to delete records of ' +
    //             objectApiName + '.'
    //         );
    //     }

    //     PreparedIds prepared = prepareIds(
    //         objectApiName,
    //         recordIds,
    //         objectType
    //     );

    //     result.messages.addAll(prepared.messages);
    //     result.totalRecords =
    //         recordIds == null ? 0 : recordIds.size();

    //     if (prepared.validIds.isEmpty()) {
    //         result.failureCount = result.totalRecords;
    //         return result;
    //     }

    //     List<SObject> recordsToDelete = new List<SObject>();

    //     for (Id recordId : prepared.validIds) {
    //         SObject record = objectType.newSObject();
    //         record.put('Id', recordId);
    //         recordsToDelete.add(record);
    //     }

    //     Database.DeleteResult[] deleteResults =
    //         Database.delete(recordsToDelete, false);

    //     for (Integer i = 0; i < deleteResults.size(); i++) {
    //         if (deleteResults[i].isSuccess()) {
    //             result.successCount++;
    //             result.messages.add(
    //                 'Deleted successfully: ' +
    //                 recordsToDelete[i].get('Id')
    //             );
    //         } else {
    //             result.failureCount++;

    //             for (Database.Error err :
    //                 deleteResults[i].getErrors()) {
    //                 result.messages.add(
    //                     'Delete failed for ' +
    //                     recordsToDelete[i].get('Id') +
    //                     ': ' + err.getMessage()
    //                 );
    //             }
    //         }
    //     }

	// 	Integer invalidCount = result.totalRecords - prepared.validIds.size();
	// 	result.failureCount += invalidCount;

    //     return result;
    // }

    
    @AuraEnabled
    public static OperationResult deleteRecords(
        String objectApiName,
        List<String> recordIds
    ) {
        OperationResult result = new OperationResult();
        List<Delete_Undelete_Record__c> logsToInsert =
            new List<Delete_Undelete_Record__c>();

        Schema.SObjectType objectType = getObjectType(objectApiName);

        if (!objectType.getDescribe().isDeletable()) {
            throw new AuraHandledException(
                'You do not have permission to delete records of ' +
                objectApiName + '.'
            );
        }

        result.jobId = generateJobId();
        result.totalRecords = recordIds == null ? 0 : recordIds.size();

        if (recordIds == null || recordIds.isEmpty()) {
            result.messages.add('No record IDs were provided.');
            return result;
        }

        // Keep a mapping to the original CSV rows so every row gets a log,
        // including invalid IDs and duplicate IDs.
        List<Id> validIds = new List<Id>();
        List<Integer> validRowIndexes = new List<Integer>();

        for (Integer i = 0; i < recordIds.size(); i++) {
            String rawId = recordIds[i];
            String status = 'Failed';
            String errorMessage;
            Id parsedId;

            if (String.isBlank(rawId)) {
                errorMessage = 'Record ID is blank.';
            } else {
                try {
                    parsedId = Id.valueOf(rawId.trim());

                    if (parsedId.getSObjectType() != objectType) {
                        errorMessage =
                            'ID belongs to a different object: ' + rawId;
                        parsedId = null;
                    }
                } catch (Exception e) {
                    errorMessage = 'Invalid Salesforce ID: ' + rawId;
                }
            }

            if (parsedId == null) {
                logsToInsert.add(
                    createLog(
                        rawId,
                        'Delete',
                        objectApiName,
                        result.jobId,
                        status,
                        errorMessage
                    )
                );

                result.failureCount++;
                result.messages.add(errorMessage);
            } else {
                validIds.add(parsedId);
                validRowIndexes.add(i);
            }
        }

        if (!validIds.isEmpty()) {
            List<SObject> recordsToDelete = new List<SObject>();

            for (Id recordId : validIds) {
                SObject record = objectType.newSObject();
                record.put('Id', recordId);
                recordsToDelete.add(record);
            }

            // allOrNone=false allows each record to succeed or fail independently.
            Database.DeleteResult[] deleteResults =
                Database.delete(recordsToDelete, false);

            for (Integer i = 0; i < deleteResults.size(); i++) {
                Id recordId = validIds[i];

                if (deleteResults[i].isSuccess()) {
                    result.successCount++;

                    logsToInsert.add(
                        createLog(
                            String.valueOf(recordId),
                            'Delete',
                            objectApiName,
                            result.jobId,
                            'Success',
                            null
                        )
                    );

                    result.messages.add(
                        'Deleted successfully: ' + recordId
                    );
                } else {
                    String errorMessage = '';

                    for (Database.Error err : deleteResults[i].getErrors()) {
                        if (errorMessage != '') {
                            errorMessage += '; ';
                        }
                        errorMessage += err.getMessage();
                    }

                    result.failureCount++;

                    logsToInsert.add(
                        createLog(
                            String.valueOf(recordId),
                            'Delete',
                            objectApiName,
                            result.jobId,
                            'Failed',
                            errorMessage
                        )
                    );

                    result.messages.add(
                        'Delete failed for ' + recordId +
                        ': ' + errorMessage
                    );
                }
            }
        }

        // Save the logs after attempting the record operations.
        if (!logsToInsert.isEmpty()) {
            Database.SaveResult[] logResults =
                Database.insert(logsToInsert, false);

            for (Integer i = 0; i < logResults.size(); i++) {
                if (!logResults[i].isSuccess()) {
                    for (Database.Error err : logResults[i].getErrors()) {
                        result.messages.add(
                            'Could not save operation log: ' +
                            err.getMessage()
                        );
                    }
                }
            }
        }

        return result;
    }


    // @AuraEnabled
    // public static OperationResult undeleteRecords(
    //     String objectApiName,
    //     List<String> recordIds
    // ) {
    //     OperationResult result = new OperationResult();

    //     Schema.SObjectType objectType =
    //         getObjectType(objectApiName);

    //     PreparedIds prepared = prepareIds(
    //         objectApiName,
    //         recordIds,
    //         objectType
    //     );

    //     result.messages.addAll(prepared.messages);
    //     result.totalRecords =
    //         recordIds == null ? 0 : recordIds.size();

    //     if (prepared.validIds.isEmpty()) {
    //         result.failureCount = result.totalRecords;
    //         return result;
    //     }

	// 	// Create a local variable for the dynamic SOQL bind.
	// 	Set<Id> validIds = prepared.validIds;

	// 	String queryString =
	// 		'SELECT Id, IsDeleted FROM ' +
	// 		objectType.getDescribe().getName() +
	// 		' WHERE Id IN :validIds ALL ROWS';

	// 	List<SObject> queriedRecords = Database.query(queryString);

    //     List<SObject> recordsToRestore = new List<SObject>();
    //     Set<Id> foundIds = new Set<Id>();

    //     for (SObject record : queriedRecords) {
    //         Id recordId = (Id) record.get('Id');
    //         foundIds.add(recordId);

    //         if ((Boolean) record.get('IsDeleted')) {
    //             recordsToRestore.add(record);
    //         } else {
    //             result.messages.add(
    //                 'Skipped; record is not deleted: ' + recordId
    //             );
    //         }
    //     }

    //     for (Id recordId : prepared.validIds) {
    //         if (!foundIds.contains(recordId)) {
    //             result.messages.add(
    //                 'Record not found or not available to restore: ' +
    //                 recordId
    //             );
    //         }
    //     }

	// 	if (recordsToRestore.isEmpty()) {
	// 		result.failureCount = result.totalRecords - result.successCount;
	// 		return result;
	// 	}

	// 	Database.UndeleteResult[] undeleteResults =
	// 		Database.undelete(recordsToRestore, false);

	// 	for (Integer i = 0; i < undeleteResults.size(); i++) {
	// 		if (undeleteResults[i].isSuccess()) {
	// 			result.successCount++;
	// 			result.messages.add(
	// 				'Restored successfully: ' +
	// 				recordsToRestore[i].get('Id')
	// 			);
	// 		} else {
	// 			result.failureCount++;

	// 			for (Database.Error err : undeleteResults[i].getErrors()) {
	// 				result.messages.add(
	// 					'Restore failed for ' +
	// 					recordsToRestore[i].get('Id') +
	// 					': ' + err.getMessage()
	// 				);
	// 			}
	// 		}
	// 	}

	// 	result.failureCount = result.totalRecords - result.successCount;
	// 	return result;
    // }

    
    @AuraEnabled
    public static OperationResult undeleteRecords(
        String objectApiName,
        List<String> recordIds
    ) {
        OperationResult result = new OperationResult();
        List<Delete_Undelete_Record__c> logsToInsert =
            new List<Delete_Undelete_Record__c>();

        Schema.SObjectType objectType = getObjectType(objectApiName);

        result.jobId = generateJobId();
        result.totalRecords = recordIds == null ? 0 : recordIds.size();

        if (recordIds == null || recordIds.isEmpty()) {
            result.messages.add('No record IDs were provided.');
            return result;
        }

        List<Id> validIds = new List<Id>();

        // Validate every CSV row individually.
        for (String rawId : recordIds) {
            Id parsedId = null;
            String errorMessage;

            if (String.isBlank(rawId)) {
                errorMessage = 'Record ID is blank.';
            } else {
                try {
                    parsedId = Id.valueOf(rawId.trim());

                    if (parsedId.getSObjectType() != objectType) {
                        errorMessage =
                            'ID belongs to a different object: ' + rawId;
                        parsedId = null;
                    }
                } catch (Exception e) {
                    errorMessage = 'Invalid Salesforce ID: ' + rawId;
                }
            }

            if (parsedId == null) {
                result.failureCount++;

                logsToInsert.add(
                    createLog(
                        rawId,
                        'Undelete',
                        objectApiName,
                        result.jobId,
                        'Failed',
                        errorMessage
                    )
                );

                result.messages.add(errorMessage);
            } else {
                validIds.add(parsedId);
            }
        }

        if (!validIds.isEmpty()) {
            Set<Id> idsToQuery = new Set<Id>();
            idsToQuery.addAll(validIds);

            String queryString =
                'SELECT Id, IsDeleted FROM ' +
                objectType.getDescribe().getName() +
                ' WHERE Id IN :idsToQuery ALL ROWS';

            List<SObject> queriedRecords = Database.query(queryString);

            Map<Id, SObject> recordsById = new Map<Id, SObject>();
            for (SObject record : queriedRecords) {
                recordsById.put((Id) record.get('Id'), record);
            }

            List<SObject> recordsToRestore = new List<SObject>();
            List<Id> restoreIds = new List<Id>();

            // Process each valid input row. Duplicate IDs are logged separately.
            for (Id recordId : validIds) {
                SObject record = recordsById.get(recordId);

                if (record == null) {
                    result.failureCount++;

                    logsToInsert.add(
                        createLog(
                            String.valueOf(recordId),
                            'Undelete',
                            objectApiName,
                            result.jobId,
                            'Failed',
                            'Record not found or not available to restore.'
                        )
                    );

                    result.messages.add(
                        'Record not found or not available to restore: ' +
                        recordId
                    );
                } else if (!(Boolean) record.get('IsDeleted')) {
                    result.failureCount++;

                    logsToInsert.add(
                        createLog(
                            String.valueOf(recordId),
                            'Undelete',
                            objectApiName,
                            result.jobId,
                            'Skipped',
                            'Record is not deleted.'
                        )
                    );

                    result.messages.add(
                        'Skipped; record is not deleted: ' + recordId
                    );
                } else {
                    recordsToRestore.add(record);
                    restoreIds.add(recordId);
                }
            }

            if (!recordsToRestore.isEmpty()) {
                Database.UndeleteResult[] undeleteResults =
                    Database.undelete(recordsToRestore, false);

                for (Integer i = 0; i < undeleteResults.size(); i++) {
                    Id recordId = restoreIds[i];

                    if (undeleteResults[i].isSuccess()) {
                        result.successCount++;

                        logsToInsert.add(
                            createLog(
                                String.valueOf(recordId),
                                'Undelete',
                                objectApiName,
                                result.jobId,
                                'Success',
                                null
                            )
                        );

                        result.messages.add(
                            'Restored successfully: ' + recordId
                        );
                    } else {
                        String errorMessage = '';

                        for (Database.Error err :
                            undeleteResults[i].getErrors()) {
                            if (errorMessage != '') {
                                errorMessage += '; ';
                            }
                            errorMessage += err.getMessage();
                        }

                        result.failureCount++;

                        logsToInsert.add(
                            createLog(
                                String.valueOf(recordId),
                                'Undelete',
                                objectApiName,
                                result.jobId,
                                'Failed',
                                errorMessage
                            )
                        );

                        result.messages.add(
                            'Restore failed for ' + recordId +
                            ': ' + errorMessage
                        );
                    }
                }
            }
        }

        if (!logsToInsert.isEmpty()) {
            Database.SaveResult[] logResults =
                Database.insert(logsToInsert, false);

            for (Integer i = 0; i < logResults.size(); i++) {
                if (!logResults[i].isSuccess()) {
                    for (Database.Error err : logResults[i].getErrors()) {
                        result.messages.add(
                            'Could not save operation log: ' +
                            err.getMessage()
                        );
                    }
                }
            }
        }

        return result;
    }


    @AuraEnabled(cacheable=true)
    public static List<Delete_Undelete_Record__c> getOperationLogs(
        String jobId,
        Integer pageSize,
        Integer offsetValue
    ) {
        if (String.isBlank(jobId)) {
            throw new AuraHandledException('Job ID is required.');
        }

        Integer safePageSize =
            pageSize == null ? 50 : Math.min(Math.max(pageSize, 1), 200);

        Integer safeOffset =
            offsetValue == null ? 0 : Math.max(offsetValue, 0);

        return [
            SELECT Id, Name, Record_ID__c, Operation__c,
                Target_Object__c, Status__c, Error_Message__c,
                Job_Id__c, Processed_Date__c, User__c
            FROM Delete_Undelete_Record__c
            WHERE Job_Id__c = :jobId
            ORDER BY CreatedDate DESC
            LIMIT :safePageSize
            OFFSET :safeOffset
        ];
    }
}