trigger AccountDisqualifiedTrigger on Account (after update) {
    List<Account> disqualifiedAccounts = new List<Account>();

    for (Account acc : Trigger.new) {
        Account oldAcc = Trigger.oldMap.get(acc.Id);

        if (acc.Disqualified__c == true && oldAcc.Disqualified__c != true) {
            disqualifiedAccounts.add(acc);
        }
    }

    if (!disqualifiedAccounts.isEmpty()) {
        AccountAssignmentHelper.reassignAccounts(disqualifiedAccounts);
    }
}
