[CmdletBinding()]
param (
    [string]$IPAddress,
    [string]$Type
)

Import-Module .\IsPrivateIPAddress.psm1

If ( $IPAddress -Or $Type ) {
    IsPrivateIPAddress -IPAddress $IPAddress -Type $Type
}
