# VoltaGoLive

Coloca **somente o Discord** dentro de um túnel WireGuard (ProtonVPN gratuito) no Windows.
O resto do computador continua usando a sua conexão normal.

> **English summary.** VoltaGoLive is a small, readable PowerShell tool for Windows that
> routes only Discord (Stable, PTB and Canary) through a WireGuard tunnel, using
> [WireSock](https://wiresock.net/) and its `AllowedApps` setting. You bring your own
> WireGuard `.conf` (for example from a free Proton VPN account). Nothing else on the PC
> goes through the tunnel. No compiled binaries, no credentials stored, logs are redacted.
> It is not affiliated with Discord, Proton or WireSock. The documentation is in Portuguese.

## Avisos importantes

- **Uso por sua conta e risco.** Usar VPN para contornar restrições regionais pode violar os
  Termos de Serviço do Discord. Cada pessoa é responsável pelo próprio uso e pelas
  consequências na própria conta.
- **Sem afiliação.** Este projeto não tem nenhuma ligação com Discord, Proton ou WireSock.
  Os nomes pertencem aos respectivos donos.
- **O que foi e o que não foi testado.** Leia a seção
  [Estado dos testes](#estado-dos-testes) antes de confiar no projeto.

## O que é

Um conjunto de scripts PowerShell (que você pode abrir e ler) com quatro botões de dois cliques:

| Arquivo | O que faz |
| --- | --- |
| `Ativar.bat` | Fecha o Discord, sobe o túnel só para ele e abre o Discord de novo |
| `Desativar.bat` | Derruba o túnel, limpa os arquivos temporários e abre o Discord normal |
| `Status.bat` | Mostra se o túnel está ativo, há quanto tempo e o último handshake |
| `Diagnostico.bat` | Gera um relatório sem dados pessoais para você pedir ajuda |

## Como funciona

```text
                         +---------------------------+
   Discord.exe  -------> |  túnel WireGuard (Proton) | -----> internet (saída em outro país)
   DiscordPTB.exe        +---------------------------+
   DiscordCanary.exe            ^
                                |  WireSock decide por programa (AllowedApps)
                                |
   navegador, jogos,  ----------+-----------------------------> internet (sua conexão normal)
   todo o resto
```

1. Você baixa, na sua conta Proton, um arquivo de configuração WireGuard (`.conf`).
2. O VoltaGoLive faz uma **cópia** desse arquivo e acrescenta nela a linha
   `AllowedApps = Discord.exe, DiscordPTB.exe, DiscordCanary.exe`. O seu arquivo original
   nunca é alterado.
3. O [WireSock](https://wiresock.net/) sobe o túnel usando a cópia. Com essa linha, só os
   programas listados usam o túnel.
4. Ao desativar, o túnel cai e a cópia é apagada.

O VoltaGoLive **não** pede nem guarda usuário ou senha da Proton, não inclui nenhum
programa compilado e não redistribui o WireSock (ele é instalado da fonte oficial).

## Requisitos

- Windows 10 ou 11.
- Discord instalado (versão normal, PTB ou Canary).
- Uma conta Proton VPN (a gratuita serve).
- WireSock Secure Connect (o `Ativar.bat` oferece a instalação).

## Passo a passo

### 1. Baixe e confira o VoltaGoLive

1. Na página de [Releases](https://github.com/juvxncio/VoltaGoLive/releases), baixe o
   arquivo `VoltaGoLive-vX.Y.Z.zip`.
2. Confira o download (opcional, mas recomendado): veja [Como conferir o SHA256](#como-conferir-o-sha256-do-zip).
3. Clique com o botão direito no zip, escolha **Propriedades**, marque **Desbloquear** (se
   aparecer) e clique em OK.
4. Extraia o zip numa pasta simples, por exemplo `C:\VoltaGoLive`.

### 2. Baixe a sua configuração na Proton

1. Entre em <https://account.protonvpn.com> com a sua conta.
2. Vá em **Downloads** e depois em **WireGuard configuration**.
3. Dê um nome qualquer, escolha a plataforma **Windows** e um servidor **fora do Brasil**.
4. Clique em **Create** e depois em **Download**. Você recebe um arquivo `.conf`.
5. Coloque esse arquivo dentro da pasta `config`, que fica ao lado do `Ativar.bat`.
   Deixe só um arquivo `.conf` nessa pasta.

> O arquivo `.conf` contém a sua chave. Não envie para ninguém e não publique em lugar nenhum.

### 3. Ative

1. Dê dois cliques em `Ativar.bat`.
2. Na primeira vez, se o WireSock não estiver instalado, responda `S` para instalar. O
   Windows vai pedir permissão de administrador, porque o WireSock instala um driver de rede.
3. Espere a mensagem verde `Pronto! O túnel está ativo`.
4. No Discord, teste o Go Live e a câmera.

### 4. Desative quando terminar

Dê dois cliques em `Desativar.bat`. O Discord volta para a conexão normal.

Se você desligar ou reiniciar o computador, o túnel cai sozinho. Rode o `Ativar.bat` de novo
quando precisar.

## Como conferir o SHA256 do zip

Cada release traz um arquivo `SHA256SUMS` com a "impressão digital" do zip. Para conferir:

1. Abra a pasta onde o zip foi baixado, clique na barra de endereço, digite `powershell` e
   aperte Enter.
2. Rode (trocando o nome pelo do arquivo que você baixou):

   ```powershell
   Get-FileHash .\VoltaGoLive-v0.1.0.zip -Algorithm SHA256
   ```

3. Compare o valor mostrado em `Hash` com o que está no arquivo `SHA256SUMS` da release
   (maiúsculas e minúsculas não importam). Se for diferente, **não use o arquivo**.

## Solução de problemas

| O que aparece | O que fazer |
| --- | --- |
| `Não encontrei nenhum arquivo .conf na pasta "config"` | Refaça o passo 2 e coloque o `.conf` na pasta `config` |
| `Há N arquivos .conf na pasta "config"` | Deixe só um arquivo `.conf` na pasta |
| `O arquivo .conf tem problemas` | Baixe o arquivo de novo na Proton, sem editar |
| `O WireSock não está instalado` | Rode o `Ativar.bat` e responda `S`, ou instale pelo [site oficial](https://wiresock.net/wiresock-secure-connect/download) |
| `O winget não está disponível` | Instale o WireSock pelo [site oficial](https://wiresock.net/wiresock-secure-connect/download) |
| `não tem uma assinatura digital válida` | Reinstale o WireSock pelo site oficial. Por segurança o VoltaGoLive não executa arquivos sem assinatura válida |
| `O WireSock não ficou em execução` | Rode o `Diagnostico.bat` e envie o relatório |
| `não consegui confirmar o handshake` | Teste o Go Live mesmo assim. Se não funcionar, baixe uma configuração de outro servidor na Proton e tente de novo |
| O túnel ativa, mas o Go Live continua bloqueado | Confira se o servidor escolhido na Proton fica fora do Brasil. Rode o `Diagnostico.bat` e veja se `AllowedIPs cobre IPv6 inteiro` está como `True`; se estiver `False` e a sua internet usar IPv6, parte do Discord pode estar saindo fora do túnel |
| O Windows mostra "O Windows protegeu o computador" | Clique em **Mais informações** e em **Executar assim mesmo**. Isso acontece com arquivos baixados da internet |
| A transmissão fica lenta | O plano gratuito da Proton tem velocidade limitada. Tente outro servidor |

Para pedir ajuda, rode o `Diagnostico.bat`. Ele gera um relatório **sem** chaves, endereços
IP, seu nome de usuário, nome do computador ou caminhos da sua pasta pessoal, e já copia o
texto para você colar.

## Perguntas frequentes

**O resto do meu computador passa pela VPN?**
Não. Só os programas do Discord listados no `AllowedApps`.

**Vocês guardam minha senha da Proton?**
Não. O VoltaGoLive nunca pede usuário nem senha. Ele só usa o arquivo `.conf` que você baixou.

**Meu arquivo `.conf` é alterado?**
Não. O túnel usa uma cópia, que é apagada quando você desativa.

**Por que não é um `.exe`?**
Programas compilados sem assinatura costumam ser marcados como suspeitos por antivírus, e
ninguém consegue ler o que eles fazem. Aqui tudo é texto: abra os arquivos da pasta `src` e leia.

**Posso usar outra VPN?**
Qualquer provedor que entregue um arquivo `.conf` WireGuard deve servir, mas só o da Proton
foi considerado no projeto.

**Posso usar o aplicativo da Proton ao mesmo tempo, em outro aparelho?**
O plano gratuito da Proton permite um aparelho por vez.

**O WireSock é gratuito?**
É gratuito para uso pessoal, segundo a [licença dele](https://wiresock.net/license/wiresock_eula).
A versão gratuita envia relatórios de falha para o fabricante por padrão. Isso pode ser
desligado nas configurações do WireSock.

**Onde ficam os arquivos do VoltaGoLive?**
Na pasta onde você extraiu o zip e em `%LOCALAPPDATA%\VoltaGoLive` (logs, estado e
relatórios de diagnóstico).

## Desinstalação limpa

1. Rode o `Desativar.bat`.
2. Apague a pasta onde você extraiu o VoltaGoLive (o seu `.conf` está dentro dela, na pasta `config`).
3. Apague a pasta de dados: aperte `Win + R`, digite `%LOCALAPPDATA%` e apague a pasta `VoltaGoLive`.
4. Se quiser remover também o WireSock: **Configurações > Aplicativos**, procure por
   **WireSock** e desinstale. Ou, no PowerShell: `winget uninstall NTKERNEL.WireSockVPNClient`.
5. Se quiser invalidar a configuração: em <https://account.protonvpn.com>, em **Downloads**,
   apague a configuração WireGuard que você criou.

O VoltaGoLive não cria serviços do Windows, tarefas agendadas nem entradas no registro.

## Privacidade e segurança

- Logs e relatórios passam sempre por uma redação que remove chaves, endereços IP, nome de
  usuário, nome do computador e caminhos do perfil.
- O código não lê variáveis de ambiente em massa. Lê só as necessárias, pelo nome.
- O WireSock só é executado se o arquivo tiver assinatura digital válida.
- Encontrou uma falha de segurança? Veja o [SECURITY.md](SECURITY.md).

## Estado dos testes

O que é verificado automaticamente a cada mudança, em Windows real (GitHub Actions):

- Leitura e validação do `.conf`, inclusão do `AllowedApps`, redação de dados, detecção do
  Discord e a ordem dos passos de ativar e desativar (com simulação do que depende de rede).
- PSScriptAnalyzer sem avisos, no Windows PowerShell 5.1 e no PowerShell 7.
- gitleaks e a verificação de que nenhuma chave entrou no repositório.

O que **não** tem como ser verificado automaticamente:

- Se o Discord libera o Go Live e a câmera quando passa pelo túnel.
- O comportamento com uma conta Proton real.

Veja o roteiro em [docs/TESTE-MANUAL.md](docs/TESTE-MANUAL.md) para testar no seu computador.

## Para quem quer contribuir

Veja o [CONTRIBUTING.md](CONTRIBUTING.md). Histórico de versões no [CHANGELOG.md](CHANGELOG.md).

## Licença

[MIT](LICENSE).
