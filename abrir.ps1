# Launcher de distribuicao oficial. Sem elevacao, instalacao ou gravacao de arquivo.
& {
    $ErrorActionPreference = 'Stop'
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) {
        throw 'Use Windows PowerShell 5.1.'
    }
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw 'Use Windows PowerShell em modo STA.'
    }
    $web = New-Object System.Net.WebClient
    try {
        $tag = $web.DownloadString('https://raw.githubusercontent.com/joaoldsxyzbr/otimizador-de-windows/main/versao-atual.txt').Trim()
        if ($tag -notmatch '\Av2\.\d+\.\d+(?:-(?:rc|beta|alpha|preview)\.\d+)?\z') {
            throw 'Versao publicada invalida. Nenhum aplicativo foi executado.'
        }
        $base = 'https://github.com/joaoldsxyzbr/otimizador-de-windows/releases/download/' + $tag
        $hashText = $web.DownloadString($base + '/otimizadorpc.ps1.sha256').TrimStart([char]0xFEFF).Trim()
        if ($hashText -notmatch '\A([a-fA-F0-9]{64})\s+\*?otimizadorpc\.ps1\z') {
            throw 'Arquivo SHA256 invalido. Nenhum aplicativo foi executado.'
        }
        $esperado = $Matches[1]
        $bytes = $web.DownloadData($base + '/otimizadorpc.ps1')
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $real = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '') }
        finally { $sha.Dispose() }
        if ($real -ine $esperado) { throw 'SHA256 divergente. Nenhum aplicativo foi executado.' }
        $codigo = (New-Object System.Text.UTF8Encoding($false,$true)).GetString($bytes).TrimStart([char]0xFEFF)
    } finally { $web.Dispose() }
    Write-Host ('OtimizadorPC ' + $tag + ' - SHA256 conferido.')
    & ([scriptblock]::Create($codigo)) -Diagnostico
}
