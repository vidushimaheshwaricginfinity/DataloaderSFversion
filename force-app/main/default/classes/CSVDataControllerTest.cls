@IsTest
public class CSVDataControllerTest {

    // --------------------------------------------------
    // TEST 1: Get Salesforce objects
    // --------------------------------------------------
    @IsTest
    static void testGetObjects() {

        Test.startTest();
        List<CSVDataController.SObjectDescribe> results =
            CSVDataController.getObjects();
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() > 0);

        Boolean accountFound = false;

        for (CSVDataController.SObjectDescribe obj : results) {
            if (obj.apiName == 'Account') {
                accountFound = true;
                System.assertNotEquals(null, obj.label);
            }
        }

        System.assertEquals(
            true,
            accountFound,
            'Account should be present in the available objects.'
        );
    }


    // --------------------------------------------------
    // TEST 2: Get fields for Account
    // --------------------------------------------------
    @IsTest
    static void testGetFields() {

        Test.startTest();
        List<CSVDataController.FieldDescribe> results =
            CSVDataController.getFields('Account');
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() > 0);

        Boolean nameFound = false;
        Boolean idFound = false;

        for (CSVDataController.FieldDescribe field : results) {
            if (field.apiName == 'Name') {
                nameFound = true;
            }

            if (field.apiName == 'Id') {
                idFound = true;
            }
        }

        System.assertEquals(true, nameFound);
        System.assertEquals(true, idFound);
    }


    // --------------------------------------------------
    // TEST 3: Invalid object name returns empty list
    // --------------------------------------------------
    @IsTest
    static void testGetFields_InvalidObject() {

        Test.startTest();
        List<CSVDataController.FieldDescribe> results =
            CSVDataController.getFields('InvalidObjectXYZ');
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assertEquals(0, results.size());
    }


    // --------------------------------------------------
    // TEST 4: Test lookup field detection
    // --------------------------------------------------
    @IsTest
    static void testIsLookupField() {

        Schema.SObjectField accountIdField =
            Account.Id.getDescribe().getSObjectField();

        Schema.SObjectField contactAccountIdField =
            Contact.AccountId.getDescribe().getSObjectField();

        Test.startTest();

        Boolean idResult =
            CSVDataController.isLookupField(accountIdField);

        Boolean lookupResult =
            CSVDataController.isLookupField(contactAccountIdField);

        Boolean nameResult =
            CSVDataController.isLookupField(Account.Name);

        Test.stopTest();

        System.assertEquals(true, idResult);
        System.assertEquals(true, lookupResult);
        System.assertEquals(false, nameResult);
    }


    // --------------------------------------------------
    // TEST 5: Fetch Account data
    // --------------------------------------------------
    @IsTest
    static void testFetchData() {

        Account acc = new Account(
            Name = 'CSV Test Account',
            AccountNumber = 'CSV001'
        );
        insert acc;

        Test.startTest();

        List<Map<String, Object>> results =
            CSVDataController.fetchData(
                'Account',
                new List<String>{ 'Name', 'AccountNumber' }
            );

        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() > 0);

        Boolean recordFound = false;

        for (Map<String, Object> row : results) {
            if (String.valueOf(row.get('Name')) ==
                'CSV Test Account') {

                recordFound = true;

                System.assertEquals(
                    'CSV001',
                    String.valueOf(row.get('AccountNumber'))
                );
            }
        }

        System.assertEquals(
            true,
            recordFound,
            'The inserted Account should be returned.'
        );
    }


    // --------------------------------------------------
    // TEST 6: Generate CSV with regular fields
    // --------------------------------------------------
    @IsTest
    static void testGenerateCSV_RegularFields() {

        Account acc = new Account(
            Name = 'CSV Generate Account',
            AccountNumber = 'CSV100'
        );
        insert acc;

        Test.startTest();

        String result = CSVDataController.generateCSV(
            'Account',
            new List<String>{ 'Name', 'AccountNumber' }
        );

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.contains('Name,AccountNumber'));
        System.assert(result.contains('CSV Generate Account'));
        System.assert(result.contains('CSV100'));
    }


    // --------------------------------------------------
    // TEST 7: Generate CSV with relationship fields
    // --------------------------------------------------
    @IsTest
    static void testGenerateCSV_RelationshipFields() {

        Account acc = new Account(
            Name = 'Relationship Test Account'
        );
        insert acc;

        Contact con = new Contact(
            FirstName = 'Chirag',
            LastName = 'TestContact',
            AccountId = acc.Id
        );
        insert con;

        Test.startTest();

        String result = CSVDataController.generateCSV(
            'Contact',
            new List<String>{
                'FirstName',
                'LastName',
                'Account.Name'
            }
        );

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.contains('FirstName,LastName,Account.Name'));
        System.assert(result.contains('Chirag'));
        System.assert(result.contains('TestContact'));
        System.assert(result.contains('Relationship Test Account'));
    }


    // --------------------------------------------------
    // TEST 8: Generate CSV with null relationship
    // --------------------------------------------------
    @IsTest
    static void testGenerateCSV_NullRelationship() {

        Contact con = new Contact(
            FirstName = 'No',
            LastName = 'RelatedAccount'
        );
        insert con;

        Test.startTest();

        String result = CSVDataController.generateCSV(
            'Contact',
            new List<String>{
                'FirstName',
                'LastName',
                'Account.Name'
            }
        );

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.contains('No,RelatedAccount,null'));
    }


    // --------------------------------------------------
    // TEST 9: Generate CSV with empty object name
    // --------------------------------------------------
    @IsTest
    static void testGenerateCSV_EmptyObject() {

        Test.startTest();

        String result = CSVDataController.generateCSV(
            '',
            new List<String>{ 'Name' }
        );

        Test.stopTest();

        System.assertEquals(null, result);
    }


    // --------------------------------------------------
    // TEST 10: Generate CSV with empty fields
    // --------------------------------------------------
    @IsTest
    static void testGenerateCSV_EmptyFields() {

        Test.startTest();

        String result = CSVDataController.generateCSV(
            'Account',
            new List<String>()
        );

        Test.stopTest();

        System.assertEquals(null, result);
    }
}