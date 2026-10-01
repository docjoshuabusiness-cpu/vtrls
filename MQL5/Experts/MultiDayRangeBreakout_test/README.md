# MultiDayRangeBreakout

`../MultiDayRangeBreakout.mq5` e' la **v3.00**, riscrittura della v2.00 (nella storia di git: commit "v2.00 cosi' come ricevuto"). Stessa idea: nella finestra di entrata si piazza una coppia di ordini stop (BuyStop sopra il massimo del range, SellStop sotto il minimo), quando uno scatta l'altro viene cancellato, gli ordini non eseguiti scadono a fine finestra, poi stop loss, take profit, break even e trailing.

Non e' stato compilato con MetaEditor (non disponibile qui): compilare con F7 e segnalare gli errori con il numero di riga. La logica e' stata provata traducendo l'EA in C++ e facendolo girare contro un MT5 simulato (sotto).

## Cosa non andava nella v2.00
Misure sulle stesse serie sintetiche (26 settimane, parametri del file), v2 contro v3:

| | v2.00 | v3.00 |
|---|---|---|
| Range "di ieri" corretto (10 settimane, barre H1) | 7 giorni su 48 (lunedi' quasi giusto, martedi'-venerdi' **tutti sbagliati**: usa il giorno prima di ieri) | 48 su 48 |
| Tick con ordini pendenti fuori dalla finestra di entrata | 66% (nessuna scadenza: gli ordini non scattati restano vivi per giorni) | 0 |
| Posizioni aperte fuori dalla finestra | 20 su 43 | 0 |
| Ordine gemello cancellato dopo l'esecuzione | fino a 480 s dopo (limite di 5 minuti sui tentativi) | stesso tick |
| Giorni con piu' posizioni del massimo | 2 | 0 |
| Righe di log al giorno (parametri del file) | 385 | 2,7 |
| Righe di log al giorno con il range sempre scartato | 6192 | 1,1 |
| Livello minimo degli stop del broker a 50 punti: richieste rifiutate | 495 su 873 (modifiche dello SL del trailing, a ogni tick) | 0 su 247 |
| Posizione ancora aperta dal giorno prima | piazza una coppia di ordini e la cancella 5 minuti dopo | non piazza nulla |

Cause, nel codice della v2:
- `CalculateBarRangeForDate` parte dalla mezzanotte di ieri e prende le barre **precedenti**: il "range di ieri" e' quello del giorno prima. Il martedi' e' quello del venerdi'.
- Gli ordini non hanno scadenza e `CancelPendingOrders` e' dentro la funzione con il limite di 5 minuti e dopo altri `return`: la finestra 10:00-11:00 limita solo il piazzamento, non l'esecuzione.
- Il prezzo dell'ordine viene spostato vicino al mercato se il range e' gia' stato rotto (`priceBuy = mid + minStop + 10`): cambia la strategia senza dirlo, e lo SL parte dal prezzo spostato.
- `OrderSend()` restituisce true anche se la richiesta non e' stata eseguita (la documentazione dice di controllare `retcode`): `pendingOrdersPlaced` e il conteggio dei trade si basano su quel valore.
- `PositionSelect(_Symbol)` senza filtro sul magic: BE e trailing toccano anche posizioni manuali o di altri EA sul simbolo; su conti hedging gestisce una sola posizione. `PositionsTotalByMagic` ha lo stesso difetto.
- `AllowNewTradeIfPositionHeld`: i nuovi ordini venivano cancellati 5 minuti dopo perche' c'e' una posizione aperta.
- `MaxTradesPerDay` non veniva mai applicato con `OneTradePerRange = false` (il contatore cresce solo dentro `if(OneTradePerRange)`).
- `IsMarketOpen()` stampa a ogni tick con il mercato chiuso (e `DisplayInfo` la chiama a ogni tick); `ShouldCalculateNewRange` ricalcola il range a ogni tick quando e' scartato, con un `Print` ogni volta. I messaggi piu' frequenti nella prova: "Venerdi' dopo 22:00 GMT" (12960), "Range non valido" (11520), "Lunedi' prima 01:00 GMT" (8160).
- Trailing: a ogni tick prova a modificare lo SL anche quando il broker lo rifiuta (livello minimo degli stop), senza pausa.
- Nessun filtro di spread; `type_filling` non impostato (il default e' FOK, che alcuni simboli non accettano); lotto non normalizzato al passo del simbolo.

## Cosa cambia nella v3
- **Un solo parametro per il range**: `RangeMode` = ultime N barre, finestra oraria, oppure massimo/minimo di giorni D1 (sostituisce `EnableMultiDayTrading`, `UsePreviousDayRange`, `UseBarRange`, `UseTimeRange`). Il "giorno di riferimento" e' l'N-esimo giorno di mercato prima di oggi, contato con le barre D1: il lunedi' 1 = venerdi'. `RangeDaysBack = 0` da' il range rolling (barre) o il range di oggi (orario, per esempio il range asiatico 00:00-08:00).
- **Gli ordini vivono solo nella finestra** (piu' `ExpireExtraMinutes`): scadenza dal broker se il simbolo la supporta, e in ogni caso cancellazione da parte dell'EA.
- **OCO immediato**: appena c'e' una posizione i pendenti vengono cancellati nello stesso tick.
- **Prezzo gia' oltre il livello**: di default non piazza nulla e aspetta il rientro nel range fino a fine finestra; `ChaseIfBroken = true` ripristina il comportamento della v2.
- Risultati di `OrderSend` controllati su `retcode`; filling impostato dal simbolo; volume normalizzato; se il SellStop fallisce il BuyStop viene cancellato.
- **Filtro di spread** (`MaxSpreadPoints`, `MaxSpreadPctOfSL`, default 15% dello SL).
- Un solo posto per BE e trailing, solo sulle posizioni dell'EA (simbolo + magic), rispettando livello minimo degli stop e livello di congelamento, pausa di 5 s dopo un rifiuto.
- Contatori del giorno riletti dalla storia: un riavvio dell'EA a meta' giornata non raddoppia la coppia ne' i trade.
- Log solo sugli eventi; pannello aggiornato al massimo una volta al secondo; linee del range sul grafico.
- **Rimossi**: `OneTradePerRange`, `ResetOnNewDay`, `TradeSameDayOnly` (non hanno senso con un range per giorno), `AvoidMidnightHours` (gli ordini scadono a fine finestra), `AllowNewTradeIfPositionHeld` (con una posizione aperta non si piazza nulla). Se serve davvero sovrapporre posizioni su conto hedging va riscritto a parte.
- Default come nella v2 (SL 100, TP 200, BE 100/10, trailing 150/20/30, finestra 10:00-11:00 ora server, magic 123456). Con la v2 il range massimo di 500 punti scarta quasi tutti i giorni su un cambio a 5 cifre: ne servono circa 1000-2000.

## Banco di prova (`MultiDayRangeBreakout_test/`)
`./run.sh` traduce l'EA con `MarketProfiler/tests/translate.py` (qui esteso per ignorare `input group`), lo compila con `-Wall -Wextra -Wshadow` contro `ea_rt.h` e lo esegue. `ea_rt.h` e' un MT5 finto: barre costruite dai tick (M1-D1), ordini stop con scatto al prezzo di mercato, SL/TP, scadenze, storia di ordini e operazioni, controlli sugli stop minimi, scadenza e filling del simbolo; `CTrade` sopra `OrderSend`.

Prove (`./run.sh v3 <nome>`; `./run.sh v2 <nome>` per l'originale): `range` (10 modalita' contro un calcolo indipendente dalle serie), `held`, `stops` e `spam` (confronto con la v2), `life` (26 settimane: niente pendenti fuori finestra, niente posizioni fuori finestra, OCO nello stesso tick, SL mai arretrati, zero rifiuti), `manage` (BE e trailing su un rialzo e un ribasso costruiti a mano, passo minimo e distanza), `restart` (riavvio con coppia viva, con posizione chiusa, con posizione aperta), `spread`, `chase`, `expiry` (broker senza scadenza specifica), `random` (24 combinazioni casuali di parametri e vincoli del broker: stop minimo, congelamento, filling, passo del lotto, 3 o 5 cifre), `pnl` (serie senza tendenza: nessun vantaggio nascosto). `python3 mutants.py` introduce 9 guasti nell'EA, uno alla volta (niente OCO, niente scadenza, range sbagliato di un giorno, ecc.) e verifica che almeno una prova li trovi.

Limiti: e' una simulazione della logica di controllo, non di MT5. Non copre conti netting, requote, orari di sessione del broker, swap, commissioni, slittamento reale su ordini stop; non dice nulla sulla redditivita'. Il test `pnl` mostra solo che su una serie senza tendenza l'EA perde i costi (circa -0,10 R per posizione con SL 100, spread 8-12 punti): per guadagnare serve un vantaggio reale di almeno quella misura.
