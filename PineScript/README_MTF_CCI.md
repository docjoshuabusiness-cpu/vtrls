# MTF CCI Confluence — protocollo di taratura

Ordine obbligato. Saltare un passo significa non sapere quale parametro sta
producendo il risultato.

## 0 · Prima di tutto: misura la banda
Accendi solo il modulo stallo, `coil` SPENTO. Guarda la riga "stallo" del
cruscotto: ogni cella mostra la percentuale di barre in cui quella sezione sta
dentro la sua banda.

- sopra il 70% → la banda non filtra, allargala verso il basso (30-40) o cambia `len`
- sotto il 15% → stai chiedendo un evento raro, il campione non crescera' mai
- 40-55% e' l'intervallo in cui la banda separa davvero due stati

Questo numero dipende da `len` e dal simbolo, non c'e' un valore universale.

## 1 · Accendi il coil
`coil` ON, soglia 1.0. Guarda la cella "epi": confermati/grezzi.

- rapporto vicino a 1 → il coil non sta filtrando: abbassa la soglia a 0.8
- rapporto sotto 0.2 → troppo severo, il campione muore

Il coil e' l'unica misura del gruppo che distingue accumulazione da "prezzo
vicino alla media mentre si muove".

## 2 · Persistenza
Alza `persistenza` finche' la durata media (cella "med") smette di essere
dominata da episodi di 2-3 barre. Unita' consigliata: candele della sezione
dominante.

## 3 · Il segnale: attraversamento a chiusura candela

Configurazione di default, che e' esattamente la regola "BUY quando il CCI
supera +50 a chiusura candela, SELL quando scende sotto -50":

    serie che rompe = S3        (5m con i timeframe di default)
    lettura         = Nativo    (chiusura candela della sezione)
    livello         = 50
    direzione       = Continuazione
    solo da dentro la banda = ON
    episodio di stallo confermato = OFF

In lettura NATIVA il valore della sezione cambia una volta per candela, quindi
l'attraversamento cade sulla prima barra del grafico dopo la chiusura di quella
candela e non puo' ripetersi dentro la stessa candela. In lettura LIVE la stessa
candela puo' produrre tre attraversamenti dello stesso livello: e' l'errore piu'
costoso di questo gruppo, e nessun "emetti a barra chiusa" lo corregge, perche'
quella opzione conferma la barra del GRAFICO, non la candela della sezione.

"Solo da dentro la banda" e' cio' che distingue un'uscita dalla zona di stallo
da un CCI che attraversa +50 mentre sta gia' risalendo da -200.

## 4 · Irrigidire, misurando
`livello di rottura` = banda (50) significa "la candela ha chiuso fuori dalla zona".
Alzarlo a 100 pretende altri 50 punti oltre il bordo. Confronta, a parita di
campione e su almeno 30 osservazioni:

- continuazione vs reversione
- efficienza minima 0 vs 0.45 vs 0.6

Il criterio non e' "quanti segnali" ma il p80 della MAE nella riga MAE, colonna
K. Un setup con meta' dei segnali e p80 dimezzato e' strettamente migliore.

## 5 · Stop
`Bordo dello stallo` e' lo stop naturale della rottura: se il prezzo rientra dal
lato opposto del coil, la rottura e' falsa per costruzione. Confrontalo con
MAE p80 nella riga "stop cons.". Se il bordo e' piu' stretto del p80 stai
uscendo dentro la banda di rumore misurata.

## Errori di taratura piu' probabili
1. Lettura LIVE per lo stallo su grafici a secondi: gli episodi si moltiplicano
   per dieci e la persistenza conta oscillazioni intracandela, non candele.
2. Filtro COMPRESSIONE (8c) applicato alle rotture: chiede il contrario di cio'
   che la rottura e'. Lasciarlo agli estremi.
3. Sommare la MAE degli estremi con quella delle rotture: sono due ipotesi
   diverse, la media non descrive nessuna delle due.
4. Cinque sezioni tutte attive credendo che siano cinque conferme: sono CCI
   dello stesso prezzo, fortemente collineari. Misura K=2,3,4,5 prima di
   decidere.
