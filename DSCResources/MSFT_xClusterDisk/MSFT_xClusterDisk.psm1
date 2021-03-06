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
		$DiskFriendlyName,

		[parameter(Mandatory = $true)]
		[AllowEmptyString()]
        [System.String]
		$DiskNumbers
	)

    $Count = 0
    $DiskResources = Get-WmiObject -Class MSCluster_Resource -Namespace root/mscluster -ErrorAction SilentlyContinue | Where-Object {$_.Type -eq "Physical Disk"}
    foreach($DiskResource in $DiskResources)
    {
        $Disks = Get-WmiObject -Namespace root/mscluster -Query "Associators of {$DiskResource} Where ResultClass=MSCluster_Disk"
        foreach($Disk in $Disks)
        {
            if((Get-Disk -Number $Disk.Number).FriendlyName -eq $DiskFriendlyName)
            {
                $Count++
            }
        }
    }

	$returnValue = @{
		DiskFriendlyName = $DiskFriendlyName
		Count = $Count
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
		$DiskFriendlyName,

		[parameter(Mandatory = $true)]
		[AllowEmptyString()]
        [System.String]
		$DiskNumbers,

		[ValidateSet("MBR","GPT")]
		[System.String]
		$PartitionStyle = "MBR",

		[ValidateSet("NTFS","ReFS")]
		[System.String]
		$FileSystem = "NTFS"
	)

    Write-Verbose "Get disks with friendly name `"$DiskFriendlyName`""
    $Disks = GetDisks -DiskFriendlyName $DiskFriendlyName -DiskNumbers $DiskNumbers
    Write-Verbose "Get cluster available disks"
    $ClusterAvailableDisks = Get-ClusterAvailableDisk -Verbose:$false

    foreach($Disk in $Disks)
    {
        Write-Verbose "Disk $($Disk.Number)"
        if(!($Disk.IsClustered))
        {
            if(!($ClusterAvailableDisks | Where-Object {$_.Number -eq $Disk.Number}))
            {
                if($Disk.IsOffline)
                {
                    Write-Verbose "  Online disk $($Disk.Number)"
                    Get-Disk -Number $Disk.Number | Set-Disk -IsOffline $false
                }
                if($Disk.IsReadOnly)
                {
                    Write-Verbose "  Read/write disk $($Disk.Number)"
                    Get-Disk -Number $Disk.Number | Set-Disk -IsReadOnly $false
                }
                if($Disk.PartitionStyle -eq "RAW")
                {
                    Write-Verbose "  Initialize disk $($Disk.Number)"
                    Get-Disk -Number $Disk.Number | Initialize-Disk -PartitionStyle $PartitionStyle
                }
            }
            else
            {
                Write-Verbose "  Disk $($Disk.Number) is a cluster available disk"
            }
            if(Get-ClusterAvailableDisk -Verbose:$false | Where-Object {$_.Number -eq $Disk.Number})
            {
                if(!(Get-Partition -DiskNumber $Disk.Number -ErrorAction SilentlyContinue))
                {
                    Write-Verbose "  Partition and format disk $($Disk.Number)"
                    New-Partition -DiskNumber $Disk.Number -UseMaximumSize -AssignDriveLetter | Format-Volume -FileSystem $FileSystem -Confirm:$false
                }
                Write-Verbose "  Add disk $($Disk.Number) to cluster"
                $ClusterDiskName = (Get-ClusterAvailableDisk -Verbose:$false | Where-Object {$_.Number -eq $Disk.Number} | Add-ClusterDisk).Name
                Write-Verbose "  Wait for online $ClusterDiskName"
                while((Get-ClusterResource -Name $ClusterDiskName -Verbose:$false).State -ne "Online")
                {
                    Start-Sleep 1
                }
            }
            else
            {
                Write-Verbose "  Disk $($Disk.Number) is not a cluster available disk"
            }
        }
        else
        {
            Write-Verbose "  Disk $($Disk.Number) is a cluster disk"
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
		$DiskFriendlyName,

		[parameter(Mandatory = $true)]
        [AllowEmptyString()]
		[System.String]
		$DiskNumbers,

		[ValidateSet("MBR","GPT")]
		[System.String]
		$PartitionStyle = "MBR",

		[ValidateSet("NTFS","ReFS")]
		[System.String]
		$FileSystem = "NTFS"
	)

    $result = $true
    Write-Verbose "Get disks with friendly name `"$DiskFriendlyName`""
    $Disks = GetDisks -DiskFriendlyName $DiskFriendlyName -DiskNumbers $DiskNumbers
    Write-Verbose "Get cluster disk resources"
    $ClusterAvailableDisks = Get-ClusterAvailableDisk -Verbose:$false

    foreach($Disk in $Disks)
    {
        if($result)
        {
            Write-Verbose "Disk $($Disk.Number)"
            if (!($Disk.IsClustered))
            {
                if($result)
                {
                    if($ClusterAvailableDisks | Where-Object {$_.Number -eq $Disk.Number})
                    {
                        # There is a cluster available disk, fail test
                        Write-Verbose "  Disk $($Disk.Number) is a cluster available disk, fail test and skip remainder"
                        $result = $false
                    }
                    else
                    {
                        Write-Verbose "  Disk $($Disk.Number) is not a cluster available disk"
                    }
                }
                if($result)
                {
                    if($Disk.IsOffline -or ($Disk.PartitionStyle -eq "RAW"))
                    {
                        # There is an uninitialized disk, fail test
                        Write-Verbose "  Disk $($Disk.Number) is not initialized, fail test and skip remainder"
                        $result = $false
                    }
                    else
                    {
                        Write-Verbose "  Disk $($Disk.Number) is initialized"
                    }
                }
                if($result)
                {
                    $Partitions = Get-Partition -DiskNumber $Disk.Number -ErrorAction SilentlyContinue
                    if($Partitions.Count -ne 0)
                    {
                        # There is a disk with no partitions, fail test
                        Write-Verbose "  Disk $($Disk.Number) has no partitions, fail test and skip remainder"
                        $result = $false
                    }
                    else
                    {
                        Write-Verbose "  Disk $($Disk.Number) is partitioned"
                    }
                }
            }
            else
            {
                Write-Verbose "  Disk $($Disk.Number) is a cluster disk, skipping test"
            }
        }
    }

    $result
}


