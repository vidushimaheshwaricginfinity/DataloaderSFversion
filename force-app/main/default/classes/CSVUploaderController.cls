public without sharing class CSVUploaderController {
    @AuraEnabled
    public static UploadChunkResult uploadToApex(
        List<String> jsonDataList,
        String fileName,
        Id jobTrackerId
    ) {
        if (jobTrackerId == null) {
            throw new AuraHandledException(
                'A job tracker ID is required.'
            );
        }

        UploadChunkResult response = new UploadChunkResult();

        if (jsonDataList == null || jsonDataList.isEmpty()) {
            return response;
        }

        List<Data_Feed_Record__c> records =
            new List<Data_Feed_Record__c>();

        for (String jsonString : jsonDataList) {
            Data_Feed_Record__c record =
                new Data_Feed_Record__c();

            record.Data_Feed_Record_JSON__c = jsonString;
            record.File_Name__c = fileName;
            record.Data_Feed_Job_Tracker__c = jobTrackerId;
            record.Is_Processed__c = false;
            record.Is_Failed__c = false;

            records.add(record);
        }

        // Partial success: valid rows are inserted even if others fail.
        Database.SaveResult[] results = Database.insert(records, false);

        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()){
                response.successCount++;
            }else{
                response.failedCount++;
                for (Database.Error err : results[i].getErrors()) {
                    response.failedRows.add(
                        'Chunk row ' + (i + 1) + ': ' +
                        err.getMessage()
                    );
                }
            }
        }

        if (response.failedCount > 0) {
            System.debug(
                LoggingLevel.ERROR,
                'Failed staging rows: ' +
                String.join(response.failedRows, ' | ')
            );
        }

        return response;
    }

    @AuraEnabled
    public static void updateDataFeedJobTrackerStatus(
        Id jobTrackerId,
        String status
    ) {
        if (jobTrackerId == null) {
            throw new AuraHandledException(
                'A job tracker ID is required.'
            );
        }

        if (String.isBlank(status)) {
            throw new AuraHandledException(
                'A status is required.'
            );
        }

        try {
            Data_Feed_Job_Tracker__c tracker = [
                SELECT Id, Status__c
                FROM Data_Feed_Job_Tracker__c
                WHERE Id = :jobTrackerId
                LIMIT 1
            ];

            tracker.Status__c = status;
            update tracker;

        } catch (Exception e) {
            throw new AuraHandledException(
                'Unable to update job tracker: ' + e.getMessage()
            );
        }
    }

    @AuraEnabled
    public static void invokeProcessDataFeedBatch(
        Id jobTrackerId,
        String fileName,
        String operationType,
        String targetObject
    ) {
        if (jobTrackerId == null) {
            throw new AuraHandledException(
                'A job tracker ID is required.'
            );
        }

        Database.executeBatch(
            new ProcessDataFeed(
                fileName,
                operationType,
                targetObject,
                jobTrackerId
            ),
            200
        );
    }

    @AuraEnabled
    public static String getPresignedUrl(String fileName) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:AWS_API/getPresignedUrl');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(new Map<String, Object>{'fileName' => fileName}));
            HttpResponse res = (new Http()).send(req);
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            System.debug(result);
            if (result.containsKey('presignedUrl')) 
            {
                String url = (String) result.get('presignedUrl');
                System.debug(url);
                return url;
            }
            throw new AuraHandledException('Presigned URL not found in response');
        } catch(Exception e) {
            throw new AuraHandledException('Error getting presigned URL: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Id createDataFeedJobTracker(
        String fileName,
        String operationType,
        String targetObject,
        String selectedMappingName
    ) {
        if (String.isBlank(fileName) ||
            String.isBlank(operationType) ||
            String.isBlank(targetObject)) {
            throw new AuraHandledException(
                'File name, operation type, and target object are required.'
            );
        }

        Data_Feed_Job_Tracker__c tracker =
            new Data_Feed_Job_Tracker__c();

        tracker.File_Name__c = fileName;
        tracker.Operation_Type__c = operationType;
        tracker.Target_Object__c = targetObject;

        if (String.isNotBlank(selectedMappingName)) {
            tracker.Selected_Mapping_Name__c = selectedMappingName;
        }

        insert tracker;

        return tracker.Id;
    }
}