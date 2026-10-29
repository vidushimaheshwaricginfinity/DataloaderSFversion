// public class DataFeedJobTrackerTriggerHandler {

//     public static void startBatchProcessor(List<Data_Feed_Job_Tracker__c> newRecords) {
//         // We only care about the file name and parameters from the first record.
//         // The batch will query for all the others.
//         Data_Feed_Job_Tracker__c trackerRacord = newRecords[0];

//         if(trackerRacord.Status__c == 'Upload Complete') {
//             CSVUploaderController.invokeProcessDataFeedBatch(trackerRacord.File_Name__c, trackerRacord.Operation_Type__c, trackerRacord.Target_Object__c);
//         }
//     }
// }


public class DataFeedJobTrackerTriggerHandler {

    public static void startBatchProcessor(
        List<Data_Feed_Job_Tracker__c> newRecords,
        Map<Id, Data_Feed_Job_Tracker__c> oldMap
    ) {
        for (Data_Feed_Job_Tracker__c tracker : newRecords) {

            Boolean transitionedToUploadComplete =
                tracker.Status__c == 'Upload Complete' &&
                (
                    oldMap == null ||
                    !oldMap.containsKey(tracker.Id) ||
                    oldMap.get(tracker.Id).Status__c != 'Upload Complete'
                );

            if (transitionedToUploadComplete) {
                CSVUploaderController.invokeProcessDataFeedBatch(
                    tracker.Id,
                    tracker.File_Name__c,
                    tracker.Operation_Type__c,
                    tracker.Target_Object__c
                );
            }
        }
    }
}