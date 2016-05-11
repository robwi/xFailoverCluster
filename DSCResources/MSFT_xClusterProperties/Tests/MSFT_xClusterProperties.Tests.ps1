<###################################################
 #                                                 #
 #  Copyright (c) Microsoft. All rights reserved.  #
 #                                                 #
 ##################################################>

 <#
.SYNOPSIS
    Pester Tests for MSFT_xClusterProperties

.DESCRIPTION
    See Pester Wiki at https://github.com/pester/Pester/wiki
    Download Module from https://github.com/pester/Pester to run tests
#>

Get-Module -Name FailoverClusters | Remove-Module
New-Module -Name FailoverClusters -ScriptBlock `
{
    # Create Schema of needed functions/parameters so they can be Mocked in the tests
    function Get-Cluster
    {
        [CmdletBinding()]
        param
        (
            $Name,
            $ErrorActionPreference
        )
    }

    Export-ModuleMember -Function *
} | Import-Module -Force

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$testModule = "$here\..\MSFT_xClusterProperties.psm1"

If (Test-Path $testModule)
{
    Import-Module $testModule -Force
}
Else
{
    Throw "Unable to find '$testModule'"
}

InModuleScope MSFT_xClusterProperties {

    $mockClusterName = "MockCluster"
    $mockClusterSize = 300
    $mockDatabaseReadWrite = 0
    $mockShutdownTimeout = 200

    Describe "MSFT_xClusterProperties Tests" {
       
      Mock -ModuleName MSFT_xClusterProperties -CommandName Get-Cluster { 
        
            $mock = New-Object PSObject -Property @{
                ClusterLogSize = $mockClusterSize
                ShutdownTimeoutInMinutes = $mockShutdownTimeout
                DatabaseReadWriteMode = $mockDatabaseReadWrite } 

            Write-Verbose "Mock Get-Cluster $mock."

            $mock
      }

      Context "Mock Context" {

            It "Get-TargetResource" {
                $result = Get-TargetResource -ClusterName $mockClusterName -Verbose

                $result.ClusterName | Should be $mockClusterName
                $result.ClusterLogSizeInMB | Should be $mockClusterSize
                $result.ShutdownTimeoutInMinutes | Should be $mockShutdownTimeout
                $result.DatabaseReadWriteMode | Should be $mockDatabaseReadWrite
            }

            It "Test-TargetResource" {

                $result = Test-TargetResource -ClusterName $mockClusterName `
                            -ClusterLogSizeInMB $mockClusterSize `
                            -ShutdownTimeoutInMinutes $mockShutdownTimeout `
                            -DatabaseReadWriteMode $mockDatabaseReadWrite `
                            -Verbose

                $result | Should be $true
            }

            It "Test-TargetResource tests failed" {
            
                $result = Test-TargetResource -ClusterName $mockClusterName `
                    -ClusterLogSizeInMB 999 `
                    -ShutdownTimeoutInMinutes 999 `
                    -DatabaseReadWriteMode 999 `
                    -Verbose

                $result | Should Be $false
            }
        }

        Context "Mock Context" {

            Mock -ModuleName MSFT_xClusterProperties -CommandName Get-Cluster { 
               
                Write-Verbose "Get Cluster Mock Count: $Global:Count"
                                    
                if($Global:Count -eq 0)
                {
                    $mock = New-Object PSObject -Property @{
                        ClusterLogSize = 999
                        ShutdownTimeoutInMinutes = 999
                        DatabaseReadWriteMode = 3  } 
                }
                else
                {
                    $mock = New-Object PSObject -Property @{
                        ClusterLogSize = $mockClusterSize
                        ShutdownTimeoutInMinutes = $mockShutdownTimeout
                        DatabaseReadWriteMode = $mockDatabaseReadWrite } 
                }

                $Global:Count++  

                Write-Verbose "Mock Get-Cluster $mock."

                $mock
            }

            BeforeEach {

                $Global:Count = 0
            }

            AfterEach {

                $Global:Count = 0
            }
            
            It "Set-TargetResource" {

                Set-TargetResource -ClusterName $mockClusterName `
                    -ClusterLogSizeInMB $mockClusterSize `
                    -ShutdownTimeoutInMinutes $mockShutdownTimeout `
                    -DatabaseReadWriteMode $mockDatabaseReadWrite `
                    -Verbose
            }

            It "Set-TargetResource No Properties" {

                Set-TargetResource -ClusterName $mockClusterName -Verbose
            }

            It "Set-TargetResource ClusterLogSizeInMB Property" {

                Set-TargetResource -ClusterName $mockClusterName -ClusterLogSizeInMB $mockClusterSize -Verbose
            }

            It "Set-TargetResource ShutdownTimeoutInMinutes Property" {

                Set-TargetResource -ClusterName $mockClusterName -ShutdownTimeoutInMinutes $mockShutdownTimeout -Verbose
            }

            It "Set-TargetResource DatabaseReadWriteMode Property" {

                Set-TargetResource -ClusterName $mockClusterName -DatabaseReadWriteMode $mockDatabaseReadWrite -Verbose
            }
        }
    }
}

Get-Module -Name MSFT_xClusterProperties | Remove-Module