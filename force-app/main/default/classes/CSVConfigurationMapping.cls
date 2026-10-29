public without sharing class CSVConfigurationMapping {
    @AuraEnabled
    public static void createConfiguration(String wrapperJson) {
        try {
            system.debug('Received JSON: ' + wrapperJson);
            ConfigurationWrapper wrapper = (ConfigurationWrapper) JSON.deserialize(wrapperJson, ConfigurationWrapper.class);
            // Validate input
            if (wrapper == null) {
                throw new AuraHandledException('Configuration wrapper is null');
            }
            
            if (String.isEmpty(wrapper.objectName)) {
                throw new AuraHandledException('Object name is required');
            }
            
            if (String.isEmpty(wrapper.operationType)) {
                throw new AuraHandledException('Operation type is required');
            }
            if (String.isEmpty(wrapper.mappingName)) {
                throw new AuraHandledException('Mapping Name is required');
            }
            if (wrapper.mapping == null || wrapper.mapping.isEmpty()) {
                throw new AuraHandledException('No mappings provided');
            }
            
            System.debug('Creating configuration mappings...');
            system.debug('wrapper: ' + wrapper);
            system.debug('wrapper.objectName: ' + wrapper.objectName);
            system.debug('wrapper.operationType: ' + wrapper.operationType);
            system.debug('wrapper.fileName: ' + wrapper.fileName);
            system.debug('wrapper.mapping size: ' + wrapper.mapping.size());
            
            List<Data_Feed_Mapping__c> mappings = new List<Data_Feed_Mapping__c>();
            for (ConfigurationMapping mp : wrapper.mapping) {
                system.debug('Processing mapping: ' + mp);
                
                if (String.isEmpty(mp.csvFieldName)) {
                    throw new AuraHandledException('CSV Field Name is required in mapping');
                }
                
                if (String.isEmpty(mp.selectedField)) {
                    throw new AuraHandledException('Selected Field is required for CSV column: ' + mp.csvFieldName);
                }
                
                Data_Feed_Mapping__c mapping = new Data_Feed_Mapping__c();
                mapping.Operation__c = wrapper.operationType;
                mapping.File_Name__c = wrapper.fileName;
                mapping.Field_to_update__c = mp.selectedField;
                mapping.File_Column_Name__c = mp.csvFieldName;
                mapping.SObject_API_Name__c = wrapper.objectName;
                mapping.Mapping_Name__c = wrapper.mappingName;
                if (mp.isLookup == true) {
                    mapping.Lookup_Object_Name__c = String.isNotBlank(mp.targetObject) ? mp.targetObject : mp.lookupObject;
                    mapping.Lookup_Field__c = String.isNotBlank(mp.matchField) ? mp.matchField : mp.selectedLookupFields;
                    mapping.Lookup_Return_Field__c = String.isNotBlank(mp.returnField) ? mp.returnField : 'Id';
                }
                mapping.Is_Lookup__c = (mp.isLookup == true);
                mapping.Lookup_Filter_Criteria__c = String.isNotBlank(mp.whereClause) ? mp.whereClause : '';
                // Set the unique key flag for Upsert operations
                if (wrapper.operationType == 'Upsert' && mp.isUniqueKey == true) {
                    mapping.Is_Unique_Key__c = true;
                }
                mappings.add(mapping);
                system.debug('mapping created: ' + mapping);
            }
            
            if(mappings.size() == 0) {
                throw new AuraHandledException('No valid mappings to insert');
            }
            
            insert mappings;
            system.debug('Successfully inserted ' + mappings.size() + ' mappings');
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (DmlException dmlEx) {
            system.debug('DML Error: ' + dmlEx.getMessage());
            throw new AuraHandledException('DML Error: ' + dmlEx.getDmlMessage(0));
        } catch (Exception e) {
            system.debug('Error in createConfiguration: ' + e.getMessage() + ' Line: ' + e.getLineNumber());
            throw new AuraHandledException('Error: ' + e.getTypeName() + ' - ' + e.getMessage());
        }
    }
    @AuraEnabled
public static void appendNewMappingColumns(
    String wrapperJson,
    String configurationDisplayName
) {
    if (String.isBlank(wrapperJson)) {
    throw new AuraHandledException(
        'Missing parameter: wrapperJson.'
    );
}

if (String.isBlank(configurationDisplayName)) {
    throw new AuraHandledException(
        'Missing parameter: configurationDisplayName.'
    );
}

ConfigurationWrapper wrapper;

try {
    wrapper = (ConfigurationWrapper) JSON.deserialize(
        wrapperJson,
        ConfigurationWrapper.class
    );
} catch (Exception e) {
    System.debug(LoggingLevel.ERROR,
        'Modify Mapping JSON: ' + wrapperJson);
    System.debug(LoggingLevel.ERROR,
        'Deserialization error: ' + e.getMessage());

    throw new AuraHandledException(
        'Invalid mapping JSON: ' + e.getMessage()
    );
}

if (wrapper == null || wrapper.mapping == null) {
    throw new AuraHandledException(
        'Mapping configuration or mapping rows are missing.'
    );
}

    List<Data_Feed_Mapping__c> existingRecords = [
        SELECT File_Column_Name__c
        FROM Data_Feed_Mapping__c
        WHERE Configuration_Display_Name__c =
            :configurationDisplayName
    ];

    Set<String> existingHeaders = new Set<String>();

    for (Data_Feed_Mapping__c record : existingRecords) {
        if (String.isNotBlank(record.File_Column_Name__c)) {
            existingHeaders.add(
                record.File_Column_Name__c.trim().toLowerCase()
            );
        }
    }

    List<Data_Feed_Mapping__c> recordsToInsert =
        new List<Data_Feed_Mapping__c>();

    for (ConfigurationMapping mapping : wrapper.mapping) {
        if (String.isBlank(mapping.csvFieldName)) {
            continue;
        }

        String headerKey =
            mapping.csvFieldName.trim().toLowerCase();

        // Never insert a column that already exists.
        if (existingHeaders.contains(headerKey)) {
            continue;
        }

        if (String.isBlank(mapping.selectedField)) {
            throw new AuraHandledException(
                'Select a Salesforce field for column: ' +
                mapping.csvFieldName
            );
        }

        Data_Feed_Mapping__c record =
            new Data_Feed_Mapping__c();

        record.Mapping_Name__c = wrapper.mappingName;
        record.Operation__c = wrapper.operationType;
        record.File_Name__c = wrapper.fileName;
        record.SObject_API_Name__c = wrapper.objectName;
        record.File_Column_Name__c = mapping.csvFieldName;
        record.Field_to_update__c = mapping.selectedField;
        record.Is_Lookup__c = mapping.isLookup;
        record.Lookup_Filter_Criteria__c = mapping.whereClause;

        if (mapping.isLookup) {
            record.Lookup_Object_Name__c = mapping.lookupObject;
            record.Lookup_Field__c =
                mapping.selectedLookupFields;
            record.Lookup_Return_Field__c = mapping.returnField;
        }

        record.Is_Unique_Key__c = mapping.isUniqueKey;

        recordsToInsert.add(record);
        existingHeaders.add(headerKey);
    }

    if (!recordsToInsert.isEmpty()) {
        insert recordsToInsert;
    }
}
    @AuraEnabled(cacheable=true)
    public static List<Data_Feed_Mapping__c> getMappingDetails(String configurationDisplayName) {
        System.debug('Inside getMappingDetails');
        System.debug('configurationDisplayName-->' +configurationDisplayName);
        try {
            if (String.isBlank(configurationDisplayName)) {
                return new List<Data_Feed_Mapping__c>();
            }

            List<Data_Feed_Mapping__c> mappingDetails = [
                SELECT Mapping_Name__c,
                    File_Column_Name__c,
                    Field_to_update__c,
                    Is_LookUp__c,
                    Lookup_Object_Name__c,
                    Lookup_Field__c,
                    Lookup_Return_Field__c,
                    Lookup_Filter_Criteria__c, Is_Unique_Key__c, Operation__c
                FROM Data_Feed_Mapping__c
                WHERE Configuration_Display_Name__c =
                    :configurationDisplayName
                ORDER BY CreatedDate ASC, Id ASC 
            ];

            System.debug(
                'Selected Configuration: ' + configurationDisplayName
            );

            System.debug(
                'Mapping Details: ' + mappingDetails
            );
            System.debug('mappingDetails size -->' + mappingDetails.size());

            return mappingDetails;

            

        } catch (Exception e) {
            System.debug(
                'Error in getMappingDetails: ' +
                e.getMessage() +
                ' Line: ' + e.getLineNumber()
            );

            throw new AuraHandledException(
                'Unable to retrieve mapping details: ' + e.getMessage()
            );
        }
    }
@AuraEnabled(cacheable=true)
public static List<String> getExistingMappings(String objectName,String operationType) {

    Set<String> mappingNames = new Set<String>();
    if (String.isBlank(objectName) || String.isBlank(operationType)) {
        return new List<String>();
    }

    for (Data_Feed_Mapping__c ar : [
        SELECT Configuration_Display_Name__c
        FROM Data_Feed_Mapping__c
        WHERE Configuration_Display_Name__c != null
        AND SObject_API_Name__c = :objectName
        AND Operation__c = :operationType
        order by CreatedDate desc
    ]) {
        mappingNames.add(ar.Configuration_Display_Name__c);
    }

    List<String> result = new List<String>(mappingNames);
    result.sort();

    System.debug('Mapping Names --> ' + result);

    return result;
}


@AuraEnabled
public static Boolean mappingNameExists(String mappingName) {
    if (String.isBlank(mappingName)) {
        return false;
    }

    String trimmedName = mappingName.trim();

    List<Data_Feed_Mapping__c> existingMappings = [
        SELECT Id
        FROM Data_Feed_Mapping__c
        WHERE Mapping_Name__c = :trimmedName
        LIMIT 1
    ];

    return !existingMappings.isEmpty();
}
    public class ConfigurationWrapper{
        @AuraEnabled public String objectName {get; set;}
        @AuraEnabled public String operationType {get; set;}
        @AuraEnabled public String fileName {get; set;}
        @AuraEnabled public List<ConfigurationMapping> mapping {get; set;}
        @AuraEnabled public String mappingName {get; set;}

    }
    
    public class ConfigurationMapping {
        @AuraEnabled public String csvFieldName {get; set;}
        @AuraEnabled public String selectedField {get; set;}
        @AuraEnabled public Boolean isLookup {get; set;}
        @AuraEnabled public String selectedLookupFields {get; set;}
        @AuraEnabled public String lookupObject {get; set;}
        @AuraEnabled public String whereClause {get; set;}
        @AuraEnabled public Boolean isUniqueKey {get; set;}
        @AuraEnabled public String targetObject {get; set;}
        @AuraEnabled public String matchField {get; set;}
        @AuraEnabled public String returnField {get; set;}
    }
}