function GetDisks
{
    param
    (
		[parameter(Mandatory = $true)]
		[System.String]
		$DiskFriendlyName,

		[parameter(Mandatory = $true)]
        [AllowEmptyString()]
		[System.String]
		$DiskNumbers
    )

    $Disks = @()
    $DiskNumbersToGet = @()
    foreach($DiskNumber in $DiskNumbers.Split(","))
    {
        if ($DiskNumber.Contains("-"))
        {
            $DiskNumberRange = $DiskNumber.Split("-")
            if($DiskNumber.Trim("-").Contains("-"))
            {
                $DiskNumberRangeStart = $DiskNumberRange[0]
                $DiskNumberRangeEnd = $DiskNumberRange[1]
            }
            else
            {
                if($DiskNumber.SubString(0,1) -eq "-")
                {
                    $DiskNumberRangeStart = 1
                    $DiskNumberRangeEnd = $DiskNumberRange[1]
                }
                else
                {
                    $DiskNumberRangeStart = $DiskNumberRange[0]
                    $DiskNumberRangeEnd = ((Get-Disk).Number | Sort-Object -Descending)[0]
                }
            }
            $DiskNumbersToGet += @($DiskNumberRangeStart..$DiskNumberRangeEnd)
        }
        else
        {
            $DiskNumbersToGet += $DiskNumber
        }
    }
    if ([String]::IsNullOrEmpty($DiskNumbersToGet))
    {
        $Disks = Get-Disk -FriendlyName $DiskFriendlyName -ErrorAction SilentlyContinue
    }
    else
    {
        $DiskNumbersToGet = $DiskNumbersToGet | Sort-Object
        foreach($DiskNumber in $DiskNumbersToGet)
        {
            $Disks += Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue | Where-Object {$_.FriendlyName -eq $DiskFriendlyName}
        }
    }

    $Disks | Sort-Object {$_.Number}
}


Export-ModuleMember -Function *-TargetResource