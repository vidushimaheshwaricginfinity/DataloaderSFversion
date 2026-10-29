@IsTest
public class ProcessDataFeedTest {

    /*
     * Creates a Job Tracker record.
     */
    private static Data_Feed_Job_Tracker__c createJobTracker(
        String fileName,
        String operation,
        String targetObject,
        String status
    ) {
        Data_Feed_Job_Tracker__c tracker =
            new Data_Feed_Job_Tracker__c(
                File_Name__c = fileName,
                Operation_Type__c = operation,
                Target_Object__c = targetObject,
                Status__c = status
            );

        insert tracker;
        return tracker;
    }


    /*
     * Creates a Data Feed Mapping.
     */
    private static Data_Feed_Mapping__c createMapping(
        String fileName,
        String csvColumn,
        String targetObject,
        String targetField,
        String operation,
        Boolean isLookup,
        Boolean isUniqueKey
    ) {
        Data_Feed_Mapping__c mapping =
            new Data_Feed_Mapping__c(
                File_Name__c = fileName,
                File_Column_Name__c = csvColumn,
                SObject_API_Name__c = targetObject,
                Field_to_update__c = targetField,
                Operation__c = operation,
                Is_Lookup__c = isLookup,
                Is_Unique_Key__c = isUniqueKey
            );

        insert mapping;
        return mapping;
    }


    /*
     * Creates a Lookup Mapping.
     */
    private static Data_Feed_Mapping__c createLookupMapping(
        String fileName,
        String csvColumn,
        String targetObject,
        String targetField,
        String operation,
        String lookupObject,
        String lookupField,
        String returnField
    ) {
        Data_Feed_Mapping__c mapping =
            new Data_Feed_Mapping__c(
                File_Name__c = fileName,
                File_Column_Name__c = csvColumn,
                SObject_API_Name__c = targetObject,
                Field_to_update__c = targetField,
                Operation__c = operation,
                Is_Lookup__c = true,
                Is_Unique_Key__c = false,
                Lookup_Object_Name__c = lookupObject,
                Lookup_Field__c = lookupField,
                Lookup_Return_Field__c = returnField
            );

        insert mapping;
        return mapping;
    }


    /*
     * Creates Data Feed Record.
     */
    private static Data_Feed_Record__c createFeedRecord(
        String fileName,
        Id jobTrackerId,
        Map<String, Object> data
    ) {
        Data_Feed_Record__c record =
            new Data_Feed_Record__c(
                File_Name__c = fileName,
                Data_Feed_Job_Tracker__c = jobTrackerId,
                Data_Feed_Record_JSON__c = JSON.serialize(data),
                Is_Processed__c = false,
                Is_Failed__c = false
            );

        insert record;
        return record;
    }


    // ============================================================
    // TEST 1 : INSERT
    // ============================================================

    @IsTest
    static void testInsert() {

        String fileName = 'Test_Insert.csv';

        Data_Feed_Job_Tracker__c tracker =
            createJobTracker(
                fileName,
                'Insert',
                'Account',
                'Upload Complete'
            );

        createMapping(
            fileName,
            'AccountName',
            'Account',
            'Name',
            'Insert',
            false,
            false
        );

        createFeedRecord(
            fileName,
            tracker.Id,
            new Map<String, Object>{
                'AccountName' => 'Test Insert Account'
            }
        );

        Test.startTest();

        ProcessDataFeed batch =
            new ProcessDataFeed(
                fileName,
                'Insert',
                'Account',
                tracker.Id
            );

        Database.executeBatch(batch, 200);

        Test.stopTest();

        Account acc = [
            SELECT Id, Name
            FROM Account
            WHERE Name = 'Test Insert Account'
            LIMIT 1
        ];

        System.assertEquals(
            'Test Insert Account',
            acc.Name
        );

        Data_Feed_Record__c feedRecord = [
            SELECT Is_Processed__c, Is_Failed__c, Error_Message__c
            FROM Data_Feed_Record__c
            WHERE Data_Feed_Job_Tracker__c = :tracker.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            feedRecord.Is_Processed__c
        );

        System.assertEquals(
            false,
            feedRecord.Is_Failed__c
        );

        Data_Feed_Job_Tracker__c updatedTracker = [
            SELECT Status__c
            FROM Data_Feed_Job_Tracker__c
            WHERE Id = :tracker.Id
        ];

        System.assertEquals(
            'Completed',
            updatedTracker.Status__c
        );
    }


