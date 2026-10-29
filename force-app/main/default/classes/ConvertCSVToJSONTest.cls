@IsTest
public class ConvertCSVToJSONTest {

    // Test 1: Parse multiple rows
    @IsTest
    static void testParseCSV_MultipleRows() {

        String csv =
            'Name,AccountNumber\n' +
            'Test Account 1,ACC001\n' +
            'Test Account 2,ACC002';

        Blob csvBlob = Blob.valueOf(csv);

        Test.startTest();
        List<Object> results =
            ConvertCSVToJSON.parseCSV(csvBlob);
        Test.stopTest();

        System.assertEquals(2, results.size());

        Map<String, Object> row1 =
            (Map<String, Object>) results[0];

        Map<String, Object> row2 =
            (Map<String, Object>) results[1];

        System.assertEquals(
            'Test Account 1',
            row1.get('Name')
        );

        System.assertEquals(
            'ACC001',
            row1.get('AccountNumber')
        );

        System.assertEquals(
            'Test Account 2',
            row2.get('Name')
        );

        System.assertEquals(
            'ACC002',
            row2.get('AccountNumber')
        );
    }


    // Test 2: Verify whitespace is trimmed
    @IsTest
    static void testParseCSV_TrimWhitespace() {

        String csv =
            ' Name , AccountNumber \n' +
            ' Test Account , ACC100 ';

        List<Object> results =
            ConvertCSVToJSON.parseCSV(
                Blob.valueOf(csv)
            );

        System.assertEquals(1, results.size());

        Map<String, Object> row =
            (Map<String, Object>) results[0];

        System.assertEquals(
            'Test Account',
            row.get('Name')
        );

        System.assertEquals(
            'ACC100',
            row.get('AccountNumber')
        );
    }


    // Test 3: A row has fewer values than headers
    @IsTest
    static void testParseCSV_MissingColumnValue() {

        String csv =
            'Name,AccountNumber,Phone\n' +
            'Test Account,ACC200';

        List<Object> results =
            ConvertCSVToJSON.parseCSV(
                Blob.valueOf(csv)
            );

        System.assertEquals(1, results.size());

        Map<String, Object> row =
            (Map<String, Object>) results[0];

        System.assertEquals(
            'Test Account',
            row.get('Name')
        );

        System.assertEquals(
            'ACC200',
            row.get('AccountNumber')
        );

        // Missing values are not added to the map
        System.assertEquals(
            false,
            row.containsKey('Phone')
        );
    }


    // Test 4: Header only, no data rows
    @IsTest
    static void testParseCSV_HeaderOnly() {

        String csv = 'Name,AccountNumber';

        List<Object> results =
            ConvertCSVToJSON.parseCSV(
                Blob.valueOf(csv)
            );

        System.assertEquals(0, results.size());
    }


    // Test 5: Empty input
    @IsTest
    static void testParseCSV_EmptyInput() {

        String csv = '';

        Test.startTest();

        List<Object> results =
            ConvertCSVToJSON.parseCSV(
                Blob.valueOf(csv)
            );

        Test.stopTest();

        // Current implementation treats the empty string
        // as one empty header and returns no records.
        System.assertEquals(0, results.size());
    }
}