<##########################################

# Overview:
    This script is used to remove deprecated/stale(invalid) AAD identities role assignments from subscription.

ControlId: 
    Azure_Subscription_AuthZ_Remove_Deprecated_Accounts
DisplayName:
    Remove Orphaned accounts from your subscription(s).

# Pre-requisites:
    You will need owner or User Access Administrator role at subscription level.

# Steps performed by the script
    1. Install and validate pre-requisites to run the script for subscription.

    2. Get role assignments for the subscription and filter deprecated/stale(invalid) identities.

    3. Taking backup of deprecated/stale(invalid) identities that are going to be removed using remediation script.

    4. Clean up deprecated/stale(invalid) AAD object identities role assignments from subscription.

# Step to execute script:
    Download and load remediation script in PowerShell session and execute below command.
    To know how to load script in PowerShell session refer link: https://aka.ms/AzTS-docs/RemediationscriptExcSteps.

# Command to execute:
    Examples:
        1. Run below command to remove all deprecated/stale(invalid) identities role assignments from subscription

         Remove-AzTSInvalidAADAccounts -SubscriptionId '<Sub_Id>' -PerformPreReqCheck: $true

        2. Run below command, if you have deprecated/stale(invalid) identities list with you. You will get deprecated/stale(invalid) object id (UserName) from AzTS UI status reason section.

         Remove-AzTSInvalidAADAccounts -SubscriptionId '<Sub_Id>' -ObjectIds @('<Object_Id_1>', '<Object_Id_2>') -PerformPreReqCheck: $true
         
        Note:
            i. [Recommended] Use -DryRun parameter to take all deprecated/invalid identity's role assignment in CSV for pre-check.
            ii. Use -FilePath parameter by providing CSV file path generated by DryRun script to remove all role assignments available in CSV file.
         
To know more about parameter execute below command:
    Get-Help Remove-AzTSInvalidAADAccounts -Detailed

########################################
#>

function Pre_requisites
{
    <#
    .SYNOPSIS
    This command would check pre requisites modules.
    .DESCRIPTION
    This command would check pre requisites modules to perform remediation.
	#>

    Write-Host "Required modules are: Az.Resources, AzureAD, Az.Accounts, Az.ResourceGraph" -ForegroundColor Cyan
    Write-Host "Checking for required modules..."
    $availableModules = $(Get-Module -ListAvailable Az.Resources, AzureAD, Az.Accounts, Az.ResourceGraph)
    
    # Checking if 'Az.Accounts' module is available or not.
    if($availableModules.Name -notcontains 'Az.Accounts')
    {
        Write-Host "Installing module Az.Accounts..." -ForegroundColor Yellow
        Install-Module -Name Az.Accounts -Scope CurrentUser -Repository 'PSGallery'
    }
    else
    {
        Write-Host "Az.Accounts module is available." -ForegroundColor Green
    }

    # Checking if 'Az.Resources' module is available or not.
    if($availableModules.Name -notcontains 'Az.Resources')
    {
        Write-Host "Installing module Az.Resources..." -ForegroundColor Yellow
        Install-Module -Name Az.Resources -Scope CurrentUser -Repository 'PSGallery'
    }
    else
    {
        Write-Host "Az.Resources module is available." -ForegroundColor Green
    }

     # Checking if 'ARG' module is available or not.
    if($availableModules.Name -notcontains 'Az.ResourceGraph')
    {
        Write-Host "Installing module Az.ResourceGraph..." -ForegroundColor Yellow
        Install-Module -Name Az.ResourceGraph -Scope CurrentUser -Repository 'PSGallery'
    }
    else
    {
        Write-Host "Az.ResourceGraph module is available." -ForegroundColor Green
    }

    # Checking if 'AzureAD' module is available or not.
    if($availableModules.Name -notcontains 'AzureAD')
    {
        Write-Host "Installing module AzureAD..." -ForegroundColor Yellow
        Install-Module -Name AzureAD -Scope CurrentUser -Repository 'PSGallery'
    }
    else
    {
        Write-Host "AzureAD module is available." -ForegroundColor Green
    }
}