    // ============================================================
    // TEST 2 : UPSERT
    // ============================================================

    @IsTest
    static void testUpsert() {

        Account existingAccount =
            new Account(
                Name = 'Original Account',
                AccountNumber = 'ACC001'
            );

        insert existingAccount;

        String fileName = 'Test_Upsert.csv';

        Data_Feed_Job_Tracker__c tracker =
            createJobTracker(
                fileName,
                'Upsert',
                'Account',
                'Upload Complete'
            );

        createMapping(
            fileName,
            'AccountNumber',
            'Account',
            'AccountNumber',
            'Upsert',
            false,
            true
        );

        createMapping(
            fileName,
            'AccountName',
            'Account',
            'Name',
            'Upsert',
            false,
            false
        );

        createFeedRecord(
            fileName,
            tracker.Id,
            new Map<String, Object>{
                'AccountNumber' => 'ACC001',
                'AccountName' => 'Updated Account'
            }
        );

        Test.startTest();

        ProcessDataFeed batch =
            new ProcessDataFeed(
                fileName,
                'Upsert',
                'Account',
                tracker.Id
            );

        Database.executeBatch(batch, 200);

        Test.stopTest();

        Account result = [
            SELECT Id, Name, AccountNumber
            FROM Account
            WHERE AccountNumber = 'ACC001'
            LIMIT 1
        ];

        System.assertEquals(
            existingAccount.Id,
            result.Id
        );

        System.assertEquals(
            'Updated Account',
            result.Name
        );

        System.assertEquals(
            'ACC001',
            result.AccountNumber
        );
    }


    // ============================================================
    // TEST 3 : UPDATE USING LOOKUP
    // ============================================================

    @IsTest
    static void testUpdateUsingLookup() {

        Account existingAccount =
            new Account(
                Name = 'Original Update Account',
                AccountNumber = 'ACC002'
            );

        insert existingAccount;

        String fileName = 'Test_Update.csv';

        Data_Feed_Job_Tracker__c tracker =
            createJobTracker(
                fileName,
                'Update',
                'Account',
                'Upload Complete'
            );

        /*
         * Lookup mapping:
         *
         * CSV AccountNumber
         *        ↓
         * Account.AccountNumber
         *        ↓
         * Account.Id
         *        ↓
         * Account.Id
         */

        createLookupMapping(
            fileName,
            'AccountNumber',
            'Account',
            'Id',
            'Update',
            'Account',
            'AccountNumber',
            'Id'
        );

        createMapping(
            fileName,
            'AccountName',
            'Account',
            'Name',
            'Update',
            false,
            false
        );

        createFeedRecord(
            fileName,
            tracker.Id,
            new Map<String, Object>{
                'AccountNumber' => 'ACC002',
                'AccountName' => 'Updated Through Lookup'
            }
        );

        Test.startTest();

        ProcessDataFeed batch =
            new ProcessDataFeed(
                fileName,
                'Update',
                'Account',
                tracker.Id
            );

        Database.executeBatch(batch, 200);

        Test.stopTest();

        Account result = [
            SELECT Id, Name, AccountNumber
            FROM Account
            WHERE Id = :existingAccount.Id
        ];

        System.assertEquals(
            existingAccount.Id,
            result.Id
        );

        System.assertEquals(
            'Updated Through Lookup',
            result.Name
        );
    }


