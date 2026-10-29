public class ProcessDataFeed implements Database.Batchable<SObject>
{
        private String fileToBeProcessed = '';
        private String operationType = '';
        private String targetObj = '';
        private Id jobTrackerId;
        Map<String,String> fieldColumnMapping=new Map<String,String>();
        Map<String,String> lookupColumnMapping=new Map<String,String>();
        List<String> lookupQueries=new List<String>();
        List<Data_Feed_Mapping__c> lookupMappings=new List<Data_Feed_Mapping__c>();
        //Map<String,String> lookupFieldColumnMapping=new Map<String,String>();
        //Map<String,String> lookupFieldQueryMapping=new Map<String,String>();
        private String selectedMappingName;
   
        public ProcessDataFeed(String fileName, String operation, String targetObject, Id jobTrackerId)
        {
            fileToBeProcessed = fileName;
            operationType = operation;
            targetObj=targetObject;
            this.jobTrackerId = jobTrackerId;
            Data_Feed_Job_Tracker__c tracker = [
                SELECT Selected_Mapping_Name__c
                FROM Data_Feed_Job_Tracker__c
                WHERE Id = :jobTrackerId
                LIMIT 1
            ];
            selectedMappingName = tracker.Selected_Mapping_Name__c;
            List<Data_Feed_Mapping__c> mappings;
            if (String.isNotBlank(selectedMappingName)) {
                mappings = [
                    SELECT File_Name__c, File_Column_Name__c,
                        SObject_API_Name__c, Field_to_update__c,
                        Lookup_Filter_Criteria__c, Lookup_Object_Name__c,
                        Lookup_Field__c, Lookup_Return_Field__c,
                        Operation__c, Id, Name
                    FROM Data_Feed_Mapping__c
                    WHERE Configuration_Display_Name__c = :selectedMappingName
                    AND Operation__c = :operation
                    AND SObject_API_Name__c = :targetObject
                    AND Is_Lookup__c = false
                ];

                lookupMappings = [
                    SELECT File_Name__c, File_Column_Name__c,
                        SObject_API_Name__c, Field_to_update__c,
                        Lookup_Filter_Criteria__c, Lookup_Object_Name__c,
                        Lookup_Field__c, Lookup_Return_Field__c,
                        Operation__c, Id, Name, Is_Lookup__c
                    FROM Data_Feed_Mapping__c
                    WHERE Configuration_Display_Name__c = :selectedMappingName
                    AND Operation__c = :operation
                    AND SObject_API_Name__c = :targetObject
                    AND Is_Lookup__c = true
                ];
            } else {
                mappings = [
                    SELECT File_Name__c, File_Column_Name__c,
                        SObject_API_Name__c, Field_to_update__c,
                        Lookup_Filter_Criteria__c, Lookup_Object_Name__c,
                        Lookup_Field__c, Lookup_Return_Field__c,
                        Operation__c, Id, Name
                    FROM Data_Feed_Mapping__c
                    WHERE File_Name__c = :fileName
                    AND Operation__c = :operation
                    AND SObject_API_Name__c = :targetObject
                    AND Is_Lookup__c = false
                ];

                lookupMappings = [
                    SELECT File_Name__c, File_Column_Name__c,
                        SObject_API_Name__c, Field_to_update__c,
                        Lookup_Filter_Criteria__c, Lookup_Object_Name__c,
                        Lookup_Field__c, Lookup_Return_Field__c,
                        Operation__c, Id, Name, Is_Lookup__c
                    FROM Data_Feed_Mapping__c
                    WHERE File_Name__c = :fileName
                    AND Operation__c = :operation
                    AND SObject_API_Name__c = :targetObject
                    AND Is_Lookup__c = true
                ];
            }
            for(Data_Feed_Mapping__c mapping:mappings)
            {
                fieldColumnMapping.put(mapping.File_Column_Name__c,mapping.Field_to_update__c);
            }
            for(Data_Feed_Mapping__c mapping:lookupMappings)
            {
                /*lookupColumnMapping.put(mapping.File_Column_Name__c,mapping.Field_to_update__c);*/
				Boolean hasValidLookup = String.isNotBlank(mapping.Lookup_Object_Name__c) && String.isNotBlank(mapping.Lookup_Field__c) && String.isNotBlank(mapping.Lookup_Return_Field__c);
                
                if(hasValidLookup) { 
                    //lookupMappings.add(mapping); 
                    lookupColumnMapping.put( mapping.File_Column_Name__c, mapping.Field_to_update__c ); 
                }else { 
                    // No lookup configured. 
                    // Treat Excel value as the actual Salesforce field value. 
                    fieldColumnMapping.put( mapping.File_Column_Name__c, mapping.Field_to_update__c ); 
                }
            }            
            /*for(Data_Feed_Mapping__c mapping:lookupMappings)
            {
                String lookupQuery = 'SELECT ' + mapping.Lookup_Return_Field__c + ' FROM ' + mapping.Lookup_Object_Name__c +
                                    ' WHERE ' + mapping.Lookup_Field__c + ' IN: \'' +mapping.File_Column_Name__c + '\'';
                                if (mapping.Lookup_Filter_Criteria__c != null && mapping.Lookup_Filter_Criteria__c != '') {
                                    lookupQuery += ' AND ' + mapping.Lookup_Filter_Criteria__c;
                                }
                lookupQueries.add(lookupQuery);
                //lookupFieldColumnMapping.put(mapping.File_column_Name__c,mapping.Field_to_update__c);
                //lookupFieldQueryMapping.put(mapping.File_column_Name__c,lookupQuery);
            }*/
        }
        public Database.QueryLocator start(Database.BatchableContext context)
        {
            return Database.getQueryLocator([SELECT Id, File_Name__c, Error_Message__c,Data_Feed_Record_JSON__c,Is_Failed__c,Is_Processed__c FROM Data_Feed_Record__c
            WHERE Is_Processed__c = false AND Data_Feed_Job_Tracker__c = :jobTrackerId
            Order by Id asc // ordering as in csv
            ]);
        }
        public void execute(Database.BatchableContext context, List<Data_Feed_Record__c> scope)
        {
            /*Map<String,List<SObject>> lookupRecordsMap=new Map<String,List<Sobject>>();
            for(String lookupQuery:lookupQueries)
            {
                List<SObject> lookupRecords = Database.query(lookupQuery);      
                lookupRecordsMap.put((lookupRecords[0].getSObjectType().getDescribe().getName()),lookupRecords);
            }*/
           
           
           
            List<SObject> records = new List<SObject>();
            List<Map<String,Object>> dataFeedRecords= new List<Map<String,Object>>();
            Map<String,Set<Object>> lookupRecordsMap= new Map<String,Set<Object>>();
 
            // Only run this block for Upsert or Update operations
            List<Data_Feed_Mapping__c> uniqueKeyMappings = new List<Data_Feed_Mapping__c>();
            List<String> targetCsvCols = new List<String>();
            List<String> targetSfFields = new List<String>();
            if (operationType == 'Update') {
                if (String.isNotBlank(selectedMappingName)) {
                    uniqueKeyMappings = [
                        SELECT File_Column_Name__c, Field_to_update__c,
                            Is_Lookup__c, Lookup_Field__c
                        FROM Data_Feed_Mapping__c
                        WHERE Configuration_Display_Name__c = :selectedMappingName
                        AND Operation__c = :operationType
                        AND SObject_API_Name__c = :targetObj
                        AND Field_to_update__c = 'Id'
                    ];
                } else {
                    uniqueKeyMappings = [
                        SELECT File_Column_Name__c, Field_to_update__c,
                            Is_Lookup__c, Lookup_Field__c
                        FROM Data_Feed_Mapping__c
                        WHERE File_Name__c = :fileToBeProcessed
                        AND Operation__c = :operationType
                        AND SObject_API_Name__c = :targetObj
                        AND Field_to_update__c = 'Id'
                    ];
                }

                for (Data_Feed_Mapping__c m : uniqueKeyMappings) {
                    System.debug(m);

                    if (m.Is_Lookup__c && m.Lookup_Field__c != null &&
                        m.Lookup_Field__c.contains(',')) {
                        continue;
                    }

                    targetCsvCols.add(m.File_Column_Name__c);

                    if (m.Is_Lookup__c == true &&
                        String.valueOf(m.Field_to_update__c).toLowerCase() == 'id') {
                        targetSfFields.add(m.Lookup_Field__c);
                    } else {
                        targetSfFields.add(m.Field_to_update__c);
                    }
                }
            }
            else if (operationType == 'Upsert') {
                if (String.isNotBlank(selectedMappingName)) {
                    uniqueKeyMappings = [
                        SELECT File_Column_Name__c, Field_to_update__c
                        FROM Data_Feed_Mapping__c
                        WHERE Configuration_Display_Name__c = :selectedMappingName
                        AND Operation__c = :operationType
                        AND SObject_API_Name__c = :targetObj
                        AND Is_Unique_Key__c = true
                    ];
                } else {
                    uniqueKeyMappings = [
                        SELECT File_Column_Name__c, Field_to_update__c
                        FROM Data_Feed_Mapping__c
                        WHERE File_Name__c = :fileToBeProcessed
                        AND Operation__c = :operationType
                        AND SObject_API_Name__c = :targetObj
                        AND Is_Unique_Key__c = true
                    ];
                }

                for (Data_Feed_Mapping__c m : uniqueKeyMappings) {
                    targetCsvCols.add(m.File_Column_Name__c);
                    targetSfFields.add(m.Field_to_update__c);
                }

                System.debug('targetCsvCols' + targetCsvCols);
                System.debug('targetSfFields' + targetSfFields);
            }
 
            // Deserialize records
            for (Data_Feed_Record__c d:scope) {
                Map<String,Object> dataFeedRecord=(Map<String,Object>)JSON.deserializeuntyped(d.Data_Feed_Record_JSON__c);
                dataFeedRecords.add(dataFeedRecord);
            }
 
            // For update: build a map of composite key values for SOQL
            Map<String, Map<String, Object>> fieldValuesMap = new Map<String, Map<String, Object>>();
            if (operationType == 'Update' && !targetCsvCols.isEmpty()) {
                for (Map<String, Object> rec : dataFeedRecords) {
                    String key = '';
                    for (String col : targetCsvCols) {
                        key += String.valueOf(rec.get(col)).trim();
                    }
                    fieldValuesMap.put(key, rec);
                }
            }
 
            // Bulk query for existing records if update
            Map<String, Id> existingRecordMap = new Map<String, Id>();
            if ((operationType == 'Update' || operationType == 'Upsert') && !targetSfFields.isEmpty()) {
                // Build dynamic SOQL
                // String soql = 'SELECT Id';
                // system.debug(targetSfFields);
                // for (String f : targetSfFields) {
                //     soql += ', ' + f;
                // }
                String soql = 'SELECT Id';

                // Deduplicate fields only for the SELECT clause.
                // Keep targetSfFields unchanged because it is paired by index
                // with targetCsvCols when building the WHERE clauses.
                Set<String> selectFields = new Set<String>();
                selectFields.add('Id');

                for (String f : targetSfFields) {
                    if (String.isNotBlank(f)) {
                        selectFields.add(f.trim());
                    }
                }

                soql = 'SELECT ' + String.join(
                    new List<String>(selectFields),
                    ', '
                );
                
                soql += ' FROM ' + targetObj + ' WHERE ';
                List<String> whereClauses = new List<String>();
                for (Integer i = 0; i < targetSfFields.size(); i++) {
                    String f = targetSfFields[i];
                    Set<String> values = new Set<String>();
                    // for (Map<String, Object> rec : dataFeedRecords) {
                    //     values.add(String.valueOf(rec.get(targetCsvCols[i])).trim());
                    // }
                                        
                    for (Map<String, Object> rec : dataFeedRecords) {
                        Object rawValue = rec.get(targetCsvCols[i]);

                        if (rawValue == null ||
                            String.isBlank(String.valueOf(rawValue))) {
                            continue;
                        }

                        values.add(String.valueOf(rawValue).trim());
                    }

                    // Do not create an IN clause if no usable values exist.
                    if (values.isEmpty()) {
                        continue;
                    }

                    String inClause = '';
                    for (String v : values) {
                        inClause += '\'' + String.escapeSingleQuotes(v) + '\',';
                    }
                    if (inClause.endsWith(',')) inClause = inClause.substring(0, inClause.length()-1);
                    whereClauses.add(f + ' IN (' + inClause + ')');
                }
                soql += String.join(whereClauses, ' AND ');
                List<SObject> existingRecords = Database.query(soql);
                for (SObject s : existingRecords) {
                    String key = '';
                    for (String f : targetSfFields) {
                        key += String.valueOf(s.get(f)).trim();
                    }
                    existingRecordMap.put(key, (Id)s.get('Id'));
                }
            }
            system.debug('existingRecordMap'+existingRecordMap);
 
            // ...existinuniqueKeyMappingsg code for lookupRecordsMap...
            for(Map<String,Object> mp: dataFeedRecords)
            {
                for(Data_Feed_Mapping__c dfm:lookupMappings)
                {
                    if((dfm.file_column_name__c).contains(','))
                    {
                        List<String> multipleLookups=(dfm.file_column_name__c).split(',');
                        for(String s:multipleLookups)
                        {
                            if(mp.get(s)!=null)
                            {  
                                System.debug('lookupRecordsMap'+lookupRecordsMap);
                                if(!(lookupRecordsMap.containsKey(s)) || (lookupRecordsMap.get(s)).isEmpty())
                                {
                                    Set<Object> lookupValues=new Set<Object>();
                                    lookupValues.add('\''+mp.get(s)+'\'');
                                    lookupRecordsMap.put(s,lookupValues);
                                }
                                else if(!(lookupRecordsMap.get(s)).isEmpty())
                                {
                                    Set<Object> lookupValues=lookupRecordsMap.get(s);
                                    lookupValues.add('\''+mp.get(s)+'\'');
                                    lookupRecordsMap.put(s,lookupValues);
                                }
                            }                              
                        }
                    }
                    else
                    {
                        if(mp.get(dfm.file_column_name__c)!=null)
                        {  
                            System.debug('lookupRecordsMap'+lookupRecordsMap);
                            if(!(lookupRecordsMap.containsKey(dfm.file_column_name__c)) || (lookupRecordsMap.get(dfm.file_column_name__c)).isEmpty())
                            {
                                Set<Object> lookupValues=new Set<Object>();
                                lookupValues.add('\''+mp.get(dfm.file_column_name__c)+'\'');
                                lookupRecordsMap.put(dfm.file_column_name__c,lookupValues);
                            }
                            else if(!(lookupRecordsMap.get(dfm.file_column_name__c)).isEmpty())
                            {
                                Set<Object> lookupValues=lookupRecordsMap.get(dfm.file_column_name__c);
                                lookupValues.add('\''+mp.get(dfm.file_column_name__c)+'\'');
                                lookupRecordsMap.put(dfm.file_column_name__c,lookupValues);
                            }
                        }                        
                    }
                }              
            }
 
 
            Map<String,Map<String,String>> lookupResultsMap=new Map<String,Map<String,String>>();          
            for(Data_Feed_Mapping__c mapping:lookupMappings)
            {
                String lookupQuery;
                
                String lookupField = mapping.Lookup_Field__c.trim();
                String returnField = mapping.Lookup_Return_Field__c.trim();
                
                String selectFields = lookupField;
                
                if(!lookupField.equalsIgnoreCase(returnField)){
					selectFields += ',' + returnField;
                }
                
                if((mapping.file_column_name__c).contains(','))
                {
                    List<String> multipleLookups=(mapping.file_column_name__c).split(',');
                    List<String> multipleLookupFields=(mapping.Lookup_field__c).split(',');
                    lookupQuery = 'SELECT ' + selectFields + ' FROM ' + mapping.Lookup_Object_Name__c +
                        ' WHERE ';
               
                    for(integer k = 0; k < multipleLookups.size(); k++)
                    {
                        String s = multipleLookups[k];
                        //int arraySize=multipleLookups.size();
                        Set<Object> tempObject=lookupRecordsMap.get(s);
                        List<String> tempList = new List<String>();
                        for(Object o:tempObject)
                        {
                            tempList.add(String.valueOf(o));
                        }    
                        String inClause = '';
                        for (integer i = 0; i < tempList.size(); i++) {
                            inClause += String.escapeSingleQuotes(tempList[i]);
                            if (i < tempList.size() - 1) {
                                inClause += ',';
                            }
                            inClause=inClause.replace('\\', '');
                        }
                        if(k < multipleLookups.size() - 1)
                        {
                            system.debug('multipleLookupFields[k]'+multipleLookupFields[k]);
                            system.debug('inClause'+inClause);
                            lookupQuery += multipleLookupFields[k] + ' IN (' + inClause + ')'+' AND ';                          
                        }
                        else
                        {
                            System.debug('multipleLookupFields[k] 21'+multipleLookupFields[k]);
                            lookupQuery += multipleLookupFields[k] + ' IN (' + inClause + ')';                                                    
                        }
                    }
                    if (mapping.Lookup_Filter_Criteria__c != null && mapping.Lookup_Filter_Criteria__c != '')
                    {
                        lookupQuery += ' AND ' + mapping.Lookup_Filter_Criteria__c;
                    }                        
                }
                else
                {
                    Set<Object> tempObject=lookupRecordsMap.get(mapping.file_column_name__c);
                    List<String> tempList = new List<String>();
                    for(Object o:tempObject)
                    {
                        tempList.add(String.valueOf(o));
                    }
                    // Properly quote and comma-separate the values
                    String inClause = '';
                    for (Integer i = 0; i < tempList.size(); i++) {
                        inClause += String.escapeSingleQuotes(tempList[i]);
                        if (i < tempList.size() - 1) {
                            inClause += ',';
                        }
                        inClause=inClause.replace('\\', '');
                    }
                    lookupQuery = 'SELECT ' + selectFields + ' FROM ' + mapping.Lookup_Object_Name__c +
                        ' WHERE ' + mapping.Lookup_Field__c + ' IN (' + inClause + ')';
                    if (mapping.Lookup_Filter_Criteria__c != null && mapping.Lookup_Filter_Criteria__c != '') {
                        lookupQuery += ' AND ' + mapping.Lookup_Filter_Criteria__c;
                    }
                    System.debug('lookupQuery'+lookupQuery);
                }
 
                system.debug('Final lookupQuery'+lookupQuery);
                List<SObject> lookupRecords = Database.query(lookupQuery);                    
                for(Sobject s:lookupRecords)
                {
                    if((mapping.file_column_name__c).contains(','))
                    {
                        List<String> fileColumns=(mapping.file_column_name__c).split(',');
                        List<String> fields = (mapping.Lookup_Field__c).split(',');
                        String tempFileColumnName='';
                        String tempValues='';
                        for(Integer i=0;i<fileColumns.size();i++)
                        {
                            tempValues+=(String)s.get(fields[i]);
                            if(i<fileColumns.size()-1)
                            {
                                 tempFileColumnName+=fileColumns[i]+',';                                    
                            }
                            else
                            {
                                tempFileColumnName+=fileColumns[i];
                            }
                        }
                        if(lookupResultsMap.get(String.valueOf(tempFileColumnName))==null)
                        {
                            Map<String,String> tempMap=new Map<String,String>();
                            tempMap.put(tempValues,(String)s.get(mapping.Lookup_Return_Field__c));
                            lookupResultsMap.put(tempFileColumnName,tempMap);                  
                        }
                        else if(lookupResultsMap.get(tempFileColumnName)!=null)
                        {
                            Map<String,String> tempMap=new Map<String,String>();    
                            tempMap=lookupResultsMap.get(tempFileColumnName);
                            tempMap.put(tempValues,(String)s.get(mapping.Lookup_Return_Field__c));
                            lookupResultsMap.put(tempFileColumnName,tempMap);
                        }                        
                    }
                    else
                    {
                        if(lookupResultsMap.get(String.valueOf(mapping.file_column_name__c))==null)
                        {
                            Map<String,String> tempMap=new Map<String,String>();
                            tempMap.put((String)s.get(mapping.Lookup_Field__c),(String)s.get(mapping.Lookup_Return_Field__c));
                            lookupResultsMap.put(String.valueOf(mapping.File_Column_Name__c),tempMap);                  
                        }
                        else if(lookupResultsMap.get(mapping.File_Column_Name__c)!=null)
                        {
                            Map<String,String> tempMap=new Map<String,String>();    
                            tempMap=lookupResultsMap.get(mapping.File_Column_Name__c);
                            tempMap.put((String)s.get(mapping.Lookup_Field__c),(String)s.get(mapping.Lookup_Return_Field__c));
                            lookupResultsMap.put(String.valueOf(mapping.File_Column_Name__c),tempMap);
                        }
                    }
                }
            }
 
 
            for (Integer idx = 0; idx < scope.size(); idx++) {
                Data_Feed_Record__c d = scope[idx];
                try {
                    System.debug('lookupResultsMap'+lookupResultsMap);
                    Map<String,Object> dataFeedRecord=(Map<String,Object>)JSON.deserializeuntyped(d.Data_Feed_Record_JSON__c);
                    SObject targetRecord = Schema.getGlobalDescribe().get(targetObj).newSObject();
 
                    // If update, assign Id by composite key
                    if ((operationType == 'Update' || operationType == 'Upsert') && !targetCsvCols.isEmpty()) {
                        String rowKey = '';
                        for (String col : targetCsvCols) {
                            rowKey += String.valueOf(dataFeedRecord.get(col)).trim();
                        }
                        if (existingRecordMap.containsKey(rowKey)) {
                            targetRecord.put('Id', existingRecordMap.get(rowKey));
                        }
                        system.debug('rowKey'+rowKey);
                        system.debug('targetRecord'+targetRecord);
                        // For Upsert: do NOT throw, just don't set Id (will be insert)
                    }
                   
                    // if ((operationType == 'Update' || operationType == 'Upsert')
                    //     && !targetCsvCols.isEmpty()) {

                    //     List<String> keyParts = new List<String>();
                    //     Boolean missingKey = false;

                    //     for (String col : targetCsvCols) {
                    //         Object rawValue = dataFeedRecord.get(col);

                    //         if (rawValue == null ||
                    //             String.isBlank(String.valueOf(rawValue))) {
                    //             missingKey = true;
                    //             break;
                    //         }

                    //         keyParts.add(String.valueOf(rawValue).trim());
                    //     }

                    //     if (missingKey) {
                    //         throw new IllegalArgumentException(
                    //             'Missing required unique key value: ' +
                    //             String.join(targetCsvCols, ', ')
                    //         );
                    //     }

                    //     String rowKey = String.join(keyParts, '');

                    //     if (existingRecordMap.containsKey(rowKey)) {
                    //         targetRecord.put('Id', existingRecordMap.get(rowKey));
                    //     }
                    // }

                    // Prepare field describe map for type conversion
                    Schema.SObjectType objType = Schema.getGlobalDescribe().get(targetObj);
                    Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
 
                    for(String key: dataFeedRecord.keySet()) {
                        if(fieldColumnMapping.get(key)!=NULL) {
                            String sfField = fieldColumnMapping.get(key);
                            Object value = dataFeedRecord.get(key);
                            if(fieldMap.containsKey(sfField)) {
                                Schema.DescribeFieldResult fdesc = fieldMap.get(sfField).getDescribe();
                                Schema.DisplayType dtype = fdesc.getType();
                                if(value != null && String.valueOf(value) != '') {
                                    try {
                                        switch on dtype {
                                            when CURRENCY, DOUBLE {
                                                value = Decimal.valueOf(String.valueOf(value));
                                            }
                                            when INTEGER {
                                                value = Integer.valueOf(String.valueOf(value));
                                            }
                                            when DATE {
                                                 String dateValue = String.valueOf(value).trim();

                                                // Enforce the YYYY-MM-DD format.
                                                if (!Pattern.matches(
                                                    '^\\d{4}-\\d{2}-\\d{2}$',
                                                    dateValue
                                                )) {
                                                    throw new IllegalArgumentException(
                                                        'Invalid date format for field "' + sfField +
                                                        '". Expected YYYY-MM-DD, but received "' +
                                                        dateValue + '".'
                                                    );
                                                }

                                                // Validate that the date itself exists.
                                                try {
                                                    value = Date.valueOf(dateValue);
                                                } catch (Exception dateEx) {
                                                    throw new IllegalArgumentException(
                                                        'Invalid date for field "' + sfField +
                                                        '": "' + dateValue +
                                                        '". Expected a valid date in YYYY-MM-DD format.'
                                                    );
                                                }
                                            }
                                            when DATETIME {
                                                value = Datetime.valueOf(String.valueOf(value));
                                            }
                                            when BOOLEAN {
                                                value = (String.valueOf(value).toLowerCase() == 'true');
                                            }
                                            when PERCENT {
                                                value = Decimal.valueOf(String.valueOf(value));
                                            }
                                            when TIME {
                                                // FIX 2: Time.valueOf() does not exist. Using JSON hack to cast String to Time.
                                                // Ensure input format is HH:mm:ss.SSSZ or similar standard format
                                                String timeStr = String.valueOf(value);
                                                value = (Time)JSON.deserialize('"' + timeStr + '"', Time.class);
                                            }
                                            when ID, REFERENCE, STRING, EMAIL, URL, PHONE, TEXTAREA, ENCRYPTEDSTRING, PICKLIST, MULTIPICKLIST {
                                                value = String.valueOf(value);
                                            }
                                            // NOTE: Schema.DisplayType does NOT have a 'LONG' value.
                                            // Salesforce treats Long numbers usually as Strings in text areas or Doubles in numeric fields.
                                            // If you need to handle specific logic for large integers, include it in the 'INTEGER' or 'DOUBLE' block or 'else'.
                                           
                                            when BASE64 {
                                                value = EncodingUtil.base64Decode(String.valueOf(value));
                                            }
                                            when ADDRESS, LOCATION {
                                                value = String.valueOf(value);
                                            }
                                            when COMBOBOX {
                                                value = String.valueOf(value);
                                            }
                                            when ANYTYPE {
                                                // assign as is
                                            }
                                            when else {
                                                value = String.valueOf(value);
                                            }
                                        }
                                    } catch(Exception convEx) {
                                        String errorMessage =
                                            'Invalid value "' + String.valueOf(value) +
                                            '" for field "' + sfField +
                                            '" (Salesforce type: ' + String.valueOf(dtype) +
                                            '). ' + convEx.getMessage();

                                        System.debug(errorMessage);

                                        throw new IllegalArgumentException(errorMessage);
                                    }
                                } else {
                                    value = null;
                                }
                            }
                            targetRecord.put(sfField, value);
                            System.debug('targetRecord'+targetRecord);
                        }
                    //     if(lookupColumnMapping.get(key)!=NULL) {
                    //         System.debug('lookupColumnMapping.get(key)'+lookupColumnMapping.get(key));
                    //         System.debug('(lookupResultsMap.get(key)).get(String.valueof(dataFeedRecord.get(key)))'+(lookupResultsMap.get(key)).get(String.valueof(dataFeedRecord.get(key))));
                    //         targetRecord.put(lookupColumnMapping.get(key),(lookupResultsMap.get(key)).get(String.valueof(dataFeedRecord.get(key))));
                    //     }
                    //     for(String compositeKey:lookupColumnMapping.keyset()) {
                    //         if(compositeKey.contains(key) && compositeKey.contains(',')) {
                    //             List<String> fileColumns=compositeKey.split(',');
                    //             String tempStr='';
                    //             for(String temp:fileColumns) {
                    //                 tempStr+=dataFeedRecord.get(temp);
                    //             }
                    //             System.debug('lookupColumnMapping'+lookupColumnMapping);
                    //             System.debug('compositeKey'+compositeKey);
                    //             System.debug('tempStr'+tempStr);
                    //             System.debug('lookupColumnMapping.get(compositeKey'+lookupColumnMapping.get(compositeKey));
                    //             System.debug('(lookupResultsMap.get(compositeKey))'+(lookupResultsMap.get(compositeKey)));
                    //             System.debug('(lookupResultsMap.get(compositeKey)).get(tempStr)'+(lookupResultsMap.get(compositeKey)).get(tempStr));
                    //             targetRecord.put(lookupColumnMapping.get(compositeKey),(lookupResultsMap.get(compositeKey)).get(tempStr));
                    //         }
                    //     }
                    // }
                    for(Data_Feed_Mapping__c mapConfig : lookupMappings)
                    {
                        String csvKey = mapConfig.File_Column_Name__c;
                   
                            // Reconstruct key from current CSV Row Data
                            List<String> cols = csvKey.split(',');
                            String csvCompositeValue = '';
                            Boolean missingData = false;
                       
                            for(String c : cols) {
                                Object val = dataFeedRecord.get(c.trim());
                                if(val == null) { missingData = true; break; }
                                csvCompositeValue += String.valueOf(val);
                            }
                       
                            if(!missingData) {
                                Map<String,String> resMap = lookupResultsMap.get(csvKey);
                                if(resMap != null && resMap.containsKey(csvCompositeValue)) {
                                 // This sets the value. If Field_to_update__c is 'Id', it sets the ID for Update.
                                    targetRecord.put(mapConfig.Field_to_update__c, resMap.get(csvCompositeValue));
                                }
                            }
                        }
                    }
                    if(operationType == 'Update' && targetRecord.get('Id') == null)
                    {
                        throw new DmlException('No existing record found for update. Key lookup failed.');
                    }
                    records.add(targetRecord);
               
                } catch (Exception e) {
                    d.Is_Processed__c = true;
                    d.Is_Failed__c = true;

                    d.Error_Message__c =
                        'Error preparing record for ' + operationType +
                        ': ' + e.getMessage() +
                        ' at line ' + e.getLineNumber();

                    records.add(null);
                }
            }
           
            System.debug('records'+records);
           
            Map<Id, String> errorMap = new Map<Id, String>();
            List<SObject> recordsToProcess = new List<SObject>();
            Map<Integer, Integer> originalIndexMap = new Map<Integer, Integer>();
 
            // Filter out any nulls that were added from preparation errors
            // Deduplicate by Id to avoid 'Duplicate id in list' error
            Map<Id, SObject> uniqueRecordsMap = new Map<Id, SObject>();
            for(Integer i = 0; i < records.size(); i++){
                SObject rec = records[i];
                if(rec != null){
                    Id recId = (Id)rec.get('Id');
                    if(recId != null){
                        // Only keep the first occurrence
                        if(!uniqueRecordsMap.containsKey(recId)){
                            uniqueRecordsMap.put(recId, rec);
                            originalIndexMap.put(recordsToProcess.size(), i); // Map new list index to original scope index
                            recordsToProcess.add(rec);
                        }
                    } else {
                        // For inserts (no Id yet), just add
                        originalIndexMap.put(recordsToProcess.size(), i);
                        recordsToProcess.add(rec);
                    }
                }
            }
            if(!recordsToProcess.isEmpty()) {
                List<Database.SaveResult> saveResults;
                List<Database.UpsertResult> upsertResults;
 
                // 2. Perform the specific database operation
                if (operationType == 'Upsert') {
                   
                    system.debug(recordsToProcess);
                    upsertResults = Database.upsert(recordsToProcess,false);
                    system.debug('upsertResults'+upsertResults);
                } else if (operationType == 'Update') {
                    System.debug(recordsToProcess);
                    saveResults = Database.update(recordsToProcess, false);
                } else {
                    saveResults = Database.insert(recordsToProcess, false);
                }
 
                Integer resultSize = (operationType == 'Upsert') ? upsertResults.size() : saveResults.size();
 
                // 4. Iterate over the results dynamically
                for (Integer i = 0; i < resultSize; i++) {
                    Boolean isSuccess;
                    List<Database.Error> errors;
 
                    if (operationType == 'Upsert') {
                        isSuccess = upsertResults[i].isSuccess();
                        errors = upsertResults[i].getErrors();
                    } else {
                        isSuccess = saveResults[i].isSuccess();
                        errors = saveResults[i].getErrors();
                    }
 
                    if (!isSuccess) {
                        Integer originalScopeIndex = originalIndexMap.get(i);
                        Id failedRecordId = scope[originalScopeIndex].Id;
                        String errorMessage = '';
                        for (Database.Error err : errors) {
                            errorMessage += 'Error: ' + err.getStatusCode() + ' - ' + err.getMessage();
                            if (err.getFields() != null && !err.getFields().isEmpty()) {
                                errorMessage += ' (Fields: ' + String.join(err.getFields(), ', ') + '). ';
                            } else {
                                errorMessage += '. ';
                            }
                        }
                        errorMap.put(failedRecordId, errorMessage.trim());
                    }
                }
            }
 
            // Now, update the original Data_Feed_Record__c records with status and any errors
            for (Data_Feed_Record__c dfr : scope) {
                dfr.Is_Processed__c = true; // Mark as processed regardless of outcome
                if (errorMap.containsKey(dfr.Id)) {
                    dfr.Error_Message__c = errorMap.get(dfr.Id);
                    dfr.Is_Failed__c = true;
                } else if (dfr.Error_Message__c == null) {
                    dfr.Error_Message__c = null;
                }
            }
            update scope;
        }
        // public void finish(Database.BatchableContext context)
        // {
        //     Data_Feed_Job_Tracker__c jobTracker = [SELECT Id, File_Name__c, Operation_Type__c, Target_Object__c, Status__c, CreatedBy.Email FROM Data_Feed_Job_Tracker__c WHERE File_Name__c = :fileToBeProcessed order by createddate desc LIMIT 1][0];
        //     if(jobTracker.Status__c == 'Upload Complete') {
        //         jobTracker.Status__c = 'Completed';
        //         update jobTracker;
 
        //         // Prepare counts for the email
        //         Integer totalRecords = [SELECT count() FROM Data_Feed_Record__c WHERE File_Name__c = :fileToBeProcessed];
        //         Integer processedRecords = [SELECT count() FROM Data_Feed_Record__c WHERE File_Name__c = :fileToBeProcessed AND Is_Processed__c = true];
 
        //         // Cannot filter on long text area fields in SOQL (Error_Message__c), so query processed records
        //         // and count non-blank Error_Message__c values in Apex.
        //         Integer failedRecords = 0;
        //         for (Data_Feed_Record__c rec : [SELECT Error_Message__c FROM Data_Feed_Record__c WHERE File_Name__c = :fileToBeProcessed AND Is_Processed__c = true]) {
        //             if (rec.Error_Message__c != null && rec.Error_Message__c.trim().length() > 0) {
        //                 failedRecords++;
        //             }
        //         }
 
        //         try {
        //             List<String> toAddresses = new List<String>();
        //             if (jobTracker.CreatedBy != null && String.isNotBlank(jobTracker.CreatedBy.Email)) {
        //                 // toAddresses.add(jobTracker.CreatedBy.Email);
        //                 toAddresses.add('karansbisht7@gmail.com');
        //                 toAddresses.add('mayank.aggarwal@cginfinity.com');
        //             }
        //             System.debug('toAddresses: ' + toAddresses);
        //             if (!toAddresses.isEmpty()) {
        //                 Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        //                 mail.setToAddresses(toAddresses);
        //                 String subject = 'Data Feed Processing Completed: ' + jobTracker.File_Name__c;
        //                 String body = 'Dear Team,\n\nThe data feed file "' + jobTracker.File_Name__c + '" has finished processing.\n\n' +
        //                               'Operation: ' + jobTracker.Operation_Type__c + '\n' +
        //                               'Target Object: ' + jobTracker.Target_Object__c + '\n' +
        //                               'Total Records: ' + totalRecords + '\n' +
        //                               'Processed Records: ' + processedRecords + '\n' +
        //                               'Successful Records: ' + (processedRecords - failedRecords) + '\n' +
        //                               'Failed Records: ' + failedRecords + '\n\n' +
        //                                'You can review the Data Feed Job Tracker records and any error messages in Salesforce.\n\n' +
        //                               'Regards,\nYour Salesforce Data Importer';
        //                 mail.setSubject(subject);
        //                 mail.setPlainTextBody(body);
        //                 Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        //             }
        //         } catch (Exception e) {
        //             System.debug('Failed to send completion email: ' + e.getMessage());
        //         }
 
        //         //CSVUploaderController.invokeProcessDataFeedBatch(jobTracker.File_Name__c, jobTracker.Operation_Type__c, jobTracker.Target_Object__c);
        //     }
        //     // else {
        //     //     jobTracker.Status__c = 'Ready for Processing';
        //     //     update jobTracker;
        //     // }
        // }
    public void finish(Database.BatchableContext context) {
        List<Data_Feed_Job_Tracker__c> trackers = [
            SELECT Id, File_Name__c, Operation_Type__c, Target_Object__c,
                Status__c, CreatedBy.Email
            FROM Data_Feed_Job_Tracker__c
            WHERE Id = :jobTrackerId
            LIMIT 1
        ];

        if (trackers.isEmpty()) {
            System.debug('Job tracker not found for ID: ' + jobTrackerId);
            return;
        }

        Data_Feed_Job_Tracker__c jobTracker = trackers[0];

        if (jobTracker.Status__c == 'Upload Complete') {
            jobTracker.Status__c = 'Completed';
            update jobTracker;

            // Count only records belonging to this specific upload.
            Integer totalRecords = [
                SELECT COUNT()
                FROM Data_Feed_Record__c
                WHERE Data_Feed_Job_Tracker__c = :jobTrackerId
            ];

            Integer processedRecords = [
                SELECT COUNT()
                FROM Data_Feed_Record__c
                WHERE Data_Feed_Job_Tracker__c = :jobTrackerId
                AND Is_Processed__c = true
            ];

            // Error_Message__c is a long text area, so count failures in Apex.
            Integer failedRecords = 0;

            for (Data_Feed_Record__c rec : [
                SELECT Error_Message__c
                FROM Data_Feed_Record__c
                WHERE Data_Feed_Job_Tracker__c = :jobTrackerId
                AND Is_Processed__c = true
            ]) {
                if (String.isNotBlank(rec.Error_Message__c)) {
                    failedRecords++;
                }
            }

            try {
                List<String> toAddresses = new List<String>();

                if (jobTracker.CreatedBy != null &&
                    String.isNotBlank(jobTracker.CreatedBy.Email)) {
                    // toAddresses.add(jobTracker.CreatedBy.Email);
                    toAddresses.add('karansbisht7@gmail.com');
                }

                System.debug('toAddresses: ' + toAddresses);

                if (!toAddresses.isEmpty()) {
                    Messaging.SingleEmailMessage mail =
                        new Messaging.SingleEmailMessage();

                    mail.setToAddresses(toAddresses);

                    String subject =
                        'Data Feed Processing Completed: ' +
                        jobTracker.File_Name__c;

                    String body =
                        'Dear Team,\n\n' +
                        'The data feed file "' + jobTracker.File_Name__c +
                        '" has finished processing.\n\n' +
                        'Operation: ' + jobTracker.Operation_Type__c + '\n' +
                        'Target Object: ' + jobTracker.Target_Object__c + '\n' +
                        'Total Records: ' + totalRecords + '\n' +
                        'Processed Records: ' + processedRecords + '\n' +
                        'Successful Records: ' +
                            (processedRecords - failedRecords) + '\n' +
                        'Failed Records: ' + failedRecords + '\n\n' +
                        'You can review the Data Feed Job Tracker records ' +
                        'and any error messages in Salesforce.\n\n' +
                        'Regards,\nYour Salesforce Data Importer';

                    mail.setSubject(subject);
                    mail.setPlainTextBody(body);

                    Messaging.sendEmail(
                        new Messaging.SingleEmailMessage[] { mail }
                    );
                }
            } catch (Exception e) {
                System.debug(
                    'Failed to send completion email: ' + e.getMessage()
                );
            }
        }
    }
}