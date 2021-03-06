$currentPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Debug -Message "CurrentPath: $currentPath"

# Load Common Code
Import-Module $currentPath\..\..\xFailoverClusterHelper.psm1 -Verbose:$false -ErrorAction Stop


function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name
	)

    # Nothing useful to be returned by Get-TargetResource for this resource

	$returnValue = @{
		Name = $Name
	}

	$returnValue
}


function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name,

		[System.String[]]
		$Nodes,

		[ValidateSet("Ignore","Include")]
		[System.String]
		$Mode = "Ignore",

		[System.String[]]
		$Tests,

		[ValidateSet("Info","Warn")]
		[System.String]
        $Level = "Warn"
	)

    Assert-Module -ModuleName FailoverClusters

    $TestClusterParameters = `
    @{
        Cluster = $Name
    }
    if($PSBoundParameters.ContainsKey('Nodes'))
    {
        # Get valid nodes
        $ClusterNodes = (Get-ClusterNode -Cluster $Name).Name
        # Build list of valid nodes
        $ActualNodes = @()
        foreach($Node in $Nodes)
        {
            if($Node.Split('.')[0] -in $ClusterNodes)
            {
                $ActualNodes += $Node.Split('.')[0]
            }
            else
            {
                Write-Verbose "$Test is not a valid cluster node"
            }
        }
        # Add valid nodes to parameters
        if($ActualNodes)
        {
            $TestClusterParameters += `
            @{
                Node = $ActualNodes
            }
        }
    }
    if($PSBoundParameters.ContainsKey('Tests'))
    {
        # Get valid tests
        $AllClusterTests = Test-Cluster -List
        $ValidClusterTests = $AllClusterTests.Category + $AllClusterTests.DisplayName
        # Build list of valid tests
        $ActualTests = @()
        foreach($Test in $Tests)
        {
            if($Test -in $ValidClusterTests)
            {
                $ActualTests += $Test
            }
            else
            {
                Write-Verbose "$Test is not a valid cluster test"
            }
        }
        # Add valid tests to parameters
        if($ActualTests)
        {
            $TestClusterParameters += `
            @{
                $Mode = $ActualTests
            }
        }
    }
    
    # Get the current XML files so we can tell which is ours when validation is complete
    $XMLFiles = Get-ChildItem -Path $env:Temp -Filter "Validation Report*.xml"
    
    # Test the cluster
    Test-Cluster @TestClusterParameters -Verbose

    # Get the new XML file
    if($XMLReportFile = Get-ChildItem -Path $env:Temp -Filter "Validation Report*.xml" | Where-Object {$_.Name -notin $XMLFiles.Name})
    {
        Write-Verbose "Cluster validation XML is $XMLReportFile"
        try
        {
            $XMLReport = [XML](Get-Content -Path $XMLReportFile.FullName)
        }
        catch
        {
            Write-Verbose "Failed to load cluster validation XML"
        }
        if($XMLReport)
        {
            # filter for messages 
            if($Level -eq "Info")
            {
                $XMLMessages = $XMLReport.SelectNodes("//Message[@Level='Warn' or @Level='Fail']")
            }
            else
            {
                $XMLMessages = $XMLReport.SelectNodes("//Message[@Level='Fail']")
            }
            # if there are no messages, validation was successful
            if($XMLMessages.Count -eq 0)
            {
                Write-Verbose "Cluster validation passed"
                if(!(Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Cloud Solutions"))
                {
                    $null = New-Item -Path "HKLM:\SOFTWARE\Microsoft" -Name "Cloud Solutions"
                }
                if(!(Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Cloud Solutions\Deployment"))
                {
                    $null = New-Item -Path "HKLM:\SOFTWARE\Microsoft\Cloud Solutions" -Name "Deployment"
                }
                if(!(Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Cloud Solutions\Deployment\ClusterValidation"))
                {
                    $null = New-Item -Path "HKLM:\SOFTWARE\Microsoft\Cloud Solutions\Deployment" -Name "ClusterValidation"
                }
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cloud Solutions\Deployment\ClusterValidation" -Name $Name -Value 1
            }
            else
            {
                Write-Verbose "Cluster validation failed - failure messages are:"
                foreach($XMLMessage in $XMLMessages)
                {
                    Write-Verbose "  $($XMLMessage.'#cdata-section')"
                }
            }
        }
    }

    if(!(Test-TargetResource @PSBoundParameters))
    {
        throw New-TerminatingError -ErrorType TestFailedAfterSet -ErrorCategory InvalidResult
    }    
}


function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name,

		[System.String[]]
		$Nodes,

		[ValidateSet("Ignore","Include")]
		[System.String]
		$Mode = "Ignore",

		[System.String[]]
		$Tests,

		[ValidateSet("Info","Warn")]
		[System.String]
        $Level = "Warn"
	)

    # Set-TargetResource will set the registry to indicate a successful validation

    if((Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cloud Solutions\Deployment\ClusterValidation" -Name $Name -ErrorAction SilentlyContinue).$Name -eq 1)
    {
        $result = $true
    }
    else
    {
        $result = $false
    }

	$result
}


Export-ModuleMember -Function *-TargetResource