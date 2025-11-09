public class MasterDataManagementController {

    public String statusMessage { get; set; }
    public String userInput { get; set; }
    public String threadId { get; set; }
    public String threadId_query { get; set; }
    
        public void init() {
        getInformation();
    }
    // 1. Import Nursing Home Accounts
    public void runImportAccounts() {
        try {
            List<Nursing_Home__c> nursingHomes = [
                SELECT Name, Provider_Address__c, Telephone_Number__c,
                       CMS_Certification_Number_CCN__c, 
                       Reported_Total_Nurse_Staffing_Hours_per__c, 
                       State__c
                FROM Nursing_Home__c
                WHERE State__c IN ('AZ', 'NV', 'UT', 'CO')
            ];
    
            if (nursingHomes.isEmpty()) {
                statusMessage = '⚠️ No nursing home records found for AZ, NV, UT, or CO.';
                return;
            }
    
            Set<String> names = new Set<String>();
            for (Nursing_Home__c nh : nursingHomes) {
                if (String.isNotBlank(nh.Name)) names.add(nh.Name.trim());
            }
    
            Map<String, Account> existingAccounts = new Map<String, Account>(
                [SELECT Id, Name FROM Account WHERE Name IN :names]
            );
    
            List<Account> toInsert = new List<Account>();
            List<Account> toUpdate = new List<Account>();
    
            for (Nursing_Home__c nh : nursingHomes) {
                if (String.isBlank(nh.Name)) continue;
                Account acc;
                if (existingAccounts.containsKey(nh.Name)) {
                    acc = existingAccounts.get(nh.Name);
                    acc.Phone = nh.Telephone_Number__c;
                    acc.BillingStreet = nh.Provider_Address__c;
                    acc.Reported_Total_Nurse_Staffing_Hours_per__c = nh.Reported_Total_Nurse_Staffing_Hours_per__c;
                    acc.CMS_Certification_Number_CCN__c = nh.CMS_Certification_Number_CCN__c;
                    acc.State__c = nh.State__c;
                    toUpdate.add(acc);
                } else {
                    acc = new Account(
                        Name = nh.Name,
                        Phone = nh.Telephone_Number__c,
                        BillingStreet = nh.Provider_Address__c,
                        Reported_Total_Nurse_Staffing_Hours_per__c = nh.Reported_Total_Nurse_Staffing_Hours_per__c,
                        CMS_Certification_Number_CCN__c = nh.CMS_Certification_Number_CCN__c,
                        State__c = nh.State__c
                    );
                    toInsert.add(acc);
                }
            }
    
            if (!toInsert.isEmpty()) insert toInsert;
            if (!toUpdate.isEmpty()) update toUpdate;
    
            statusMessage = '✅ Nursing Home Accounts processed successfully! (' +
                toInsert.size() + ' new, ' + toUpdate.size() + ' updated)';
        } catch (Exception e) {
            statusMessage = '❌ Error importing Nursing Home Accounts: ' + e.getMessage();
        }
    }
    
// 2. Import Admin Contacts (filtered by Account BillingState = 'AZ')
public void importAdminContacts() {
    Integer totalAccounts = 0;
    Integer totalContactsCreated = 0;
    Integer totalContactsUpdated = 0;
    Integer totalSkipped = 0;

    List<Contact> contactsToInsert = new List<Contact>();
    List<Contact> contactsToUpdate = new List<Contact>();

    // Total AZ accounts
    Integer totalAzAccounts = [SELECT COUNT() FROM Account WHERE State__c = 'AZ' AND Name != null];

    // Remaining (without Administrator)
    Integer remainingBefore = [
        SELECT COUNT() 
        FROM Account 
        WHERE State__c = 'AZ' 
        AND Name != null 
        AND Id NOT IN (SELECT AccountId FROM Contact WHERE Title = 'Administrator')
    ];

    // Fetch up to 50 remaining
    List<Account> accounts = [
        SELECT Id, Name, State__c 
        FROM Account 
        WHERE State__c = 'AZ' 
        AND Name != null 
        AND Id NOT IN (SELECT AccountId FROM Contact WHERE Title = 'Administrator')
        LIMIT 50
    ];
    totalAccounts = accounts.size();

    if (totalAccounts == 0) {
        statusMessage = '✅ All accounts completed — nothing left to import (' + Datetime.now().format('HH:mm:ss') + ').';
        return;
    }

    for (Account acc : accounts) {
        try {
            // API callout
            String endpoint = 'https://script.google.com/macros/s/AKfycbxJmKVYp0LhokRDX5NcxtxuxQ05GUH1ut25qACi5zPt2NLLFl8zDc9M_nzun0vlZa9ApA/exec?name=' 
                              + EncodingUtil.urlEncode(acc.Name, 'UTF-8');
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(60000);

            Http http = new Http();
            HttpResponse res = http.send(req);
            String body = res.getBody();

            // Handle redirect if needed
            if (res.getStatusCode() == 301 || res.getStatusCode() == 302) {
                String redirectUrl = res.getHeader('Location');
                HttpRequest redirectReq = new HttpRequest();
                redirectReq.setEndpoint(redirectUrl);
                redirectReq.setMethod('GET');
                redirectReq.setTimeout(60000);
                res = http.send(redirectReq);
                body = res.getBody();
            }

            // Skip if empty or "None"
            if (body == 'None' || String.isBlank(body)) {
                totalSkipped++;
                continue;
            }

            // Parse JSON
            Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(body);
            String adminName = (String) jsonResponse.get('adminname');
            String phone = (String) jsonResponse.get('phone');
            String address = (String) jsonResponse.get('address');

            if (String.isBlank(adminName)) {
                totalSkipped++;
                continue;
            }

            // Parse name
            String firstName = '';
            String lastName = '';
            List<String> nameParts = adminName.split(' ');
            if (nameParts.size() > 1) {
                firstName = nameParts[0];
                lastName = nameParts[nameParts.size() - 1];
            } else {
                lastName = adminName;
            }

            // Check for existing contacts
            List<Contact> existingContacts = [
                SELECT Id, FirstName, LastName, Title, Is_Active__c 
                FROM Contact 
                WHERE AccountId = :acc.Id 
                AND Title = 'Administrator'
            ];

            Boolean exists = false;
            for (Contact c : existingContacts) {
                if (c.LastName != null && c.LastName.equalsIgnoreCase(lastName)) {
                    exists = true;
                } else {
                    c.Is_Active__c = false;
                    contactsToUpdate.add(c);
                }
            }

            // Create new contact if not found
            if (!exists) {
                Contact newC = new Contact();
                newC.FirstName = firstName;
                newC.LastName = lastName;
                newC.Title = 'Administrator';
                newC.Phone = phone;
                newC.MailingStreet = address;
                newC.AccountId = acc.Id;
                newC.Is_Active__c = true;
                contactsToInsert.add(newC);
            }

        } catch (Exception e) {
            System.debug('Error processing account ' + acc.Name + ': ' + e.getMessage());
            totalSkipped++;
            continue;
        }
    }

    // DML outside the loop
    if (!contactsToInsert.isEmpty()) {
        insert contactsToInsert;
        totalContactsCreated = contactsToInsert.size();
    }
    if (!contactsToUpdate.isEmpty()) {
        update contactsToUpdate;
        totalContactsUpdated = contactsToUpdate.size();
    }

    // Recount remaining after this batch
    Integer remainingAfter = [
        SELECT COUNT() 
        FROM Account 
        WHERE State__c = 'AZ' 
        AND Name != null 
        AND Id NOT IN (SELECT AccountId FROM Contact WHERE Title = 'Administrator')
    ];

    // Update status message with timestamp and remaining count
    statusMessage =
        '✅ Processed this round: ' + totalAccounts +
        ', Created: ' + totalContactsCreated +
        ', Updated: ' + totalContactsUpdated +
        ', Skipped: ' + totalSkipped +
        ' | Remaining: ' + remainingAfter +
        ' | Completed: ' + (totalAzAccounts - remainingAfter) + '/' + totalAzAccounts +
        ' | Time: ' + Datetime.now().format('HH:mm:ss');

    System.debug(statusMessage);
}



  
    //// 3. Lead score

     public void calculateLeadScores() {
        try {
            List<Account> accountsToUpdate = new List<Account>();
            
            for (Account acc : [
                SELECT Id, Name, Reported_Total_Nurse_Staffing_Hours_per__c, State__c
                FROM Account
                WHERE State__c IN ('AZ','NV','UT','CO')
            ]) {
                Decimal staffingHours = acc.Reported_Total_Nurse_Staffing_Hours_per__c != null 
                    ? acc.Reported_Total_Nurse_Staffing_Hours_per__c 
                    : 0;

                // Lower hours = higher score (inverse relationship)
                Integer score = 0;
                if (staffingHours > 0) {
                    score = (Integer)(1000 / staffingHours);
                } else {
                    score = 1000;
                }

                acc.Lead_Score__c = score;
                accountsToUpdate.add(acc);
            }

            if (!accountsToUpdate.isEmpty()) update accountsToUpdate;
            statusMessage = '✅ Lead Scores calculated and updated for all accounts!';
        } catch (Exception e) {
            statusMessage = '❌ Error calculating Lead Scores: ' + e.getMessage();
        }
    }


    // =====================================
// 4. Assign Accounts (Auto Territory Assignment)
// =====================================
public void assignAccounts() {
    calculateLeadScores();
    try {
        // Get the logged-in user
        User currentUser = [
            SELECT Id, Name, Territory__c 
            FROM User 
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        // If the user doesn’t have a territory, auto-assign one
        if (String.isBlank(currentUser.Territory__c)) {
            List<String> allStates = new List<String>{'AZ','NV','UT','CO'};

            // Find which states already have users assigned
            Set<String> assignedStates = new Set<String>();
            for (User u : [
                SELECT Territory__c 
                FROM User 
                WHERE Territory__c != null
                AND Territory__c IN :allStates
            ]) {
                assignedStates.add(u.Territory__c);
            }

            // Find the first available state not yet assigned
            String newState;
            for (String s : allStates) {
                if (!assignedStates.contains(s)) {
                    newState = s;
                    break;
                }
            }

            // If all states are taken, assign randomly to one
            if (newState == null) newState = allStates[Math.mod(Crypto.getRandomInteger(), allStates.size())];

            // Update the user record
            currentUser.Territory__c = newState;
            update currentUser;

            statusMessage = '🗺️ You have been automatically assigned to the ' + newState + ' territory. ';
        }

        String userTerritory = currentUser.Territory__c;

        // Fetch top 20 accounts in this user's territory (lowest staffing hours)
        List<Account> accounts = [
            SELECT Id, Name, State__c, OwnerId, Reported_Total_Nurse_Staffing_Hours_per__c, Lead_Score__c
            FROM Account
            WHERE State__c = :userTerritory
            AND (Assigned__c = false)
            ORDER BY Reported_Total_Nurse_Staffing_Hours_per__c ASC
            LIMIT 20
        ];

        if (accounts.isEmpty()) {
            statusMessage += '⚠️ No available accounts found for your territory (' + userTerritory + ').';
            return;
        }

        // Assign accounts to current user
        for (Account a : accounts) {
              a.OwnerId = currentUser.Id;
              a.Assigned__c = true;
        }

        update accounts;

        statusMessage += '✅ ' + accounts.size() + ' accounts successfully assigned to you for ' + userTerritory + '.';
    } catch (Exception e) {
        statusMessage = '❌ Error assigning Accounts: ' + e.getMessage();
    }
}
    

    // 3. Assign Accounts
   // public void assignAccounts() {
   // }
   // 
   // 
   //               AI ZONE NOW               
   // 
   // 
   // 
   //
   // 
 ///DASHBOARD INFO 
   public Integer getTotalAccounts() {
    return [SELECT COUNT() FROM Account];
}

public Integer getTotalContacts() {
    return [SELECT COUNT() FROM Contact];
}

public Integer getAssignedAccounts() {
    // Get the current user
    User currentUser = [
        SELECT Id, Name, Territory__c 
        FROM User 
        WHERE Id = :UserInfo.getUserId()
        LIMIT 1
    ];

    // Query the number of unassigned accounts not owned by the current user
    Integer unassignedCount = [
        SELECT COUNT()
        FROM Account
        WHERE OwnerId = :currentUser.Id
        AND Assigned__c = true
    ];

    return unassignedCount;
}


// SEND MESSAGES
public String sendAIMessage1(String userInput) {
    try {
        // Send message directly to fixed assistant
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.openai.com/v1/assistants/asst_62qzwRKyxYazjXNQ9RuTy9wK/messages');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer HIDDEN');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(new Map<String, Object>{
    'messages' => new List<Map<String, Object>>{
        new Map<String, Object>{
            'role' => 'user',
            'content' => userInput
        }
    }
}));


        Http http = new Http();
        HttpResponse res = http.send(req);

        Map<String, Object> resMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> messages = (List<Object>) resMap.get('messages');

        if (messages == null || messages.isEmpty()) return '⚠️ No AI response received';

        Map<String, Object> lastMsg = (Map<String, Object>) messages[messages.size() - 1];
        String responseText = '';
        if (lastMsg.containsKey('content')) {
            List<Object> contentList = (List<Object>) lastMsg.get('content');
            if (!contentList.isEmpty()) {
                Map<String, Object> contentItem = (Map<String, Object>) contentList[0];
                responseText = (String) contentItem.get('text');
            }
        }

        return '🧠 AI says: ' + responseText;

    } catch (Exception e) {
        return '❌ Error sending message: ' + e.getMessage();
    }
}

