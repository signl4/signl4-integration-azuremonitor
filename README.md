# signl4-integration-azuremonitor
Holds information and assets required to integrate SIGNL4 with AzureMonitor

## Usage
Download the PowerShell script. It creates a new application client for SIGNL4 in your AzureInstance.
It also creates a new role in Azure that only has permission to AzureMonitor alerts.
At the end it ouputs four GUIDs that you need to enter in the SIGNL4 configuration.
The script requires you to login to your Azure Tenant, please use an administrator account here.
