@IsTest
public class CSVUploaderControllerTest {

    // --------------------------------------------------
    // Helper: Create Job Tracker
    // --------------------------------------------------
    private static Data_Feed_Job_Tracker__c createTracker() {
        Data_Feed_Job_Tracker__c tracker =
            new Data_Feed_Job_Tracker__c(
                File_Name__c = 'TestFile.csv',
                Operation_Type__c = 'Insert',
                Target_Object__c = 'Account',
                Status__c = 'Upload Complete'
            );

        insert tracker;
        return tracker;
    }


    // --------------------------------------------------
    // Mock: Successful AWS response
    // --------------------------------------------------
    private class PresignedUrlSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{"presignedUrl":"https://example.com/upload.csv"}'
            );
            return res;
        }
    }


    // --------------------------------------------------
    // Mock: Response without presignedUrl
    // --------------------------------------------------
    private class PresignedUrlMissingMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"message":"URL unavailable"}');
            return res;
        }
    }


    // --------------------------------------------------
    // Mock: Invalid JSON response
    // --------------------------------------------------
    private class PresignedUrlInvalidJsonMock
        implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('INVALID JSON');
            return res;
        }
    }


    // ==================================================
    // TEST 1: Create Job Tracker
    // ==================================================
    @IsTest
    static void testCreateDataFeedJobTracker() {

        Test.startTest();

        Id trackerId =
            CSVUploaderController.createDataFeedJobTracker(
                'Accounts.csv',
                'Insert',
                'Account'
            );

        Test.stopTest();

        Data_Feed_Job_Tracker__c tracker = [
            SELECT File_Name__c, Operation_Type__c, Target_Object__c
            FROM Data_Feed_Job_Tracker__c
            WHERE Id = :trackerId
        ];

        System.assertEquals('Accounts.csv', tracker.File_Name__c);
        System.assertEquals('Insert', tracker.Operation_Type__c);
        System.assertEquals('Account', tracker.Target_Object__c);
    }


    // ==================================================
    // TEST 2: Create Job Tracker - Invalid Inputs
    // ==================================================
    @IsTest
    static void testCreateDataFeedJobTrackerInvalid() {

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            CSVUploaderController.createDataFeedJobTracker(
                '',
                'Insert',
                'Account'
            );
        } catch (Exception e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }


    // ==================================================
    // TEST 3: Upload Successful Rows
    // ==================================================
    @IsTest
    static void testUploadToApexSuccess() {

        Data_Feed_Job_Tracker__c tracker = createTracker();

        List<String> jsonRows = new List<String>{
            '{"Name":"Upload Account 1"}',
            '{"Name":"Upload Account 2"}'
        };

        Test.startTest();

        UploadChunkResult result =
            CSVUploaderController.uploadToApex(
                jsonRows,
                'TestFile.csv',
                tracker.Id
            );

        Test.stopTest();

        System.assertEquals(2, result.successCount);
        System.assertEquals(0, result.failedCount);
        System.assertEquals(0, result.failedRows.size());

        System.assertEquals(
            2,
            [
                SELECT COUNT()
                FROM Data_Feed_Record__c
                WHERE Data_Feed_Job_Tracker__c = :tracker.Id
            ]
        );
    }


    // ==================================================
    // TEST 4: Upload Empty List
    // ==================================================
    @IsTest
    static void testUploadToApexEmptyList() {

        Data_Feed_Job_Tracker__c tracker = createTracker();

        Test.startTest();

        UploadChunkResult result =
            CSVUploaderController.uploadToApex(
                new List<String>(),
                'TestFile.csv',
                tracker.Id
            );

        Test.stopTest();

        System.assertEquals(0, result.successCount);
        System.assertEquals(0, result.failedCount);
        System.assertEquals(0, result.failedRows.size());
    }


    // ==================================================
    // TEST 5: Upload Null List
    // ==================================================
    @IsTest
    static void testUploadToApexNullList() {

        Data_Feed_Job_Tracker__c tracker = createTracker();

        Test.startTest();

        UploadChunkResult result =
            CSVUploaderController.uploadToApex(
                null,
                'TestFile.csv',
                tracker.Id
            );

        Test.stopTest();

        System.assertEquals(0, result.successCount);
        System.assertEquals(0, result.failedCount);
    }


    // ==================================================
    // TEST 6: Upload Null Job Tracker ID
    // ==================================================
    @IsTest
    static void testUploadToApexNullTracker() {

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            CSVUploaderController.uploadToApex(
                new List<String>{ '{"Name":"Test"}' },
                'TestFile.csv',
                null
            );
        } catch (Exception e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }


    // ==================================================
    // TEST 7: Partial Upload Failure
    // ==================================================
    @IsTest
    static void testUploadToApexPartialFailure() {

        Data_Feed_Job_Tracker__c tracker = createTracker();

        List<String> jsonRows = new List<String>{
            '{"Name":"Valid Account"}',
            null
        };

        Test.startTest();

       UploadChunkResult result =
            CSVUploaderController.uploadToApex(
                jsonRows,
                'TestFile.csv',
                tracker.Id
            );

        Test.stopTest();

        System.assertEquals(1, result.successCount);
        System.assertEquals(1, result.failedCount);
        System.assertEquals(1, result.failedRows.size());

        System.assert(
            result.failedRows[0].contains('Chunk row 2')
        );
    }


    // ==================================================
    // TEST 8: Update Job Tracker Status
    // ==================================================
    @IsTest
    static void testUpdateJobTrackerStatus() {

        Data_Feed_Job_Tracker__c tracker = createTracker();

        Test.startTest();

        CSVUploaderController.updateDataFeedJobTrackerStatus(
            tracker.Id,
            'Completed'
        );

        Test.stopTest();

        Data_Feed_Job_Tracker__c updatedTracker = [
            SELECT Status__c
            FROM Data_Feed_Job_Tracker__c
            WHERE Id = :tracker.Id
        ];

        System.assertEquals('Completed', updatedTracker.Status__c);
    }


    // ==================================================
    // TEST 9: Update Status - Null Tracker ID
    // ==================================================
    @IsTest
    static void testUpdateStatusNullTracker() {

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            CSVUploaderController.updateDataFeedJobTrackerStatus(
                null,
                'Completed'
            );
        } catch (Exception e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }


    // ==================================================
    // TEST 10: Update Status - Blank Status
    // ==================================================
    @IsTest
    static void testUpdateStatusBlankStatus() {

        Data_Feed_Job_Tracker__c tracker = createTracker();

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            CSVUploaderController.updateDataFeedJobTrackerStatus(
                tracker.Id,
                ''
            );
        } catch (Exception e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }


    // ==================================================
    // TEST 11: Update Status - Missing Tracker Record
    // ==================================================
    @IsTest
    static void testUpdateStatusMissingRecord() {

        Id trackerId = createTracker().Id;

        delete [
            SELECT Id
            FROM Data_Feed_Job_Tracker__c
            WHERE Id = :trackerId
        ];

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            CSVUploaderController.updateDataFeedJobTrackerStatus(
                trackerId,
                'Completed'
            );
        } catch (Exception e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }


    // ==================================================
    // TEST 12: Invoke Batch
    // ==================================================
    @IsTest
    static void testInvokeProcessDataFeedBatch() {

        Data_Feed_Job_Tracker__c tracker = createTracker();

        Test.startTest();

        CSVUploaderController.invokeProcessDataFeedBatch(
            tracker.Id,
            'TestFile.csv',
            'Insert',
            'Account'
        );

        Test.stopTest();

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE ApexClass.Name = 'ProcessDataFeed'
            ]
        );
    }


    // ==================================================
    // TEST 13: Invoke Batch - Null Tracker ID
    // ==================================================
    @IsTest
    static void testInvokeBatchNullTracker() {

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            CSVUploaderController.invokeProcessDataFeedBatch(
                null,
                'TestFile.csv',
                'Insert',
                'Account'
            );
        } catch (Exception e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }


    // ==================================================
    // TEST 14: Get Presigned URL Success
    // ==================================================
    @IsTest
    static void testGetPresignedUrlSuccess() {

        Test.setMock(
            HttpCalloutMock.class,
            new PresignedUrlSuccessMock()
        );

        Test.startTest();

        String result =
            CSVUploaderController.getPresignedUrl('TestFile.csv');

        Test.stopTest();

        System.assertEquals(
            'https://example.com/upload.csv',
            result
        );
    }


    // ==================================================
    // TEST 15: Presigned URL Missing From Response
    // ==================================================
    @IsTest
    static void testGetPresignedUrlMissing() {

        Test.setMock(
            HttpCalloutMock.class,
            new PresignedUrlMissingMock()
        );

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            CSVUploaderController.getPresignedUrl('TestFile.csv');
        } catch (Exception e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }


    // ==================================================
    // TEST 16: Invalid JSON Response
    // ==================================================
    @IsTest
    static void testGetPresignedUrlInvalidJson() {

        Test.setMock(
            HttpCalloutMock.class,
            new PresignedUrlInvalidJsonMock()
        );

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            CSVUploaderController.getPresignedUrl('TestFile.csv');
        } catch (Exception e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }
}