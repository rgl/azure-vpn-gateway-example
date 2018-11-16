Write-Host 'Importing the example CA...'
Import-Certificate `
    -FilePath 'c:\vagrant\shared\example-ca\example-ca-crt.der' `
    -CertStoreLocation Cert:\LocalMachine\Root `
    | Out-Null

Write-Host 'Importing the example VPN client certificate...'
Import-PfxCertificate `
    -FilePath 'c:\vagrant\shared\example-ca\windows-p2s-vpn-client-key.p12' `
    -CertStoreLocation Cert:\CurrentUser\My `
    -Password $null `
    -Exportable `
    | Out-Null

Write-Host 'Saving the current routing table as ip-routes-original.txt...'
route print >"$env:USERPROFILE\Desktop\ip-routes-original.txt"

Write-Host 'Expanding the shared/vpn-client.zip into the Desktop...'
Expand-Archive C:\vagrant\shared\vpn-client.zip "$env:USERPROFILE\Desktop\vpn-client"

# TODO why is this not installing?
#Write-Host 'Installing the example VPN...'
#&'C:\Users\vagrant\Desktop\vpn-client\WindowsAmd64\VpnClientSetupAmd64.exe' /Q | Out-String -Stream
