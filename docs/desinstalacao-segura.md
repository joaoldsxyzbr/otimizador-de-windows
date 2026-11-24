# F2/F6 - validacao de desinstalacao

Refs #2. Software de seguranca reconhecido e bloqueado no desinstalador e limpeza, sem classificar todo o computador como corporativo. Nome/editor sao indicios, nao classificacao infalivel.

MSI: exigir metadado WindowsInstaller e codigo da chave exata, rejeitar comandos ambiguos e argumentos nao previstos; executar somente msiexec nativo com /x e /norestart. Executaveis de terceiros: manter restricao a Program Files e assinatura valida, recusar caminhos redirecionados, calcular hash antes da confirmacao e conferir novamente apos o dialogo. Metadados de registro (inclusive versao e MSI) relidos antes da execucao.

Limites: assinatura valida nao prova que o executavel e o desinstalador correto, nem elimina corrida de arquivo entre verificacao e execucao. Nao certifica dependencias, politicas efetivas, desinstaladores per-user ou todos os argumentos de terceiros. Fluxos nao reconhecidos ficam para a interface nativa. Nenhuma remocao de software real nos testes desta PR. Modo protegido existente preservado.
