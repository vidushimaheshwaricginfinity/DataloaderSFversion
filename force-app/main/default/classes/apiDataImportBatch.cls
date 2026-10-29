public with sharing class apiDataImportBatch
    implements Database.Batchable<Integer>,
               Database.AllowsCallouts,
               Database.Stateful {

    private String fileName;
    private Integer page;
    private Integer pageSize;
    private String operationType;
    private String targetObject;

    private List<String> apiHeaders;
    private Id apiConfigurationId;
    private Id jobTrackerId;

    private Boolean hasMore = false;
    private Boolean failed = false;
    private String errorMessage;

    // Constructor used for the first page.
    public apiDataImportBatch(
        String fileName,
        Integer page,
        Integer pageSize,
        String operationType,
        String targetObject,
        Id apiConfigurationId,
        Id jobTrackerId
    ) {
        this(
            fileName,
            page,
            pageSize,
            operationType,
            targetObject,
            apiConfigurationId,
            jobTrackerId,
            null
        );
    }

    // Constructor used for subsequent pages.
    public apiDataImportBatch(
        String fileName,
        Integer page,
        Integer pageSize,
        String operationType,
        String targetObject,
        Id apiConfigurationId,
        Id jobTrackerId,
        List<String> apiHeaders
    ) {
        this.fileName = fileName;
        this.page = page;
        this.pageSize = pageSize;
        this.operationType = operationType;
        this.targetObject = targetObject;
        this.apiConfigurationId = apiConfigurationId;
        this.jobTrackerId = jobTrackerId;
        this.apiHeaders = apiHeaders;
    }

    // ==========================================================
    // START
    // ==========================================================
    public Iterable<Integer> start(Database.BatchableContext context) {
        System.debug(LoggingLevel.ERROR,
            '=== API BATCH START ===' +
            ' | Job=' + context.getJobId() +
            ' | Page=' + page +
            ' | PageSize=' + pageSize +
            ' | ConfigId=' + apiConfigurationId +
            ' | TrackerId=' + jobTrackerId +
            ' | HeadersAvailable=' + (apiHeaders != null) +
            ' | HeaderCount=' +
                (apiHeaders == null ? 0 : apiHeaders.size())
        );

        return new List<Integer>{ page };
    }

    // ==========================================================
    // EXECUTE
    // ==========================================================
    public void execute(
        Database.BatchableContext context,
        List<Integer> scope
    ) {
        Integer currentPage = scope[0];

        System.debug(LoggingLevel.ERROR,
            '=== API EXECUTE ENTERED ===' +
            ' | Job=' + context.getJobId() +
            ' | Page=' + currentPage +
            ' | ConfigId=' + apiConfigurationId +
            ' | TrackerId=' + jobTrackerId
        );

        try {
            // 1. Retrieve configuration.
            if (apiConfigurationId == null) {
                throw new CalloutException(
                    'API Configuration Id was not provided.'
                );
            }

            API_Configuration__c apiConfig = [
                SELECT Id,
                       Name,
                       Named_Credential__c,
                       Route__c,
                       Active__c,
                       Method_Type__c,
                       Query_Params_Config__c,
                       Request_Body_Payload__c
                FROM API_Configuration__c
                WHERE Id = :apiConfigurationId
                LIMIT 1
            ];

            System.debug(LoggingLevel.ERROR,
                'CONFIG LOADED' +
                ' | Name=' + apiConfig.Name +
                ' | Active=' + apiConfig.Active__c +
                ' | Method=' + apiConfig.Method_Type__c +
                ' | Route=' + apiConfig.Route__c
            );

            if (apiConfig.Active__c != true) {
                throw new CalloutException(
                    'API Configuration is inactive: ' +
                    apiConfig.Name
                );
            }

            if (String.isBlank(apiConfig.Named_Credential__c)) {
                throw new CalloutException(
                    'Named Credential is missing for: ' +
                    apiConfig.Name
                );
            }

            if (String.isBlank(apiConfig.Route__c)) {
                throw new CalloutException(
                    'Route is missing for: ' + apiConfig.Name
                );
            }

            String methodType = String.isBlank(
                apiConfig.Method_Type__c
            )
                ? 'GET'
                : apiConfig.Method_Type__c.trim().toUpperCase();

            if (methodType != 'GET' && methodType != 'POST') {
                throw new CalloutException(
                    'Unsupported HTTP method: ' + methodType
                );
            }

            // 2. Build endpoint.
            String route = apiConfig.Route__c.trim();

            if (!route.startsWith('/')) {
                route = '/' + route;
            }

            String baseEndpoint =
                'callout:' +
                apiConfig.Named_Credential__c.trim() +
                route;

            List<String> queryParts = new List<String>{
                'page=' + currentPage,
                'pageSize=' + pageSize
            };

            // Configured query filters apply to GET only.
            if (
                methodType == 'GET' &&
                String.isNotBlank(apiConfig.Query_Params_Config__c)
            ) {
                Map<String, Object> rawParams =
                    (Map<String, Object>) JSON.deserializeUntyped(
                        apiConfig.Query_Params_Config__c
                    );

                for (String key : rawParams.keySet()) {
                    Object value = rawParams.get(key);

                    if (
                        value == null ||
                        key.equalsIgnoreCase('page') ||
                        key.equalsIgnoreCase('pageSize')
                    ) {
                        continue;
                    }

                    queryParts.add(
                        EncodingUtil.urlEncode(key, 'UTF-8') +
                        '=' +
                        EncodingUtil.urlEncode(
                            String.valueOf(value),
                            'UTF-8'
                        )
                    );
                }
            }

            String endpoint = baseEndpoint;

            endpoint +=
                (endpoint.contains('?') ? '&' : '?') +
                String.join(queryParts, '&');

            System.debug(LoggingLevel.ERROR,
                '=== REQUEST DETAILS ===' +
                ' | Job=' + context.getJobId() +
                ' | Page=' + currentPage +
                ' | Endpoint=' + endpoint +
                ' | Method=' + methodType +
                ' | PageSize=' + pageSize
            );

            // 3. Create and send request.
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod(methodType);
            request.setTimeout(120000);

            if (methodType == 'POST') {
                if (
                    String.isBlank(
                        apiConfig.Request_Body_Payload__c
                    )
                ) {
                    throw new CalloutException(
                        'Request body is required for POST configuration: ' +
                        apiConfig.Name
                    );
                }

                request.setHeader(
                    'Content-Type',
                    'application/json'
                );

                request.setBody(
                    apiConfig.Request_Body_Payload__c
                );

                System.debug(LoggingLevel.ERROR,
                    'POST BODY LENGTH=' +
                    request.getBody().length()
                );
            }

            HttpResponse response = new Http().send(request);

            System.debug(LoggingLevel.ERROR,
                '=== RESPONSE RECEIVED ===' +
                ' | Page=' + currentPage +
                ' | Status=' + response.getStatusCode() +
                ' | StatusText=' + response.getStatus() +
                ' | BodyLength=' +
                    (response.getBody() == null
                        ? 0
                        : response.getBody().length())
            );

            // Log pagination headers as returned by the API.
            System.debug(LoggingLevel.ERROR,
                'RESPONSE HEADER NAMES=' +
                response.getHeaderKeys()
            );

            if (response.getStatusCode() != 200) {
                throw new CalloutException(
                    'API returned HTTP ' +
                    response.getStatusCode() +
                    ': ' + response.getBody()
                );
            }

            // 4. Determine whether another page exists.
                    
            String hasMoreHeader =
                getResponseHeaderIgnoreCase(response, 'X-Has-More');

            String pageHeader =
                getResponseHeaderIgnoreCase(response, 'X-Page');

            String pageSizeHeader =
                getResponseHeaderIgnoreCase(response, 'X-Page-Size');

            String totalCountHeader =
                getResponseHeaderIgnoreCase(response, 'X-Total-Count');

            hasMore =
                hasMoreHeader != null &&
                hasMoreHeader.trim().equalsIgnoreCase('true');

            System.debug(LoggingLevel.ERROR,
                '=== PAGINATION DECISION ===' +
                ' | Page=' + currentPage +
                ' | RawHasMore=[' + hasMoreHeader + ']' +
                ' | ParsedHasMore=' + hasMore +
                ' | X-Page=' + pageHeader +
                ' | X-Page-Size=' + pageSizeHeader +
                ' | X-Total-Count=' + totalCountHeader
            );


            // 5. Read CSV response.
            String csvData = response.getBody();

            if (String.isBlank(csvData)) {
                if (currentPage == 1) {
                    throw new CalloutException(
                        'The first API page is empty; CSV headers ' +
                        'could not be retrieved.'
                    );
                }

                System.debug(LoggingLevel.ERROR,
                    'EMPTY CSV PAGE=' + currentPage +
                    ' | HasMore=' + hasMore
                );

                return;
            }

            System.debug(LoggingLevel.ERROR,
                'CSV RECEIVED' +
                ' | Page=' + currentPage +
                ' | CharacterCount=' + csvData.length()
            );

            // Page 1 contains headers; later pages contain data only.
            if (currentPage == 1) {
                apiHeaders = parseCsvHeaders(csvData);

                if (apiHeaders == null || apiHeaders.isEmpty()) {
                    throw new CalloutException(
                        'Could not extract CSV headers from page 1.'
                    );
                }

                System.debug(LoggingLevel.ERROR,
                    'CSV HEADERS EXTRACTED=' + apiHeaders
                );

            } else if (
                apiHeaders == null || apiHeaders.isEmpty()
            ) {
                throw new CalloutException(
                    'CSV headers were not passed to page ' +
                    currentPage + '.'
                );
            }

            // 6. Parse CSV.
            List<Map<String, String>> parsedRows = parseCsv(
                csvData,
                apiHeaders,
                currentPage == 1
            );

            System.debug(LoggingLevel.ERROR,
                'CSV PARSING COMPLETE' +
                ' | Page=' + currentPage +
                ' | ParsedRows=' + parsedRows.size() +
                ' | HeaderCount=' + apiHeaders.size()
            );

            if (!parsedRows.isEmpty()) {
                System.debug(LoggingLevel.DEBUG,
                    'FIRST PARSED ROW=' +
                    JSON.serialize(parsedRows[0])
                );
            }

            // 7. Prepare staging records.
            List<Data_Feed_Record__c> feedRecords =
                new List<Data_Feed_Record__c>();

            for (Map<String, String> row : parsedRows) {
                Data_Feed_Record__c feedRecord =
                    new Data_Feed_Record__c();

                feedRecord.File_Name__c = fileName;

                feedRecord.Data_Feed_Record_JSON__c =
                    JSON.serialize(row);

                feedRecord.Data_Feed_Job_Tracker__c =
                    jobTrackerId;

                feedRecord.Is_Processed__c = false;
                feedRecord.Is_Failed__c = false;

                feedRecords.add(feedRecord);
            }

            // 8. Insert staging records with partial success.
            Integer successfulInserts = 0;
            Integer failedInserts = 0;

            if (!feedRecords.isEmpty()) {
                Database.SaveResult[] results =
                    Database.insert(feedRecords, false);

                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        successfulInserts++;
                    } else {
                        failedInserts++;

                        for (
                            Database.Error err :
                            results[i].getErrors()
                        ) {
                            System.debug(LoggingLevel.ERROR,
                                'STAGING INSERT FAILURE' +
                                ' | Page=' + currentPage +
                                ' | Index=' + i +
                                ' | Status=' + err.getStatusCode() +
                                ' | Message=' + err.getMessage()
                            );
                        }
                    }
                }
            }

            System.debug(LoggingLevel.ERROR,
                '=== STAGING SUMMARY ===' +
                ' | Page=' + currentPage +
                ' | ParsedRows=' + parsedRows.size() +
                ' | Prepared=' + feedRecords.size() +
                ' | Inserted=' + successfulInserts +
                ' | Failed=' + failedInserts +
                ' | HasMore=' + hasMore
            );

        } catch (Exception e) {
            failed = true;

            errorMessage =
                e.getMessage() +
                ' | Line=' + e.getLineNumber();

            System.debug(LoggingLevel.ERROR,
                '=== API BATCH EXECUTE EXCEPTION ===' +
                ' | Job=' + context.getJobId() +
                ' | Page=' + currentPage +
                ' | Type=' + e.getTypeName() +
                ' | Message=' + e.getMessage() +
                ' | Line=' + e.getLineNumber() +
                ' | StackTrace=' + e.getStackTraceString()
            );
        }

        System.debug(LoggingLevel.ERROR,
            '=== API EXECUTE EXIT ===' +
            ' | Job=' + context.getJobId() +
            ' | Page=' + currentPage +
            ' | HasMore=' + hasMore +
            ' | Failed=' + failed +
            ' | Error=' + errorMessage
        );
    }

    // ==========================================================
    // FINISH AND PAGE CHAINING
    // ==========================================================
    public void finish(Database.BatchableContext context) {
        System.debug(LoggingLevel.ERROR,
            '=== API BATCH FINISH START ===' +
            ' | Job=' + context.getJobId() +
            ' | Page=' + page +
            ' | HasMore=' + hasMore +
            ' | Failed=' + failed +
            ' | Error=' + errorMessage +
            ' | ConfigId=' + apiConfigurationId +
            ' | TrackerId=' + jobTrackerId +
            ' | HeaderCount=' +
                (apiHeaders == null ? 0 : apiHeaders.size())
        );

        try {
            if (failed) {
                System.debug(LoggingLevel.ERROR,
                    '=== CHAIN STOPPED: EXECUTE FAILED ===' +
                    ' | Page=' + page +
                    ' | Error=' + errorMessage
                );

                return;
            }

            if (hasMore == true) {
                Integer nextPage = page + 1;

                System.debug(LoggingLevel.ERROR,
                    '=== CHAINING NEXT PAGE ===' +
                    ' | CurrentPage=' + page +
                    ' | NextPage=' + nextPage +
                    ' | PageSize=' + pageSize +
                    ' | ConfigId=' + apiConfigurationId +
                    ' | TrackerId=' + jobTrackerId +
                    ' | HeadersAvailable=' +
                        (apiHeaders != null)
                );

                Id nextJobId = Database.executeBatch(
                    new apiDataImportBatch(
                        fileName,
                        nextPage,
                        pageSize,
                        operationType,
                        targetObject,
                        apiConfigurationId,
                        jobTrackerId,
                        apiHeaders
                    ),
                    1
                );

                System.debug(LoggingLevel.ERROR,
                    '=== NEXT PAGE SCHEDULED ===' +
                    ' | Page=' + nextPage +
                    ' | NewJobId=' + nextJobId
                );

                return;
            }

            System.debug(LoggingLevel.ERROR,
                '=== PAGINATION COMPLETE ===' +
                ' | FinalPage=' + page +
                ' | HasMore=' + hasMore +
                ' | UpdatingTracker=' + jobTrackerId
            );

            updateDataFeedJobTrackerStatus(
                jobTrackerId,
                'Upload Complete'
            );

            System.debug(LoggingLevel.ERROR,
                '=== TRACKER UPDATED ===' +
                ' | TrackerId=' + jobTrackerId +
                ' | Status=Upload Complete'
            );

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                '=== API BATCH FINISH EXCEPTION ===' +
                ' | Job=' + context.getJobId() +
                ' | Page=' + page +
                ' | Type=' + e.getTypeName() +
                ' | Message=' + e.getMessage() +
                ' | Line=' + e.getLineNumber() +
                ' | StackTrace=' + e.getStackTraceString()
            );
        }

        System.debug(LoggingLevel.ERROR,
            '=== API BATCH FINISH END ===' +
            ' | Page=' + page
        );
    }

    // ==========================================================
    // UPDATE JOB TRACKER
    // ==========================================================
    private void updateDataFeedJobTrackerStatus(
        Id trackerId,
        String status
    ) {
        if (trackerId == null) {
            System.debug(LoggingLevel.ERROR,
                'TRACKER UPDATE SKIPPED: Tracker ID is null.'
            );
            return;
        }

        Data_Feed_Job_Tracker__c tracker = [
            SELECT Id, Status__c
            FROM Data_Feed_Job_Tracker__c
            WHERE Id = :trackerId
            LIMIT 1
        ];

        String previousStatus = tracker.Status__c;
        tracker.Status__c = status;
        update tracker;

        System.debug(LoggingLevel.ERROR,
            'TRACKER STATUS CHANGED' +
            ' | TrackerId=' + trackerId +
            ' | Previous=' + previousStatus +
            ' | New=' + status
        );
    }

    // ==========================================================
    // PARSE CSV HEADERS
    // ==========================================================
    private static List<String> parseCsvHeaders(String csv) {
        if (String.isBlank(csv)) {
            return new List<String>();
        }

        List<String> rows = splitCsvRows(csv);

        if (rows.isEmpty()) {
            return new List<String>();
        }

        String headerRow = rows[0].replace('\uFEFF', '');

        List<String> headers = parseCsvLine(headerRow);

        for (Integer i = 0; i < headers.size(); i++) {
            headers[i] = headers[i].trim();
        }

        return headers;
    }

    // ==========================================================
    // PARSE CSV ROWS
    // ==========================================================
    private static List<Map<String, String>> parseCsv(
        String csv,
        List<String> headers,
        Boolean hasHeaderRow
    ) {
        List<Map<String, String>> result =
            new List<Map<String, String>>();

        List<String> rows = splitCsvRows(csv);

        if (rows.isEmpty()) {
            return result;
        }

        Integer startIndex = hasHeaderRow ? 1 : 0;

        for (Integer i = startIndex; i < rows.size(); i++) {
            if (String.isBlank(rows[i])) {
                continue;
            }

            List<String> values = parseCsvLine(rows[i]);

            Map<String, String> record =
                new Map<String, String>();

            for (Integer j = 0; j < headers.size(); j++) {
                String value = '';

                if (j < values.size()) {
                    value = values[j];
                }

                record.put(headers[j], value);
            }

            result.add(record);
        }

        return result;
    }

    // ==========================================================
    // SPLIT CSV INTO RECORDS, HANDLING QUOTED NEWLINES
    // ==========================================================
    private static List<String> splitCsvRows(String csv) {
        List<String> rows = new List<String>();

        String current = '';
        Boolean insideQuotes = false;

        for (Integer i = 0; i < csv.length(); i++) {
            String c = csv.substring(i, i + 1);

            if (c == '"') {
                if (
                    insideQuotes &&
                    i + 1 < csv.length() &&
                    csv.substring(i + 1, i + 2) == '"'
                ) {
                    current += '""';
                    i++;
                    continue;
                }

                insideQuotes = !insideQuotes;
                current += c;

            } else if (
                (c == '\n' || c == '\r') &&
                !insideQuotes
            ) {
                if (
                    c == '\r' &&
                    i + 1 < csv.length() &&
                    csv.substring(i + 1, i + 2) == '\n'
                ) {
                    i++;
                }

                rows.add(current);
                current = '';

            } else {
                current += c;
            }
        }

        if (!String.isBlank(current)) {
            rows.add(current);
        }

        return rows;
    }

    // ==========================================================
    // PARSE ONE CSV LINE
    // ==========================================================
    private static List<String> parseCsvLine(String line) {
        List<String> values = new List<String>();

        String current = '';
        Boolean insideQuotes = false;

        for (Integer i = 0; i < line.length(); i++) {
            String c = line.substring(i, i + 1);

            if (c == '"') {
                if (
                    insideQuotes &&
                    i + 1 < line.length() &&
                    line.substring(i + 1, i + 2) == '"'
                ) {
                    current += '"';
                    i++;
                } else {
                    insideQuotes = !insideQuotes;
                }

            } else if (c == ',' && !insideQuotes) {
                values.add(current.trim());
                current = '';

            } else {
                current += c;
            }
        }

        values.add(current.trim());

        return values;
    }

    
    private static String getResponseHeaderIgnoreCase(
        HttpResponse response,
        String requestedName
    ) {
        for (String headerName : response.getHeaderKeys()) {
            if (
                headerName != null &&
                headerName.equalsIgnoreCase(requestedName)
            ) {
                String value = response.getHeader(headerName);

                System.debug(LoggingLevel.ERROR,
                    'HEADER LOOKUP' +
                    ' | Requested=' + requestedName +
                    ' | Actual=' + headerName +
                    ' | Value=' + value
                );

                return value;
            }
        }

        System.debug(LoggingLevel.ERROR,
            'HEADER NOT FOUND: ' + requestedName
        );

        return null;
    }

}