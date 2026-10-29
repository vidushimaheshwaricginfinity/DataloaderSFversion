/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : URLCSVImportController
 * Author          : Karan Singh Bisht
 * Created Date    : Sep 23, 2026
 * Last Modified By: Karan Singh Bisht
 * Last Modified On: Sep 23, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Sep 23, 2026  │ Karan Singh Bisht   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public without sharing class URLCSVImportController {

    // Fixed page size for the POC.
    private static final Integer PAGE_SIZE = 200;


    /*
     * ============================================================
     * PREVIEW URL
     * ============================================================
     *
     * Called when the user clicks "Next" after entering the URL.
     *
     * It fetches page 1 only to discover the CSV headers.
     * It does NOT create Data_Feed_Record__c records.
     */
    @AuraEnabled
    public static URLPreviewResponse previewUrl(String sourceUrl) {

        if (String.isBlank(sourceUrl)) {
            throw new AuraHandledException('Source URL is required.');
        }

        HttpRequest request = new HttpRequest();

        request.setMethod('GET');
        request.setEndpoint(
            buildPageUrl(sourceUrl, 1, PAGE_SIZE)
        );

        request.setTimeout(120000);

        HttpResponse response;

        try {
            response = new Http().send(request);
        } catch (Exception e) {
            throw new AuraHandledException(
                'Unable to connect to the source API: ' + e.getMessage()
            );
        }

        if (response.getStatusCode() < 200 ||
            response.getStatusCode() >= 300) {

            throw new AuraHandledException(
                'Source API returned HTTP ' +
                response.getStatusCode() +
                ': ' +
                response.getStatus()
            );
        }

        String contentType = response.getHeader('Content-Type');

        if (String.isBlank(contentType) ||
            !contentType.toLowerCase().contains('text/csv')) {

            throw new AuraHandledException(
                'The source API did not return a CSV response.'
            );
        }

        String csvBody = response.getBody();

        if (String.isBlank(csvBody)) {
            throw new AuraHandledException(
                'The source API returned an empty CSV.'
            );
        }

        /*
         * The first line of the CSV contains the headers.
         *
         * Example:
         *
         * ID,WORK ITEM TYPE,TITLE
         *
         */
        List<String> headers = extractHeaders(csvBody);

        if (headers.isEmpty()) {
            throw new AuraHandledException(
                'No CSV headers were found in the API response.'
            );
        }

        URLPreviewResponse result = new URLPreviewResponse();

        result.headers = headers;

        result.page = parseIntegerHeader(
            response.getHeader('x-page'),
            1
        );

        result.pageSize = parseIntegerHeader(
            response.getHeader('x-page-size'),
            PAGE_SIZE
        );

        result.totalCount = parseIntegerHeader(
            response.getHeader('x-total-count'),
            0
        );

        result.hasMore = parseBooleanHeader(
            response.getHeader('x-has-more')
        );

        return result;
    }


    /*
     * ============================================================
     * START IMPORT
     * ============================================================
     *
     * Called only after the user has completed or selected
     * a mapping.
     *
     * At this point the mapping MUST already exist.
     */
    @AuraEnabled
    public static String startImport(
        String sourceUrl,
        String fileName,
        String operationType,
        String targetObject
    ) {

        if (String.isBlank(sourceUrl)) {
            throw new AuraHandledException(
                'Source URL is required.'
            );
        }

        if (String.isBlank(fileName)) {
            throw new AuraHandledException(
                'Mapping file name is required.'
            );
        }

        if (String.isBlank(operationType)) {
            throw new AuraHandledException(
                'Operation type is required.'
            );
        }

        if (String.isBlank(targetObject)) {
            throw new AuraHandledException(
                'Target object is required.'
            );
        }

        /*
         * Create the Job Tracker.
         *
         * IMPORTANT:
         * We do NOT set Upload Complete here.
         *
         * The Queueable must fetch all pages first.
         */
        Data_Feed_Job_Tracker__c jobTracker =
            new Data_Feed_Job_Tracker__c();

        jobTracker.File_Name__c = fileName;
        jobTracker.Operation_Type__c = operationType;
        jobTracker.Target_Object__c = targetObject;
        jobTracker.Status__c = 'Ready for Processing';

        insert jobTracker;


        /*
         * Start the first page.
         *
         * The Queueable will handle:
         *
         * page 1
         *    ↓
         * page 2
         *    ↓
         * page 3
         *    ↓
         * ...
         *    ↓
         * last page
         *
         * Only the last Queueable will change the Job Tracker
         * to "Upload Complete".
         */
        System.enqueueJob(
            new URLCSVImportQueueable(
                sourceUrl,
                fileName,
                operationType,
                targetObject,
                1,
                PAGE_SIZE
            )
        );

        return 'URL CSV import started successfully.';
    }


    /*
     * ============================================================
     * BUILD PAGINATED URL
     * ============================================================
     *
     * Converts:
     *
     * https://api.example.com/api/Data
     *
     * into:
     *
     * https://api.example.com/api/Data?page=1&pageSize=20
     */
    private static String buildPageUrl(
        String sourceUrl,
        Integer page,
        Integer pageSize
    ) {

        String separator = sourceUrl.contains('?')
            ? '&'
            : '?';

        return sourceUrl +
            separator +
            'page=' +
            page +
            '&pageSize=' +
            pageSize;
    }


    /*
     * ============================================================
     * EXTRACT CSV HEADERS
     * ============================================================
     *
     * We only need the first line during preview.
     *
     * Example:
     *
     * ID,WORK ITEM TYPE,TITLE
     *
     * becomes:
     *
     * ["ID", "WORK ITEM TYPE", "TITLE"]
     */
    private static List<String> extractHeaders(String csvBody) {

        List<String> headers = new List<String>();

        if (String.isBlank(csvBody)) {
            return headers;
        }

        /*
         * Handle both Windows and Unix line endings.
         */
        Integer newlineIndex = csvBody.indexOf('\n');

        String headerLine;

        if (newlineIndex >= 0) {
            headerLine = csvBody.substring(0, newlineIndex);
        } else {
            headerLine = csvBody;
        }

        headerLine = headerLine.replace('\r', '');

        /*
         * Remove UTF-8 BOM if the API includes one.
         */
        if (headerLine.startsWith('\uFEFF')) {
            headerLine = headerLine.substring(1);
        }

        for (String header : headerLine.split(',')) {

            String cleanedHeader = header.trim();

            if (!String.isBlank(cleanedHeader)) {
                headers.add(cleanedHeader);
            }
        }

        return headers;
    }


    /*
     * ============================================================
     * HEADER PARSING HELPERS
     * ============================================================
     */

    private static Integer parseIntegerHeader(
        String value,
        Integer defaultValue
    ) {

        if (String.isBlank(value)) {
            return defaultValue;
        }

        try {
            return Integer.valueOf(value);
        } catch (Exception e) {
            return defaultValue;
        }
    }


    private static Boolean parseBooleanHeader(String value) {

        if (String.isBlank(value)) {
            return false;
        }

        return value.toLowerCase() == 'true';
    }


    /*
     * ============================================================
     * RESPONSE WRAPPER
     * ============================================================
     *
     * This is what the LWC receives from previewUrl().
     */
    public class URLPreviewResponse {

        @AuraEnabled
        public List<String> headers { get; set; }

        @AuraEnabled
        public Integer page { get; set; }

        @AuraEnabled
        public Integer pageSize { get; set; }

        @AuraEnabled
        public Integer totalCount { get; set; }

        @AuraEnabled
        public Boolean hasMore { get; set; }
    }
}