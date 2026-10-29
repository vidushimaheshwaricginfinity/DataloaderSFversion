@IsTest
private class CSVConfigurationMappingTest {

    // ============================================================
    // TEST DATA HELPER
    // ============================================================

    private static String buildWrapperJson(
        String objectName,
        String operationType,
        String fileName,
        String mappingName,
        List<Map<String, Object>> mappingList
    ) {
        Map<String, Object> wrapper = new Map<String, Object>();

        wrapper.put('objectName', objectName);
        wrapper.put('operationType', operationType);
        wrapper.put('fileName', fileName);
        wrapper.put('mappingName', mappingName);
        wrapper.put('mapping', mappingList);

        return JSON.serialize(wrapper);
    }


    // ============================================================
    // TEST 1
    // Normal INSERT mapping
    // ============================================================

    @IsTest
    static void testCreateConfiguration_NormalMapping() {

        List<Map<String, Object>> mappings =
            new List<Map<String, Object>>();

        mappings.add(
            new Map<String, Object>{
                'csvFieldName' => 'AccountName',
                'selectedField' => 'Name',
                'isLookup' => false,
                'isUniqueKey' => false
            }
        );

        String wrapperJson = buildWrapperJson(
            'Account',
            'Insert',
            'Account.csv',
            'Account Mapping',
            mappings
        );

        Test.startTest();

        CSVConfigurationMapping.createConfiguration(wrapperJson);

        Test.stopTest();

        Data_Feed_Mapping__c result = [
            SELECT
                File_Name__c,
                File_Column_Name__c,
                Field_to_update__c,
                SObject_API_Name__c,
                Mapping_Name__c,
                Operation__c,
                Is_Lookup__c,
                Is_Unique_Key__c,
                Lookup_Filter_Criteria__c
            FROM Data_Feed_Mapping__c
            WHERE Mapping_Name__c = 'Account Mapping'
            LIMIT 1
        ];

        System.assertEquals(
            'Account.csv',
            result.File_Name__c
        );

        System.assertEquals(
            'AccountName',
            result.File_Column_Name__c
        );

        System.assertEquals(
            'Name',
            result.Field_to_update__c
        );

        System.assertEquals(
            'Account',
            result.SObject_API_Name__c
        );

        System.assertEquals(
            'Insert',
            result.Operation__c
        );

        System.assertEquals(
            false,
            result.Is_Lookup__c
        );

        System.assertEquals(
            false,
            result.Is_Unique_Key__c
        );
    }
    @IsTest
static void testCreateConfiguration_NullWrapper() {

    Boolean exceptionThrown = false;

    Test.startTest();

    try {
        CSVConfigurationMapping.createConfiguration('null');
    } catch (Exception e) {
        exceptionThrown = true;
    }

    Test.stopTest();

    System.assertEquals(
        true,
        exceptionThrown,
        'Expected AuraHandledException for null wrapper.'
    );
}
    @IsTest
static void testCreateConfiguration_MissingObjectName() {

    List<Map<String, Object>> mappings =
        new List<Map<String, Object>>();

    mappings.add(
        new Map<String, Object>{
            'csvFieldName' => 'Name',
            'selectedField' => 'Name',
            'isLookup' => false,
            'isUniqueKey' => false
        }
    );

    String json = buildWrapperJson(
        '',
        'Insert',
        'Test.csv',
        'Test Mapping',
        mappings
    );

    Boolean exceptionThrown = false;

    Test.startTest();

    try {
        CSVConfigurationMapping.createConfiguration(json);
    } catch (Exception e) {
        exceptionThrown = true;
    }

    Test.stopTest();

    System.assertEquals(true, exceptionThrown);
}
    @IsTest
static void testCreateConfiguration_MissingOperation() {

    List<Map<String, Object>> mappings =
        new List<Map<String, Object>>();

    mappings.add(
        new Map<String, Object>{
            'csvFieldName' => 'Name',
            'selectedField' => 'Name',
            'isLookup' => false,
            'isUniqueKey' => false
        }
    );

    String json = buildWrapperJson(
        'Account',
        '',
        'Test.csv',
        'Test Mapping',
        mappings
    );

    Boolean exceptionThrown = false;

    Test.startTest();

    try {
        CSVConfigurationMapping.createConfiguration(json);
    } catch (Exception e) {
        exceptionThrown = true;
    }

    Test.stopTest();

    System.assertEquals(true, exceptionThrown);
}
    @IsTest
static void testCreateConfiguration_MissingMappingName() {

    List<Map<String, Object>> mappings =
        new List<Map<String, Object>>();

    mappings.add(
        new Map<String, Object>{
            'csvFieldName' => 'Name',
            'selectedField' => 'Name',
            'isLookup' => false,
            'isUniqueKey' => false
        }
    );

    String json = buildWrapperJson(
        'Account',
        'Insert',
        'Test.csv',
        '',
        mappings
    );

    Boolean exceptionThrown = false;

    Test.startTest();

    try {
        CSVConfigurationMapping.createConfiguration(json);
    } catch (Exception e) {
        exceptionThrown = true;
    }

    Test.stopTest();

    System.assertEquals(true, exceptionThrown);
}
    @IsTest
static void testCreateConfiguration_NoMappings() {

    String json = buildWrapperJson(
        'Account',
        'Insert',
        'Test.csv',
        'Test Mapping',
        new List<Map<String, Object>>()
    );

    Boolean exceptionThrown = false;

    Test.startTest();

    try {
        CSVConfigurationMapping.createConfiguration(json);
    } catch (Exception e) {
        exceptionThrown = true;
    }

    Test.stopTest();

    System.assertEquals(true, exceptionThrown);
}


