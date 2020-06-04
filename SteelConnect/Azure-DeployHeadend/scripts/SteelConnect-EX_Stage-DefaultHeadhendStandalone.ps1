<#
    .DESCRIPTION
        Riverbed Community Toolkit
        Cloud Community Cookbooks for SteelConnect EX in Azure
        
        Pre-staging (prepare prerequisites for terraform and customize template terraform.tfvars)

    .Synopsis
        SteelConnect-EX_Stage-DefaultHeadhendStandalone

    .Description

    .EXAMPLE

        # prerequisites
        git clone https://github.com/riverbed/Riverbed-Community-Toolkit.git
        cd ./Riverbed-Community-Toolkit/SteelConnect/Azure-DeployHeadend/scripts
        
        ./SteelConnect-EX_Stage-DefaultHeadhendStandalone.ps1

    .EXAMPLE

        ./SteelConnect-EX_Stage-DefaultHeadhendStandalone.ps1 -resourceGroupName "your-resource-group"

#>

# Parameters
param(
    $headendLocation = "",
    $vmSize = "Standard_F8s_v2",

    $imagesResourceGroupName="Riverbed-Images",
    $resourceGroupName="SteelConnect-EX-Headend",
    $imageResourceIdSteelConnectEX = "",
    $imageResourceIdSteelConnectDirector = "",
    $imageResourceIdSteelConnectAnalytics = "",
    $sshPublicKey="",
    $passphrase="", # used when generating the ssh key, the passphrase protects the private key,
    $ServicePrincipalName = "",
    $overlayNetwork = "99.0.0.0/8",
    $vnetAddressSpace="10.100.0.0/16",
    $newbitsSubnet = 8,
    $hostnameDirector   = "Director1",
    $hostnameAnalytics  = "Analytics1"
)

# Use Azure-EX-templates standalone
cd "../../Azure-EX-Templates/he_standalone/"

# Generate an ssh keypair if ssh public key is not provided
if (!$sshPublicKey) {
    if (!$passphrase) { $passphrase = "riverbed-community" }
    $timestamp = (Get-Date -Format "yyMMddHHmmss")
    $keyFileName = "sshkey-$timestamp"
    ssh-keygen -q -f $keyFileName -t rsa -b 2048 -N $passphrase -C "riverbed-community"
    $sshPublicKey = Get-Content "$keyFileName.pub"
    Write-Output "Generated key pair: $keyFileName / $keyFileName.pub"
}

# get azure context
$azureContext = Get-AzContext
$tenantId = $azureContext.Tenant.Id
$subscriptionId = $azureContext.Subscription.Id

# Fetch the resourceId for the image of each SteelConnect apliance
$defaultNameImageSteelconnectEX = "steelconnect-ex-flexvnf"
$defaultNameImageSteelconnectDirector = "steelconnect-ex-director"
$defaultNameImageSteelconnectAnalytics = "steelconnect-ex-analytics"
if (!$imageResourceIdSteelConnectEX) {
    $imageResource = (Get-AzImage -ResourceGroupName $imagesResourceGroupName -ImageName "$defaultNameImageSteelconnectEX*")
    $imageResourceIdSteelConnectEX = $imageResource.Id
}
if (!$imageResourceIdSteelConnectDirector) {
    $imageResource = (Get-AzImage -ResourceGroupName $imagesResourceGroupName -ImageName "$defaultNameImageSteelconnectDirector*")
    $imageResourceIdSteelConnectDirector = $imageResource.Id
}
if (!$imageResourceIdSteelConnectAnalytics) {
    $imageResource = (Get-AzImage -ResourceGroupName $imagesResourceGroupName -ImageName "$defaultNameImageSteelconnectAnalytics*")
    $imageResourceIdSteelConnectAnalytics = $imageResource.Id
}

# If location is not set in parameters, then get location for the Director image
if (!$headendLocation) {
    $imageResourceDirector = Get-AzResource -ResourceId $imageResourceIdSteelConnectDirector -ErrorAction stop    
    $headendLocation = $imageResourceDirector.Location
}

# Get existing Headend resource group or create it
if (! (Get-AzResourceGroup -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -ResourceGroupName $resourceGroupName -Location $headendLocation -ErrorAction Stop
}

# Generate a service principal for terraform to interact with Azure
if (!$ServicePrincipalName) {
    $timestamp = (Get-Date -Format "yyMMddHHmmss")
    $ServicePrincipalName= "Riverbed-Community-Toolkit-SteelConnect-EX-Headend-staging-$timestamp"
}
# headend resource group
$scope = "/subscriptions/$($azureContext.Subscription.SubscriptionId)/resourceGroups/$resourceGroupName"
$sp = New-AzADServicePrincipal -DisplayName $ServicePrincipalName -Role "Contributor" -Scope $scope -
# images resource group
$scope = "/subscriptions/$($azureContext.Subscription.SubscriptionId)/resourceGroups/$imagesResourceGroupName"
New-AzRoleAssignment -RoleDefinitionName "Reader" -ApplicationId $sp.ApplicationId -Scope $scope

$clientSecret = ConvertFrom-SecureString $sp.Secret -AsPlainText
$clientId=$sp.ApplicationId

# keep copy of original
$terraformVariableTemplateFile = "$terraformVariableFile-BAK-$(Get-Date -Format yyMMddHHmmss)"
$terraformVariableStagingFile = "terraform.tfvars"
Copy-Item "$terraformVariableStagingFile" "$terraformVariableTemplateFile"

# Substitute value in the terraform
Write-Output @"
tenant_id           = "$tenantId"
subscription_id     = "$subscriptionId"
client_id           = "$clientId"
client_secret       = "$clientSecret"
location            = "$headendLocation"
resource_group      = "$resourceGroupName"
ssh_key             = "$sshPublicKey"
image_controller    = "$imageResourceIdSteelConnectEX"
image_director      = "$imageResourceIdSteelConnectDirector"
image_analytics     = "$imageResourceIdSteelConnectAnalytics"
vpc_address_space   = "$vnetAddressSpace"
newbits_subnet      = "$newbitsSubnet"
overlay_network     = "$overlayNetwork"
hostname_director   = "$hostnameDirector"
hostname_analytics  = "$hostnameAnalytics"
director_vm_size    = "$vmSize"
controller_vm_size  = "$vmSize"
analytics_vm_size   = "$vmSize"
"@ | Out-File $terraformVariableStagingFile
Get-Content $terraformVariableStagingFile

