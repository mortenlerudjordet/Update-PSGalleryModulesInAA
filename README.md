# Update-PSGalleryModulesInAA

This Azure Automation Runbook imports the latest version of installed modules in Automation Account from PowerShell Gallery.
It can also only update the Azure modules by setting a parameter. This is meant to only run from an Automation account.

Update:  
    Now supports both 5.1 and 7.2 runtime for modules  
    Need only one version of runbook on either 5.1 or 7.2 to update both module runtime versions.

NOTE:  
    As this introduces runtime version support, before running make sure Az.Accounts, Az.Automation and Az.Resources are updated to the latest version
    on both 5.1 and 7.2 runtime before running this.  

    Also make sure to create a connection asset named "AzureRunAsConnection" of type "AzureServicePrincipal" in the Automation account before running this script.  
    Just need to add TenantId and SubscriptionId, the other parameters are not used.  

Use Import-PSGalleryModulesToAA for first time import of Az module (takes a long time to import all submodules).
