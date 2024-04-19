<#
.SYNOPSIS
    This Azure Automation Runbook imports the latest version of installed modules in Automation Account from PowerShell Gallery.
    It can also only update the Azure modules by setting a parameter. This is meant to only run from an Automation account.

    Use Import-PSGalleryModulesToAA for first time import of Az module (takes a long time to import all submodules).

    NOTE:
        As this introduces runtime version support, before running make sure Az.Accounts, Az.Automation and Az.Resources are updated to the latest version
        on both 5.1 and 7.2 runtime before running this.

.DESCRIPTION
    This Azure Automation Runbook imports the latest version from PowerShell Gallery of all modules in an
    Automation account. By connecting the Runbook to an Automation schedule, you can ensure all modules in
    your Automation account stay up to date. Or only update the Azure modules

.PARAMETER AutomationResourceGroupName
    Optional. The name of the Azure Resource Group containing the Automation account to update all modules for.
    If a resource group is not specified, then it will use the current one for the automation account
    if it is run from the automation service

.PARAMETER AutomationAccountName
    Optional. The name of the Automation account to update all modules for.
    If an automation account is not specified, then it will use the current one for the automation account
    if it is run from the automation service

.PARAMETER UpdateAzureModulesOnly
    Optional. Set to $false to have logic try to update all modules installed in account.
    Default is $true, and this will only update Azure modules. Both AzureRM and Az if present in Automation account

.PARAMETER AutomationRuntime
    What module library to target.
    Valid inputs are 5.1 and 7.2, representing either PS 5.1 modules or 7.2 modules.
    Default is 5.1

.PARAMETER Force
    Optional. Set to $true to force update of all modules, also previous failed module updates
    Default is $false

.PARAMETER UseMSI
    Optional. Use Managed Service Identity instead of legacy RunAs account

.PARAMETER DebugLocal
    Optional. Set to $true if debugging script locally to switch of logic that tries to discover the Automation account it is running in
    Default is $false

.EXAMPLE
    Update-PSGalleryModulesInAA -AutomationResourceGroupName "MyResourceGroup" -AutomationAccountName "MyAutomationAccount"
    Update-PSGalleryModulesInAA -UpdateAzureModulesOnly $false
    Update-PSGalleryModulesInAA

.NOTES
    AUTHOR:         Automation Team
    CONTRIBUTOR:    Morten Lerudjordet
    LASTEDIT:       19.04.2024
#>

param(
    [Parameter(Mandatory = $false)]
    [String] $AutomationResourceGroupName,

    [Parameter(Mandatory = $false)]
    [String] $AutomationAccountName,

    [Parameter(Mandatory = $false)]
    [Bool] $UpdateAzureModulesOnly = $true,

    [Parameter(Mandatory = $false)]
    [ValidateSet("5.1","7.2")]
    [string] $AutomationRuntime = "7.2",

    [Parameter(Mandatory = $false)]
    [Bool] $Force = $false,

    [Parameter(Mandatory = $false)]
    [bool]$UseMSI = $true,

    [Parameter(Mandatory = $false)]
    [switch] $DebugLocal = $false
)
$VerbosePreference = "silentlycontinue"
$RunbookName = "Update-PSGalleryModulesInAA"
Write-Output -InputObject "Starting Runbook: $RunbookName at time: $(get-Date -format r).`nRunning PS version: $($PSVersionTable.PSVersion)`nOn host: $($env:computername)`nLocale: $([system.threading.thread]::currentthread.currentculture)"

