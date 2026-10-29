/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : DataLoaderApiService
 * Author          : Karan Singh Bisht
 * Created Date    : Sep 22, 2026
 * Last Modified By: Karan Singh Bisht
 * Last Modified On: Sep 22, 2026
 * Description     : This class implements for testing whether apex class is calling our .NET backend
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Sep 22, 2026  │ <Karan Singh Bisht>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public with sharing class DataLoaderApiService {

    public static HttpResponse getData(Integer page, Integer pageSize) {

        HttpRequest request = new HttpRequest();

        request.setMethod('GET');

        request.setEndpoint('https://dataloader.onrender.com/api/Data' + '?page=' + page + '&pageSize=' + pageSize);

        request.setTimeout(120000);

        Http http = new Http();
        HttpResponse response = http.send(request);

        if (response.getStatusCode() != 200) {
            throw new CalloutException(
                'API failed: ' +
                response.getStatusCode() +
                ' - ' +
                response.getBody()
            );
        }

        return response;
    }
}