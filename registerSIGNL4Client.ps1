Import-Module Az.Resources # Imports the PSADPasswordCredential object

$SIGNL4AppNameAzure = "SIGNL4AzureMonitorApp"
$SIGNL4AzureRoleName = "Azure Monitor access for SIGNL4";

$s4config = [pscustomobject]@{
SubscriptionId = ''
TenantId = ''
ClientId = ''
ClientSecret = ''
}

# Login to Azure
$login = Connect-AzAccount

# Read and display all subscriptions
$subscriptions = Get-AzSubscription
$subscriptions | Format-Table -Property SubscriptionId,Name,State,TenantId

$subIndex = Read-Host -Prompt "Please enter row number of subscription to use (starting from 1)"


# Sets the tenant, subscription, and environment for cmdlets to use in the current session
Set-AzContext -SubscriptionId $subscriptions[$subIndex-1].SubscriptionId

$s4config.SubscriptionId = $subscriptions[$subIndex-1].SubscriptionId
$s4config.TenantId = $subscriptions[$subIndex-1].TenantId


$subScope = "/subscriptions/" + $s4config.SubscriptionId


# Create the SPN in the sub
$spnPwd = New-Guid
$credentials = New-Object Microsoft.Azure.Commands.ActiveDirectory.PSADPasswordCredential -Property @{ StartDate=Get-Date; EndDate=Get-Date -Year 2020; Password=$spnPwd}
$spn = New-AzADServicePrincipal -DisplayName $SIGNL4AppNameAzure -PasswordCredential $credentials


Write-Output "SPN created in Azure:"
$spn | Format-Table -Property ApplicationId,DisplayName,Id,ServicePrincipalNames

$s4config.ClientId = $spn.ApplicationId
$s4config.ClientSecret = $spnPwd



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
$role.AssignableScopes.Add($subScope)


Write-Output "Creating new role in Azure, which may take some seconds..."
New-AzRoleDefinition -Role $role

# Sleep a little while and wait until the new role is completely populated and available in Azure. Otherwise consider adding the role assignment manually in Azure Portal. The SPN shows up for assignement..
Start-Sleep -s 30

# Assign SPN to that role
Write-Output "Role created in Azure, adding SPN to that role..."
New-AzRoleAssignment -ObjectId $spn.Id -RoleDefinitionName $SIGNL4AzureRoleName -Scope $subScope

Write-Output ""
Write-Output ""
Write-Output ""
Write-Output "*** All set, please enter these details in the SIGNL4 AzureMonitor App config... ***"
$s4config | Format-List -Property SubscriptionId,TenantId,ClientId,ClientSecret
