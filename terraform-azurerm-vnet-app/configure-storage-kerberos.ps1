# This script must be run on a domain joined Azure VM

param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $true)]
    [String]$AppId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory = $true)]
    [string]$Domain
)

#region constants
$defaultPermission = "StorageFileDataSmbShareContributor"
$logpath = $PSCommandPath + '.log'
#endregion 

#region functions
function Write-Log {
    param( [string] $msg)
    "$(Get-Date -Format FileDateTimeUniversal) : $msg" | Out-File -FilePath $logpath -Append -Force
}

function Exit-WithError {
    param( [string]$msg )
    Write-Log "There was an exception during the process, please review..."
    Write-Log $msg
    Exit 2
}
#endregion

#region main
Write-Log "Running '$PSCommandPath'..."

Write-Log "Setting execution policy to 'RemoteSigned'..."
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# Retrieve secrets from key vault using managed identity
Write-Log "Logging into Azure using managed identity..."

try {
    Connect-AzAccount -Identity 
}
catch {
    Exit-WithError $_
}

Write-Log "Getting secret '$AppId' from key vault '$KeyVaultName'..."

try {
    $appSecret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $AppId -AsPlainText
}
catch {
    Exit-WithError $_
}

if ([string]::IsNullOrEmpty($appSecret)) {
    Exit-WithError "Secret '$AppId' not found in key vault '$KeyVaultName'..."
}

Write-Log "The length of secret '$AppId' is '$($appSecret.Length)'..."

Write-Log "Getting secret '$StorageAccountName-kerb1' from key vault '$KeyVaultName'..."

try {
    $storageAccountKerbKey = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "$StorageAccountName-kerb1" -AsPlainText
}
catch {
    Exit-WithError $_
}

if ([string]::IsNullOrEmpty($storageAccountKerbKey)) {
    Exit-WithError "Secret '$StorageAccountName-kerb1' not found in key vault '$KeyVaultName'..."
}

Write-Log "The length of secret '$StorageAccountName-kerb1' is '$($storageAccountKerbKey.Length)'..."

Disconnect-AzAccount

# Configure Identity-based access for storage account
$xDot500Path = "DC=$($Domain.Split('.')[0]),DC=$($Domain.Split('.')[1])"
$spnValue = "cifs/$StorageAccountName.file.core.windows.net"

Write-Log "Checking for existing computer account for storage account '$StorageAccountName' in domain '$Domain'..."

$computer = Get-ADComputer -Identity $StorageAccountName

if ($null -eq $computer) {
    Write-Log "Existing computer account for storage account '$StorageAccountName' in domain '$Domain' not found..."
}
else {
    Write-Log "Deleting existing computer account for storage account '$StorageAccountName' in domain '$Domain'..."

    try {
        Remove-ADComputer -Identity $StorageAccountName -Confirm:$false -ErrorAction Stop
    }
    catch {
        Exit-WithError $_
    }
}

Write-Log "Adding computer account for storage account '$StorageAccountName' to domain '$Domain'..."
$storageAccountKerbKeySecure = ConvertTo-SecureString $storageAccountKerbKey -AsPlainText -Force

try {
    New-ADComputer `
        -SAMAccountName $StorageAccountName `
        -Path $xDot500Path `
        -Name $StorageAccountName `
        -AccountPassword $storageAccountKerbKeySecure `
        -AllowReversiblePasswordEncryption $false `
        -Description "Computer account object for Azure storage account '$StorageAccountName'." `
        -ServicePrincipalNames $spnValue `
        -Server $Domain `
        -Enabled $true `
        -ErrorAction Stop
}
catch {
    Exit-WithError $_
}

Write-Log "Retrieving new computer account for storage account '$StorageAccountName'..."

try {
    $computer = Get-ADComputer -Identity $StorageAccountName
}
catch {
    Exit-WithError $_
}

$azureStorageSid = $computer.SID.Value
$domainInformation = Get-ADDomain -Server $Domain
$domainGuid = $domainInformation.ObjectGUID.ToString()
$domainName = $domainInformation.DNSRoot
$domainSid = $domainInformation.DomainSID.Value
$forestName = $domainInformation.Forest
$netBiosDomainName = $domainInformation.DnsRoot

Write-Log "Logging into Azure using service principal id '$AppId'..."

$appSecretSecure = ConvertTo-SecureString $appSecret -AsPlainText -Force
$spCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AppId, $appSecretSecure

try {
    Connect-AzAccount -Credential $spCredential -Tenant $TenantId -ServicePrincipal -ErrorAction Stop | Out-Null
}
catch {
    Exit-WithError $_
}

Write-Log "Setting default subscription to '$SubscriptionId'..."

try {
    Set-AzContext -Subscription $SubscriptionId | Out-Null
}
catch {
    Exit-WithError $_
}

Write-Log "Configuring storage account '$StorageAccountName' for Kerberos authentication with domain '$Domain'..."

try {
    Set-AzStorageAccount `
        -ResourceGroupName $ResourceGroupName `
        -AccountName $StorageAccountName `
        -EnableActiveDirectoryDomainServicesForFile $true `
        -ActiveDirectoryDomainName $domainName `
        -ActiveDirectoryNetBiosDomainName $netBiosDomainName `
        -ActiveDirectoryForestName $forestName `
        -ActiveDirectoryDomainGuid $domainGuid `
        -ActiveDirectoryDomainSid $domainSid `
        -ActiveDirectoryAzureStorageSid $azureStorageSid `
        -DefaultSharePermission $defaultPermission `
        -ErrorAction Stop
}
catch {
    Exit-WithError $_
}

Disconnect-AzAccount

Write-Log "'$PSCommandPath' exiting normally..."
Exit 0
#endregion