    // ============================================================
    // TEST 2
    // Lookup mapping
    // ============================================================

    @IsTest
    static void testCreateConfiguration_LookupMapping() {

        List<Map<String, Object>> mappings =
            new List<Map<String, Object>>();

        mappings.add(
            new Map<String, Object>{
                'csvFieldName' => 'AccountNumber',
                'selectedField' => 'AccountId',
                'isLookup' => true,
                'isUniqueKey' => false,
                'lookupObject' => 'Account',
                'selectedLookupFields' => 'AccountNumber',
                'whereClause' => 'IsActive__c = true',
                'returnField' => 'Id'
            }
        );

        String wrapperJson = buildWrapperJson(
            'Contact',
            'Insert',
            'Contact.csv',
            'Contact Lookup Mapping',
            mappings
        );

        Test.startTest();

        CSVConfigurationMapping.createConfiguration(wrapperJson);

        Test.stopTest();

        Data_Feed_Mapping__c result = [
            SELECT
                File_Name__c,
                File_Column_Name__c,
                Field_to_update__c,
                SObject_API_Name__c,
                Mapping_Name__c,
                Operation__c,
                Is_Lookup__c,
                Lookup_Object_Name__c,
                Lookup_Field__c,
                Lookup_Return_Field__c,
                Lookup_Filter_Criteria__c
            FROM Data_Feed_Mapping__c
            WHERE Mapping_Name__c = 'Contact Lookup Mapping'
            LIMIT 1
        ];

        System.assertEquals(
            true,
            result.Is_Lookup__c
        );

        System.assertEquals(
            'Account',
            result.Lookup_Object_Name__c
        );

        System.assertEquals(
            'AccountNumber',
            result.Lookup_Field__c
        );

        System.assertEquals(
            'Id',
            result.Lookup_Return_Field__c
        );

        System.assertEquals(
            'IsActive__c = true',
            result.Lookup_Filter_Criteria__c
        );
    }
    @IsTest
static void testCreateConfiguration_MissingCsvField() {

    List<Map<String, Object>> mappings =
        new List<Map<String, Object>>();

    mappings.add(
        new Map<String, Object>{
            'csvFieldName' => '',
            'selectedField' => 'Name',
            'isLookup' => false,
            'isUniqueKey' => false
        }
    );

    String json = buildWrapperJson(
        'Account',
        'Insert',
        'Test.csv',
        'Test Mapping',
        mappings
    );

    Boolean exceptionThrown = false;

    Test.startTest();

    try {
        CSVConfigurationMapping.createConfiguration(json);
    } catch (Exception e) {
        exceptionThrown = true;
    }

    Test.stopTest();

    System.assertEquals(true, exceptionThrown);
}
    @IsTest
static void testCreateConfiguration_MissingSelectedField() {

    List<Map<String, Object>> mappings =
        new List<Map<String, Object>>();

    mappings.add(
        new Map<String, Object>{
            'csvFieldName' => 'AccountName',
            'selectedField' => '',
            'isLookup' => false,
            'isUniqueKey' => false
        }
    );

    String json = buildWrapperJson(
        'Account',
        'Insert',
        'Test.csv',
        'Test Mapping',
        mappings
    );

    Boolean exceptionThrown = false;

    Test.startTest();

    try {
        CSVConfigurationMapping.createConfiguration(json);
    } catch (Exception e) {
        exceptionThrown = true;
    }

    Test.stopTest();

    System.assertEquals(true, exceptionThrown);
}


