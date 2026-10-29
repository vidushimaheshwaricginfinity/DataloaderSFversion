public with sharing class apiDataImportController {

    @AuraEnabled
    public static String startApiImport(
        String fileName,
        String operationType,
        String targetObject,
        Id apiConfigurationId,
        String selectedMappingName
    ) {

        if (String.isBlank(fileName)) {
            throw new AuraHandledException(
                'File name is required.'
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

        if (apiConfigurationId == null) {
            throw new AuraHandledException(
                'API Configuration is required.'
            );
        }

        Integer pageSize = 50;

        // Create a unique tracker for this import upfront so staging records can link to it
        Id jobTrackerId = CSVUploaderController.createDataFeedJobTracker(
            fileName,
            operationType,
            targetObject,
            selectedMappingName
        );

        // Pass the tracker ID into the first page batch constructor
        Id batchJobId = Database.executeBatch(
            new apiDataImportBatch(
                fileName,
                1,
                pageSize,
                operationType,
                targetObject,
                apiConfigurationId,
                jobTrackerId
            ),
            1
        );

        return String.valueOf(batchJobId);
    }

    @AuraEnabled(cacheable=true)
    public static List<API_Configuration__c> getApiConfigurations() {
        return [
            SELECT Id, Name
            FROM API_Configuration__c
            WHERE Active__c = true
            ORDER BY Name
        ];
    }


    @AuraEnabled
    public static List<String> getApiHeaders(Id apiConfigurationId) {
        if (apiConfigurationId == null) {
            throw new AuraHandledException(
                'API Configuration is required.'
            );
        }

        API_Configuration__c apiConfig = [
            SELECT Id, Name, Named_Credential__c, Route__c,
                Active__c, Method_Type__c,
                Query_Params_Config__c, Request_Body_Payload__c
            FROM API_Configuration__c
            WHERE Id = :apiConfigurationId
            LIMIT 1
        ];

        if (apiConfig.Active__c != true) {
            throw new AuraHandledException(
                'The selected API Configuration is inactive.'
            );
        }

        if (String.isBlank(apiConfig.Named_Credential__c)) {
            throw new AuraHandledException(
                'Named Credential is not configured for: ' + apiConfig.Name
            );
        }

        if (String.isBlank(apiConfig.Route__c)) {
            throw new AuraHandledException(
                'Route is not configured for: ' + apiConfig.Name
            );
        }

        String methodType = String.isBlank(apiConfig.Method_Type__c)
            ? 'GET'
            : apiConfig.Method_Type__c.trim().toUpperCase();

        if (methodType != 'GET' && methodType != 'POST') {
            throw new AuraHandledException(
                'Unsupported HTTP method: ' + methodType
            );
        }

        String route = apiConfig.Route__c.trim();

        if (!route.startsWith('/')) {
            route = '/' + route;
        }

        String endpoint =
            'callout:' + apiConfig.Named_Credential__c.trim() + route;

        // Pagination belongs to Apex, not the saved configuration.
        List<String> queryParts = new List<String>{
            'page=1',
            'pageSize=1'
        };

        // Apply saved filters for GET configurations.
        if (methodType == 'GET' &&
            String.isNotBlank(apiConfig.Query_Params_Config__c)) {

            try {
                Map<String, Object> params =
                    (Map<String, Object>) JSON.deserializeUntyped(
                        apiConfig.Query_Params_Config__c
                    );

                for (String key : params.keySet()) {
                    Object value = params.get(key);

                    if (value == null ||
                        key.equalsIgnoreCase('page') ||
                        key.equalsIgnoreCase('pageSize')) {
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
            } catch (Exception e) {
                throw new AuraHandledException(
                    'Invalid query parameter JSON in API Configuration: ' +
                    e.getMessage()
                );
            }
        }

        endpoint += (endpoint.contains('?') ? '&' : '?') +
            String.join(queryParts, '&');

        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod(methodType);
        request.setTimeout(120000);

        // POST must send the saved JSON payload.
        if (methodType == 'POST') {
            request.setHeader('Content-Type', 'application/json');

            if (String.isNotBlank(apiConfig.Request_Body_Payload__c)) {
                request.setBody(apiConfig.Request_Body_Payload__c);
            }
        }

        HttpResponse response;

        try {
            response = new Http().send(request);
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to call the configured API: ' + e.getMessage()
            );
        }

        if (response.getStatusCode() != 200) {
            throw new AuraHandledException(
                'API returned HTTP ' + response.getStatusCode() +
                ': ' + response.getStatus()
            );
        }

        return parseCsvHeaders(response.getBody());
    }


    private static List<String> splitCsvRows(
        String csv
    ) {

        List<String> rows = new List<String>();
        String current = '';
        Boolean insideQuotes = false;
        for (Integer i = 0;i < csv.length();i++) {
            String c = csv.substring(i,i + 1);
            if (c == '"') {
                if (
                    insideQuotes &&
                    i + 1 < csv.length() &&
                    csv.substring(i + 1,i + 2) == '"'
                ) {
                    current += '""';
                    i++;
                    continue;
                }
                insideQuotes = !insideQuotes;

                current += c;
            }
            else if ((c == '\n' || c == '\r') && !insideQuotes) {
                if (
                    c == '\r' &&
                    i + 1 < csv.length() &&
                    csv.substring(i + 1,i + 2) == '\n'
                ) {
                    i++;
                }
                rows.add(current);
                current = '';
            }
            else {
                current += c;
            }
        }
        if (!String.isBlank(current)) {
            rows.add(current);
        }
        return rows;
    }


    private static List<String> parseCsvLine(String line) {

        List<String> values = new List<String>();
        String current = '';
        Boolean insideQuotes = false;
        for (
            Integer i = 0;
            i < line.length();
            i++
        ) {

            String c = line.substring(i,i + 1);
            if (c == '"') {
                if (
                    insideQuotes &&
                    i + 1 < line.length() &&
                    line.substring(i + 1,i + 2) == '"'
                ) {
                    current += '"';
                    i++;
                }
                else {
                    insideQuotes = !insideQuotes;
                }
            }

            else if (c == ',' && !insideQuotes) {
                values.add(current.trim());
                current = '';
            }

            else {
                current += c;
            }
        }
        values.add(current.trim());
        return values;
    }

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

}