function Remove-AzTSInvalidAADAccounts
{
    <#
    .SYNOPSIS
    This command would help in remediating 'Azure_Subscription_AuthZ_Remove_Deprecated_Accounts' control.
    .DESCRIPTION
    This command would help in remediating 'Azure_Subscription_AuthZ_Remove_Deprecated_Accounts' control.
    .PARAMETER SubscriptionId
        Enter subscription id on which remediation need to perform.
    .PARAMETER ObjectIds
        Enter objectIds of invalid AAD accounts.
    .Parameter Force
        Enter force parameter value to remove deprecated/stale identity's role assignment.
    .PARAMETER PerformPreReqCheck,
        Perform pre requisites check to ensure all required module to perform remediation operation is available.
    .PARAMETER DryRun
        Run pre-script before actual remediating the subscription
    .PARAMETER FilePath
        Enter file path name if you have list of all deprecated/invalid identity's role assignment.
    #>

    param (
        [string]
        $SubscriptionId,

        [string[]]
        $ObjectIds,

        [switch]
        $Force,

        [switch]
        $PerformPreReqCheck,

        [switch]
        $DryRun,

        [string]
        $FilePath
    )

    Write-Host "======================================================"
    Write-Host "Starting with removal of invalid AAD object guids from subscriptions..."
    Write-Host "------------------------------------------------------"

    if($PerformPreReqCheck)
    {
        try 
        {
            Write-Host "Checking for pre-requisites..."
            Pre_requisites
            Write-Host "------------------------------------------------------"     
        }
        catch 
        {
            Write-Host "Error occurred while checking pre-requisites. ErrorMessage [$($_)]" -ForegroundColor Red    
            break
        }
    }

    # Connect to AzAccount
    $isContextSet = Get-AzContext
    if ([string]::IsNullOrEmpty($isContextSet))
    {       
        Write-Host "Connecting to AzAccount..."
        Connect-AzAccount -ErrorAction Stop
        Write-Host "Connected to AzAccount" -ForegroundColor Green
    }

    # Setting context for current subscription.
    $currentSub = Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop

    
    Write-Host "Note: `n 1. Exclude checking PIM assignment for deprecated account due to insufficient privilege. `n 2. Exclude checking deprecated account with 'AccountAdministrator' role due to insufficient privilege. `n    (To remove deprecated account role assignment with 'AccountAdministrator' role, please reach out to Azure Support) `n 3. Exclude checking role assignments at MG scope. `n 4. Checking only for user type assignments." -ForegroundColor Yellow
    Write-Host "------------------------------------------------------"
    Write-Host "Metadata Details: `n SubscriptionId: $($SubscriptionId) `n AccountName: $($currentSub.Account.Id) `n AccountType: $($currentSub.Account.Type)"
    Write-Host "------------------------------------------------------"
    Write-Host "Starting with Subscription [$($SubscriptionId)]..."


    Write-Host "Step 1 of 5: Validating whether the current user [$($currentSub.Account.Id)] has the required permissions to run the script for subscription [$($SubscriptionId)]..."

    # Safe Check: Checking whether the current account is of type User and also grant the current user as UAA for the sub to support fallback
    if($currentSub.Account.Type -ne "User")
    {
        Write-Host "Warning: This script can only be run by user account type." -ForegroundColor Yellow
        return;
    }

    # Safe Check: Current user need to be either UAA or Owner for the subscription
    $currentLoginRoleAssignments = Get-AzRoleAssignment -SignInName $currentSub.Account.Id -Scope "/subscriptions/$($SubscriptionId)";
    $userMemberGroups = @()
    $currentLoginUserObjectId = "";

    $requiredRoleDefinitionName = @("Owner", "User Access Administrator")
    if(($currentLoginRoleAssignments | Where { $_.RoleDefinitionName -in $requiredRoleDefinitionName} | Measure-Object).Count -le 0 )
    {
        # The user does not have direct access to the subscription, checking if the user has access through groups
        # Need to connect to Azure AD before running any other command for fetching Entra Id related information (e.g. - group membership)
        try
        {
            Get-AzureADTenantDetail | Out-Null
        }
        catch
        {
            Connect-AzureAD -TenantId $currentSub.Tenant.Id | Out-Null
        }
        
        $allRoleAssignments = Get-AzRoleAssignment -Scope "/subscriptions/$($SubscriptionId)" # Fetch all the role assignmenets for the given scope
        $userMemberGroups = Get-AzureADUserMembership -ObjectId $currentSub.Account.Id -All $true | Select-Object -ExpandProperty ObjectId # Fetch all the groups the user has access to and get all the object ids
        if(($allRoleAssignments | Where-Object { $_.RoleDefinitionName -in $requiredRoleDefinitionName -and $_.ObjectId -in $userMemberGroups } | Measure-Object).Count -le 0)
        {
            Write-Host "Warning: This script can only be run by an [$($requiredRoleDefinitionName -join ", ")]." -ForegroundColor Yellow
            return;
        }

        $currentLoginUserObjectId = Get-AzureADUser -Filter "userPrincipalName eq '$($currentSub.Account.Id)'" | Select-Object ObjectId -ExpandProperty ObjectId # Fetch the user object id
    }

    Write-Host "Current user [$($currentSub.Account.Id)] has the required permission for subscription [$($SubscriptionId)]." -ForegroundColor Green

    # Safe Check: saving the current login user object id to ensure we don't remove this during the actual removal
    $currentLoginUserObjectIdArray = @()
    $currentLoginUserObjectIdArray += $currentLoginRoleAssignments | select ObjectId -Unique
    if(($currentLoginUserObjectIdArray | Measure-Object).Count -gt 0)
    {
        $currentLoginUserObjectId = $currentLoginUserObjectIdArray[0].ObjectId;
    }

    $currentLoginUserObjectIdArray += $userMemberGroups
    if([String]::IsNullOrWhiteSpace($FilePath))
    { 
        Write-Host "Step 2 of 5: Fetching all the role assignments for subscription [$($SubscriptionId)]..."

        $classicAssignments = $null
        $distinctObjectIds = @();

        # adding one valid object guid, so that even if graph call works, it has to get atleast 1. If we don't get any, means Graph API failed.
        $distinctObjectIds += $currentLoginUserObjectId;
        if(($ObjectIds | Measure-Object).Count -eq 0)
        {
            # Getting all classic role assignments.
            $classicAssignments = [ClassicRoleAssignments]::new()
            $res = $classicAssignments.GetClassicRoleAssignments($subscriptionId)
            $classicDistinctRoleAssignmentList = $res.value | Where-Object { ![string]::IsNullOrWhiteSpace($_.properties.emailAddress) }
            
            # Renaming property name
            $classicRoleAssignments = $classicDistinctRoleAssignmentList | select @{N='SignInName'; E={$_.properties.emailAddress}},  @{N='RoleDefinitionName'; E={$_.properties.role}}, @{N='RoleId'; E={$_.name}}, @{N='Type'; E={$_.type }}, @{N='RoleAssignmentId'; E={$_.id }}

        
            # Getting all role assignments of subscription.
            $currentRoleAssignmentList = Get-AzRoleAssignment

            # Excluding MG scoped role assignment
            $currentRoleAssignmentList = $currentRoleAssignmentList | Where-Object { !$_.Scope.Contains("/providers/Microsoft.Management/managementGroups/") }
            
            # Getting all permanent role assignments.
            $currentRoleAssignmentList = $currentRoleAssignmentList | Where-Object {![string]::IsNullOrWhiteSpace($_.ObjectId)};
            $currentRoleAssignmentList | select -Unique -Property 'ObjectId' | ForEach-Object { $distinctObjectIds += $_.ObjectId }

            
            $method = [Microsoft.PowerShell.Commands.WebRequestMethod]::Get
            $classicAssignments = [ClassicRoleAssignments]::new()
            $headers = $classicAssignments.GetAuthHeader()

            # Getting MDC reported deprecated account object ids.
            $mdcDeprecated = [MDCDeprecatedAccounts]::new()
            $mdcDeprecatedAccountList  = $mdcDeprecated.GetMDCDeprecatedAccounts([string] $SubscriptionId)
      
            $mdcDeprecatedRoleAssignmentList = @();
            if (($mdcDeprecatedAccountList | Measure-Object).Count -gt 0)
            {
                $mdcDeprecatedRoleAssignmentList = $currentRoleAssignmentList | Where-Object {  $mdcDeprecatedAccountList -contains $_.ObjectId}
            }          
        }    
        else
        {
            $currentRoleAssignmentList = @()
            $ObjectIds | Foreach-Object {
            $objectId = $_;
            
            if(![string]::IsNullOrWhiteSpace($objectId))
                {
                    $currentRoleAssignmentList += Get-AzRoleAssignment -ObjectId $objectId | Where-Object { !$_.Scope.Contains("/providers/Microsoft.Management/managementGroups/")}
                    $distinctObjectIds += $objectId
                }
                else
                {
                    Write-Host "Warning: Don't pass empty string array in the ObjectIds param. If you don't want to use the param, just remove while executing the command" -ForegroundColor Yellow
                    break;
                }  
            }
        } 

        Write-Host "Step 3 of 5: Resolving all the AAD Object guids against Tenant. Number of distinct object guids [$($distinctObjectIds.Count)]..."
        # Connect to Azure Active Directory.
        try
        {
            # Check if Connect-AzureAD session is already active 
            Get-AzureADUser -ObjectId $currentLoginUserObjectId | Out-Null
        }
        catch
        {
            Write-Host "Connecting to Azure AD..."
            Connect-AzureAD -TenantId $currentSub.Tenant.Id -ErrorAction Stop
        }   

        # Batching object ids in count of 900.
        $activeIdentities = @();
        for( $i = 0; $i -lt $distinctObjectIds.Length; $i = $i + 900)
        {
            if($i + 900 -lt $distinctObjectIds.Length)
            {
                $endRange = $i + 900
            }
            else
            {
                $endRange = $distinctObjectIds.Length -1;
            }

            $subRange = $distinctObjectIds[$i..$endRange]

            # Getting active identities from Azure Active Directory.
            $subActiveIdentities = Get-AzureADObjectByObjectId -ObjectIds $subRange
            # Safe Check 
            if(($subActiveIdentities | Measure-Object).Count -le 0)
            {
                # If the active identities count has come as Zero, then API might have failed.  Print Warning and abort the execution
                Write-Host "Warning: Graph API hasnt returned any active account. Current principal don't have access to Graph or Graph API is throwing error. Aborting the operation. Reach out to aztssup@microsoft.com" -ForegroundColor Yellow
                return;
            }

            $activeIdentities += $subActiveIdentities.ObjectId
        }

        $invalidAADObjectIds = $distinctObjectIds | Where-Object { $_ -notin $activeIdentities}

        # Get list of all invalid classic role assignments followed by principal name.
        $invalidClassicRoles = @();
        
        if(($classicRoleAssignments | Measure-Object).count -gt 0)
        {
            $classicRoleAssignments | ForEach-Object { 
                $userDetails = Get-AzureADUser -Filter "userPrincipalName eq '$($_.SignInName)' or Mail eq '$($_.SignInName)'"
                if (($userDetails | Measure-Object).Count -eq 0 ) 
                {
                    $invalidClassicRoles += $_ 
                }
            }
        }
        
        $invalidClassicRoles += $mdcDeprecatedRoleAssignmentList | Where-Object {[string]::IsNullOrWhiteSpace($_.ObjectId)}; 
        
        # Get list of all invalidAADObject guid assignments followed by object ids.
        $invalidAADObjectRoleAssignments = $currentRoleAssignmentList | Where-Object {  $invalidAADObjectIds -contains $_.ObjectId}
        $invalidAADObjectRoleAssignments += $mdcDeprecatedRoleAssignmentList | Where-Object {![string]::IsNullOrWhiteSpace($_.ObjectId)};
        Write-Host "Checking current User account is valid AAD Object guid or not..."
    }

    else
    {
        Write-Host "Step 2 of 5: Fetching all the role assignments for subscription [$($SubscriptionId)] from given CSV file..."
        # Connect to Azure Active Directory.
        try
        {
            # Check if Connect-AzureAD session is already active 
            Get-AzureADUser -ObjectId $currentLoginUserObjectId | Out-Null
        }
        catch
        {
            Write-Host "Connecting to Azure AD..."
            Connect-AzureAD -ErrorAction Stop
        }  

        $allRoleAssignments = Import-Csv -LiteralPath $FilePath
        $invalidAADObjectRoleAssignments = $allRoleAssignments | Where-Object {![string]::IsNullOrWhiteSpace($_.ObjectId)};
        $invalidClassicRoles = $allRoleAssignments | Where-Object {[string]::IsNullOrWhiteSpace($_.ObjectId)};

        Write-Host "Step 3 of 5: Checking current User account is valid AAD Object guid or not..."       
    }   

    # Safe Check: Check whether the current user accountId is part of invalid AAD Object guids List 
    if(($invalidAADObjectRoleAssignments | where { $_.ObjectId -in $currentLoginUserObjectIdArray } | Measure-Object).Count -gt 0)
    {
        Write-Host "Warning: Current User account is found as part of the invalid AAD Object guids collection. This is not expected behaviour. This can happen typically during Graph API failures. Aborting the operation. Reach out to aztssup@microsoft.com" -ForegroundColor Yellow
        return;
    }
    else
    {
        Write-Host "Current user account is valid identity in AAD." -ForegroundColor Green
    }

    if(($invalidClassicRoles | Measure-Object).Count -gt 0)
    {
        # If there is any classic deprecated assignment present for 'AccountAdministrator' role remove from the collection
        # As AccounAdministrator assignment can't be removed using pwsh/script
        $invalidClassicRoles = $invalidClassicRoles | Where-Object { $_.RoleDefinitionName -notlike "*AccountAdministrator*"}
    }

    # Getting count of deprecated/invalid accounts
    $invalidAADObjectRoleAssignmentsCount = ($invalidAADObjectRoleAssignments | Measure-Object).Count
    $invalidClassicRolesCount = ($invalidClassicRoles | Measure-Object).Count

    if(($invalidAADObjectRoleAssignmentsCount -eq 0) -and ($invalidClassicRolesCount -eq 0))
    {
        Write-Host "No invalid/deprecated accounts found for the subscription [$($SubscriptionId)]. Exiting the process."
        return;
    }

    if($invalidAADObjectRoleAssignmentsCount -gt 0 )
    {
       Write-Host "Found [$($invalidAADObjectRoleAssignmentsCount)] invalid role assignments against invalid AAD object guids for the subscription [$($SubscriptionId)]" -ForegroundColor Cyan
    }    

    if($invalidClassicRolesCount -gt 0 )
    {
        Write-Host "Found [$($invalidClassicRolesCount)] invalid classic role assignments for the subscription [$($SubscriptionId)]" -ForegroundColor Cyan
    }
     
    $folderPath = [Environment]::GetFolderPath("MyDocuments") 
    if (Test-Path -Path $folderPath)
    {
        $folderPath += "\AzTS\Remediation\Subscriptions\$($subscriptionid.replace("-","_"))\$((Get-Date).ToString('yyyyMMdd_hhmm'))\InvalidAADAccounts\"
        New-Item -ItemType Directory -Path $folderPath | Out-Null
    }

    Write-Host "Step 4 of 5: Taking backup of current role assignments at [$($folderPath)]..."  
    
    # Safe Check: Exporting all role assignments in CSV file.
    # Safe Check: Taking backup of invalid identities.   
    if (($invalidAADObjectRoleAssignments | Measure-Object).Count -gt 0)
    {
        $invalidAADObjectRoleAssignments | ConvertTo-json | out-file "$($folderpath)\InvalidRoleAssignments.json"       
        $invalidAADObjectRoleAssignments | Export-CSV -Path "$($folderpath)\DeprecatedIdentitiesRoleAssignments.csv" -NoTypeInformation        
    }

    # Safe Check: Taking backup of invalid classic role assignments.    
    if (($invalidClassicRoles | Measure-Object).Count -gt 0)
    {
        $invalidClassicRoles | ConvertTo-json | out-file "$($folderpath)\InvalidClassicRoleAssignments.json"       
        $invalidClassicRoles | Export-CSV -Path "$($folderpath)\DeprecatedIdentitiesRoleAssignments.csv" -Append -Force     
    }
     
   

    if(-not $DryRun)       
    {
        if(-not $Force)
        {
            Write-Host "Note: Once deprecated role assignments deleted, it can not be restored." -ForegroundColor Yellow
            Write-Host "Do you want to delete the above listed role assignment?" -ForegroundColor Yellow -NoNewline
            $UserInput = Read-Host -Prompt "(Y|N)"

            if($UserInput -ne "Y")
            {
                return;
            }
        }
        
        Write-Host "Step 5 of 5: Clean up invalid object guids for subscription [$($SubscriptionId)]..."

        # Start deletion of all deprecated accounts/invalid AAD Object guids.
        Write-Host "Starting to delete invalid AAD object guid role assignments..." -ForegroundColor Cyan

        $isRemoved = $true

        if (($invalidAADObjectRoleAssignments | Measure-Object).Count -gt 0)
        {
            $invalidAADObjectRoleAssignments | ForEach-Object {
                try 
                {
                    Remove-AzRoleAssignment $_ 
                    $_ | Select-Object -Property "Scope", "RoleDefinitionName", "ObjectId"    
                }
                catch
                {
                    $isRemoved = $false
                    Write-Host "Not able to remove invalid role assignment. ErrorMessage [$($_)]" -ForegroundColor Red  
                }
            }
        }

        # Deleting deprecated account having classic role assignment.
        if(($invalidClassicRoles | Measure-Object).Count -gt 0)
        {
            $invalidClassicRoles | ForEach-Object {
                try 
                {
                    if($_.RoleDefinitionName -in ("CoAdministrator", "ServiceAdministrator") -and $_.RoleAssignmentId.contains("/providers/Microsoft.Authorization/classicAdministrators/"))
                    {
                        $isServiceAdminAccount = $false
                        if($_.RoleDefinitionName -eq "ServiceAdministrator")
                        {
                            $isServiceAdminAccount = $true;
                        }

                        $classicAssignments = [ClassicRoleAssignments]::new()
                        $res = $classicAssignments.DeleteClassicRoleAssignment($_.RoleAssignmentId, $isServiceAdminAccount)

                        if(($null -ne $res) -and ($res.StatusCode -eq 202 -or $res.StatusCode -eq 200))
                        {
                            $_ | Select-Object -Property "SignInName", "RoleAssignmentId", "RoleDefinitionName"
                        }
                    }
                }
                catch
                {
                    $isRemoved = $false
                    Write-Host "Not able to remove invalid classic role assignment. ErrorMessage [$($_)]" -ForegroundColor Red  
                }
            }
        }

        if($isRemoved)
        {
            Write-Host "Completed deleting deprecated/invalid AAD Object guids role assignments." -ForegroundColor Green
        }
        else 
        {
            Write-Host "`n"
            Write-Host "Not able to successfully delete deprecated/invalid AAD Object guids role assignments." -ForegroundColor Red
        }
    }
    else
    {
        Write-Host "Validate all role assignments that are going to remediate using this script at [$($folderPath)]..." -ForegroundColor Green
        return;
    }    
}