    // ============================================================
    // TEST 3
    // Lookup using targetObject + matchField
    // This covers the preferred lookup values
    // ============================================================

    @IsTest
    static void testCreateConfiguration_LookupPreferredFields() {

        List<Map<String, Object>> mappings =
            new List<Map<String, Object>>();

        mappings.add(
            new Map<String, Object>{
                'csvFieldName' => 'BrandCode',
                'selectedField' => 'Brand__c',
                'isLookup' => true,
                'isUniqueKey' => false,

                // Preferred values
                'targetObject' => 'Brand__c',
                'matchField' => 'Brand_Code__c',
                'returnField' => 'Id',

                // Fallback values deliberately different
                'lookupObject' => 'Account',
                'selectedLookupFields' => 'Name'
            }
        );

        String wrapperJson = buildWrapperJson(
            'Account',
            'Insert',
            'Brand.csv',
            'Brand Lookup Mapping',
            mappings
        );

        Test.startTest();

        CSVConfigurationMapping.createConfiguration(wrapperJson);

        Test.stopTest();

        Data_Feed_Mapping__c result = [
            SELECT
                Is_Lookup__c,
                Lookup_Object_Name__c,
                Lookup_Field__c,
                Lookup_Return_Field__c
            FROM Data_Feed_Mapping__c
            WHERE Mapping_Name__c = 'Brand Lookup Mapping'
            LIMIT 1
        ];

        System.assertEquals(
            true,
            result.Is_Lookup__c
        );

        System.assertEquals(
            'Brand__c',
            result.Lookup_Object_Name__c
        );

        System.assertEquals(
            'Brand_Code__c',
            result.Lookup_Field__c
        );

        System.assertEquals(
            'Id',
            result.Lookup_Return_Field__c
        );
    }


    // ============================================================
    // TEST 4
    // Lookup fallback values
    // ============================================================

    @IsTest
    static void testCreateConfiguration_LookupFallbackFields() {

        List<Map<String, Object>> mappings =
            new List<Map<String, Object>>();

        mappings.add(
            new Map<String, Object>{
                'csvFieldName' => 'AccountNumber',
                'selectedField' => 'AccountId',
                'isLookup' => true,
                'isUniqueKey' => false,

                // targetObject / matchField blank
                // so fallback values should be used
                'targetObject' => '',
                'matchField' => '',
                'returnField' => '',

                'lookupObject' => 'Account',
                'selectedLookupFields' => 'AccountNumber'
            }
        );

        String wrapperJson = buildWrapperJson(
            'Contact',
            'Insert',
            'ContactFallback.csv',
            'Fallback Lookup Mapping',
            mappings
        );

        Test.startTest();

        CSVConfigurationMapping.createConfiguration(wrapperJson);

        Test.stopTest();

        Data_Feed_Mapping__c result = [
            SELECT
                Lookup_Object_Name__c,
                Lookup_Field__c,
                Lookup_Return_Field__c
            FROM Data_Feed_Mapping__c
            WHERE Mapping_Name__c = 'Fallback Lookup Mapping'
            LIMIT 1
        ];

        System.assertEquals(
            'Account',
            result.Lookup_Object_Name__c
        );

        System.assertEquals(
            'AccountNumber',
            result.Lookup_Field__c
        );

        // returnField blank -> Id
        System.assertEquals(
            'Id',
            result.Lookup_Return_Field__c
        );
    }


