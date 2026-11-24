# otimizador-de-windows (OtimizadorPC)

## Abrir sem instalar

Em computador autorizado, abra o **Windows PowerShell 5.1 normal (sem administrador)**:

```powershell
irm https://github.com/joaoldsxyzbr/otimizador-de-windows/releases/download/v2.0.0-rc.7/otimizadorpc.ps1 | iex
```

A RC.7 inicia em modo diagnostico, inclusive em console elevado. Para uso pessoal autorizado, revise o codigo e o SHA256 da release e execute o script com `-Pessoal` em PowerShell elevado. Sinais de gerenciamento impedem alteracoes. Em computador empresarial, solicite autorizacao do TI; nao execute codigo externo sem aprovacao. O comando direto nao verifica o hash automaticamente.

[RC.7 e SHA256](https://github.com/joaoldsxyzbr/otimizador-de-windows/releases/tag/v2.0.0-rc.7) | [Codigo V2 em desenvolvimento](https://github.com/joaoldsxyzbr/otimizador-de-windows/tree/desenvolvimento-v2)

**Atenção:** a descricao e as instrucoes de clone abaixo referem-se ao codigo legado desta branch main. As protecoes corporativas da RC.7 estao na release e na branch desenvolvimento-v2, nao no script legado desta branch. Validacao manual da candidata ainda pendente.

[![ci](https://github.com/joaoldsxyzbr/otimizador-de-windows/actions/workflows/ci.yml/badge.svg)](https://github.com/joaoldsxyzbr/otimizador-de-windows/actions/workflows/ci.yml)

App de otimizacao do Windows 10 e 11 em PowerShell + janela nativa WPF (estilo Winutil do Chris Titus, MIT), 100% PT-BR, com journal de desfazer por acao e quarantena. Feito pra uso geral/pessoal: visual, privacidade, desempenho, debloat, desinstalacao limpa e manutencao, tudo num so lugar.

## como usar

1. baixe/clone o repo e abra a pasta
2. (opcional, recomendado) rode a bateria de testes: `powershell -ExecutionPolicy Bypass -File .\testar.ps1`
3. de dois cliques em `rodar-como-admin.bat` (o app pede elevacao sozinho)

nao quer janela? modo cli:

```powershell
.\otimizadorpc.ps1 -Cli seguro -Simular   # so descreve o que faria
.\otimizadorpc.ps1 -Cli balanceado        # aplica o preset
```

## o que tem dentro

- **47 tweaks** em catalogo (3 presets: seguro / balanceado / agressivo): telemetria, privacidade (copilot/ia inclusos), desempenho, barra de tarefas, explorer, energia e rede
- **66 apps** pra instalar via winget e **34 pacotes** da store pra debloat
- **desinstalador com limpeza de rastros**: pastas, registro, servicos orfaos, tarefas agendadas, regras de firewall, entradas run e path morto; tudo que some vai pra quarantena (nada e apagado de verdade sem querer)
- **journal de desfazer**: cada acao grava o valor anterior; a aba desfazer reverte sessao inteira; o journal e salvo a cada acao (a prova de crash)
- **planos**: exporte os ajustes marcados num .json e importe em outro pc
- **arquivo unico**: `.\montar-portatil.ps1` gera `dist\otimizadorpc-portatil.ps1`, o app inteiro num arquivo so pro pendrive
- **tweaks custom**: jogue seus .reg em `custom\` e eles viram ajustes com journal e desfazer

## seguranca

- **nunca** desativa windows defender, firewall ou atualizacoes de seguranca
- nao remove edge/onedrive
- cria ponto de restauracao antes de aplicar (opcional, marcado por padrao)
- detecta pc gerenciado por empresa (dominio/av corporativo) e avisa

documentacao completa: [leia-me.md](leia-me.md)

## licenca

MIT - veja [LICENSE](LICENSE)

uso por sua conta e risco: e um app que mexe no sistema, leia o que cada ajuste faz antes de aplicar.
