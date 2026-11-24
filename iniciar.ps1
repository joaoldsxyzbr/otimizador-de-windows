# iniciar.ps1 - launcher sem instalacao, exclusivo do repositorio OtimizadorPC
# Execute no Windows PowerShell 5.1, como administrador para abrir o aplicativo.
[CmdletBinding()]
param(
    [ValidatePattern('^(main|desenvolvimento-v2|[a-fA-F0-9]{40})$')]
    [string]$Ref = 'main',
    [ValidateSet('seguro','balanceado','agressivo','essencial','gamer','notebook','privacidade','corporativo','recomendado')]
    [string]$Cli,
    [switch]$Simular,
    [switch]$SomenteValidar,
    # Fonte local para testes e uso offline; somente de uma copia confiavel.
    [string]$FonteLocal
)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Este aplicativo requer Windows.' }
if ($Simular -and -not $Cli) { throw 'Use -Simular junto com -Cli.' }
if (-not $SomenteValidar) {
    $identidade = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identidade)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Abra o Windows PowerShell como administrador e execute novamente.'
    }
}

$hostPS = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $hostPS -PathType Leaf)) { throw 'Windows PowerShell 5.1 nao encontrado.' }
$temporario = Join-Path ([IO.Path]::GetTempPath()) ('otimizadorpc-' + [guid]::NewGuid().ToString('N'))
$repo = 'joaoldsxyzbr/otimizador-de-windows'
$arquivos = @(
    'otimizadorpc.ps1', 'montar-portatil.ps1',
    'src/modules/comum.ps1', 'src/modules/motor.ps1', 'src/modules/consertos.ps1',
    'src/modules/desinstalador.ps1', 'src/modules/sistema.ps1', 'src/modules/gui.ps1',
    'src/ui/principal.xaml', 'data/tweaks.json', 'data/aplicativos.json', 'data/uwp.json'
)
$tlsAnterior = [Net.ServicePointManager]::SecurityProtocol
try {
    New-Item -ItemType Directory -Path $temporario | Out-Null
    if ($FonteLocal) {
        $origem = (Get-Item -LiteralPath $FonteLocal).FullName
        $fonte = Join-Path $temporario 'fonte'
        New-Item -ItemType Directory -Path $fonte | Out-Null
        foreach ($rel in $arquivos) {
            $dest = Join-Path $fonte $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $origem $rel) -Destination $dest
        }
        Write-Host 'Usando fonte local explicitamente selecionada.'
    } else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $headers = @{ 'User-Agent' = 'OtimizadorPC-Launcher'; Accept = 'application/vnd.github+json' }
        $commit = Invoke-RestMethod -Uri ('https://api.github.com/repos/' + $repo + '/commits/' + $Ref) -Headers $headers -TimeoutSec 30
        $sha = [string]$commit.sha
        $treeSha = [string]$commit.commit.tree.sha
        if ($sha -notmatch '^[0-9a-f]{40}$' -or $treeSha -notmatch '^[0-9a-f]{40}$') { throw 'Resposta de commit invalida.' }
        if ($Ref -match '^[0-9a-f]{40}$' -and $sha -ne $Ref) { throw 'Commit recebido diferente do solicitado.' }
        Write-Host ('Baixando OtimizadorPC: ' + $Ref + ' (' + $sha + ')')
        $arvore = Invoke-RestMethod -Uri ('https://api.github.com/repos/' + $repo + '/git/trees/' + $treeSha + '?recursive=1') -Headers $headers -TimeoutSec 30
        if ($arvore.truncated -or $arvore.sha -ne $treeSha) { throw 'Arvore Git invalida ou incompleta.' }
        $zip = Join-Path $temporario 'fonte.zip'
        Invoke-WebRequest -UseBasicParsing -Uri ('https://codeload.github.com/' + $repo + '/zip/' + $sha) -OutFile $zip -TimeoutSec 120
        $extraido = Join-Path $temporario 'extraido'
        Expand-Archive -LiteralPath $zip -DestinationPath $extraido
        $pastas = @(Get-ChildItem -LiteralPath $extraido -Directory)
        if ($pastas.Count -ne 1) { throw 'Estrutura inesperada do arquivo ZIP.' }
        $fonte = Join-Path $temporario 'fonte'
        New-Item -ItemType Directory -Path $fonte | Out-Null
        # Confere cada arquivo executado com o identificador de blob do commit.
        # Isto verifica consistencia com o GitHub, nao assinatura independente do autor.
        foreach ($rel in $arquivos) {
            $entrada = @($arvore.tree | Where-Object { $_.path -ceq $rel -and $_.type -eq 'blob' -and $_.mode -eq '100644' })
            if ($entrada.Count -ne 1 -or $entrada[0].sha -notmatch '^[0-9a-f]{40}$') { throw ('Arquivo Git invalido: ' + $rel) }
            $src = Join-Path $pastas[0].FullName $rel
            $item = Get-Item -LiteralPath $src
            if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw ('Arquivo inesperado: ' + $rel) }
            $bytes = [IO.File]::ReadAllBytes($src)
            $prefixo = [Text.Encoding]::ASCII.GetBytes(('blob ' + $bytes.Length + [char]0))
            $hash = [Security.Cryptography.SHA1]::Create()
            try {
                $calculado = ([BitConverter]::ToString($hash.ComputeHash([byte[]]($prefixo + $bytes)))).Replace('-','').ToLowerInvariant()
            } finally { $hash.Dispose() }
            if ($calculado -ne $entrada[0].sha) { throw ('Integridade Git divergente: ' + $rel) }
            $dest = Join-Path $fonte $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
            [IO.File]::WriteAllBytes($dest, $bytes)
        }
        Write-Host 'Arquivos conferidos com o commit do GitHub.'
    }

    $montador = Join-Path $fonte 'montar-portatil.ps1'
    & $hostPS -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $montador
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao montar a versao portatil.' }
    $portatil = Join-Path $fonte 'dist\otimizadorpc-portatil.ps1'
    $erros = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($portatil, [ref]$null, [ref]$erros)
    if (-not (Test-Path -LiteralPath $portatil -PathType Leaf) -or @($erros).Count -gt 0) { throw 'Versao portatil invalida.' }
    if ($SomenteValidar) { Write-Host 'Launcher validado; aplicativo nao executado.'; return }

    Write-Host 'Abrindo OtimizadorPC...'
    $argsApp = @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',$portatil)
    if ($Cli) { $argsApp += @('-Cli',$Cli) }
    if ($Simular) { $argsApp += '-Simular' }
    & $hostPS @argsApp
    if ($LASTEXITCODE -ne 0) { throw ('OtimizadorPC terminou com codigo ' + $LASTEXITCODE) }
} finally {
    [Net.ServicePointManager]::SecurityProtocol = $tlsAnterior
    if (Test-Path -LiteralPath $temporario) {
        try { Remove-Item -LiteralPath $temporario -Recurse -Force -ErrorAction Stop }
        catch { Write-Warning ('Nao foi possivel limpar a pasta temporaria: ' + $temporario) }
    }
}
