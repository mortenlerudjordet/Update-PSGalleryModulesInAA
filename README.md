# Update-PSGalleryModulesInAA

This Azure Automation Runbook imports the latest version of installed modules in Automation Account from PowerShell Gallery.
It can also only update the Azure modules by setting a parameter. This is meant to only run from an Automation account.

Update: Now supports both 5.1 and 7.2 runtime for modules  

NOTE:  
    As this introduces runtime version support, before running make sure Az.Accounts, Az.Automation and Az.Resources are updated to the latest version
    on both 5.1 and 7.2 runtime before running this.  
    Also if error "The term 'Get-AutomationConnection' is not recognized as the name of a cmdlet" running against 7.2 runtime, check that the 
    module: Orchestrator.AssetManagement.Cmdlets is available in 7.2. If not import AzureAutomationAuthoringToolkit into 7.2 from the portal.  

Use Import-PSGalleryModulesToAA for first time import of Az module (takes a long time to import all submodules).
