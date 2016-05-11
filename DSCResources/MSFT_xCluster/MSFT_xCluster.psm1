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
		$Name,

		[System.String[]]
        $StaticIPAddress,

		[System.String[]]
        $IgnoreNetwork,

		[parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$DomainAdminCredential
	)

    $ComputerInfo = Get-WmiObject Win32_ComputerSystem
    if (($ComputerInfo -eq $null) -or ($ComputerInfo.Domain -eq $null))
    {
        throw New-TerminatingError -ErrorType DomainNotFound -ErrorCategory ObjectNotFound
    }
    
    try
    {
        ($oldToken, $context, $newToken) = ImpersonateAs -cred $DomainAdminCredential
        $cluster = Get-Cluster -Name $Name -Domain $ComputerInfo.Domain
        if ($null -eq $cluster)
        {
            throw New-TerminatingError -ErrorType ClusterNotFound -FormatArgs @($Name) -ErrorCategory ObjectNotFound
        }

        $address = @((Get-ClusterGroup -Cluster $Name | Get-ClusterResource -Name "Cluster IP Address" | Get-ClusterParameter -Name "Address").Value)
    }
    finally
    {
        if ($context)
        {
            $context.Undo()
            $context.Dispose()
            CloseUserToken($newToken)
        }
    }

    @{
        Name = $Name
        StaticIPAddress = $address
    }
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
        $StaticIPAddress,

		[System.String[]]
        $IgnoreNetwork,

		[parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$DomainAdminCredential
	)

    $bCreate = $true

    Write-Verbose -Message "Checking if Cluster $Name is present ..."
    try
    {
        $ComputerInfo = Get-WmiObject Win32_ComputerSystem
        if (($ComputerInfo -eq $null) -or ($ComputerInfo.Domain -eq $null))
        {
            throw New-TerminatingError -ErrorType DomainNotFound -ErrorCategory ObjectNotFound
        }

        $cluster = Get-Cluster -Name $Name -Domain $ComputerInfo.Domain

        if ($cluster)
        {
            $bCreate = $false     
        }
    }
    catch
    {
        $bCreate = $true
    }

    try
    {
        ($oldToken, $context, $newToken) = ImpersonateAs -cred $DomainAdminCredential  

        if ($bCreate)
        {
            Write-Verbose -Message "Cluster $Name is NOT present"

            if($IgnoreNetwork)
            {
                New-Cluster -Name $Name -Node $env:COMPUTERNAME -StaticAddress $StaticIPAddress -IgnoreNetwork $IgnoreNetwork -NoStorage -Force -ErrorAction Stop
            }
            else
            {
                New-Cluster -Name $Name -Node $env:COMPUTERNAME -StaticAddress $StaticIPAddress -NoStorage -Force -ErrorAction Stop
            }

            Write-Verbose -Message "Created Cluster $Name"

            $ClusterNameOnline = $false
            while(!($ClusterNameOnline))
            {
                Start-Sleep 1
                Write-Verbose "Waiting for cluster name $Name to be online."
                $ClusterGroup = Get-WmiObject -Class MSCluster_ResourceGroup -Namespace root/mscluster -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq "Cluster Group"}
                if ($ClusterGroup -ne $Null)
                {
                    $ClusterName = Get-WmiObject -Namespace root/mscluster -Query "Associators of {$ClusterGroup} Where ResultClass=MSCluster_Resource" -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq "Cluster Name"}
                    if ($ClusterName.State -eq 2)
                    {
                        $ClusterNameOnline = $true
                    }
                }
            }
        }
        else
        {
            Write-Verbose -Message "Add node to Cluster $Name ..."

            Write-Verbose -Message "Add-ClusterNode $env:COMPUTERNAME to cluster $Name"
                           
            $list = Get-ClusterNode -Cluster $Name
            foreach ($node in $list)
            {
                if ($node.Name -eq $env:COMPUTERNAME)
                {
                    if ($node.State -eq "Down")
                    {
                        Write-Verbose -Message "node $env:COMPUTERNAME was down, need remove it from the list."

                        Remove-ClusterNode $env:COMPUTERNAME -Cluster $Name -Force
                    }
                }
            }

            Add-ClusterNode $env:COMPUTERNAME -Cluster $Name -NoStorage
            
            Write-Verbose -Message "Added node to Cluster $Name"
        
        }
    }
    finally
    {
        if ($context)
        {
            $context.Undo()
            $context.Dispose()
            CloseUserToken($newToken)
        }
    }


    if(!(Test-TargetResource @PSBoundParameters))
    {
#        throw "Set-TargetResouce failed"
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
        $StaticIPAddress,

		[System.String[]]
        $IgnoreNetwork,

		[parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]
		$DomainAdminCredential
	)

    $result = $false

    Write-Verbose -Message "Checking if cluster $Name is present ..."
    try
    {
        $ComputerInfo = Get-WmiObject Win32_ComputerSystem
        if (($ComputerInfo -eq $null) -or ($ComputerInfo.Domain -eq $null))
        {
            Write-Verbose -Message "Can't find machine's domain name"
        }
        else
        {
            try
            {
                ($oldToken, $context, $newToken) = ImpersonateAs -cred $DomainAdminCredential
         
                $cluster = Get-Cluster -Name $Name -Domain $ComputerInfo.Domain

                if ($cluster)
                {
                    Write-Verbose -Message "Cluster $Name is present"

                    Write-Verbose -Message "Checking if the node is in cluster $Name ..."
         
                    $allNodes = Get-ClusterNode -Cluster $Name

                    foreach ($node in $allNodes)
                    {
                        if ($node.Name -eq $env:COMPUTERNAME)
                        {
                            if ($node.State -eq "Up")
                            {
                                $result = $true
                            }
                            else
                            {
                                 Write-Verbose -Message "Node is in cluster $Name but is NOT up, treat as NOT in cluster."
                            }

                            break
                        }
                    }

                    if ($result)
                    {
                        Write-Verbose -Message "Node is in cluster $Name"
                    }
                    else
                    {
                        Write-Verbose -Message "Node is NOT in cluster $Name"
                    }
                }
                else
                {
                    Write-Verbose -Message "Cluster $Name is NOT present"
                }
            }
            finally
            {    
                if ($context)
                {
                    $context.Undo()
                    $context.Dispose()

                    CloseUserToken($newToken)
                }
            }
        }
    }
    catch
    {
        Write-Verbose -Message "Cluster $Name is NOT present with Error $_.Message"
    }
    $result
}


