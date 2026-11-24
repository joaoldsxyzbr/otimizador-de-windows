# otimizador-de-windows (OtimizadorPC)

## Abrir sem instalar

Abra o **Windows PowerShell 5.1 como administrador** e cole:

```powershell
irm https://github.com/joaoldsxyzbr/otimizador-de-windows/releases/download/v2.0.0-rc.3/otimizadorpc.ps1 | iex
```

O OtimizadorPC abre diretamente em memoria, sem instalacao. Requer Windows 10/11 e conexao com a internet.

**Versao candidata v2.0.0-rc.3:** testes automatizados aprovados; validacao manual ainda pendente. O comando executa codigo remoto com privilegios administrativos. Revise a origem e use inicialmente o modo de simulacao. [Release e SHA256](https://github.com/joaoldsxyzbr/otimizador-de-windows/releases/tag/v2.0.0-rc.3).

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
