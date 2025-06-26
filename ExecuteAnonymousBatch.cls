/**
 * Batch for Execute Anonymous
 * 
 * @author Enrico Murru (http://enree.co)
 * @version 1.0
 * @description Execute custom code in batch. Needs a named credentials with OAuth 2.0 on running user.
 * Example
 * String script = 'List<Account> acList = [Select Id, Name From Account Where Id IN :ID_LIST];' 
 *		+'\nfor(Account acc : acList){'
 *		+'\n   acc.BillingCity = \'Gnite City\';'
 *		+'\n}'
 *		+'\n update acList;';
 * ExecuteAnonymousBatch batch = new ExecuteAnonymousBatch('Select Id From Account',script, true);
 * Database.executeBatch(batch, 100);
 * @history
 * 2017-08-02 : Enrico Murru - Original version
 */
public class ExecuteAnonymousBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
    private static final String API_VERSION = '40.0';
    private static final String NAMED_CREDENTIAL = 'EXECUTE_ANONYMOUS';

    private String executeScript{get;set;}
    private String soqlQuery{get;set;}
    @testVisible
    private List<String> errors{get;set;}
    private Boolean sendEmail{get;set;}
    
    /*
     * Constructor
     * @param soqlQuery - SOQL query to be issued
     * @param executeScript - Apex script to be executed: the script has the "ID_LIST" list of type List<ID>
     * @param sendEmail - send a finish email
     */
    public ExecuteAnonymousBatch(String soqlQuery, String executeScript, Boolean sendEmail){
        this.executeScript = executeScript;
        this.soqlQuery = soqlQuery;
        this.errors = new List<String>();
        this.sendEmail = sendEmail;
    }
    
    /*
     * Batchable Start method
     */
    public Database.QueryLocator start(Database.BatchableContext BC){
        return Database.getQueryLocator(this.soqlQuery);
    }
    
    /*
     * Executes the anonymous code on the batch objects.
     * The original script is "augmented" by the ID_List variable (of type List<ID>)
     * that contains the list of current batch's ids.
     */
    public void execute(Database.BatchableContext BC, List<SObject> scope){
        List<ID> scopeIds = new List<ID>();
        for(Sobject obj : scope){
            scopeIds.add((ID)obj.get('Id'));
        }
        
        String idList = '\''+String.join(scopeIds, '\',\'')+'\'';
        String script = 'List<ID> ID_LIST = new List<ID>{'
            + idList
            + '};\n'
            + this.executeScript;
        String result = executeAnonymous(script);
        if (String.isNotBlank(result) && !result.containsIgnoreCase('Success')) {
            errors.add(idList+': '+result);
        }
    }
    
    /*
     * Sends an email when done
     */
    public void finish(Database.BatchableContext BC) {
        
        if(sendEmail == true){
            String subject = 'Elaboration completed: ';
            if(this.errors.isEmpty()){
                subject += ' no errors.';
            }else{
                subject += ' with '+this.errors.size()+' errors.';
            }
            String body = 'Query: \n\t'
                        +this.soqlQuery
                        +'\nExecute anonymous code: \n\t'
                        +this.executeScript.replace('\n','\n\t')
                        +'\nErrors:\n\t'
                        +String.join(this.errors,'\n\t')
                		+'\n\n\nSent by: '+userinfo.getUserName();
            sendEmail(subject,body);
        }
    }
    
    /*
     * Executes the execute anonymous script.
     * Uses a named credential to get a valid session ID.
     * @param script - script to be executed (contains the ID_LIST variable)
     * @return (String) error message or null in case of success
     */
private static String executeAnonymous(String script) {
    String encodedScript = EncodingUtil.urlEncode(script, 'UTF-8');

    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:EXECUTE_ANONYMOUS/services/data/v60.0/tooling/executeAnonymous/?anonymousBody=' + encodedScript);
    req.setMethod('GET');

    Http http = new Http();
    HttpResponse res = http.send(req);

    if (res.getStatusCode() != 200) {
        System.debug('Erreur HTTP : ' + res.getStatusCode());
        System.debug('Body : ' + res.getBody());
        return 'Erreur HTTP ' + res.getStatusCode() + ' : ' + res.getBody();
    }

    // Déserialisation basique
    Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    Boolean compiled = (Boolean) result.get('compiled');
    Boolean success = (Boolean) result.get('success');

    if (compiled && success) {
        return 'Success';
    } else {
        return 'Failure: ' + res.getBody();
    }
}


    
    /**
     * Sends an email to current user
     * @param subject - email's subject
     * @param message - email's body
     */
    private static void sendEmail(String subject, String message)
    {
        Messaging.SingleEmailMessage mail=new Messaging.SingleEmailMessage();
        mail.setTargetObjectId(UserInfo.getUserId());
        mail.setSaveAsActivity(false);
        subject = '[Execute Anonymous Batch] '+subject;
        mail.setSubject(subject);
        mail.setPlainTextBody(message);
        if(Test.isRunningTest()==false){
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        }
    }
}