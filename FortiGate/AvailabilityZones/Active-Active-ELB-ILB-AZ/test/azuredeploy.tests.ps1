#Requires -Modules Pester
<#
.SYNOPSIS
    Tests a specific ARM template
.EXAMPLE
    Invoke-Pester
.NOTES
    This file has been created as an example of using Pester to evaluate ARM templates
#>

Function random-password ($length = 15) {
    $punc = 46..46
    $digits = 48..57
    $letters = 65..90 + 97..122

    # Thanks to
    # https://blogs.technet.com/b/heyscriptingguy/archive/2012/01/07/use-pow
    $password = get-random -count $length `
        -input ($punc + $digits + $letters) |
        % -begin { $aa = $null } `
        -process {$aa += [char]$_} `
        -end {$aa}

    return $password
}

# Basic Variables
$templateName = "Active-Active-ELB-ILB-AZ"
$sourcePath = "$env:BUILD_SOURCESDIRECTORY\FortiGate\AvailabilityZones\$templateName"
$scriptPath = "$env:BUILD_SOURCESDIRECTORY\FortiGate\AvailabilityZones\$templateName\test"
$templateFileName = "azuredeploy.json"
$templateFileLocation = "$sourcePath\$templateFileName"
$templateMetadataFileName = "metadata.json"
$templateMetadataFileLocation = "$sourcePath\$templateMetadataFileName"
$templateParameterFileName = "azuredeploy.parameters.json"
$templateParameterFileLocation = "$sourcePath\$templateParameterFileName"

$testsRandom = Get-Random 10001
$testsPrefix = "FORTIQA"
$testsResourceGroupName = "FORTIQA-$testsRandom-$templateName"
$testsAdminUsername = "azureuser"
$testsResourceGroupLocation = "northeurope"

Describe 'FGT A/A' {
    Context 'Validation' {
        It 'Has a JSON template' {
            $templateFileLocation | Should -Exist
        }

        It 'Has a parameters file' {
            $templateParameterFileLocation | Should -Exist
        }

        It 'Converts from JSON and has the expected properties' {
            $expectedProperties = '$schema',
            'contentVersion',
            'parameters',
            'resources',
            'variables'
            $templateProperties = (get-content $templateFileLocation | ConvertFrom-Json -ErrorAction SilentlyContinue) | Get-Member -MemberType NoteProperty | % Name
            $templateProperties | Should -Be $expectedProperties
        }

        It 'Creates the expected Azure resources' {
            $expectedResources = 'Microsoft.Resources/deployments',
                                 'Microsoft.Compute/availabilitySets',
                                 'Microsoft.Network/virtualNetworks',
                                 'Microsoft.Network/loadBalancers',
                                 'Microsoft.Network/routeTables',
                                 'Microsoft.Network/networkSecurityGroups',
                                 'Microsoft.Network/publicIPAddresses',
                                 'Microsoft.Network/loadBalancers',
                                 'Microsoft.Network/networkInterfaces',
                                 'Microsoft.Network/networkInterfaces',
                                 'Microsoft.Network/networkInterfaces',
                                 'Microsoft.Network/networkInterfaces',
                                 'Microsoft.Compute/virtualMachines',
                                 'Microsoft.Compute/virtualMachines'
            $templateResources = (get-content $templateFileLocation | ConvertFrom-Json -ErrorAction SilentlyContinue).Resources.type
            $templateResources | Should -Be $expectedResources
        }

        It 'Contains the expected parameters' {
            $expectedTemplateParameters =   'adminUsername',
                                            'adminPassword',
                                            'fortiGateNamePrefix',
                                            'fortiGateImageSKU',
                                            'fortiGateImageVersion',
                                            'fortiGateAdditionalCustomData',
                                            'instanceType',
                                            'availabilityOptions',
                                            'acceleratedNetworking',
                                            'publicIP1NewOrExisting',
                                            'publicIP1Name',
                                            'publicIP1ResourceGroup',
                                            'vnetNewOrExisting',
                                            'vnetName',
                                            'vnetResourceGroup',
                                            'vnetAddressPrefix',
                                            'subnet1Name',
                                            'subnet1Prefix',
                                            'subnet1StartAddress',
                                            'subnet2Name',
                                            'subnet2Prefix',
                                            'subnet2StartAddress',
                                            'subnet3Name',
                                            'subnet3Prefix',
                                            'subnet4Name',
                                            'subnet4Prefix',
                                            'fortiManager',
                                            'fortiManagerIP',
                                            'fortiManagerSerial',
                                            'fortiGateLicenseBYOLA',
                                            'fortiGateLicenseBYOLB',
                                            'fortiGateLicenseFlexVMA',
                                            'fortiGateLicenseFlexVMB',
                                            'location',
                                            'fortinetTags'
            $templateParameters = (get-content $templateFileLocation | ConvertFrom-Json -ErrorAction SilentlyContinue).Parameters | Get-Member -MemberType NoteProperty | % Name | sort
            $templateParameters | Should -Be $expectedTemplateParameters
        }

    }

    Context 'Deployment' {

        # Set working directory & create resource group
        Set-Location $sourcePath
        New-AzResourceGroup -Name $testsResourceGroupName -Location "$testsResourceGroupLocation"

        # Validate all ARM templates one by one
        $testsErrorFound = $false

        $params = @{ 'adminUsername'=$testsAdminUsername
                     'adminPassword'=$testsResourceGroupName
                     'FortiGateNamePrefix'=$testsPrefix
                    }
        $publicIPName = "FGTLBPublicIP"
        $publicIP2Name = "FGTLBPublicIP2"

        It "Test deployment" {
            (Test-AzResourceGroupDeployment -ResourceGroupName "$testsResourceGroupName" -TemplateFile "$templateFileName" -TemplateParameterObject $params).Count | Should -Not -BeGreaterThan 0
        }
        It "Deployment" {
            $resultDeployment = New-AzResourceGroupDeployment -ResourceGroupName "$testsResourceGroupName" -TemplateFile "$templateFileName" -TemplateParameterObject $params
            Write-Host ($resultDeployment | Format-Table | Out-String)
            Write-Host ("Deployment state: " + $resultDeployment.ProvisioningState | Out-String)
            $resultDeployment.ProvisioningState | Should -Be "Succeeded"
        }
        It "Search deployment" {
            $result = Get-AzVM | Where-Object { $_.Name -like "$testsPrefix*" }
            Write-Host ($result | Format-Table | Out-String)
            $result | Should -Not -Be $null
        }

        40030, 50030, 40031, 50031 | Foreach-Object {
            it "Port [$_] is listening" {
                $result = Get-AzPublicIpAddress -Name $publicIPName -ResourceGroupName $testsResourceGroupName
                $portListening = (Test-Connection -TargetName $result.IpAddress -TCPPort $_ -TimeoutSeconds 100)
                $portListening | Should -Be $true
            }
        }

        It "Cleanup" {
            Remove-AzResourceGroup -Name $testsResourceGroupName -Force
        }
    }
}