#region Import Modules
# Prefer to use Az module if available
if((Get-Module -Name "Az.Accounts" -ListAvailable) -and (Get-Module -Name "Az.Automation" -ListAvailable) -and (Get-Module -Name "Az.Resources" -ListAvailable))
{
    $AccountsModule = Get-Module -Name Az.Accounts -ListAvailable | Sort-Object -Unique -Descending -Property Version | Select-Object -First 1
    $AutomationModule = Get-Module -Name Az.Automation -ListAvailable | Sort-Object -Unique -Descending -Property Version | Select-Object -First 1
    $ResourcesModule = Get-Module -Name Az.Resources -ListAvailable | Sort-Object -Unique -Descending -Property Version | Select-Object -First 1

    Write-Output -InputObject "Running Az.Account version: $($AccountsModule.Version)"
    Write-Output -InputObject "Running Az.Automation version: $($AutomationModule.Version)"
    Write-Output -InputObject "Running Az.Resources version: $($ResourcesModule.Version)"

    Import-Module -Name Az.Accounts, Az.Automation, Az.Resources -ErrorAction Continue -ErrorVariable oErr
    if($oErr)
    {
        Write-Error -Message "Failed to load needed modules for Runbook: Az.Accounts, Az.Automation,Az.Resources" -ErrorAction Continue
        throw "Check AA account for modules"
    }
    Write-Output -InputObject "Using Az modules to execute runbook"
    # This will negate the need to change syntax of AzureRM function names even if using Az modules
    Enable-AzureRmAlias
    $script:AzureModuleFlavor = "Az"
}
elseif((Get-Module -Name AzureRM.Profile -ListAvailable) -and (Get-Module -Name AzureRM.Automation -ListAvailable) -and (Get-Module -Name AzureRM.Resources -ListAvailable))
{
    $ProfileModule = Get-Module -Name AzureRM.Profile -ListAvailable | Sort-Object -Unique -Descending -Property Version | Select-Object -First 1
    $AutomationModule = Get-Module -Name AzureRM.Automation -ListAvailable | Sort-Object -Unique -Descending -Property Version | Select-Object -First 1
    $ResourcesModule = Get-Module -Name AzureRM.Resources -ListAvailable | Sort-Object -Unique -Descending -Property Version | Select-Object -First 1

    Write-Output -InputObject "Running AzureRM.Profile version: $($ProfileModule.Version)"
    Write-Output -InputObject "Running AzureRM.Automation version: $($AutomationModule.Version)"
    Write-Output -InputObject "Running AzureRM.Resources version: $($ResourcesModule.Version)"

    if( ([System.Version]$ProfileModule.Version -le [System.Version]"5.0.0") -and ([System.Version]$AutomationModule.Version -le [System.Version]"5.0.0") -and ([System.Version]$ResourcesModule.Version -le [System.Version]"5.0.0") )
    {
        Write-Error -Message "Manually update: AzureRM.Profile, AzureRM.Automation, AzureRM.Resources for first time usage through the portal" -ErrorAction Continue
        throw "Check AA account for modules"
    }
    else
    {
        Import-Module -Name AzureRM.Profile, AzureRM.Automation, AzureRM.Resources -ErrorAction Continue -ErrorVariable oErr
        if($oErr)
        {
            Write-Error -Message "Failed to load needed modules for Runbook: AzureRM.Profile, AzureRM.Automation,AzureRM.Resources" -ErrorAction Continue
            throw "Check AA account for modules"
        }
    }
    Write-Output -InputObject "Using AzureRM modules to execute runbook"
    $script:AzureModuleFlavor = "AzureRM"
}
else
{
    Write-Error -Message "Did not find AzureRM or Az modules installed in Automation account" -ErrorAction Stop
}

$VerbosePreference = "continue"
#endregion

#region Variables
$script:ModulesImported = [System.Collections.ArrayList]@()
# track depth of module dependencies import
$script:RecursionDepth = 0
# Make sure not to try to import dependencies of dependencies, like AzureRM module where some of the sub modules have different version dependencies on AzureRM.Accounts
$script:RecursionDepthLimit = 3
#endregion
#region Constants
$script:AzureSdkOwnerName = "azure-sdk"
$script:PsGalleryApiUrl = 'https://www.powershellgallery.com/api/v2'
#endregion