    // ============================================================
    // TEST 5
    // UPSERT + UNIQUE KEY
    // ============================================================

    @IsTest
    static void testCreateConfiguration_UpsertUniqueKey() {

        List<Map<String, Object>> mappings =
            new List<Map<String, Object>>();

        mappings.add(
            new Map<String, Object>{
                'csvFieldName' => 'AccountNumber',
                'selectedField' => 'AccountNumber',
                'isLookup' => false,
                'isUniqueKey' => true
            }
        );

        mappings.add(
            new Map<String, Object>{
                'csvFieldName' => 'AccountName',
                'selectedField' => 'Name',
                'isLookup' => false,
                'isUniqueKey' => false
            }
        );

        String wrapperJson = buildWrapperJson(
            'Account',
            'Upsert',
            'AccountUpsert.csv',
            'Account Upsert Mapping',
            mappings
        );

        Test.startTest();

        CSVConfigurationMapping.createConfiguration(wrapperJson);

        Test.stopTest();

        List<Data_Feed_Mapping__c> results = [
            SELECT
                File_Column_Name__c,
                Field_to_update__c,
                Operation__c,
                Is_Unique_Key__c
            FROM Data_Feed_Mapping__c
            WHERE Mapping_Name__c = 'Account Upsert Mapping'
            ORDER BY CreatedDate ASC
        ];

        System.assertEquals(
            2,
            results.size()
        );

        System.assertEquals(
            true,
            results[0].Is_Unique_Key__c
        );

        System.assertEquals(
            false,
            results[1].Is_Unique_Key__c
        );

        System.assertEquals(
            'Upsert',
            results[0].Operation__c
        );
    }


    // ============================================================
    // TEST 6
    // getMappingDetails - blank
    // ============================================================

    @IsTest
    static void testGetMappingDetails_Blank() {

        Test.startTest();

        List<Data_Feed_Mapping__c> results =
            CSVConfigurationMapping.getMappingDetails('');

        Test.stopTest();

        System.assertNotEquals(
            null,
            results
        );

        System.assertEquals(
            0,
            results.size()
        );
    }


    // ============================================================
    // TEST 7
    // getMappingDetails - valid configuration
    // ============================================================

    @IsTest
    static void testGetMappingDetails_Valid() {

        Data_Feed_Mapping__c mapping =
            new Data_Feed_Mapping__c(
                File_Name__c = 'Details.csv',
                File_Column_Name__c = 'AccountNumber',
                Field_to_update__c = 'AccountNumber',
                SObject_API_Name__c = 'Account',
                Mapping_Name__c = 'Details Mapping',
                //Configuration_Display_Name__c = 'Account - Upsert - Details',
                Operation__c = 'Upsert',
                Is_Lookup__c = false,
                Is_Unique_Key__c = true,
                Lookup_Filter_Criteria__c = ''
            );

        insert mapping;

        Test.startTest();

        List<Data_Feed_Mapping__c> results =
            CSVConfigurationMapping.getMappingDetails(
                'Account - Upsert - Details'
            );

        Test.stopTest();

        System.assertEquals(
            1,
            results.size()
        );

        System.assertEquals(
            'AccountNumber',
            results[0].File_Column_Name__c
        );

        System.assertEquals(
            'AccountNumber',
            results[0].Field_to_update__c
        );

        System.assertEquals(
            true,
            results[0].Is_Unique_Key__c
        );

        System.assertEquals(
            'Upsert',
            results[0].Operation__c
        );
    }


    // ============================================================
    // TEST 8
    // getExistingMappings - blank
    // ============================================================

