# Update-PSGalleryModulesInAA

This Azure Automation Runbook imports the latest version of installed modules in Automation Account from PowerShell Gallery.
It can also only update the Azure modules by setting a parameter. This is meant to only run from an Automation account.

Use Import-PSGalleryModulesToAA for first time import of Az module (takes a long time to import all submodules).
