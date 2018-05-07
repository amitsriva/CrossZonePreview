###################################Setup########################################
$input = Read-Host "Do want to log in again ? [y/n]"
if ($input -eq "y")
{
    Connect-AzureRmAccount
}

$location = "eastus2"
$version = "200"

##################################Constants#####################################

$rgname = "RG_A_$version"
$appgwName = "AGW_A_$version"
$vaultName = "KVA$version"
$userAssignedIdentityName = "UI_A_$version"
$certificateName = "KVCA$version"
$nsgName = "NSG_A_$version"
$vnetName = "VN_A_$version"
$gwSubnetName = "SN_A_$version"
$gipconfigname = "GC_A_$version"
$publicIpName = "PIP_A_$version"
$fipconfig01Name = "FC_A_$version"
$poolName = "BP_A_$version"
$frontendPort01Name = "FP1_A_$version"
$frontendPort02Name = "FP2_A_$version"
$poolSetting01Name = "BS_A_$version"
$listener01Name = "HL1_A_$version"
$listener02Name = "HL2_A_$version"
$rule01Name = "RR1_A_$version"
$rule02Name = "RR2_A_$version"
$AddressPrefix = "111.111.222.0"

##################################Dependency Resources#####################################

$input = Read-Host "Do want to deploy the dependency resources for Application Gateway again (n if you want to just update application gateway) ? [y/n]"

if ($input -eq "y") {

    Write-Host "Creating ResourceGroup..."
    $resourceGroup = New-AzureRmResourceGroup -Name $rgname -Location $location -Force

    Write-Host "Creating Identity..."
    $userAssignedIdentity = New-AzureRmResource -ResourceGroupName $rgname -Location $location -ResourceName $userAssignedIdentityName -ResourceType Microsoft.ManagedIdentity/userAssignedIdentities -Force

    Write-Host "Creating KV..."
    $keyVault = New-AzureRmKeyVault -VaultName $vaultName -ResourceGroupName $rgname -Location $location -EnableSoftDelete
    $keyVault = Get-AzureRmKeyVault -VaultName $vaultName -ResourceGroupName $rgname

    Write-Host "Adding cer to KV..."
    # https://blogs.technet.microsoft.com/kv/2016/09/26/get-started-with-azure-key-vault-certificates/
    $securepfxpwd = ConvertTo-SecureString -String "abc" -AsPlainText -Force
    $cert = Import-AzureKeyVaultCertificate -VaultName $vaultName -Name $certificateName -FilePath '\\ae-share\scratch\aksgupta\AppGWv2PS\rsa4096.pfx' -Password $securepfxpwd

    # Give read access to secrets for identity on KeyVault
    Set-AzureRmKeyVaultAccessPolicy -VaultName $vaultName -ResourceGroupName $rgname -PermissionsToSecrets get -ObjectId $userAssignedIdentity.Properties.principalId

    Write-Host "Creating NSG..."
    $srule01 = New-AzureRmNetworkSecurityRuleConfig -Name "listeners" -Direction Inbound -SourceAddressPrefix * -SourcePortRange * -Protocol * `
    -DestinationAddressPrefix * -DestinationPortRange 22,80,443 `
    -Access Allow -Priority 100
    $srule02 = New-AzureRmNetworkSecurityRuleConfig -Name "managementPorts" -Direction Inbound -SourceAddressPrefix * -SourcePortRange * -Protocol * `
    -DestinationAddressPrefix * -DestinationPortRange "65200-65535" `
    -Access Allow -Priority 101
    $nsg = New-AzureRmNetworkSecurityGroup -Name $nsgName -ResourceGroupName $rgname -Location $location -SecurityRules $srule01,$srule02 -Force

    Write-Host "Creating Vnet..."
    $gwSubnet = New-AzureRmVirtualNetworkSubnetConfig -Name $gwSubnetName -AddressPrefix "$AddressPrefix/24" -NetworkSecurityGroup $nsg
    $vnet = New-AzureRmvirtualNetwork -Name $vnetName -ResourceGroupName $rgname -Location $location -AddressPrefix "$AddressPrefix/24" -Subnet $gwSubnet -Force

    Write-Host "Creating PublicIP..."
    $publicip = New-AzureRmPublicIpAddress -ResourceGroupName $rgname -name $publicIpName -location $location -AllocationMethod Static -Sku Standard -Force

}

