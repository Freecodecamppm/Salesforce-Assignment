trigger OpportunityReassignmentTrigger on Opportunity (after update) {
    List<Account> accountsToReassign = new List<Account>();

    for (Opportunity opp : Trigger.new) {
        Opportunity oldOpp = Trigger.oldMap.get(opp.Id);

        if ((opp.StageName == 'Closed Won' || opp.StageName == 'Closed Lost') &&
            opp.StageName != oldOpp.StageName &&
            opp.AccountId != null) {
            accountsToReassign.add(new Account(Id = opp.AccountId));
        }
    }

    if (!accountsToReassign.isEmpty()) {
        AccountAssignmentHelper.reassignAccounts(accountsToReassign);
    }
}
