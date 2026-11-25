# Test-only context: disposable integration runner and offline mocks.
# Product code never imports this file. Save the live resolver before mocking.
$script:ContextoAutorizacaoReal=(Get-Command Obter-ContextoAutorizacaoAtual -CommandType Function).ScriptBlock
function Obter-ContextoAutorizacaoAtual {
    param([string]$Id,[switch]$Previa)
    [pscustomobject]@{
        admin=$true;diagnostico=($global:ModoProtegido -ne $false);consentiu=$true
        identidade='S-1-5-21-123-456-789-1000';sidInicial='S-1-5-21-123-456-789-1000'
        visaoCorreta=$true;usuarioCorreto=$true
        windows=[pscustomobject]@{build=26100;edicao='Professional';cliente=$true}
        sinais=@();sinaisConfirmados=$true
    }
}
