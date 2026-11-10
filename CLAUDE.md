# VoltaGoLive: instruções para o Claude

Módulo PowerShell que coloca somente o Discord dentro de um túnel WireGuard (Proton VPN
gratuito) no Windows, usando o WireSock e a diretiva `AllowedApps`. O dono do projeto
distribui para amigos que não são técnicos.

## Regras que não mudam sem consultar o dono

- PowerShell compatível com o Windows PowerShell 5.1. Sem `.exe` compilado e sem
  redistribuir binários do WireSock.
- O `.conf` é do usuário, baixado por ele na conta Proton. O projeto nunca pede nem guarda
  usuário ou senha, e nunca altera o `.conf` original (o túnel usa uma cópia).
- Zero vazamento: nunca imprimir variáveis de ambiente em massa, tokens, chaves, IP,
  hostname ou nome de usuário, em chat, arquivo, log ou commit. Nada de `.env`.
- Tudo que vai para log, tela de diagnóstico ou arquivo passa por `Protect-VoltaGoLiveText`.
- O nome do campo da chave privada do WireGuard e o travessão são proibidos em qualquer
  arquivo versionado. `tools/Test-Repository.ps1` reprova. No código o nome é montado em
  duas partes (veja `src/VoltaGoLive/Private/Constants.ps1`).
- GitHub: operar somente em `juvxncio/VoltaGoLive`, sempre com `--repo`. Nunca tocar em
  nenhuma organização da conta. O repositório fica privado, e nenhuma release é publicada,
  até o dono autorizar.
- Commits pequenos, Conventional Commits, autor com o e-mail noreply do GitHub do dono.
- Nunca dizer que algo funciona só porque os testes passaram. O que depende de Discord e
  Proton reais só está concluído quando for visto funcionando no Windows.

## Antes de cada commit

```powershell
./tools/Add-Bom.ps1
./tools/Test-Repository.ps1
./tools/Invoke-Lint.ps1
./tools/Invoke-Tests.ps1
```

O hook de pre-commit (`git config core.hooksPath .githooks`) roda o gitleaks e a
verificação do repositório.

## Estrutura

- `src/VoltaGoLive/Public`: funções públicas (`Enable-`, `Disable-`, `Get-...Status`,
  `New-...Diagnostic`, `Install-...WireSock`, `Protect-...Text`).
- `src/VoltaGoLive/Private`: funções internas, prefixo `Vgl`.
- `src/VoltaGoLive/TunnelHost.ps1`: processo oculto e elevado que executa o
  `wiresock-client` e grava o log redigido. Para parar, basta criar o arquivo de sinal.
- `scripts/VoltaGoLive.ps1`: ponto de entrada dos `.bat`. `scripts/Janela.ps1`: janela
  Windows Forms (`VoltaGoLive.bat`).
- `tools/Invoke-EndToEndTest.ps1` e `.github/workflows/e2e.yml`: teste com WireSock real
  no GitHub Actions (disparo manual).

## O que já foi visto em Windows real

- O pacote certo do winget é `NTKERNEL.WireSockVPNClientCLI` (traz
  `sdk\wiresock-client.exe`). O pacote com interface gráfica não traz esse arquivo.
- Assinante do executável: `The Anti-Cloud Corporation` (fixado no código).
- Comando: `wiresock-client.exe run -config <arquivo> -log-level <nível>`.
- O `wiresock-client` precisa de administrador. Sem isso falha com
  `Windows Packet Filter driver is not available!`.
- `AllowedApps` captura o tráfego de um processo chamado `Discord.exe` e deixa os outros de fora.
- No nível `debug` o WireSock lista os programas com conexão aberta. Essas linhas são
  descartadas antes de ir para o disco (`Test-VglLogNoise`).

## O que ainda falta verificar

1. O túnel subir no PC do dono com a configuração Proton real (a primeira tentativa falhou
   por falta de elevação, já corrigida, mas ainda não testada de novo lá).
2. Qual linha do log do WireSock confirma o handshake. Os padrões em
   `HandshakePatterns` são palpites. Depois de saber, ajustar os padrões e avaliar baixar
   o nível de log de `debug` para `info`.
3. Se o Discord libera o Go Live e a câmera passando pelo túnel. É a premissa do projeto.
4. A janela vista na tela e clicada por uma pessoa.

## Entregas finais ainda devidas ao dono

- Roteiro de teste manual atualizado (`docs/TESTE-MANUAL.md`).
- Texto curto em português para ele mandar aos amigos (baixar, conferir e usar).