function Get-ARGData
{
    param (

        [string]
        $kqlQuery,

        [int]
        $BatchSize = 1000
    )

    $skipResult = 0

    $kqlResponse = @()

    while ($true) {

      if ($skipResult -gt 0) {
        $graphResult = Search-AzGraph -Query $kqlQuery -First $batchSize -SkipToken $graphResult.SkipToken
      }
      else {
        $graphResult = Search-AzGraph -Query $kqlQuery -First $batchSize
      }

      $kqlResponse += $graphResult.data.ToArray()

      if ($graphResult.data.Count -lt $batchSize) {
        break;
      }
      $skipResult += $skipResult + $batchSize
    }

    return $kqlResponse
}


class ClassicRoleAssignments
{
    [PSObject] GetAuthHeader()
    {
        [psobject] $headers = $null
        try 
        {
            $resourceAppIdUri = "https://management.core.windows.net/"
            $rmContext = Get-AzContext
            $authResult = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate(
            $rmContext.Account,
            $rmContext.Environment,
            $rmContext.Tenant,
            [System.Security.SecureString] $null,
            "Never",
            $null,
            $resourceAppIdUri); 

            $header = "Bearer " + $authResult.AccessToken
            $headers = @{"Authorization"=$header;"Content-Type"="application/json";}
        }
        catch 
        {
            Write-Host "Error occurred while fetching auth header. ErrorMessage [$($_)]" -ForegroundColor Red   
        }
        return($headers)
    }