#region Functions
function doModuleImport
{
    param(
        [Parameter(Mandatory = $true)]
        [String] $AutomationResourceGroupName,

        [Parameter(Mandatory = $true)]
        [String] $AutomationAccountName,

        [Parameter(Mandatory = $true)]
        [String] $ModuleName,

        # if not specified latest version will be imported
        [Parameter(Mandatory = $false)]
        [String] $ModuleVersion
    )
    try
    {
        $Filter = @($ModuleName.Trim('*').Split('*') | ForEach-Object { "substringof('$_',Id)" }) -join " and "
        $Url = "$script:PsGalleryApiUrl/Packages?`$filter=$Filter and IsLatestVersion"

        # Fetch results and filter them with -like, and then shape the output
        $SearchResult = Invoke-RestMethod -Method Get -Uri $Url -ErrorAction Continue -ErrorVariable oErr | Where-Object { $_.title.'#text' -like $ModuleName } |
            Select-Object @{n = 'Name'; ex = {$_.title.'#text'}},
        @{n = 'Version'; ex = {$_.properties.version}},
        @{n = 'Url'; ex = {$_.Content.src}},
        @{n = 'Dependencies'; ex = {$_.properties.Dependencies}},
        @{n = 'Owners'; ex = {$_.properties.Owners}}
        If($oErr)
        {
            # Will stop runbook, though message will not be logged
            Write-Error -Message "Failed to retrieve details of module: $ModuleName from Gallery" -ErrorAction Stop
        }
        # Should not be needed as filter will only return one hit, though will keep the code to strip away if search ever get multiple hits
        if($SearchResult.Length -and $SearchResult.Length -gt 1)
        {
            $SearchResult = $SearchResult | Where-Object -FilterScript {
                return $_.Name -eq $ModuleName
            }
        }

        if(-not $SearchResult)
        {
            Write-Warning "Could not find module '$ModuleName' on PowerShell Gallery. This may be a module you imported from a different location"
        }
        else
        {
            $ModuleName = $SearchResult.Name # get correct casing for the module name

            if(-not $ModuleVersion)
            {
                # get latest version
                $ModuleContentUrl = $SearchResult.Url
            }
            else
            {
                $ModuleContentUrl = "$($script:PsGalleryApiUrl)/package/$ModuleName/$ModuleVersion"
            }

            # Make sure module dependencies are imported
            $Dependencies = $SearchResult.Dependencies

            if($Dependencies -and $Dependencies.Length -gt 0)
            {
                # Track recursion depth
                $script:RecursionDepth ++
                $Dependencies = $Dependencies.Split("|")

                # parse dependencies, which are in the format: module1name:module1version:|module2name:module2version:
                $Dependencies | ForEach-Object {

                    if( $_ -and $_.Length -gt 0 )
                    {
                        $Parts = $_.Split(":")
                        $DependencyName = $Parts[0]
                        # Gallery is returning double the same version number on some modules: Az.Aks:[1.0.1, 1.0.1] some do [1.0.1, ]
                        if($Parts[1] -match ",")
                        {
                            $DependencyVersion = (($Parts[1]).Split(","))[0] -replace "[^0-9.]", ''
                        }
                        else
                        {
                            $DependencyVersion = $Parts[1] -replace "[^0-9.]", ''
                        }
                        # check if we already imported this dependency module during execution of this script
                        if( -not $script:ModulesImported.Contains($DependencyName) )
                        {
                            # check if Automation account already contains this dependency module of the right version
                            $AutomationModule = $null
                            $AutomationModule = Get-AzureRMAutomationModule `
                                -ResourceGroupName $AutomationResourceGroupName `
                                -AutomationAccountName $AutomationAccountName `
                                -RuntimeVersion $AutomationRuntime `
                                -Name $DependencyName `
                                -ErrorAction SilentlyContinue
                            # Filter out Global modules
                            $AutomationModule = $AutomationModule | Where-Object { $PsItem.IsGlobal -eq $false }
                            # Do not downgrade version of module if newer exists in Automation account (limitation of AA that one can only have only one version of a module imported)
                            # limit also recursion depth of dependencies search
                            if( ($script:RecursionDepth -le $script:RecursionDepthLimit) -and ((-not $AutomationModule) -or [System.Version]$AutomationModule.Version -lt [System.Version]$DependencyVersion) )
                            {
                                Write-Output -InputObject "$ModuleName depends on: $DependencyName with version $DependencyVersion, importing this module first"

                                # this dependency module has not been imported, import it first
                                doModuleImport `
                                    -AutomationResourceGroupName $AutomationResourceGroupName `
                                    -AutomationAccountName $AutomationAccountName `
                                    -ModuleName $DependencyName `
                                    -ModuleVersion $DependencyVersion -ErrorAction Continue
                                # Register module has been imported
                                # TODO: If module import fails, do not add and remove the failed imported module from AA account
                                $null = $script:ModulesImported.Add($DependencyName)
                                $script:RecursionDepth --
                            }
                            else
                            {
                                Write-Output -InputObject "$ModuleName has a dependency on: $DependencyName with version: $DependencyVersion, though this is already installed with version: $($AutomationModule.Version)"
                            }
                        }
                        else
                        {
                            Write-Output -InputObject "$DependencyName already imported to Automation account"
                        }
                    }
                }
            }

            # Find the actual blob storage location of the module
            do
            {
                $ActualUrl = $ModuleContentUrl
                # In PS 7.1 settting -MaximumRedirection 0 will throw an termination error
                if( $PSVersionTable.PSVersion.Major -eq 7 )
                {
                    Write-Verbose -Message "Running under PS 7 or newer"
                    try
                    {
                        $Content = Invoke-WebRequest -Uri $ModuleContentUrl -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction Ignore
                    }
                    catch
                    {
                        Write-Verbose -Message "Invoke-WebRequest termination error detected"
                    }
                }
                else
                {
                    Write-Verbose -Message "Running under PS 5.1"
                    $Content = Invoke-WebRequest -Uri $ModuleContentUrl -MaximumRedirection 0 -UseBasicParsing -ErrorAction Ignore
                }
                [String]$ModuleContentUrl = $Content.Headers.Location
                Write-Verbose -Message "Module content location URL found inside loop is: $ModuleContentUrl"
            }
            while( $ModuleContentUrl -notmatch ".nupkg" -or [string]::IsNullOrEmpty($ModuleContentUrl) )

            Write-Verbose -Message "Do/While loop ended"

            if( [string]::IsNullOrEmpty($ModuleContentUrl) )
            {
                Write-Error -Message "Fetching module content URL returned empty value." -ErrorAction Stop
            }
            else
            {
                Write-Verbose -Message "Final Module content location URL is: $ModuleContentUrl"
            }

            $ActualUrl = $ModuleContentUrl

            if($ModuleVersion)
            {
                Write-Output -InputObject "Importing version: $ModuleVersion of module: $ModuleName to Automation account"
            }
            else
            {
                Write-Output -InputObject "Importing version: $($SearchResult.Version) of module: $ModuleName to Automation account"
            }
            if(-not ([string]::IsNullOrEmpty($ActualUrl)))
            {
                $AutomationModule = New-AzureRMAutomationModule `
                    -ResourceGroupName $AutomationResourceGroupName `
                    -AutomationAccountName $AutomationAccountName `
                    -Name $ModuleName `
                    -RuntimeVersion $AutomationRuntime `
                    -ContentLink $ActualUrl -ErrorAction continue
                $oErr = $null
                while(
                    (-not ([string]::IsNullOrEmpty($AutomationModule))) -and
                    $AutomationModule.ProvisioningState -ne "Created" -and
                    $AutomationModule.ProvisioningState -ne "Succeeded" -and
                    $AutomationModule.ProvisioningState -ne "Failed" -and
                    [string]::IsNullOrEmpty($oErr)
                )
                {
                    Start-Sleep -Seconds 5
                    Write-Verbose -Message "Polling module import status for: $($AutomationModule.Name)"
                    $AutomationModule = $AutomationModule | Get-AzureRMAutomationModule -ErrorAction silentlycontinue -ErrorVariable oErr
                    if($oErr)
                    {
                        Write-Error -Message "Error fetching module status for: $($AutomationModule.Name)" -ErrorAction Continue
                    }
                    else
                    {
                        Write-Verbose -Message "Module import pull status: $($AutomationModule.ProvisioningState)"
                    }
                }
                if( ($AutomationModule.ProvisioningState -eq "Failed") -or $oErr )
                {
                    Write-Error -Message "Import of $($AutomationModule.Name) module to Automation account failed." -ErrorAction Continue
                    Write-Output -InputObject "Import of $($AutomationModule.Name) module to Automation account failed."
                    $oErr = $null
                }
                else
                {
                    Write-Output -InputObject "Import of $ModuleName module to Automation account succeeded."
                }
            }
            else
            {
                Write-Error -Message "Failed to retrieve download URL of module: $ModuleName in Gallery, update of module aborted" -ErrorId continue
            }
        }
    }
    catch
    {
        if ($_.Exception.Message)
        {
            Write-Error -Message "$($_.Exception.Message)" -ErrorAction Continue
        }
        else
        {
            Write-Error -Message "$($_.Exception)" -ErrorAction Continue
        }
        throw "$($_.Exception)"
    }
}
#endregion

#region Main
try
{
    $RunAsConnection = Get-AutomationConnection -Name "AzureRunAsConnection"
    if($RunAsConnection)
    {
        Write-Output -InputObject ("Logging in to Azure...")
        if( $UseMSI )
        {
            $Null = Add-AzureRMAccount -Identity -ErrorAction Continue -ErrorVariable oErr
            if($oErr)
            {
                Write-Error -Message "Failed to connect to Azure Resource Manager using Managed Service Identity" -ErrorAction Stop
            }
        }
        else
        {
            $Null = Add-AzureRMAccount `
                -ServicePrincipal `
                -TenantId $RunAsConnection.TenantId `
                -ApplicationId $RunAsConnection.ApplicationId `
                -CertificateThumbprint $RunAsConnection.CertificateThumbprint -ErrorAction Continue -ErrorVariable oErr
            if($oErr)
            {
                Write-Error -Message "Failed to connect to Azure using legacy RunAs account" -ErrorAction Stop
            }
        }

        Write-Verbose -Message "Selecting subscription to use"
        $Subscription = Select-AzureRMSubscription -SubscriptionId $RunAsConnection.SubscriptionID -TenantId $RunAsConnection.TenantId -ErrorAction Continue -ErrorVariable oErr
        if($oErr)
        {
            Write-Error -Message "Failed to select Azure subscription" -ErrorAction Stop
        }
        else
        {
            Write-Output -InputObject "Running in subscription: $($Subscription.Subscription.Name) and tenantId: $($Subscription.Tenant.Id)"
        }
        if(-not $DebugLocal)
        {
            # Find the automation account or resource group is not specified
            if  (([string]::IsNullOrEmpty($AutomationResourceGroupName)) -or ([string]::IsNullOrEmpty($AutomationAccountName)))
            {
                if( $PSVersionTable.PSVersion.Major -eq 7 )
                {
                    Write-Error -Message "Powershell 7 does not support metode used to find AA account. Populate AutomationResourceGroupName and AutomationAccountName then run again."  -ErrorAction Stop
                }
                Write-Verbose -Message ("Finding the ResourceGroup and AutomationAccount that this job is running in ...")
                if ([string]::IsNullOrEmpty($PSPrivateMetadata.JobId.Guid))
                {
                    Write-Error -Message "This is not running from the automation service. Please specify ResourceGroupName and AutomationAccountName as parameters" -ErrorAction Stop
                }

                $AutomationResource = Get-AzureRmResource -ResourceType Microsoft.Automation/AutomationAccounts -ErrorAction Stop

                foreach ($Automation in $AutomationResource)
                {
                    $Job = Get-AzureRmAutomationJob -ResourceGroupName $Automation.ResourceGroupName -AutomationAccountName $Automation.Name -Id $PSPrivateMetadata.JobId.Guid -ErrorAction SilentlyContinue
                    if (!([string]::IsNullOrEmpty($Job)))
                    {
                        $AutomationResourceGroupName = $Job.ResourceGroupName
                        $AutomationAccountName = $Job.AutomationAccountName
                        break;
                    }
                }
                if($AutomationAccountName)
                {
                    Write-Output -InputObject "Using AA account: $AutomationAccountName in resource group: $AutomationResourceGroupName"
                }
                else
                {
                    Write-Error -Message "Failed to discover automation account, execution stopped" -ErrorAction Stop
                }
            }
        }
        else
        {
            if(([string]::IsNullOrEmpty($AutomationResourceGroupName)) -or ([string]::IsNullOrEmpty($AutomationAccountName)))
            {
                Write-Error -Message "When debugging locally ResourceGroupName and AutomationAccountName parameters must be set" -ErrorAction Stop
            }
        }
    }
    else
    {
        Write-Error -Message "Check that AzureRunAsConnection is configured for AA account: $AutomationAccountName" -ErrorAction Stop
    }

    $Modules = Get-AzureRmAutomationModule `
        -ResourceGroupName $AutomationResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -RuntimeVersion $AutomationRuntime `
        -ErrorAction continue -ErrorVariable oErr
    if($oErr)
    {
        Write-Error -Message "Failed to retrieve modules in AA account $AutomationAccountName" -ErrorAction Stop
    }
    if($Modules)
    {
        foreach($Module in $Modules)
        {
            $ModuleName = $Module.Name
            $ModuleVersionInAutomation = $Module.Version

            $Filter = @($ModuleName.Trim('*').Split('*') | ForEach-Object { "substringof('$_',Id)" }) -join " and "
            $Url = "$script:PsGalleryApiUrl/Packages?`$filter=$Filter and IsLatestVersion"

            # Fetch results and filter them with -like, and then shape the output
            $SearchResult = Invoke-RestMethod -Method Get -Uri $Url -ErrorAction Continue -ErrorVariable oErr | Where-Object { $_.title.'#text' -like $ModuleName } |
                Select-Object @{n = 'Name'; ex = {$_.title.'#text'}},
            @{n = 'Version'; ex = {$_.properties.version}},
            @{n = 'Url'; ex = {$_.Content.src}},
            @{n = 'Dependencies'; ex = {$_.properties.Dependencies}},
            @{n = 'Owners'; ex = {$_.properties.Owners}}
            if($oErr)
            {
                Write-Error -Message "Failed to query Gallery for module $ModuleName" -ErrorAction Continue
                $oErr = $Null
            }
            if($SearchResult)
            {
                # Should not be needed anymore, though in the event of the search returning more than one hit this will strip it down
                if($SearchResult.Length -and $SearchResult.Length -gt 1)
                {
                    $SearchResult = $SearchResult | Where-Object -FilterScript {
                        return $_.Name -eq $ModuleName
                    }
                }

                $UpdateModule = $false
                if($UpdateAzureModulesOnly)
                {
                    if($SearchResult.Owners -eq $script:AzureSdkOwnerName)
                    {
                        Write-Output -InputObject "Checking if azure module '$ModuleName' is up to date in your automation account"
                        $UpdateModule = $true
                    }
                }
                else
                {
                    Write-Output -InputObject "Checking if module '$ModuleName' is up to date in your automation account"
                    $UpdateModule = $true
                }
                if($UpdateModule)
                {
                    if(-not $SearchResult)
                    {
                        Write-Output -InputObject "Could not find module '$ModuleName' on PowerShell Gallery. This may be a module imported from a different location"
                    }
                    else
                    {
                        $LatestModuleVersionOnPSGallery = $SearchResult.Version
                        if( $Module.ProvisioningState -ne "Failed" -or $Force -eq $true )
                        {
                            if( ($ModuleVersionInAutomation -ne $LatestModuleVersionOnPSGallery) -or ($Module.ProvisioningState -eq "Failed" -and $Force -eq $true) )
                            {
                                Write-Output -InputObject "Module '$ModuleName' is not up to date. Latest version on PS Gallery is '$LatestModuleVersionOnPSGallery' but this automation account has version '$ModuleVersionInAutomation'"
                                Write-Output -InputObject "Importing latest version of '$ModuleName' into your automation account"

                                doModuleImport `
                                    -AutomationResourceGroupName $AutomationResourceGroupName `
                                    -AutomationAccountName $AutomationAccountName `
                                    -ModuleName $ModuleName
                            }
                            else
                            {
                                Write-Output -InputObject "Module '$ModuleName' is up to date."
                            }
                        }
                        else
                        {
                            if($Module.ProvisioningState -eq "Failed")
                            {
                                Write-Error -Message "Module '$ModuleName' import has previously failed, skipping update of module" -ErrorAction Continue
                            }
                            else
                            {
                                Write-Warning -Message "Module '$ModuleName' in automation account has no version data. Skipping update of module" -WarningAction Continue
                            }
                        }
                    }
                }
            }
            else
            {
                if( -not $UpdateAzureModulesOnly )
                {
                    Write-Output -InputObject "No result from querying PS Gallery for module: $ModuleName"
                }
            }
        }
    }
    else
    {
        Write-Error -Message "No modules found in AA account: $AutomationAccountName" -ErrorAction Stop
    }
}
catch
{
    if ($_.Exception.Message)
    {
        Write-Error -Message "$($_.Exception.Message)" -ErrorAction Continue
    }
    else
    {
        Write-Error -Message "$($_.Exception)" -ErrorAction Continue
    }
    throw "$($_.Exception)"
}
finally
{
    Write-Output -InputObject "Runbook: $RunbookName ended at time: $(get-Date -format r)"
    if($AzureModuleFlavor -eq "Az")
    {
        Disable-AzureRmAlias
    }
}
#endregion Main