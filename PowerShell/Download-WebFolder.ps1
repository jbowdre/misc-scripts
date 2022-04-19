$outputdir = 'C:\Scripts\Download\'
$url = 'https://win01.lab.bowdre.net/stuff/files/'

# enable TLS 1.2 and TLS 1.1 protocols
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12, [Net.SecurityProtocolType]::Tls11

$WebResponse = Invoke-WebRequest -Uri $url
# get the list of links, skip the first one ("[To Parent Directory]") and download the files
$WebResponse.Links | Select-Object -ExpandProperty href -Skip 1 | ForEach-Object {
    $fileName = $_.ToString().Split('/')[-1]                        # 'filename.ext'
    $filePath = Join-Path -Path $outputdir -ChildPath $fileName     # 'C:\Scripts\Download\filename.ext'
    $baseUrl = $url.split('/')                                      # ['https', '', 'win01.lab.bowdre.net', 'stuff', 'files']
    $baseUrl = $baseUrl[0,2] -join '//'                             # 'https://win01.lab.bowdre.net'
    $fileUrl  = '{0}{1}' -f $baseUrl.TrimEnd('/'), $_               # 'https://win01.lab.bowdre.net/stuff/files/filename.ext'
    Invoke-WebRequest -Uri $fileUrl -OutFile $filePath 
}
