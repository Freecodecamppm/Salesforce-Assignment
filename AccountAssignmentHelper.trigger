public class AccountAssignmentHelper {
    public static void reassignAccounts(List<Account> accountsToReassign) {
        // Get full details for affected accounts
        Map<Id, Account> accDetails = new Map<Id, Account>(
            [SELECT Id, Name, State__c, OwnerId
             FROM Account
             WHERE Id IN :accountsToReassign]
        );

        List<Account> accountsToUpdate = new List<Account>();

        for (Account acc : accDetails.values()) {
            // Find the next highest unassigned account in this same territory
            List<Account> nextAccounts = [
                SELECT Id, State__c, OwnerId, Assigned__c, Lead_Score__c
                FROM Account
                WHERE State__c = :acc.State__c
                  AND Assigned__c = false
                  AND Id != :acc.Id
                ORDER BY Lead_Score__c DESC
                LIMIT 1
            ];

            if (!nextAccounts.isEmpty()) {
                Account nextAcc = nextAccounts[0];

                // Assign this new account to the same rep
                nextAcc.OwnerId = acc.OwnerId;
                nextAcc.Assigned__c = true;

                // Release the previous account
                acc.Assigned__c = false;

                accountsToUpdate.add(nextAcc);
                accountsToUpdate.add(acc);
            }
        }

        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
    }
}