    // ============================================================
    // TEST 4 : NORMAL LOOKUP
    // ============================================================

@IsTest
static void testNormalLookup() {

    // Two lookup Accounts
    Account lookupAccount1 = new Account(
        Name = 'Lookup Account 1',
        AccountNumber = 'ACC100'
    );

    Account lookupAccount2 = new Account(
        Name = 'Lookup Account 2',
        AccountNumber = 'ACC101'
    );

    insert new List<Account>{
        lookupAccount1,
        lookupAccount2
    };

    String fileName = 'Test_Normal_Lookup.csv';

    Data_Feed_Job_Tracker__c tracker =
        createJobTracker(
            fileName,
            'Insert',
            'Contact',
            'Upload Complete'
        );

    // Normal target field
    createMapping(
        fileName,
        'LastName',
        'Contact',
        'LastName',
        'Insert',
        false,
        false
    );

    // Lookup mapping
    Data_Feed_Mapping__c lookupMapping =
        createLookupMapping(
            fileName,
            'AccountNumber',
            'Contact',
            'AccountId',
            'Insert',
            'Account',
            'AccountNumber',
            'Id'
        );

    // Add filter criteria to cover filter branch
    lookupMapping.Lookup_Filter_Criteria__c =
        'AccountNumber != null';

    update lookupMapping;

    // TWO feed records
    createFeedRecord(
        fileName,
        tracker.Id,
        new Map<String, Object>{
            'LastName' => 'Lookup Contact 1',
            'AccountNumber' => 'ACC100'
        }
    );

    createFeedRecord(
        fileName,
        tracker.Id,
        new Map<String, Object>{
            'LastName' => 'Lookup Contact 2',
            'AccountNumber' => 'ACC101'
        }
    );

    Test.startTest();

    ProcessDataFeed batch =
        new ProcessDataFeed(
            fileName,
            'Insert',
            'Contact',
            tracker.Id
        );

    Database.executeBatch(batch, 200);

    Test.stopTest();

    List<Contact> results = [
        SELECT Id, LastName, AccountId
        FROM Contact
        WHERE LastName IN (
            'Lookup Contact 1',
            'Lookup Contact 2'
        )
        ORDER BY LastName
    ];

    System.assertEquals(
        2,
        results.size(),
        'Expected two Contacts to be created.'
    );

    System.assertEquals(
        lookupAccount1.Id,
        results[0].AccountId
    );

    System.assertEquals(
        lookupAccount2.Id,
        results[1].AccountId
    );
}
    


    // ============================================================
    // TEST 5 : COMPOSITE LOOKUP
    // ============================================================

