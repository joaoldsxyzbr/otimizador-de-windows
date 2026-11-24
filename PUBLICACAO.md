# Checklist de publicacao do OtimizadorPC

Estado: candidato em desenvolvimento, nao e uma release estavel. O comando online depende da publicacao dos assets no GitHub Releases.

## Validacao

1. Confirme que todos os jobs do pull request passaram no commit a publicar.
2. Em Windows 10 e 11 descartaveis, abra o app e teste os botoes, a simulacao, exportacao/importacao, recuperacao, cancelamento das consultas e backup de drivers. Use conta de administrador. Evite testar em uma maquina de producao.
3. Verifique que os logs, backups e journals persistem e que nenhum ajuste e aplicado ao abrir a interface.
4. Revise o comportamento dos tweaks de maior risco e os conflitos entre sessoes. Nao considere um estado confirmado manualmente como verificacao automatica.
5. Depois da revisao, integre a branch aprovada a main. Nao publique uma versao estavel com teste falhando.

## Montagem dos arquivos da release

A partir da copia do commit aprovado, em Windows PowerShell 5.1:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\testar.ps1
if ($LASTEXITCODE -ne 0) { throw 'Testes falharam.' }
powershell -NoProfile -ExecutionPolicy Bypass -File .\montar-portatil.ps1
if ($LASTEXITCODE -ne 0) { throw 'Montagem falhou.' }
Get-FileHash -Algorithm SHA256 .\dist\otimizadorpc.ps1
Get-Content .\dist\otimizadorpc.ps1.sha256
```

Os hashes devem coincidir. Para uma release candidata, mantenha o identificador preview. Antes de uma release estavel, ajuste a versao em comum.ps1 e execute novamente os testes e a compilacao no commit correspondente.

## Publicacao pelo mantenedor

Acesse https://github.com/joaoldsxyzbr/otimizador-de-windows/releases/new e crie uma release apontando para o commit revisado. Use uma tag versionada, marque como pre-release enquanto houver validacoes pendentes. Anexe os arquivos gerados:

- dist/otimizadorpc.ps1
- dist/otimizadorpc.ps1.sha256
- dist/otimizadorpc-portatil.ps1
- dist/rodar-portatil.bat

Nao marque como latest ate aprovar a entrega estavel. A publicacao automatica nao esta configurada. O comando estavel com /latest/download/otimizadorpc.ps1 so funciona apos publicar uma release estavel com esse asset.

Para testar uma pre-release, use o endereco do asset mostrado na propria release, confira o SHA256 e execute apenas codigo revisado. Nunca ignore falhas de integridade.

## Limites

O script online executa em memoria e dispensa instalacao; logs e backups permanecem em ProgramData. A verificacao SHA256 do arquivo nao substitui assinatura digital. O modo online exige Windows PowerShell 5.1 elevado, nao carrega custom .reg e nao atualiza o app automaticamente.
