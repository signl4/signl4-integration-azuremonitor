# This script:
# - Creates a new registered app in Azure AD (AzureAD)
# - Adds a password credential to it (AzureAD)
# - Creates a service principal for that app (Microsoft.Graph.Applications)
# - Creates a new dedicated role for that service principal which has only access to Azure Monitor assets (Az)
# - Assigns the service principal to that role (Az)

# Tested date 08/30/2022
# You'll need to auth to Azure with an Azure tenant amdin account multiple times because three different modules / tech stacks are used
# If modules below are not installed in your environment use these commands:
# Install-Module -Name Microsoft.Graph.Applications     # tested with 1.9.2
# Install-Module -Name AzureAD                          # tested with 2.0.2.16
# Install-Module -Name Az                               # tested with 7.2.0


# #################################################################################
# NOTE: After this script has completed you may need to 
# - log in to Azure Portal
# - navigate to AzureAD -> App registrations -> <createdApp> -> API permissions
# - click the button 'Grant admin consent for <your tenant name>
# #################################################################################


$appendix = ""
$SIGNL4AppNameAzure = "AzureMonitor Client for SIGNL4$appendix"
$SIGNL4AzureRoleName = "Azure Monitor access for 3rd party systems$appendix";
$SIGNL4AppIdentifierUri = "api://AzureMonitorClientforSIGNL4$appendix"

$s4config = [pscustomobject]@{
SubscriptionId = ''
TenantId = ''
ClientId = ''
ClientSecret = ''
}

# Login to Azure
Connect-AzAccount #For PS Module 'Az'
Connect-AzureAD #For PS Module 'AzureAD'
Connect-MgGraph -Scope "Directory.AccessAsUser.All" #For PS Module 'Microsoft.Graph.Applications'


# Read and display all subscriptions
$subscriptions = Get-AzSubscription
$global:index = 0
$subscriptions | Format-Table -Property @{name="Number";expression={$global:index;$global:index+=1}},SubscriptionId,Name,State,TenantId

$subIndexes = Read-Host -Prompt "Enter row number(s) of desired subscriptions (each in same tenant) to read alerts from separated by commas"
$subIndexes = $subIndexes.split(",")

$tenantId = "";
ForEach ($subIndex in $subIndexes) 
{
    if ($tenantId -eq "") {
        $tenantId = $subscriptions[$subIndex-1].TenantId        
    }
    elseif ($tenantId -ne $subscriptions[$subIndex-1].TenantId) {
        Write-Error "Please only select subscriptions within the same tenant. Provisioning stops here."
        exit
    }
}


# Sets the tenant, subscription, and environment for cmdlets to use in the current session
Set-AzContext -Tenant $tenantId
$app = Get-AzureADApplication -Filter "DisplayName eq '$SIGNL4AppNameAzure'"
$appId = $app.AppId
if ($null -eq $app) {
    # Create the App in the sub
    Write-Output "Creating a new Application '$SIGNL4AppNameAzure' for SIGNL4 in Azure AD..this will take 1 minute.."
    $app = New-AzureADApplication -DisplayName $SIGNL4AppNameAzure -IdentifierUris $SIGNL4AppIdentifierUri
    Start-Sleep -s 60 # Needed as it is otherwise not usable due to Azure APIU latency



    # Add an app password
    Write-Output "Adding a password to the SIGNL4 Application in Azure AD.."
    $spnPwd = New-Guid
    New-AzureADApplicationPasswordCredential -ObjectId $app.ObjectId -Value $spnPwd

    ### Create the SPN in the sub
    Write-Output "Creating an SPN for the SIGNL4 Application Azure AD.."
    $params = @{
        AppId = $app.appId
    }
    $spn = New-MgServicePrincipal -BodyParameter $params


    Write-Output "App and SPN created in Azure:"
    Write-Output ""
    $spn | Format-Table -Property AppId,DisplayName,Id
    Write-Output ""    


    $s4config.ClientId = $spn.AppId
    $s4config.ClientSecret = $spnPwd
    $s4config.TenantId = $subscriptions[$subIndex-1].TenantId


    # Remove contributor role from the SPN which is added by deefault :-S
    $roles = Get-AzRoleAssignment -ObjectId $s4config.ClientId
    foreach ($role in $roles) 
    {
        Write-Output "Removing following role from the SPN that was added by default: " + $role.RoleDefinitionName
        Remove-AzRoleAssignment -ObjectId $spn.Id -RoleDefinitionName $role.RoleDefinitionName -Scope $role.Scope
    }

    # Create new Role
    $role = Get-AzRoleDefinition -Name "Contributor"
    $role.Id = $null
    $role.Name = $SIGNL4AzureRoleName
    $role.Description = "Can only access Azure Monitor alerts"
    $role.Actions.RemoveRange(0,$role.Actions.Count)
    $role.Actions.Add("Microsoft.AlertsManagement/alerts/*")
    $role.Actions.Add("Microsoft.AlertsManagement/alertsSummary/*")
    $role.Actions.Add("Microsoft.Insights/activityLogAlerts/*")
    $role.Actions.Add("Microsoft.Insights/components/*")
    $role.Actions.Add("Microsoft.Insights/eventtypes/*")
    $role.Actions.Add("Microsoft.Insights/metricalerts/*")
    $role.AssignableScopes.Clear()

    ForEach ($subIndex in $subIndexes) 
    {
        $role.AssignableScopes.Add("/subscriptions/" + $subscriptions[$subIndex-1].SubscriptionId)
    }


    Write-Output "Creating new custom role '$SIGNL4AzureRoleName' in Azure, which may take some seconds..."
    New-AzRoleDefinition -Role $role


    # Sleep a little while and wait until the new role is completely populated and available in Azure. Otherwise consider adding the role assignment manually in Azure Portal. The SPN shows up for assignement..
    Start-Sleep -s 60


} else {
    Write-Output ""
    Write-Output "Found existing application '$SIGNL4AppNameAzure' (Id: $appId) for SIGNL4 in Azure AD.."
    Write-Output ""
}



ForEach ($subIndex in $subIndexes) 
{
    $subScope = "/subscriptions/" + $subscriptions[$subIndex-1].SubscriptionId
    $subName = $subscriptions[$subIndex-1].Name    
    $s4config.SubscriptionId = $subscriptions[$subIndex-1].SubscriptionId

    Write-Output ""
    Write-Output ""
    Write-Output "Provisioning application '$SIGNL4AppNameAzure' to custom role '$SIGNL4AzureRoleName' in subscription '$subName'..."
    New-AzRoleAssignment -ObjectId $spn.Id -RoleDefinitionName $SIGNL4AzureRoleName -Scope $subScope   


    Write-Output ""
    Write-Output ""
    Write-Output "*** All set for subscription '$subName', please enter these details in the SIGNL4 Azure Monitor connector app config... ***"
    $s4config | Format-List -Property SubscriptionId,TenantId,ClientId,ClientSecret
}