function Get-ImpersonateLib
{
    if ($script:ImpersonateLib)
    {
        return $script:ImpersonateLib
    }

    $sig = @'
[DllImport("advapi32.dll", SetLastError = true)]
public static extern bool LogonUser(string lpszUsername, string lpszDomain, string lpszPassword, int dwLogonType, int dwLogonProvider, ref IntPtr phToken);

[DllImport("kernel32.dll")]
public static extern Boolean CloseHandle(IntPtr hObject);
'@ 
   $script:ImpersonateLib = Add-Type -PassThru -Namespace 'Lib.Impersonation' -Name ImpersonationLib -MemberDefinition $sig 

   return $script:ImpersonateLib
}


function ImpersonateAs([PSCredential] $cred)
{
    [IntPtr] $userToken = [Security.Principal.WindowsIdentity]::GetCurrent().Token
    $userToken
    $ImpersonateLib = Get-ImpersonateLib

    $bLogin = $ImpersonateLib::LogonUser($cred.GetNetworkCredential().UserName, $cred.GetNetworkCredential().Domain, $cred.GetNetworkCredential().Password, 
    9, 0, [ref]$userToken)
    
    if ($bLogin)
    {
        $Identity = New-Object Security.Principal.WindowsIdentity $userToken
        $context = $Identity.Impersonate()
    }
    else
    {
        throw New-TerminatingError -ErrorType CannotLogonAsUser -FormatArgs @($cred.GetNetworkCredential().UserName)
    }
    $context, $userToken
}


function CloseUserToken([IntPtr] $token)
{
    $ImpersonateLib = Get-ImpersonateLib

    $bLogin = $ImpersonateLib::CloseHandle($token)
    if (!$bLogin)
    {
        throw New-TerminatingError -ErrorType CannotCloseToken
    }
}


Export-ModuleMember -Function *-TargetResource