    @IsTest
static void testCompositeLookup() {

    // Two existing Contacts for composite lookup
    Contact lookupContact1 = new Contact(
        FirstName = 'John',
        LastName = 'Doe'
    );

    Contact lookupContact2 = new Contact(
        FirstName = 'Jane',
        LastName = 'Smith'
    );

    insert new List<Contact>{
        lookupContact1,
        lookupContact2
    };

    String fileName = 'Test_Composite_Lookup.csv';

    Data_Feed_Job_Tracker__c tracker =
        createJobTracker(
            fileName,
            'Insert',
            'Contact',
            'Upload Complete'
        );

    // Target fields
    createMapping(
        fileName,
        'FirstName',
        'Contact',
        'FirstName',
        'Insert',
        false,
        false
    );

    createMapping(
        fileName,
        'LastName',
        'Contact',
        'LastName',
        'Insert',
        false,
        false
    );

    // Composite lookup
    Data_Feed_Mapping__c lookupMapping =
        createLookupMapping(
            fileName,
            'FirstName,LastName',
            'Contact',
            'ReportsToId',
            'Insert',
            'Contact',
            'FirstName,LastName',
            'Id'
        );

    // Add filter criteria
    lookupMapping.Lookup_Filter_Criteria__c =
        'LastName != null';

    update lookupMapping;

    // First CSV record
    createFeedRecord(
        fileName,
        tracker.Id,
        new Map<String, Object>{
            'FirstName' => 'John',
            'LastName' => 'Doe'
        }
    );

    // Second CSV record
    createFeedRecord(
        fileName,
        tracker.Id,
        new Map<String, Object>{
            'FirstName' => 'Jane',
            'LastName' => 'Smith'
        }
    );

    Test.startTest();

    ProcessDataFeed batch =
        new ProcessDataFeed(
            fileName,
            'Insert',
            'Contact',
            tracker.Id
        );

    Database.executeBatch(batch, 200);

    Test.stopTest();

    List<Contact> results = [
        SELECT Id,
               FirstName,
               LastName,
               ReportsToId
        FROM Contact
        WHERE FirstName IN ('John', 'Jane')
        AND LastName IN ('Doe', 'Smith')
        ORDER BY FirstName
    ];

    System.assertEquals(
        2,
        results.size(),
        'Expected two Contacts.'
    );

    System.assertEquals(
        lookupContact1.Id,
        results[0].ReportsToId
    );

    System.assertEquals(
        lookupContact2.Id,
        results[1].ReportsToId
    );
}
    @IsTest
static void testDirectNormalLookupCoverage() {

    // Lookup records
    Account acc1 = new Account(
        Name = 'Lookup Acc 1',
        AccountNumber = 'LKP001'
    );

    Account acc2 = new Account(
        Name = 'Lookup Acc 2',
        AccountNumber = 'LKP002'
    );

    insert new List<Account>{ acc1, acc2 };

    String fileName = 'Direct_Normal_Lookup.csv';

    Data_Feed_Job_Tracker__c tracker =
        createJobTracker(
            fileName,
            'Insert',
            'Contact',
            'Upload Complete'
        );

    // Normal field
    createMapping(
        fileName,
        'LastName',
        'Contact',
        'LastName',
        'Insert',
        false,
        false
    );

    // Lookup
    createLookupMapping(
        fileName,
        'AccountNumber',
        'Contact',
        'AccountId',
        'Insert',
        'Account',
        'AccountNumber',
        'Id'
    );

    // IMPORTANT: two records
    createFeedRecord(
        fileName,
        tracker.Id,
        new Map<String,Object>{
            'LastName' => 'Contact One',
            'AccountNumber' => 'LKP001'
        }
    );

    createFeedRecord(
        fileName,
        tracker.Id,
        new Map<String,Object>{
            'LastName' => 'Contact Two',
            'AccountNumber' => 'LKP002'
        }
    );

    List<Data_Feed_Record__c> scope = [
        SELECT Id,
               File_Name__c,
               Data_Feed_Record_JSON__c,
               Is_Processed__c,
               Is_Failed__c,
               Error_Message__c,
               Data_Feed_Job_Tracker__c
        FROM Data_Feed_Record__c
        WHERE Data_Feed_Job_Tracker__c = :tracker.Id
        ORDER BY CreatedDate
    ];

    Test.startTest();

    ProcessDataFeed batch = new ProcessDataFeed(
        fileName,
        'Insert',
        'Contact',
        tracker.Id
    );

    // DIRECTLY execute the method containing lines 170-347
    batch.execute(null, scope);

    Test.stopTest();

    List<Contact> contacts = [
        SELECT Id, LastName, AccountId
        FROM Contact
        WHERE LastName IN ('Contact One', 'Contact Two')
    ];

    System.assertEquals(2, contacts.size());

    for (Contact c : contacts) {
        System.assertNotEquals(
            null,
            c.AccountId,
            'Account lookup should have been populated.'
        );
    }
}
    @IsTest
static void testDirectCompositeLookupCoverage() {

    Contact lookup1 = new Contact(
        FirstName = 'John',
        LastName = 'Doe'
    );

    Contact lookup2 = new Contact(
        FirstName = 'Jane',
        LastName = 'Smith'
    );

    insert new List<Contact>{ lookup1, lookup2 };

    String fileName = 'Direct_Composite_Lookup.csv';

    Data_Feed_Job_Tracker__c tracker =
        createJobTracker(
            fileName,
            'Insert',
            'Contact',
            'Upload Complete'
        );

    createMapping(
        fileName,
        'FirstName',
        'Contact',
        'FirstName',
        'Insert',
        false,
        false
    );

    createMapping(
        fileName,
        'LastName',
        'Contact',
        'LastName',
        'Insert',
        false,
        false
    );

    createLookupMapping(
        fileName,
        'FirstName,LastName',
        'Contact',
        'ReportsToId',
        'Insert',
        'Contact',
        'FirstName,LastName',
        'Id'
    );

    createFeedRecord(
        fileName,
        tracker.Id,
        new Map<String,Object>{
            'FirstName' => 'John',
            'LastName' => 'Doe'
        }
    );

    createFeedRecord(
        fileName,
        tracker.Id,
        new Map<String,Object>{
            'FirstName' => 'Jane',
            'LastName' => 'Smith'
        }
    );

    List<Data_Feed_Record__c> scope = [
        SELECT Id,
               File_Name__c,
               Data_Feed_Record_JSON__c,
               Is_Processed__c,
               Is_Failed__c,
               Error_Message__c,
               Data_Feed_Job_Tracker__c
        FROM Data_Feed_Record__c
        WHERE Data_Feed_Job_Tracker__c = :tracker.Id
        ORDER BY CreatedDate
    ];

    Test.startTest();

    ProcessDataFeed batch = new ProcessDataFeed(
        fileName,
        'Insert',
        'Contact',
        tracker.Id
    );

    batch.execute(null, scope);

    Test.stopTest();

    List<Contact> results = [
        SELECT Id,
               FirstName,
               LastName,
               ReportsToId
        FROM Contact
        WHERE FirstName IN ('John', 'Jane')
        AND LastName IN ('Doe', 'Smith')
        ORDER BY FirstName
    ];

    System.assertEquals(2, results.size());
}
    // ============================================================
    // TEST 6 : DATA TYPE CONVERSION
    // ============================================================

