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

    $Group = Get-ClusterGroup -Name $Name -ErrorAction SilentlyContinue
    if($Group)
    {
        $OwnerNodes = (Get-ClusterOwnerNode -Group $Name).OwnerNodes.Name
        switch($Group.AutoFailbackType)
        {
            0
            {
                $AutoFailbackType = "Prevent"
            }
            1
            {
                $AutoFailbackType = "Allow"
            }
        }
        switch($Group.PersistentState)
        {
            0
            {
                $PersistentState = "False"
            }
            1
            {
                $PersistentState = "True"
            }
        }
        switch($Group.Priority)
        {
            0
            {
                $Priority = "No Auto Start"
            }
            1000
            {
                $Priority = "Low"
            }
            2000
            {
                $Priority = "Medium"
            }
            3000
            {
                $Priority = "High"
            }
        }
    }

	$returnValue = @{
		Name = $Name
		AntiAffinityClassNames = $Group.AntiAffinityClassNames
		AutoFailbackType = $AutoFailbackType
		FailbackWindowEnd = $Group.FailbackWindowEnd
		FailbackWindowStart = $Group.FailbackWindowStart
		FailoverPeriod = $Group.FailoverPeriod
		FailoverThreshold = $Group.FailoverThreshold
		OwnerNodes = $OwnerNodes
		PersistentState = $PersistentState
		Priority = $Priority
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

		[AllowEmptyString()]
		[System.String[]]
		$AntiAffinityClassNames,

		[ValidateSet("Prevent","Allow")]
		[System.String]
		$AutoFailbackType,

		[System.UInt32]
		$FailbackWindowEnd,

		[System.UInt32]
		$FailbackWindowStart,

		[System.UInt32]
		$FailoverPeriod,

		[System.UInt32]
		$FailoverThreshold,

		[AllowEmptyString()]
		[System.String[]]
		$OwnerNodes,

		[ValidateSet("True","False")]
		[System.String]
		$PersistentState,

		[ValidateSet("High","Medium","Low","No Auto Start")]
		[System.String]
		$Priority
	)

    $Group = Get-ClusterGroup -Name $Name -ErrorAction SilentlyContinue
    if($Group)
    {
        if($PSBoundParameters.ContainsKey("AntiAffinityClassNames"))
        {
            $SetAntiAffinityClassNames = New-Object System.Collections.Specialized.StringCollection
            foreach($AntiAffinityClassName in $AntiAffinityClassNames)
            {
                $SetAntiAffinityClassNames.Add($AntiAffinityClassName)
            }
            $Group.AntiAffinityClassNames = $SetAntiAffinityClassNames
        }

        if($PSBoundParameters.ContainsKey("AutoFailbackType"))
        {
            switch($AutoFailbackType)
            {
                "Prevent"
                {
                    $Group.AutoFailbackType = 0
                }
                "Allow"
                {
                    $Group.AutoFailbackType = 1
                }
            }
        }

        if($PSBoundParameters.ContainsKey("FailbackWindowEnd"))
        {
            $Group.FailbackWindowEnd = $FailbackWindowEnd
        }

        if($PSBoundParameters.ContainsKey("FailbackWindowStart"))
        {
            $Group.FailbackWindowStart = $FailbackWindowStart
        }

        if($PSBoundParameters.ContainsKey("FailoverPeriod"))
        {
            $Group.FailoverPeriod = $FailoverPeriod
        }

        if($PSBoundParameters.ContainsKey("FailoverThreshold"))
        {
            if($FailoverThreshold -eq 1)
            {
                $FailoverThreshold = [UInt32]::MaxValue
            }
            $Group.FailoverThreshold = $FailoverThreshold
        }

        if($PSBoundParameters.ContainsKey("OwnerNodes"))
        {
            Set-ClusterOwnerNode -Group $Name -Owners $OwnerNodes
        }
	
        if($PSBoundParameters.ContainsKey("PersistentState"))
        {
            switch($PersistentState)
            {
                "False"
                {
                    $Group.PersistentState = 0
                }
                "True"
                {
                    $Group.PersistentState = 1
                }
            }
        }

        if($PSBoundParameters.ContainsKey("Priority"))
        {
            switch($Priority)
            {
                "No Auto Start"
                {
                    $Group.Priority = 0
                }
                "Low"
                {
                    $Group.Priority = 1000
                }
                "Medium"
                {
                    $Group.Priority = 2000
                }
                "High"
                {
                    $Group.Priority = 3000
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

		[AllowEmptyString()]
		[System.String[]]
		$AntiAffinityClassNames,

		[ValidateSet("Prevent","Allow")]
		[System.String]
		$AutoFailbackType,

		[System.UInt32]
		$FailbackWindowEnd,

		[System.UInt32]
		$FailbackWindowStart,

		[System.UInt32]
		$FailoverPeriod,

		[System.UInt32]
		$FailoverThreshold,

		[AllowEmptyString()]
		[System.String[]]
		$OwnerNodes,

		[ValidateSet("True","False")]
		[System.String]
		$PersistentState,

		[ValidateSet("High","Medium","Low","No Auto Start")]
		[System.String]
		$Priority
	)

    $result = $true

	$Group = Get-TargetResource -Name $Name

    if($PSBoundParameters.ContainsKey("AntiAffinityClassNames"))
    {
        if(!(
            (([String]::IsNullOrEmpty($AntiAffinityClassNames) -and [String]::IsNullOrEmpty($Group.AntiAffinityClassNames)) -or
            (Compare-Object -ReferenceObject $AntiAffinityClassNames -DifferenceObject $Group.AntiAffinityClassNames) -eq $null)
        ))
        {
            $result = $false
        }
    }

    if($PSBoundParameters.ContainsKey("AutoFailbackType") -and ($AutoFailbackType -ne $Group.AutoFailbackType))
    {
        $result = $false
    }

    if($PSBoundParameters.ContainsKey("FailbackWindowEnd") -and ($FailbackWindowEnd -ne $Group.FailbackWindowEnd))
    {
        $result = $false
    }

    if($PSBoundParameters.ContainsKey("FailbackWindowStart") -and ($FailbackWindowStart -ne $Group.FailbackWindowStart))
    {
        $result = $false
    }

    if($PSBoundParameters.ContainsKey("FailoverPeriod") -and ($FailoverPeriod -ne $Group.FailoverPeriod))
    {
        $result = $false
    }

    if($PSBoundParameters.ContainsKey("FailoverThreshold"))
    {
        if($FailoverThreshold -eq 1)
        {
            $FailoverThreshold = [UInt32]::MaxValue
        }
        if($FailoverThreshold -ne $Group.FailoverThreshold)
        {
            $result = $false
        }
    }

    if($PSBoundParameters.ContainsKey("OwnerNodes"))
    {
        if(!(
            (([String]::IsNullOrEmpty($OwnerNodes) -and [String]::IsNullOrEmpty($Group.OwnerNodes)) -or
            (Compare-Object -ReferenceObject $OwnerNodes -DifferenceObject $Group.OwnerNodes -SyncWindow 0) -eq $null)
        ))
        {
            $result = $false
        }
    }
	
    if($PSBoundParameters.ContainsKey("PersistentState") -and ($PersistentState -ne $Group.PersistentState))
    {
        $result = $false
    }

    if($PSBoundParameters.ContainsKey("Priority") -and ($Priority -ne $Group.Priority))
    {
        $result = $false
    }

	$result
}


Export-ModuleMember -Function *-TargetResource