    @IsTest
    static void testGetExistingMappings_Blank() {

        Test.startTest();

        List<String> results =
            CSVConfigurationMapping.getExistingMappings(
                '',
                ''
            );

        Test.stopTest();

        System.assertNotEquals(
            null,
            results
        );

        System.assertEquals(
            0,
            results.size()
        );
    }


    // ============================================================
    // TEST 9
    // getExistingMappings - valid
    // ============================================================

    @IsTest
    static void testGetExistingMappings_Valid() {

        List<Data_Feed_Mapping__c> mappings =
            new List<Data_Feed_Mapping__c>();

        mappings.add(
            new Data_Feed_Mapping__c(
                File_Name__c = 'File1.csv',
                File_Column_Name__c = 'Name',
                Field_to_update__c = 'Name',
                SObject_API_Name__c = 'Account',
                Mapping_Name__c = 'Mapping 1',
                //Configuration_Display_Name__c = 'Account - Insert - Mapping 1',
                Operation__c = 'Insert',
                Is_Lookup__c = false
            )
        );

        mappings.add(
            new Data_Feed_Mapping__c(
                File_Name__c = 'File2.csv',
                File_Column_Name__c = 'AccountNumber',
                Field_to_update__c = 'AccountNumber',
                SObject_API_Name__c = 'Account',
                Mapping_Name__c = 'Mapping 2',
                //Configuration_Display_Name__c = 'Account - Insert - Mapping 2',
                Operation__c = 'Insert',
                Is_Lookup__c = false
            )
        );

        // Different operation - should not be returned
        mappings.add(
            new Data_Feed_Mapping__c(
                File_Name__c = 'File3.csv',
                File_Column_Name__c = 'Name',
                Field_to_update__c = 'Name',
                SObject_API_Name__c = 'Account',
                Mapping_Name__c = 'Mapping 3',
                //Configuration_Display_Name__c = 'Account - Update - Mapping 3',
                Operation__c = 'Update',
                Is_Lookup__c = false
            )
        );

        insert mappings;

        Test.startTest();

        List<String> results =
            CSVConfigurationMapping.getExistingMappings(
                'Account',
                'Insert'
            );

        Test.stopTest();

        System.assertEquals(
            2,
            results.size()
        );

        System.assert(
            results.contains(
                'Account - Insert - Mapping 1'
            )
        );

        System.assert(
            results.contains(
                'Account - Insert - Mapping 2'
            )
        );

        System.assert(
            !results.contains(
                'Account - Update - Mapping 3'
            )
        );
    }


    // ============================================================
    // TEST 10
    // Multiple mappings in one configuration
    // ============================================================

    @IsTest
    static void testCreateConfiguration_MultipleMappings() {

        List<Map<String, Object>> mappings =
            new List<Map<String, Object>>();

        mappings.add(
            new Map<String, Object>{
                'csvFieldName' => 'FirstName',
                'selectedField' => 'FirstName',
                'isLookup' => false,
                'isUniqueKey' => false
            }
        );

        mappings.add(
            new Map<String, Object>{
                'csvFieldName' => 'LastName',
                'selectedField' => 'LastName',
                'isLookup' => false,
                'isUniqueKey' => false
            }
        );

        mappings.add(
            new Map<String, Object>{
                'csvFieldName' => 'Email',
                'selectedField' => 'Email',
                'isLookup' => false,
                'isUniqueKey' => false
            }
        );

        String wrapperJson = buildWrapperJson(
            'Contact',
            'Insert',
            'Contacts.csv',
            'Contact Mapping',
            mappings
        );

        Test.startTest();

        CSVConfigurationMapping.createConfiguration(wrapperJson);

        Test.stopTest();

        List<Data_Feed_Mapping__c> results = [
            SELECT
                File_Column_Name__c,
                Field_to_update__c
            FROM Data_Feed_Mapping__c
            WHERE Mapping_Name__c = 'Contact Mapping'
            ORDER BY CreatedDate ASC
        ];

        System.assertEquals(
            3,
            results.size()
        );
    }
}