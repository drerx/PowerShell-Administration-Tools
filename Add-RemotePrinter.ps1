<#
.Synopsis
  A simple script for adding a printer to a remote computer.
.Description
  A PowerShell script for adding a printer to a remote computer by IP or Computername.
  Will prompt for credentials for each computer that is remoted into.
.Inputs
  Mandatory Arguments:
  -ComputerName : A list or single ComputerName(s) or IP(s). Can be piped into this script.
  -Domain : Domain name of the user account being used
  -UserName : Username for account being used to remote into the computer
  -PrinterHostAddress : IP of the printer to add
  -PrinterName : Windows display name for the printer
  -DriverName : Full name of the driver to install for the printer

  Optional Arguments:
  -PortName : Name of the printer port that will be added. If a printer port name is not specified, will use the printer IP [default].
  -Verbose : See verbose output.
.Example
  Add-RemotePrinter -ComputerName 10.10.10.123 -Domain zweilos.local -UserName zweilosec -IP 10.10.10.244 -PrinterName "Office Printer" -Driver "HP Universal Printing PCL 6"
  Remote into the computer at 10.10.10.123 as zweilos.local/zweilosec and install the printer named "Office Printer".
.Example
  Add-RemotePrinter -ComputerName (cat ./ComputerList.txt) -Domain zweilos.local -UserName zweilosec -IP 10.10.10.244 -PrinterName "Office Printer" -Driver "HP Universal Printing PCL 6"
  Add the printer "Office Printer" to all the computers specified in ComputerList.txt (one computername/IP per line!)
.Example
  Get-ADComputer -Filter * -SearchBase "OU=TestOU,DC=zweilos,DC=local" | Select -Property Name | Add-RemotePrinter -Domain zweilos.local -UserName zweilosec -IP 10.10.10.244 -PrinterName "Office Printer" -Driver "HP Universal Printing PCL 6"
  Add the printer "Office Printer" to all the computers in the specified OU (can take any list of piped-in ComputerName)  
.Notes
  Author: Beery, Christopher (https://github.com/zweilosec)
  Created: 6 Mar 2020
  Last Modified: 21 Jan 2022
  Useful links:
  https://info.sapien.com/index.php/scripting/scripting-how-tos/take-values-from-the-pipeline-in-powershell
  https://jeffbrown.tech/how-to-write-awesome-functions-with-powershell-parameter-sets/
#>

#region Parameters
[CmdletBinding()]
Param(
#ValueFromPipeline allows this parameter to take input piped into this command
[Parameter(Mandatory,
           ValueFromPipeline,
           HelpMessage="Enter one or more computer names separated by commas.",
           ParameterSetName="ComputerName")]
[Alias('Name')] #Allow for piping in from Get-ADComputer
[string[]]
$ComputerName,

[Parameter(Mandatory,
           HelpMessage="Enter a username to log into the remote computer.",
           ParameterSetName="User")]
[string]
$UserName,

[Parameter(Mandatory,
           HelpMessage="Enter a domain to log into the remote computer.",
           ParameterSetName="User")]
[Alias('Domain')]
[string]
$DomainName,

[Parameter(Mandatory,
           HelpMessage="Enter the IP of the printer to add.",
           ParameterSetName="Printer")]
[Alias('IP')]
[string]
$PrinterHostAddress,

[Parameter(Mandatory,
           HelpMessage="Enter the full name of the printer driver.",
           ParameterSetName="Printer")]
[Alias('Driver')]
[string]
$DriverName,

[Parameter(Mandatory,
           HelpMessage="Enter the name you wish to be displayed for the printer.",
           ParameterSetName="Printer")]
[Alias('PrinterName')]
[string]
$WindowsDisplayName,   
    
[Parameter(Optional,
           ParameterSetName="Printer")]
[string]
$PortName   
)
#endregion Parameters

Begin
{
    #If a portname is not specified will use the printer's IP instead.  
    if (-not ($PortName))
    {
        Write-Verbose "Port name not specified.  Using $PrinterIP instead."
        $PortName = $PrinterIP
    }
    #Initialize internal variables
    $ComputerCount = 0
}

Process
{
    Foreach ( $computer in $ComputerName ) 
    {
        Write-Verbose "Creating a remote session with $computer"
        $session = New-PSSession -ComputerName $computer -Credential $DomainName\$UserName #will prompt for credentials for each computer

        Write-Verbose "Adding printer $WindowsDisplayName to $computer."
        Invoke-Command -Session $session {Add-PrinterPort -Name $PortName -PrinterHostAddress $PrinterHostAddress}
        Invoke-Command -Session $session {Add-PrinterDriver -Name "$DriverName"}
        Invoke-Command -Session $session {Add-Printer -Name "$WindowsDisplayName" -PortName $PortName -DriverName "$DriverName"}
        Invoke-Command -Session $session {Write-Output "Printer Added Successfully."}

        Print-Verbose "Closing remote session."
        Remove-PSSession -ComputerName $computer
        
        #Increment number of computers by 1
        $ComputerCount ++
    }
}

End
{
    Write-Verbose "Printer $WindowsDisplayName added to $ComputerCount computers."
}