Write-Host "Getting dependency resources..."
$resourceGroup = Get-AzureRmResourceGroup -Name $rgname
$userAssignedIdentity = Get-AzureRmResource -ResourceGroupName $rgname -ResourceName $userAssignedIdentityName -ResourceType Microsoft.ManagedIdentity/userAssignedIdentities
$publicip = Get-AzureRmPublicIpAddress -ResourceGroupName $rgname -name $publicIpName
$vnet = Get-AzureRmvirtualNetwork -Name $vnetName -ResourceGroupName $rgname
$gwSubnet = Get-AzureRmVirtualNetworkSubnetConfig -Name $gwSubnetName -VirtualNetwork $vnet
$secret = Get-AzureKeyVaultsecret -Name $certificateName -VaultName $vaultName # https://blogs.technet.microsoft.com/kv/2016/09/26/get-started-with-azure-key-vault-certificates/

##################################Application Gateway#####################################

Write-Host "Creating GatewayConfig..."
$gipconfig = New-AzureRmApplicationGatewayIPConfiguration -Name $gipconfigname -Subnet $gwSubnet

Write-Host "Creating FrontendIpConfig..."
$fipconfig01 = New-AzureRmApplicationGatewayFrontendIPConfig -Name $fipconfig01Name -PublicIPAddress $publicip

Write-Host "Creating Pool..."
$pool = New-AzureRmApplicationGatewayBackendAddressPool -Name $poolName -BackendIPAddresses testbackend1.westus.cloudapp.azure.com, testbackend2.westus.cloudapp.azure.com

Write-Host "Creating FrontendPort.."
$fp01 = New-AzureRmApplicationGatewayFrontendPort -Name $frontendPort01Name -Port 443
$fp02 = New-AzureRmApplicationGatewayFrontendPort -Name $frontendPort02Name -Port 80

Write-Host "Creating sslCertificates.."
$sslCert01 = New-AzureRmApplicationGatewaySslCertificate -Name "SSLCert" -KeyVaultSecretId $secret.Id

Write-Host "Creating HttpListener..."
$listener01 = New-AzureRmApplicationGatewayHttpListener -Name $listener01Name -Protocol Https -FrontendIPConfiguration $fipconfig01 -FrontendPort $fp01 -SslCertificate $sslCert01
$listener02 = New-AzureRmApplicationGatewayHttpListener -Name $listener02Name -Protocol Http -FrontendIPConfiguration $fipconfig01 -FrontendPort $fp02

Write-Host "Creating BackendHttpSettings..."
$poolSetting01 = New-AzureRmApplicationGatewayBackendHttpSettings -Name $poolSetting01Name -Port 80 -Protocol Http -CookieBasedAffinity Disabled

Write-Host "Creating RequestRoutingRule..."
$rule01 = New-AzureRmApplicationGatewayRequestRoutingRule -Name $rule01Name -RuleType basic -BackendHttpSettings $poolSetting01 -HttpListener $listener01 -BackendAddressPool $pool
$rule02 = New-AzureRmApplicationGatewayRequestRoutingRule -Name $rule02Name -RuleType basic -BackendHttpSettings $poolSetting01 -HttpListener $listener02 -BackendAddressPool $pool

Write-Host "Creating SKU..."
$sku = New-AzureRmApplicationGatewaySku -Name Standard_v2 -Tier Standard_v2 -Capacity 2

$listeners = @($listener02)
$fps = @($fp01, $fp02)
$fipconfigs = @($fipconfig01)
$sslCerts = @($sslCert01)
$rules = @($rule01, $rule02)
$listeners = @($listener01, $listener02)

Write-Host "Creating ApplicationGateway..."
$appgw = New-AzureRmApplicationGateway -Name $appgwName -ResourceGroupName $rgname -Location $location -UserAssignedIdentityId $userAssignedIdentity.ResourceId -Probes $probeHttps -BackendAddressPools $pool -BackendHttpSettingsCollection $poolSetting01 -GatewayIpConfigurations $gipconfig -FrontendIpConfigurations $fipconfigs -FrontendPorts $fps -HttpListeners $listeners -RequestRoutingRules $rules -Sku $sku -SslPolicy $sslPolicy -sslCertificates $sslCerts -Force

Write-Host "Operation Complete."
$appgw
$pip = Get-AzureRmPublicIpAddress -Name $publicIpName -ResourceGroupName $rgname
Write-Host "PublicIp: $($pip.IpAddress)"