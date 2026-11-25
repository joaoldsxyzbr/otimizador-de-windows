# F3 - identidade de journal e verificacao de reversao

Refs #2. Primeira entrega: novos journals usam esquema 2, vinculados ao SID efetivo do processo, MachineGuid local e visao do registro (32/64 bits). A reversao e a confirmacao manual recusam contexto divergente ou esquema desconhecido antes de gravar. O identificador de maquina fica no journal local protegido; nao incluir esse campo em exportacoes de diagnostico nem publicar journals de maquinas reais.

O MachineGuid nao e prova criptografica de identidade (pode ser clonado); e uma barreira contra erros de contexto. O esquema legado permanece legivel e reversivel pelas regras anteriores, sem garantia de identidade. Nao altera o formato dos itens antigos. Uma nova sessao nao inicia se o contexto nao puder ser identificado.

A reversao de registro agora verifica o tipo/conteudo restaurado ou ausencia do valor, antes de reportar sucesso. Permanecem os conflitos detectados no snapshot e o marcador de reversao incerta.

Pendentes: identidade por alvo em journals antigos, validacao integral de todos os backups referenciados, recuperacao automatizada de falhas parciais e aceite em Windows cliente. Nao e certificacao de rollback integral.

## Validacao adicional do arquivo

A recuperacao, confirmacao manual e inventario validam o arquivo JSON diretamente dentro da pasta de estado, rejeitam redirecionamento e verificam ACL esperada do arquivo e da pasta. Journals antigos sem ACL esperada ficam indisponiveis para restauracao automatica. Esta barreira nao autentica o conteudo contra um administrador e nao valida todos os backups referenciados; esses requisitos permanecem pendentes. Testes unitarios exercitam caminhos externos/redirecionados; a integracao real exercita journals novos com ACL herdada.

O CI identificou que heranca de ACL de arquivo nao reproduz necessariamente as tres ACEs da pasta. A gravacao de journals agora aplica ACL explicita no arquivo temporario antes da publicacao atomica, valida o destino existente e o resultado publicado. Journals anteriores sem OWNER RIGHTS so podem ser aceitos se o dono for Administradores ou SYSTEM e os demais direitos forem estritamente esperados. Nao flexibiliza ACL para usuarios comuns.

## Limites de NTFS, ACL, fluxos e prazos

O manifesto e o hash certificam os bytes observados, nao o sistema de arquivos ao redor. Limites explicitos, sem promessa de restauracao integral:

- ACLs originais nao entram no manifesto da quarentena. A quarentena exige ACL privada e confirmada na arvore movida (barreira de seguranca do destino) e a restauracao confere o hash do conteudo, mas nao reconstroi permissoes originais alteradas fora do fluxo do app.
- Fluxos alternativos de NTFS (alternate data streams) nao fazem parte do hash nem sao restaurados de forma independente; conteudo exclusivo em ADS nao e certificado.
- Hardlinks nao sao certificados: dois nomes podem compartilhar os mesmos dados e o journal nao registra essa relacao. Links simbolicos e junctions sao recusados ou nao seguidos pelas operacoes automaticas.
- Entrada/Saida grande (pastas profundas, volume lento, antivirus em tempo real) pode exceder o prazo da operacao; resultado parcial e identificado como pendencia, nunca tratado como sucesso. O prazo protege a responsividade e nao e garantia de duracao.
- Backups legados (esquema antigo, .reg integrais de importacao antiga, backups sem hash) permanecem manuais: o app lista e verifica o que pode, mas nao promete restauracao automatica deles.

## Recuperacao de instalacao por plano (F6)

A partir do lote F6, o journal de instalacao (tipo instalacao-app) com plano por aplicativo (somente operacoes install e id/fonte do catalogo local) permite desfazer automatico: o WinGet uninstall por id roda em janela visivel, o codigo de saida e conferido e a ausencia e verificada contra o catalogo local e os inventarios de registro/AppX. Falha de verificacao vira revisao manual, nunca sucesso presumido. Planos com upgrade ou sem id catalogado continuam sem desfazer automatico. A verificacao de ausencia prova que o nome catalogado nao aparece mais nos inventarios consultados; nao certifica limpeza de rastros nem estado de outros produtos.