    [PSObject] GetClassicRoleAssignments([string] $subscriptionId)
    {
        $content = $null
        try
        {
            $armUri = "https://management.azure.com/subscriptions/$($subscriptionId)/providers/Microsoft.Authorization/classicadministrators?api-version=2015-06-01"
            $headers = $this.GetAuthHeader()
            # API to get classic role assignments
            $response = Invoke-WebRequest -Method Get -Uri $armUri -Headers $headers -UseBasicParsing
            $content = ConvertFrom-Json $response.Content
        }
        catch
        {
            Write-Host "Error occurred while fetching classic role assignment. ErrorMessage [$($_)]" -ForegroundColor Red
        }
        
        return($content)
    }

    [PSObject] DeleteClassicRoleAssignment([string] $roleAssignmentId, [bool] $isServiceAdminAccount)
    {
        $content = $null
        try
        {
            $armUri = "https://management.azure.com" + $roleAssignmentId + "?api-version=2015-06-01"
            if ($isServiceAdminAccount)
            {
                $armUri += "&adminType=serviceAdmin"
            }
            $headers = $this.GetAuthHeader()
            
            # API to get classic role assignments
            $response = Invoke-WebRequest -Method Delete -Uri $armUri -Headers $headers -UseBasicParsing
            $content = $response
        }
        catch
        {
            Write-Host "Error occurred while deleting classic role assignment. ErrorMessage [$($_)]" -ForegroundColor Red
            throw;
        }
        
        return($content)
    }
}

