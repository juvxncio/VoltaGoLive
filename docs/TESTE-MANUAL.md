# Roteiro de teste manual (Windows)

Este roteiro cobre o que os testes automáticos não conseguem: o Discord de verdade e uma
conta Proton de verdade. Siga na ordem. Se um passo não der o resultado esperado, pare,
rode o `Diagnostico.bat` e envie o relatório.

## Preparação

1. Abra o PowerShell e baixe o projeto:

   ```powershell
   git clone https://github.com/juvxncio/VoltaGoLive.git C:\VoltaGoLive
   ```

   **Esperado:** a pasta `C:\VoltaGoLive` aparece com os arquivos `Ativar.bat`,
   `Desativar.bat`, `Status.bat` e `Diagnostico.bat`.

   Para atualizar depois de uma correção: `git -C C:\VoltaGoLive pull`

2. Baixe a configuração WireGuard na Proton (passo 2 do README) e coloque o arquivo
   `.conf` em `C:\VoltaGoLive\config`.

   **Esperado:** a pasta `config` tem o `LEIA-ME.txt` e um único arquivo `.conf`.

3. Abra o Discord normalmente e confirme o ponto de partida.

   **Esperado:** o Go Live e a câmera estão bloqueados (é o problema que queremos resolver).

## Teste 1: Status antes de ativar

4. Dois cliques em `Status.bat`.

   **Esperado:** `Túnel: DESATIVADO` e `Discord: aberto`.

## Teste 2: Ativar

5. Dois cliques em `Ativar.bat`.

   **Esperado, se o WireSock ainda não estiver instalado:** a pergunta
   `Quer instalar agora pela fonte oficial? (S/N)`. Responda `S`. O Windows pede permissão
   de administrador. A instalação termina e a ativação continua sozinha.

   **Esperado em seguida:** as mensagens `Fechando o Discord...`, `Subindo o túnel...`,
   `Abrindo o Discord dentro do túnel...` e, por fim, em verde,
   `Pronto! O túnel está ativo e o Discord está passando por ele.`
   O Discord fecha e abre de novo sozinho.

6. No Discord, entre num canal de voz e inicie o Go Live. Depois ligue a câmera.

   **Esperado:** os dois funcionam. **Este é o teste principal do projeto.**

7. Com o túnel ativo, abra <https://ifconfig.me> no navegador.

   **Esperado:** aparece o seu IP normal, do Brasil. Isso prova que o resto do computador
   não está passando pelo túnel.

8. Dois cliques em `Status.bat`.

   **Esperado:** `Túnel: ATIVO`, `Ativo há: 0h 0Xmin` e `Último handshake:` com data e
   hora recentes.

9. Confira que o seu arquivo não foi alterado: abra o `.conf` da pasta `config` no Bloco de Notas.

   **Esperado:** não existe nenhuma linha com `AllowedApps`.

## Teste 3: Ativar duas vezes

10. Com o túnel ativo, rode `Ativar.bat` de novo.

    **Esperado:** o Discord fecha e reabre, a mensagem verde aparece de novo, e o
    `Status.bat` mostra o tempo ativo recomeçando do zero. No Gerenciador de Tarefas
    (aba Detalhes) existe só um `wiresock-client.exe`.

## Teste 4: Diagnóstico

11. Dois cliques em `Diagnostico.bat`.

    **Esperado:** o relatório aparece na tela e a mensagem
    `Relatório gerado e copiado.` Cole num Bloco de Notas (Ctrl+V) e procure: o seu nome
    de usuário do Windows, o nome do computador, o seu IP e qualquer trecho da chave do
    `.conf`. **Nenhum deles pode aparecer.** No lugar devem estar `<USUARIO>`, `<PC>`,
    `<IP>`, `<CHAVE>` e `%USERPROFILE%`.

## Teste 5: Desativar

12. Dois cliques em `Desativar.bat`.

    **Esperado:** `Túnel desativado. O Discord voltou para a conexão normal.` O Discord
    fecha e abre de novo.

13. `Status.bat`.

    **Esperado:** `Túnel: DESATIVADO`.

14. No Discord, tente o Go Live.

    **Esperado:** voltou a ficar bloqueado (prova que o Discord saiu do túnel).

15. Aperte `Win + R`, digite `%LOCALAPPDATA%\VoltaGoLive` e aperte Enter.

    **Esperado:** existe a pasta `logs` (e `diagnostico`), mas **não** existe a pasta
    `runtime` nem o arquivo `estado.json`.

## Teste 6: Erros com mensagem clara

16. Tire o `.conf` da pasta `config` (guarde em outro lugar) e rode `Ativar.bat`.

    **Esperado:** `ERRO: Não encontrei nenhum arquivo .conf na pasta "config".` seguido
    de `O que fazer:`. O Discord **não** é fechado.

17. Coloque dois arquivos `.conf` na pasta e rode `Ativar.bat`.

    **Esperado:** `ERRO: Há 2 arquivos .conf na pasta "config"`. O Discord não é fechado.

18. Deixe só um `.conf`, abra uma cópia dele no Bloco de Notas, apague metade da linha da
    chave, salve como único `.conf` da pasta e rode `Ativar.bat`.

    **Esperado:** `ERRO: O arquivo .conf tem problemas:` com a explicação. Depois
    devolva o arquivo original.

19. Rode `Desativar.bat` com o túnel já desativado.

    **Esperado:** `O túnel já estava desativado. Arquivos temporários limpos.`

## Teste 7: Reinício do computador

20. Ative o túnel e reinicie o computador sem desativar.

    **Esperado:** depois de reiniciar, o `Status.bat` mostra `Túnel: DESATIVADO` e o
    Discord abre normalmente. Rodar `Ativar.bat` funciona de novo.

## Se algo falhar

1. Rode o `Diagnostico.bat` logo depois da falha.
2. Envie o relatório (ele já está copiado) junto com o número do passo que falhou.
3. Depois da correção: `git -C C:\VoltaGoLive pull` e repita a partir do passo que falhou.
