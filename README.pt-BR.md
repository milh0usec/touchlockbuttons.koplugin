# TouchLockButtons para KOReader

Plugin experimental do KOReader destinado ao **Kindle Paperwhite 4 (10ª geração)**. Ele acrescenta uma barra inferior reservada com cinco controles e, opcionalmente, um controlador para o botão físico Power.

> [!WARNING]
> Quando ativado, o controlador assume o controle exclusivo do botão Power. As ações nativas de clique curto e toque longo ficam temporariamente indisponíveis. Leia as instruções de recuperação antes de ativá-lo.

## Recursos

A barra inferior possui cinco segmentos de mesma largura:

| Posição | Controle | Ação |
|---|---|---|
| 1 | Página anterior | Toque: página anterior; toque longo: voltar 10 páginas |
| 2 | Trava da barra | Define se gestos fora da barra chegam ao KOReader |
| 3 | Indicador da touchscreen | Mostra se toda a touchscreen está ativada ou desativada |
| 4 | Suspender | Libera o controlador e coloca o Kindle em suspensão |
| 5 | Próxima página | Toque: próxima página; toque longo: avançar 10 páginas |

A barra reserva espaço próprio no layout e não deve encobrir o texto do livro nem a barra de status nativa.

### Controlador opcional do botão Power

Quando ativado em um PW4 compatível:

- **Um clique:** próxima página
- **Dois cliques:** página anterior
- **Três cliques:** ativa ou desativa toda a touchscreen
- **Toque longo:** ignorado pelo plugin

O bloqueio total da touchscreen é independente da trava da barra virtual. O indicador central utiliza os ícones Font Awesome 4 `toggle-on` e `toggle-off`; a trava usa `unlock` e `lock`; a suspensão usa `moon-o`.

## Compatibilidade

Consulte [COMPATIBILITY.md](COMPATIBILITY.md).

Alvo atual:

- Kindle Paperwhite 4 / 10ª geração (PW4)
- Firmware Kindle 5.14.2 como alvo de desenvolvimento
- KOReader 2026.07.1 recomendado para a primeira versão pública

Outros modelos e outros mapeamentos de eventos de entrada não são suportados sem validação específica. O daemon atualmente espera o botão Power em `/dev/input/event1`, código `116`.

## Instalação

1. Baixe o arquivo de release `touchlockbuttons.koplugin-vX.Y.Z.zip`.
2. Extraia o arquivo. Ele contém a pasta `touchlockbuttons.koplugin`.
3. Copie a pasta completa para:

   ```text
   /mnt/us/koreader/plugins/
   ```

4. Reinicie completamente o KOReader.
5. Em **Ferramentas → Gerenciamento de plugins**, confirme que o plugin está ativado.

Não copie apenas os arquivos internos: o nome da pasta precisa terminar em `.koplugin`.

## Configuração

Abra **Ferramentas → Botões virtuais**.

Opções disponíveis:

- **Bloquear gestos fora da barra por padrão**
- **Controlador do botão Power (PW4)**
  - Ativar suporte ao botão físico Power
  - Latência do clique: 200, 250 ou 300 ms
  - Dica de utilização
  - Estado atual da touchscreen

O warning de segurança é exibido sempre que o controlador físico é ativado.

## Recuperação e segurança

Antes de desativar a touchscreen, confirme que o controlador físico está ativo.

Para restaurar o touch normalmente, pressione o Power **três vezes** dentro da janela configurada. Se o controlador parar inesperadamente, o wrapper libera o bloqueio exclusivo do dispositivo de entrada e restaura a configuração de energia do Kindle. Como último recurso, utilize o procedimento normal de reinicialização forçada do Kindle.

Log do controlador:

```text
/tmp/touchlockbuttons-power.log
```

## Desenvolvimento

A raiz do repositório corresponde diretamente à pasta do plugin. Para uma instalação de desenvolvimento, clone o repositório como:

```text
/mnt/us/koreader/plugins/touchlockbuttons.koplugin
```

Validação e empacotamento:

```sh
./scripts/validate.sh
./scripts/package.sh
```

Os arquivos finais são criados em `dist/`.

## Licenças

O código do plugin é distribuído sob a **GNU Affero General Public License v3.0 ou posterior**.

Os contornos de ícones derivados do Font Awesome 4.7.0 são distribuídos sob a **SIL Open Font License 1.1**. Consulte [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