    @IsTest
    static void testDataTypeConversion() {

        String fileName = 'Test_DataTypes.csv';

        Data_Feed_Job_Tracker__c tracker =
            createJobTracker(
                fileName,
                'Insert',
                'Account',
                'Upload Complete'
            );

        createMapping(
            fileName,
            'AccountName',
            'Account',
            'Name',
            'Insert',
            false,
            false
        );

        createMapping(
            fileName,
            'AnnualRevenue',
            'Account',
            'AnnualRevenue',
            'Insert',
            false,
            false
        );

        createFeedRecord(
            fileName,
            tracker.Id,
            new Map<String, Object>{
                'AccountName' => 'Conversion Test',
                'AnnualRevenue' => '100000.50'
            }
        );

        Test.startTest();

        ProcessDataFeed batch =
            new ProcessDataFeed(
                fileName,
                'Insert',
                'Account',
                tracker.Id
            );

        Database.executeBatch(batch, 200);

        Test.stopTest();

        Account result = [
            SELECT Id,
                   Name,
                   AnnualRevenue
            FROM Account
            WHERE Name = 'Conversion Test'
            LIMIT 1
        ];

        System.assertEquals(
            'Conversion Test',
            result.Name
        );

        System.assertEquals(
            Decimal.valueOf('100000.50'),
            result.AnnualRevenue
        );
    }


    // ============================================================
    // TEST 7 : FAILED UPDATE
    // ============================================================

    @IsTest
    static void testFailedUpdate() {

        String fileName = 'Test_Failed_Update.csv';

        Data_Feed_Job_Tracker__c tracker =
            createJobTracker(
                fileName,
                'Update',
                'Account',
                'Upload Complete'
            );

        createLookupMapping(
            fileName,
            'AccountNumber',
            'Account',
            'Id',
            'Update',
            'Account',
            'AccountNumber',
            'Id'
        );

        createMapping(
            fileName,
            'AccountName',
            'Account',
            'Name',
            'Update',
            false,
            false
        );

        /*
         * No Account exists with ACC-NOT-FOUND.
         * Therefore update should fail.
         */

        createFeedRecord(
            fileName,
            tracker.Id,
            new Map<String, Object>{
                'AccountNumber' => 'ACC-NOT-FOUND',
                'AccountName' => 'Should Fail'
            }
        );

        Test.startTest();

        ProcessDataFeed batch =
            new ProcessDataFeed(
                fileName,
                'Update',
                'Account',
                tracker.Id
            );

        Database.executeBatch(batch, 200);

        Test.stopTest();

        Data_Feed_Record__c result = [
            SELECT Is_Processed__c,
                   Is_Failed__c,
                   Error_Message__c
            FROM Data_Feed_Record__c
            WHERE Data_Feed_Job_Tracker__c = :tracker.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            result.Is_Processed__c
        );

        /*
         * Depending on the exact failure path,
         * Error_Message__c should contain the reason.
         */
        System.assert(
            String.isNotBlank(result.Error_Message__c),
            'Expected an error message for failed update.'
        );
    }
}