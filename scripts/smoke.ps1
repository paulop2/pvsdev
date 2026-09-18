param(
  [Parameter(Mandatory = $true)][string]$BaseUrl
)
$ErrorActionPreference = 'Stop'
$urls = @('/', '/posts/about-me/', '/posts/rants/', '/posts/first-post/', '/three/boxes/')
foreach ($path in $urls) {
  $url = "$BaseUrl$path"
  $status = (curl.exe -s -o NUL -w "%{http_code}" $url)
  Write-Output "$status  $url"
  if ($status -ne '200') { throw "Falha em $url ($status)" }
}
Write-Output 'smoke ok'
