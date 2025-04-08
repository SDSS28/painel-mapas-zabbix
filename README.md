# Painel de Mapas do Zabbix

Script em HTML + JavaScript que alterna automaticamente entre diferentes mapas do Zabbix, exibindo-os em uma aba separada. Ideal para uso em monitores de operação, NOC ou dashboards internos.

## 🔧 Como funciona

- A página espera 30 segundos para que você possa fazer login no Zabbix.
- Em seguida, abre uma nova aba com o primeiro mapa.
- A cada 30 segundos, troca para o próximo mapa da lista.
- Funciona apenas se o Zabbix estiver acessível e autenticado.

## 📋 Requisitos

- Estar logado previamente no Zabbix.
- O navegador deve permitir pop-ups para este script funcionar corretamente.

## 🖥️ Como usar

1. Abra o arquivo `index.html` em um navegador.
2. Faça login no Zabbix, caso ainda não tenha feito.
3. Aguarde — a troca dos mapas será feita automaticamente em uma nova aba.

## 🧠 Dicas

- Pressione `F11` para entrar em **tela cheia** no navegador.
- Mantenha a aba do script aberta — ela controla a rotação.

## 🛠️ Personalização

Para mudar os mapas, edite o array `maps[]` no arquivo `index.html`, substituindo ou adicionando os `sysmapid` dos seus próprios mapas:

```js
const maps = [
  "http://seu-zabbix/zabbix.php?action=map.view&sysmapid=ID_DO_MAPA"
];
```

## 📌 Exemplo de uso

Usado na prefeitura de Guarapari/ES para visualização contínua dos mapas de monitoramento em painéis de TV.

---

Desenvolvido com 💻 por [Seu Nome Aqui]
