/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : URLCSVImportQueueable
 * Author          : <YourName>
 * Created Date    : Sep 23, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Sep 23, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Sep 23, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public class URLCSVImportQueueable implements Queueable, Database.AllowsCallouts {

    private String sourceUrl;
    private String fileName;
    private String operationType;
    private String targetObject;
    private Integer page;
    private Integer pageSize;

    public URLCSVImportQueueable(
        String sourceUrl,
        String fileName,
        String operationType,
        String targetObject,
        Integer page,
        Integer pageSize
    ) {
        this.sourceUrl = sourceUrl;
        this.fileName = fileName;
        this.operationType = operationType;
        this.targetObject = targetObject;
        this.page = page;
        this.pageSize = pageSize;
    }

    public void execute(QueueableContext context) {

        /*
         * 1. Build the URL for the current page
         */
        String endpoint = buildPageUrl(
            sourceUrl,
            page,
            pageSize
        );

        /*
         * 2. Make the API call
         */
        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        request.setEndpoint(endpoint);
        request.setTimeout(120000);

        HttpResponse response;

        try {
            response = new Http().send(request);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,'URL CSV import callout failed: ' + e.getMessage());
            return;
        }

        /*
         * 3. Validate HTTP response
         */
        if (response.getStatusCode() < 200 ||
            response.getStatusCode() >= 300) {
			
			System.debug(
				LoggingLevel.ERROR,
				'URL CSV API returned HTTP ' +
				response.getStatusCode() +
				': ' +
				response.getStatus()
    		);
            return;
        }

        /*
         * 4. Validate that the response is CSV
         */
        String contentType = response.getHeader('Content-Type');

        if (String.isBlank(contentType) ||
            !contentType.toLowerCase().contains('text/csv')) {

            System.debug(LoggingLevel.ERROR,'Source API did not return a CSV response.');

            return;
        }

        /*
         * 5. Get CSV body
         */
        String csvBody = response.getBody();

        if (String.isBlank(csvBody)) {

            System.debug(LoggingLevel.ERROR,'Source API returned an empty CSV.');

            return;
        }

        /*
         * 6. Convert CSV rows into JSON records
         */
        List<Object> parsedRecords;

        try {
            parsedRecords = ConvertCSVToJSON.parseCSV(
                Blob.valueOf(csvBody)
            );
        } catch (Exception e) {
			System.debug(LoggingLevel.ERROR,'Unable to parse CSV: ' + e.getMessage());

            return;
        }

        /*
         * 7. Convert every CSV row into a
         *    Data_Feed_Record__c staging record
         */
        List<Data_Feed_Record__c> stagingRecords =
            new List<Data_Feed_Record__c>();

        for (Object record : parsedRecords) {

            Data_Feed_Record__c stagingRecord =
                new Data_Feed_Record__c();

            stagingRecord.Data_Feed_Record_JSON__c =
                JSON.serialize(record);

            /*
             * IMPORTANT:
             *
             * Use the same logical file name for
             * every page.
             *
             * Do NOT use:
             * work-items-page-1.csv
             * work-items-page-2.csv
             *
             * because ProcessDataFeed uses File_Name__c
             * to find all staging records.
             */
            stagingRecord.File_Name__c = fileName;

            stagingRecords.add(stagingRecord);
        }

        /*
         * 8. Insert this page's staging records
         */
        if (!stagingRecords.isEmpty()) {
            Database.insert(stagingRecords);
        }

        /*
         * 9. Check whether another page exists
         */
        Boolean hasMore = parseBooleanHeader(
            response.getHeader('x-has-more')
        );

        if (hasMore) {

            /*
             * More API data exists.
             *
             * Queue the next page.
             */
            System.enqueueJob(
                new URLCSVImportQueueable(
                    sourceUrl,
                    fileName,
                    operationType,
                    targetObject,
                    page + 1,
                    pageSize
                )
            );

        } else {

            /*
             * This was the final page.
             *
             * Changing the tracker to Upload Complete
             * will activate the existing
             * DataFeedJobTrigger.
             */
            updateJobTrackerStatus(
                'Upload Complete'
            );
        }
    }

    /*
     * Builds:
     *
     * https://.../api/Data?page=1&pageSize=20
     */
    private static String buildPageUrl(
        String sourceUrl,
        Integer page,
        Integer pageSize
    ) {
        String separator =
            sourceUrl.contains('?') ? '&' : '?';

        return sourceUrl +
            separator +
            'page=' +
            page +
            '&pageSize=' +
            pageSize;
    }

    /*
     * Converts the API header:
     *
     * x-has-more: true
     *
     * into Boolean true.
     */
    private static Boolean parseBooleanHeader(String value) {

        if (String.isBlank(value)) {
            return false;
        }

        return value.toLowerCase() == 'true';
    }

    /*
     * Updates the existing Job Tracker.
     *
     * We identify it using the same:
     * File Name + Operation Type
     * combination used by the existing system.
     */
    private void updateJobTrackerStatus(String status) {

		List<Data_Feed_Job_Tracker__c> trackers = [
			SELECT Id, Status__c
			FROM Data_Feed_Job_Tracker__c
			WHERE File_Name__c = :fileName
			AND Operation_Type__c = :operationType
			ORDER BY CreatedDate DESC
			LIMIT 1
		];

		if (trackers.isEmpty()) {
			return;
		}

		Data_Feed_Job_Tracker__c tracker = trackers[0];
		tracker.Status__c = status;

		update tracker;
	}
}