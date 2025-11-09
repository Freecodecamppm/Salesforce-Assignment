Salesforce Assignment Overview
------------------------------

This repository contains all components for the Salesforce Sales Operations Engineer assessment.

1. Apex
   - Main File: MasterDataManagementController.cls
   - Description: This Apex class contains the core automation logic for:
        • Creating and importing nursing home Accounts
        • Creating associated Contacts (Administrators)
        • Assigning Accounts to Sales Reps by territory
        • Handling triggers for Opportunities and Disqualified Accounts
        • Integrating with external scripts (Google Apps Script and AI assistant)

2. Google Apps Script
   - File: Import.gs
   - Description: Handles Question 2 — imports Administrator contact data from the Arizona Care Check page.
     This script acts as an external endpoint called by Apex to fetch and process Administrator details.

3. Triggers
   - Files:
        • AccountAssignmentHelper.trigger
        • AccountDisqualifiedTrigger.trigger
        • OpportunityReassignmentTrigger.trigger
   - Description: These triggers manage automatic Account reassignment whenever:
        • An Opportunity is marked as Closed Won or Closed Lost
        • An Account is marked as Disqualified

4. AI Assistant Query and Chatbot Instructions
   - Files:
        • QueryAssistant.txt
        • Chatbot.txt
   - Description: Contain the prompt instructions and logic used to guide the AI assistant
     in querying and interpreting Salesforce data.

5. Visualforce Page
   - File: Visualforce.page
   - Description: This page is the interface where all the Apex scripts are run and managed.  
     Users can trigger automation (such as importing contacts or assigning accounts) through this page.

Repository Link:
https://github.com/Freecodecamppm/Salesforce-Assignment
