// trigger DataFeedJobTrigger on Data_Feed_Job_Tracker__c (after insert, after update) {
//     if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
//         DataFeedJobTrackerTriggerHandler.startBatchProcessor(Trigger.new);
//     }
// }



trigger DataFeedJobTrigger on Data_Feed_Job_Tracker__c (
    after insert,
    after update
) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            DataFeedJobTrackerTriggerHandler.startBatchProcessor(
                Trigger.new,
                null
            );
        } else if (Trigger.isUpdate) {
            DataFeedJobTrackerTriggerHandler.startBatchProcessor(
                Trigger.new,
                Trigger.oldMap
            );
        }
    }
}