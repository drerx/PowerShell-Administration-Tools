<#
.Synopsis
   Locates computers where a user has signed in.
.DESCRIPTION
   Script for gathering the machines that a user has signed into from a list of computers.
   Displays the Computer Name, User Home Folder, and Last Logged-in Time for each computer. 
   Write output to a CSV log file.
   Requires the WinRM service to be running on each remote computer, however works locally without.
   To scan a remote machine without WinRM, use the -DCOM flag.
   Does not require admin rights.
.EXAMPLE
   Locate-UserProfile.ps1 -ComputerName Example-Comp1 -UserName Zweilosec -Verbose
.EXAMPLE
   Locate-UserProfile.ps1 -UserName Zweilosec .\Computers.txt 
.EXAMPLE
   Get-ADComputer -Filter * -SearchBase "OU=TestOU,DC=TestDomain,DC=com" | Select -Property Name | Locate-UserProfile.ps1 -UserName Zweilosec
.INPUTS
   -UserName <username>
   Enter the username(s) you want to search for.  These must be the actual account name not the display name.

   -ComputerName <computer name>
   Input a list of computer names, either piped in as an object or a text file file with one computer name per line.

   -DCOM
   Instructs the script to use DCOM instead of WinRM.  Does nothing if scanning the localhost.
.OUTPUTS
   This script exports a report in table format, and as a CSV file with headers.
   Example output is below:

    Searching for user profile zweiline...

    User profile zweiline was found on 4 computers.

    User     ComputerName UserHome          LastUseTime
    ----     ------------ --------          -----------
    zweiline Zweildesk-1  C:\Users\zweiline 1/22/2022 20:34:09
    zweiline Zweildesk-2  C:\Users\zweiline 1/22/2022 20:34:09
    zweiline Zweildesk-3  C:\zweiline       1/22/2022 14:08:28
    zweiline Zweildesk-4  C:\zweiline       1/22/2022 14:08:28

.NOTES
   Author: Beery, Christopher (https://github.com/zweilosec)
   Created: 6 Mar 2020
   Last Modified: 22 Jan 2022
   Useful Links:
   * http://woshub.com/convert-sid-to-username-and-vice-versa
   * https://www.nextofwindows.com/how-to-get-the-list-of-user-profiles-on-your-computer
#>

[CmdletBinding()]
Param
(
    # The User Names to conduct a hunt for
    [Parameter(Mandatory=$true, 
                ValueFromPipeline=$true,
                ValueFromPipelineByPropertyName=$true)] 
    [ValidateNotNull()]
    [ValidateNotNullOrEmpty()]
    [Alias("User","SAMAccountName")]
    [String[]]
    $UserName,

    # The list of computers to search
    [Parameter(Mandatory=$true, 
                ValueFromPipeline=$true,
                ValueFromPipelineByPropertyName=$true)]
    [Alias("Name")] #Needed to allow computers to be piped in as an attribute from Get-ADComputer
    [String[]]
    $ComputerName, 

    [Alias('NoWinRM')]
    [Switch]
    $DCOM = $false
)

Process
{
    #The CSV file to be used as a log is defined here
    $TimeStamp = (Get-Date).ToString('yyyy-MM-dd_HHmm')
    $CsvFile = "./ProfileSearch_$($TimeStamp).csv"
    Write-Host ""

    Foreach ( $User in $UserName )
    {
        Write-Host "Searching for user profile $User..."
        #Count the number of computers the user has logged into, reset to 0 for each user
        $ComputerCount = 0

        #These are the commands that will be run on each computer
        Foreach ( $Computer in $ComputerName ) 
        {
            #Parameter list that will be fed to Get-CimInstance
            $CimParameters = @{}
            #Hack to get around setting $Computer to $null if scanning localhost
            $RemoteComputer = $Computer

            #First, check if we are scanning the local machine
            #Setting the -ComputerName property of Get-CIMInstance to $null will allow you 
            # to scan a local machine without WinRM enabled
            if ( $Computer -eq $($env:COMPUTERNAME) )
            {
                $RemoteComputer = $null
            }

            #If the user wants to use DCOM instead of WinRM, enable this
            #Do not use this branch if scanning local computer because will cause errors and not needed
            if ( $DCOM -and $RemoteComputer )
            {
                $SessionOption = New-CimSessionOption -Protocol Dcom
                #Create the remote CIM session and add to CimParameters
                $RemoteSession = New-CimSession -ComputerName $RemoteComputer -SessionOption $SessionOption
                $CimParameters = @{CimSession = $RemoteSession}
            }
            else 
            {
                $CimParameters = @{ComputerName = $RemoteComputer}
            }

            #Get the user's SID because the Win32_UserProfile Class (for $RemoteProfile) has no Name property
            # -Filter is faster than piping to Where-Object; Double-double quotes needed to quote the variable properly
            $SID = (Get-CimInstance -ClassName Win32_UserAccount @CimParameters -Filter "Name = ""$User""").SID

            #This method was used since we cannot assume the user's home folder is in C:\Users\
            $RemoteProfile = (Get-CimInstance -ClassName Win32_UserProfile @CimParameters -Filter "SID = ""$SID""")

            #The results will be stored in a custom object with these four properties
            $UserProfile = [PSCustomObject]::new(@{
                User = $User
                ComputerName = $Computer
                UserHome = $RemoteProfile.LocalPath
                LastUseTime = $RemoteProfile.LastUseTime
            })

            #If the User's home directory exists, then the user has signed in
            if ( $UserProfile.UserHome )
            {            
                #Writes the results to a CSV file
                $UserProfile | Select-Object User, ComputerName, UserHome, LastUseTime |
                Export-Csv -Path $CsvFile -Append -NoTypeInformation
                
                #For each computer where a profile is found, increment ComputerCount
                $ComputerCount ++
            }
            
            #Close the remote CimSession if created
            if ($RemoteSession)
            {
                Remove-CimSession $RemoteSession
            }
        }

        if ( $ComputerCount -gt 0 ) 
        {
            Write-Host "`nUser profile $User was found on $ComputerCount computers.`n" -ForegroundColor Green
        }
        else 
        {
            Write-Host "`nUser profile $User was not found.`n" -ForegroundColor Red
        }
    }
}

End
{
    #Read results from the CSV file and print to the screen
    $output = Import-Csv -Path $CsvFile
    Write-Output $output       
}
