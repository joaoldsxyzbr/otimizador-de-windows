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

Nao marque como latest ate aprovar a entrega estavel. A publicacao automatica esta configurada no workflow Publicar OtimizadorPC, na main. O comando estavel com /latest/download/otimizadorpc.ps1 so funciona apos publicar uma release estavel com esse asset.

Para testar uma pre-release, use o endereco do asset mostrado na propria release, confira o SHA256 e execute apenas codigo revisado. Nunca ignore falhas de integridade.

## Limites

O script online executa em memoria e dispensa instalacao; logs e backups permanecem em ProgramData\otimizadorpc-v2; estado legado nao e importado automaticamente. A verificacao SHA256 do arquivo nao substitui assinatura digital. O modo online exige Windows PowerShell 5.1 elevado, nao carrega custom .reg e nao atualiza o app automaticamente.

O CI deve conferir a nova pasta de estado `ProgramData\otimizadorpc-v2` para journals e logs; os caminhos antigos dos artefatos de CI precisam ser atualizados pelo mantenedor. O teste offline verifica a pasta nova no runner.

RC.5: validar manualmente os dois temas, os botoes de gerenciador (Run do usuario, servicos do catalogo e tarefas descartaveis), o cancelamento entre acoes, o monitor, o teste sintetico e o download verificado. A escolha de atualizar permanece explicita; nunca executar um download automaticamente como administrador.

## Roteiro de aceite manual (Windows 10 e Windows 11)

Use VMs com snapshot e uma conta administrativa. Nao execute testes destrutivos em uma maquina pessoal.

| Teste | Resultado esperado |
| --- | --- |
| Abrir release, conferir titulo e executar simulacao | Versao corresponde a tag; nenhum journal novo nem alteracao no Windows. |
| Abrir segunda instancia GUI/CLI | Segunda instancia recusada; reabrir apos fechar a primeira funciona. |
| Alternar tema em Config e reabrir | Tema persistido, texto legivel, selecao visivel, botoes acessiveis em 1366x768 e com DPI 125%. |
| Inventario, filtros, exportacao | Oito abas; filtros literais; exportacao JSON; nenhuma alteracao sem confirmacao. |
| Run do usuario, servico do catalogo, tarefa descartavel | Alteracao confirmada, journal e reversao; conflito posterior deve ser preservado. |
| Varredura de aplicativo descartavel | Marcar/desmarcar uma unica caixa e varias; nada marcado por padrao; contador correto; quarentena e desfazer. |
| Lote de ajustes, debloat, recursos | Progresso; cancelar entre acoes; journal preservado; reinicio/dependencias indicados quando necessario. |
| Monitor, carga sintetica e comparativo | Resultados e JSON; mesmas condicoes de carga; cancelamento de consulta; sem promessa de ganho de FPS. |
| Backup de drivers | Exportacao de terceiros em pasta escolhida, interface responsiva, arquivos preservados em falhas. |
| Consultar e baixar versao oficial | Tags reais, confirmacao explicita, SHA256 correto, nenhum codigo executado automaticamente. |

## Ajustes pendentes nos workflows

Nos arquivos `.github/workflows/ci.yml` e `.github/workflows/publicar.yml`, substitua as referencias de journal/log em `ProgramData\otimizadorpc\desfazer` e `ProgramData\otimizadorpc\logs` pelas equivalentes em `ProgramData\otimizadorpc-v2\desfazer` e `ProgramData\otimizadorpc-v2\logs`. Inclua os dois assets online e SHA256 na coleta do CI, alem dos arquivos portateis. Preserve as validacoes de simulacao, compilacao, integracao e integridade. Nao remova o gate de testes manuais para publicacao estavel.

RC.6: conferir categorias e filtros, detalhes e ordenacao com metadados ausentes; selecionar componente protegido e selecao mista (botoes bloqueados), verificar aviso de desconhecido e driver sem executar desinstalacao, e testar uma aplicacao descartavel normal. Confirmar que uma entrada alterada apos listagem nao e usada para desinstalar/limpar.

RC.6 orientada: testar rotulos de estado e perfil recomendado, guias de ajustes, bloqueio de AppX protegidos/nao catalogados, previa da limpeza de temporarios e inspecao dos valores do journal. Conferir que a limpeza definitiva e explicita e que nenhum dado e removido ao apenas consultar.

RC.7: validar em conta comum e administrador, ambiente de dominio/Entra/MDM e ambiente inconclusivo. O modo protegido deve abrir sem UAC, sem criar pasta de estado ou logs, com apenas diagnostico local e sem exportacao. Preset real deve ser recusado e simulacao permitida. Testar criacao de ponto em Windows cliente; runner Windows Server nao oferece System Restore. A integracao usa stub isolado exclusivamente para exercitar journal/reversao em ambiente descartavel; teste separado comprova interrupcao sem ponto. Nao usar o app em empresa sem autorizacao do TI.

RC.7 adicional: diagnostico por padrao mesmo elevado; -Pessoal e explicito e nao sobrepoe sinais de TI. Testar WinGet registrado e assinado, instalacao sem upgrade, upgrade selecionado, diagnosticos avancados e historico WUA, estados dos recursos e conflitos de energia. Testar desinstalacao HKLM assinada e recusa de HKCU/arquivo nao assinado. Limpeza so apos ausencia da entrada original. Validacao real de WinGet e System Restore exige Windows cliente; runner nao certifica esses caminhos.

## Pendencias antes da estavel

- Validacao manual com Windows 10/11 cliente, conta comum e ambiente organizacional autorizado: diagnostico sem elevacao, sem arquivos de estado do app, nenhuma alteracao no modo protegido, sem contornar politicas.
- Testar modo pessoal explicito, ponto de restauracao real (limite diario), WinGet instalado/assinado, drivers reais, recursos opcionais e conflitos de reversao. CI Windows Server nao substitui esses testes.
- Corrigir caminhos de artefatos nos workflows para ProgramData\\otimizadorpc-v2 e manter todos os gates; alteracao depende do mantenedor quando a ferramenta de edicao de workflow estiver bloqueada.
- Evolucao posterior: matriz de compatibilidade por build/edicao para cada tweak documentado, APIs MSI de componentes compartilhados, medicao de gargalos com contadores e ETW, inventario PnP mais completo, relatorios de bateria e otimizacao de volumes apropriada a midia. Nao executar remocao automatica de drivers nem ajustes corporativos. Traducao EN e mudancas visuais nao bloqueiam a estavel PT-BR.
- Merge na main e release estavel somente apos aceite e verificacao dos artefatos.

RC.8: validar capacidade da bateria em notebook, contadores ausentes, Otimizar Unidades nativo (modo pessoal), matriz de builds e edicoes, consulta MSI de produto real em cache e ausencia de reparos MSI. A consulta MSI e parcial e nao mapeia todas as dependencias. Validar Windows cliente e ambiente corporativo autorizado; nenhuma coleta ETW automatica.
