public with sharing class ApiResponseTest {

    @AuraEnabled
    public static String testApi() {

        HttpRequest req = new HttpRequest();

        req.setEndpoint(
            'https://dataloader.onrender.com/api/Data?page=1&pageSize=10'
        );

        req.setMethod('GET');
        req.setTimeout(120000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        System.debug('Status Code: ' + res.getStatusCode());
        System.debug('Status: ' + res.getStatus());
        System.debug('Response Body: ' + res.getBody());

        if (res.getStatusCode() != 200) {
            throw new AuraHandledException(
                'API failed. Status: ' +
                res.getStatusCode() +
                ' Body: ' +
                res.getBody()
            );
        }

        return res.getBody();
    }
}