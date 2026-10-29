public class UploadChunkResult {
    @AuraEnabled public Integer successCount { get; set; }
    @AuraEnabled public Integer failedCount { get; set; }
    @AuraEnabled public List<String> failedRows { get; set; }

    public UploadChunkResult() {
        successCount = 0;
        failedCount = 0;
        failedRows = new List<String>();
    }
}