class MDCDeprecatedAccounts
{
    [PSObject] GetMDCDeprecatedAccounts([string] $SubcriptionId)
    {
        $response = @()
        $invalidObjectIds = @()

        $response += Get-ARGData -kqlQuery "securityresources | where type == 'microsoft.security/assessments' | where name =~ '1ff0b4c9-ed56-4de6-be9c-d7ab39645926' and subscriptionId =~ '$($SubcriptionId)'"

        if (($response | Measure-Object).Count -gt 0 )
        {
          $mdcAssessmentState = $response[0].properties.status.code

          if ((-not [string]::IsNullOrWhiteSpace($mdcAssessmentState)) -and ($mdcAssessmentState -eq 'Unhealthy') -and (-not [string]::IsNullOrWhiteSpace($response[0].properties.additionalData.subAssessmentsLink)))
          {

            $nextSubAssessmentLink = $response[0].properties.additionalData.subAssessmentsLink

            $SubAssessmentResponse = Get-ARGData -kqlQuery "securityresources | where type == 'microsoft.security/assessments/subassessments' | where id contains '$($nextSubAssessmentLink)'"

            if (($SubAssessmentResponse | Measure-Object).Count -gt 0 )
            {
              $invalidObjectIds += foreach ($obj in $SubAssessmentResponse) { ($obj.properties.resourceDetails.id -split "/")[-1]  }
            }
          }
  
        }

        return($invalidObjectIds)
         
    }
}

# ***************************************************** #
<#
Function calling with parameters.
Remove-AzTSInvalidAADAccounts -SubscriptionId '<Sub_Id>' `
                                [-ObjectIds @('<Object_Ids>')] `
                                -Force:$false  `
                                -PerformPreReqCheck: $true `
                                [-DryRun: $true] `
                                [-FilePath "<user Documents>\AzTS\Remediation\Subscriptions\<subscriptionId>\<JobDate>\InvalidAADAccounts\DeprecatedIdentitiesRoleAssignments.csv"]

Note: 
    1. Set '-DryRun' as '$true' for pre-check, if you want to validate role assignments before remediation.
    2. If you want to perform remediation only for DryRun output, use '-FilePath' parameter and set '-DryRun' as 'False'.  
#>