public String sendAIMessage(String userInput) {
    try {
        if (String.isBlank(threadId)) {
            return '❌ Thread ID is not set';
        }

        // Build payload
        Map<String, Object> threadPayload = new Map<String, Object>{
            'thread' => threadId,
            'messages' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'role' => 'user',
                    'content' => new List<Map<String, Object>>{
                        new Map<String, Object>{ 'type' => 'text', 'text' => userInput }
                    }
                }
            }
        };

        // Send HTTP request
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.openai.com/v1/threads/runs');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer YOUR_API_KEY'); 
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('OpenAI-Beta', 'assistants=v2'); // Required for assistants API
        req.setBody(JSON.serialize(threadPayload));

        Http http = new Http();
        HttpResponse res = http.send(req);

        // For now, we don't process the response
        return '✅ Message sent to thread ' + threadId;

    } catch (Exception e) {
        return '❌ Error sending message: ' + e.getMessage();
    }
}

    
    // =====================================
//  AI Utility Function: Create / Delete / Change
// =====================================
public String createDeleteChange(String actionType, String recordType, String name, Map<String, Object> fieldValues) {
    try {
        recordType = recordType != null ? recordType.toLowerCase().trim() : '';
        actionType = actionType != null ? actionType.toLowerCase().trim() : '';

        // Determine sObject type
        Schema.SObjectType sobjectType;
        if (recordType == 'account') {
            sobjectType = Account.SObjectType;
        } else if (recordType == 'contact') {
            sobjectType = Contact.SObjectType;
        } else {
            return '❌ Unknown record type: ' + recordType + '. Must be Account or Contact.';
        }

        // CREATE ACTION
        if (actionType == 'create') {
            SObject newRecord = sobjectType.newSObject();

            // Default Name/LastName
            if (recordType == 'account') newRecord.put('Name', name);
            if (recordType == 'contact') newRecord.put('LastName', name);

            if (fieldValues != null && !fieldValues.isEmpty()) {
                for (String field : fieldValues.keySet()) {
                    newRecord.put(field, fieldValues.get(field));
                }
            }

            insert newRecord;
            return '✅ Created ' + recordType + ' "' + name + '" successfully (Id: ' + newRecord.get('Id') + ').';
        }

        // FIND EXISTING RECORD
        SObject existingRecord;
        if (recordType == 'account') {
            List<Account> accs = [SELECT Id, Name FROM Account WHERE Name = :name LIMIT 1];
            existingRecord = accs.isEmpty() ? null : accs[0];
        } else {
            List<Contact> cons = [SELECT Id, LastName FROM Contact WHERE LastName = :name LIMIT 1];
            existingRecord = cons.isEmpty() ? null : cons[0];
        }

        if (existingRecord == null) {
            return '⚠️ No ' + recordType + ' found with name "' + name + '".';
        }

        // DELETE ACTION
        if (actionType == 'delete') {
            delete existingRecord;
            return '🗑️ Deleted ' + recordType + ' "' + name + '".';
        }

        // CHANGE / UPDATE ACTION
        if (actionType == 'change') {
            if (fieldValues == null || fieldValues.isEmpty()) {
                return '⚠️ No fields provided for update.';
            }

            for (String field : fieldValues.keySet()) {
                existingRecord.put(field, fieldValues.get(field));
            }

            update existingRecord;
            return '✏️ Updated ' + recordType + ' "' + name + '" successfully.';
        }

        return '❌ Unknown action: ' + actionType + '. Must be create, delete, or change.';

    } catch (Exception e) {
        return '❗ Error performing ' + actionType + ' on ' + recordType + ': ' + e.getMessage();
    }
}

    // This method is used by Visualforce to send message and get AI response
    public void sendAIChat() {
        if (String.isBlank(userInput)) {
            statusMessage = '⚠️ Please enter a message. ' + userInput;
            return;
        }
        getQueryFromAssistant(userInput);
    }
    
    
    public void getQueryFromAssistant(String userQuestion) {
    try {
        
        // --- BUILD PAYLOAD FOR OPENAI THREAD ---
        Map<String, Object> threadPayload = new Map<String, Object>();
        threadPayload.put('assistant_id', 'asst_yDbzepwwxOqzwsMxYuFYLKNX');
        threadPayload.put('thread', new Map<String, Object>{
            'messages' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'role' => 'user',
                    'content' => userQuestion
                }
            }
        });

        // --- SEND CONTEXT TO OPENAI ---
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.openai.com/v1/threads/runs');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer HIDDEN');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('OpenAI-Beta', 'assistants=v2');
        req.setBody(JSON.serialize(threadPayload));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            if (result.containsKey('thread_id')) {
                threadId_query = (String) result.get('thread_id');
            } else {
                threadId_query = 'None';
            }
        } else {
            threadId_query = 'None';
        }

    } catch (Exception e) {
        threadId_query = 'None';
        statusMessage = 'This failed to run';
    }
}
    
    
    public void getInformation() {
    try {
        // --- Get Current User ---
        User currentUser = [
            SELECT Id, Name, Email, Title, Territory__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        // --- Fetch Data ---
        List<Account> accounts = [
            SELECT Id, Name, State__c, OwnerId, Assigned__c,
                   Reported_Total_Nurse_Staffing_Hours_per__c, Lead_Score__c
            FROM Account
            LIMIT 2000
        ];

        List<Contact> contacts = [
            SELECT Id, Name, Account.State__c, AccountId, Account.Name
            FROM Contact
            WHERE AccountId != null
            LIMIT 2000
        ];

        List<Opportunity> opps = [
            SELECT Id, StageName, CloseDate, AccountId
            FROM Opportunity
            WHERE StageName IN ('Closed Won', 'Closed Lost')
            LIMIT 2000
        ];

        // --- SUMMARY CALCULATIONS ---
        Integer totalAccounts = accounts.size();
        Integer totalContacts = contacts.size();

        Map<String, Integer> accountsByState = new Map<String, Integer>();
        for (Account a : accounts) {
            String state = a.State__c != null ? a.State__c : 'Unknown';
            accountsByState.put(state, (accountsByState.containsKey(state) ? accountsByState.get(state) + 1 : 1));
        }

        Map<String, Integer> contactsByState = new Map<String, Integer>();
        for (Contact c : contacts) {
            String state = (c.Account != null && c.Account.State__c != null) ? c.Account.State__c : 'Unknown';
            contactsByState.put(state, (contactsByState.containsKey(state) ? contactsByState.get(state) + 1 : 1));
        }

        Integer totalAssigned = 0;
        Integer totalUnassigned = 0;
        for (Account a : accounts) {
            if (a.Assigned__c == true) totalAssigned++;
            else totalUnassigned++;
        }

        List<String> userAccounts = new List<String>();
        for (Account a : accounts) {
            if (a.OwnerId == currentUser.Id) userAccounts.add(a.Name);
        }

        Integer closedWonCount = 0;
        Integer closedLostCount = 0;
        Date sevenDaysAgo = System.today().addDays(-7);
        Integer closedWonThisWeek = 0;

        for (Opportunity o : opps) {
            if (o.StageName == 'Closed Won') {
                closedWonCount++;
                if (o.CloseDate != null && o.CloseDate >= sevenDaysAgo) closedWonThisWeek++;
            } else if (o.StageName == 'Closed Lost') {
                closedLostCount++;
            }
        }

        List<String> allAccountNames = new List<String>();
        for (Account a : accounts) allAccountNames.add(a.Name);

        List<String> allContactFacilityNames = new List<String>();
        for (Contact c : contacts) {
            if (c.Account != null) allContactFacilityNames.add(c.Account.Name);
        }

        // --- BUILD STORY-LIKE SUMMARY ---
        String summary = '';
        summary += 'Here is the current Salesforce summary as of ' + System.now().format('yyyy-MM-dd HH:mm') + '. ';
        summary += 'There are a total of ' + totalAccounts + ' accounts and ' + totalContacts + ' contacts in the system. ';

        if (!accountsByState.isEmpty()) {
            summary += 'Account distribution by state: ';
            for (String s : accountsByState.keySet()) {
                summary += s + ' has ' + accountsByState.get(s) + ', ';
            }
        }

        summary += ' Of all accounts, ' + totalAssigned + ' are assigned and ' + totalUnassigned + ' are unassigned. ';
        summary += 'You, ' + currentUser.Name + ', currently own ' + userAccounts.size() + ' accounts. ';
        if (!userAccounts.isEmpty()) {
            summary += 'Some of your accounts include: ' + String.join(userAccounts, ', ') + '. ';
        }

        summary += 'There are ' + closedWonCount + ' closed-won opportunities and ' + closedLostCount + ' closed-lost ones in total. ';
        summary += closedWonThisWeek + ' opportunities were closed-won within the last 7 days. ';

        if (!contactsByState.isEmpty()) {
            summary += 'Contact distribution by state: ';
            for (String s : contactsByState.keySet()) {
                summary += s + ' has ' + contactsByState.get(s) + ', ';
            }
        }

        summary += 'All account names include: ' + String.join(allAccountNames, ', ') + '. ';
        summary += 'All contact facility names include: ' + String.join(allContactFacilityNames, ', ') + '. ';
        summary += 'End of summary.';

        // --- PREPARE DATA TO SEND TO GPT ---
        Map<String, Object> data = new Map<String, Object>{
            'user' => new Map<String, Object>{
                'id' => currentUser.Id,
                'name' => currentUser.Name,
                'email' => currentUser.Email,
                'title' => currentUser.Title,
                'territory' => currentUser.Territory__c
            },
            'contextSummary' => summary
        };

        String jsonPayload = JSON.serialize(data);

        // --- BUILD PAYLOAD FOR OPENAI THREAD ---
        Map<String, Object> threadPayload = new Map<String, Object>();
        threadPayload.put('assistant_id', 'asst_62qzwRKyxYazjXNQ9RuTy9wK');
        threadPayload.put('thread', new Map<String, Object>{
            'messages' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'role' => 'user',
                    'content' => jsonPayload
                }
            }
        });

        // --- SEND CONTEXT TO OPENAI ---
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.openai.com/v1/threads/runs');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer HIDDEN');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('OpenAI-Beta', 'assistants=v2');
        req.setBody(JSON.serialize(threadPayload));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            if (result.containsKey('thread_id')) {
                threadId = (String) result.get('thread_id');
            } else {
                threadId = 'None';
            }
        } else {
            threadId = 'None';
        }

    } catch (Exception e) {
        threadId = 'None';
    }
}
    
    
    public void askQuery() {
    if (String.isBlank(threadId_query)) {
        statusMessage = '❌ Thread ID is not set' ;
        return;
    }

    try {
        // Prepare the HTTP request
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.openai.com/v1/threads/' + threadId_query + '/messages');
        req.setMethod('GET'); // GET to retrieve messages
        req.setHeader('Authorization', 'Bearer HIDDEN');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('OpenAI-Beta', 'assistants=v2'); // Required for Assistants API

        Http http = new Http();
        HttpResponse res = http.send(req);

        // Parse the response
        Map<String, Object> resMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> dataList = (List<Object>) resMap.get('data');

        if (dataList == null || dataList.isEmpty()) {
            statusMessage = '⚠️ No data found in thread';
            return;
        }

        // Get the first message in the data list
        Map<String, Object> firstMessage = (Map<String, Object>) dataList[0];
        List<Object> contentList = (List<Object>) firstMessage.get('content');

        if (contentList == null || contentList.isEmpty()) {
            statusMessage = '⚠️ No content found in first message';
            return;
        }

        // Get the first content item
        Map<String, Object> firstContent = (Map<String, Object>) contentList[0];
        Map<String, Object> textObj = (Map<String, Object>) firstContent.get('text');
        String responseText = (textObj != null && textObj.containsKey('value')) ? (String) textObj.get('value') : '';

        // Pass the AI response text to the new handler
        sendQuery(responseText);

    } catch (Exception e) {
        statusMessage = '❌ Error fetching conversation: ' + e.getMessage();
    }
}
    
    
    public void get_conversation() {
    if (String.isBlank(threadId)) {
        statusMessage = '❌ Thread ID is not set for Answer';
        return;
    }

    try {
        // Prepare the HTTP request
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.openai.com/v1/threads/' + threadId + '/messages');
        req.setMethod('GET'); // GET to retrieve messages
        req.setHeader('Authorization', 'Bearer HIDDEN');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('OpenAI-Beta', 'assistants=v2'); // Required for Assistants API

        Http http = new Http();
        HttpResponse res = http.send(req);

        // Parse the response
        Map<String, Object> resMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> dataList = (List<Object>) resMap.get('data');

        if (dataList == null || dataList.isEmpty()) {
            statusMessage = '⚠️ No data found in thread';
            return;
        }

        // Get the first message in the data list
        Map<String, Object> firstMessage = (Map<String, Object>) dataList[0];
        List<Object> contentList = (List<Object>) firstMessage.get('content');

        if (contentList == null || contentList.isEmpty()) {
            statusMessage = '⚠️ No content found in first message';
            return;
        }

        // Get the first content item
        Map<String, Object> firstContent = (Map<String, Object>) contentList[0];
        Map<String, Object> textObj = (Map<String, Object>) firstContent.get('text');
        String responseText = (textObj != null && textObj.containsKey('value')) ? (String) textObj.get('value') : '';

        // Pass the AI response text to the new handler
        statusMessage = 'Here also works!';
        handle_ai_response(responseText);

    } catch (Exception e) {
        statusMessage = '❌ Error fetching conversation: ' + e.getMessage();
    }
}
    
    
    public void sendQuery(String query) {
    try {
        String soqlQuery1 = query;
        if (String.isBlank(soqlQuery1)) {
            threadId = 'None';
            return;
        }
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(query);
        String soqlQuery = (String) parsed.get('query');
        String summaryText;
        if (soqlQuery.toLowerCase().contains('count()')) {
        Integer results = Database.countQuery(soqlQuery);
        summaryText = 'For the question: ' + userInput +', I ran the query: ' + soqlQuery + '. It returned ' + results;
        } else {
        List<SObject> results = Database.query(soqlQuery);
        summaryText = 'For the question: ' + userInput +', I ran the query: ' + soqlQuery + '. It returned ' + results;
        }
        //List<SObject> results = Database.query(soqlQueryfixed);
        //statusMessage = 'here are the results: ' + results;
        // --- BUILD PAYLOAD FOR OPENAI THREAD ---
        Map<String, Object> threadPayload = new Map<String, Object>();
        threadPayload.put('assistant_id', 'asst_62qzwRKyxYazjXNQ9RuTy9wK');
        threadPayload.put('thread', new Map<String, Object>{
            'messages' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'role' => 'user',
                    'content' => summaryText
                }
            }
        });

        // --- SEND CONTEXT TO OPENAI ---
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.openai.com/v1/threads/runs');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer HIDDEN');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('OpenAI-Beta', 'assistants=v2');
        req.setBody(JSON.serialize(threadPayload));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            if (result.containsKey('thread_id')) {
                threadId = (String) result.get('thread_id');
                statusMessage = 'Loading response...';
            } else {
                threadId = 'None';
            }
        } else {
            threadId = 'None';
        }

    } catch (Exception e) {
        threadId = 'None';
        //statusMessage = 'here is the problem!: ' + e + ' For query ' + query;
        statusMessage = 'Sorry I cant get that right now, please try again...';
    }
}


    public void handle_ai_response(String aiResponse) {
    if (String.isBlank(aiResponse)) {
        statusMessage = '⚠️ AI response is empty';
        return;
    }

    try {
        Map<String, Object> respMap = (Map<String, Object>) JSON.deserializeUntyped(aiResponse);

        if (!respMap.containsKey('type')) {
            statusMessage = '❌ Invalid AI response: missing type';
            return;
        }

        String type = (String) respMap.get('type');

        if (type == 'info') {
            // Simply show the info message
            statusMessage = (String) respMap.get('message');
            getInformation();
        } 
        else if (type == 'action') {
            statusMessage = 'Sorry cant take actions';
           // if (!respMap.containsKey('actions')) {
            //    statusMessage = '❌ Invalid AI response: actions array missing';
           //     return;
          //  }

          //  List<Object> actionsList = (List<Object>) respMap.get('actions');
          //  if (actionsList.isEmpty()) {
          //      statusMessage = '⚠️ No actions to perform';
          //      return;
         //   }
//
  //          // Track summary of all operations
    //        List<String> resultLogs = new List<String>();
//
  //          for (Object obj : actionsList) {
    //            Map<String, Object> actionMap = (Map<String, Object>) obj;
//
  //              String actionType = (String) actionMap.get('actionType');
    //            String recordType = (String) actionMap.get('recordType');
      //          String name = (String) actionMap.get('name');
        //        Map<String, Object> fieldValues = (Map<String, Object>) actionMap.get('fieldValues');
//
                // Call existing Apex helper
  //              String result = createDeleteChange(actionType, recordType, name, fieldValues);
    //            resultLogs.add(result);
      //      }

            // Build a clear status message summarizing all operations
        //    statusMessage = '✅ AI actions completed:\n' + String.join(resultLogs, '\n');
        } 
        else {
            statusMessage = '❌ Unknown AI response type: ' + type;
        }

    } catch (Exception e) {
        statusMessage = '❌ Error handling AI response: ' + e.getMessage();
    }
}
}
