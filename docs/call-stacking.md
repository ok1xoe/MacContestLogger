# Call stacking

When several stations answer a CQ, call stacking lets you note the extra calls and work them one after
the other without typing them again — N1MM Logger+ "Single Operator Call Stacking", "Digital Call
Stacking" and partner call stacking. MacContestLogger has **one stack** for all of them: the calls you
stack yourself, the calls clicked in the Digital Interface and the calls a partner sends over the
network all wait in the same list.

## The stack line

As soon as a call is stacked, the info strip of the entry window shows **"ZÁSOBNÍK K1ZZ JA1ABC
(Alt+G)"** (STACK …) — the calls in the order in which they will come off the stack.

- At most **10** calls; the oldest falls out when an eleventh comes.
- **Dupes are never stacked** ("… je dupe — do zásobníku nejde"), and a call that becomes a dupe
  while it waits (you worked it in the meantime) is skipped.
- A call already on the stack is not added twice.
- **A band change clears the stack** (the calls answered on the old run frequency). The option is
  in **Settings → Function Keys → Call stacking** and is on by default.

## Order

**Settings → Function Keys → Call stacking → Order off the stack**:

| Order | Next call |
|---|---|
| **FIFO, mults first** (default) | the call that brings the most new multipliers; among equal ones the one stacked first. N1MM does this in CW and SSB. |
| **FIFO** | the call stacked first |
| **LIFO** | the call stacked last |

The multiplier value is evaluated at the active entry window's frequency and mode at the moment the
next call is taken, so it follows the QSOs logged in the meantime.

## Putting calls on the stack

| Key / macro | Action |
|---|---|
| **Ctrl+Alt+G** or `{STACKANOTHER}` | the call from the call field goes on the stack and the entry window is wiped for the next call (`{STACKANOTHER}` only in Run) |
| `{SOCALLSTACK}` (Run only) | a single-level stack: with an empty stack the call is stacked and the field cleared; with a stacked call the field and the stack are **exchanged**; with an empty field the stacked call comes back. With an empty stack a dupe does nothing. |
| **Option+click** on a call in the Digital Interface | the clicked call goes on the stack, the call field stays (N1MM Alt+click) |
| a partner's **Do zásobníku** | see [Multi-op and the network](multi-op.md#partner-and-call-stacking) |

## Taking calls off the stack

| Key / macro | Action |
|---|---|
| **Alt+G** (also Ctrl+Alt+K) | the entry window is wiped and the next call comes into the call field (no QSO is logged) |
| **Alt+D** with an empty call field | deletes the next call without working it (with a call in the field Alt+D removes its spot, as before) |
| `{CLRSTACK}` | clears the stack |
| `{LOGTHENPOP}` / `{LOGTHENNEXT}` (Run only) | logs the QSO and starts the next one, see below |

## {LOGTHENPOP}: log and go on

`{LOGTHENPOP}` in an F-key message splits the message:

- the text **before** the macro is sent to the station being logged,
- the QSO is logged,
- the next call comes off the stack into the call field,
- the text **after** the macro is sent to the **next** station — `!`, `#`, `{F5}` and `{F2}` already
  mean the new QSO.

The suggested Next Call message (N1MM): **`! {LOGTHENPOP} TU {F5}{F2}`** — in CW it sends "DL1ABC TU
K1ZZ 5NN 15" in one go, so the pileup does not start again. Use `{F5}{F2}` rather than `!` and the
exchange text itself; the ESM progress of the next QSO follows the keys the message refers to
(`{F2}` = the exchange was sent), so the next Enter in ESM is already the TU of the new QSO.

- With **nothing on the stack** the QSO is logged and the **TU message (F3)** is sent instead of the
  rest of the message.
- `{LOGTHENPOP}` never logs an incomplete QSO: **outside Run**, **before the exchange was sent**
  (F2) or with an **incomplete received exchange** the key sends nothing and the status line says
  why.
- `{LOGTHENNEXT}` does the same, but ESM never chooses it by itself.
- In **SSB** (voice keyer) the stack macros run **before** the message plays, wherever they are in
  it: `{LOGTHENPOP},tu.wav,{F5},{F2}` logs, takes the next call and then plays the whole message to
  it.

## ESM: the Next Call key

**Settings → Function Keys → Call stacking → Next Call key (ESM)** chooses the F-key that holds
`{LOGTHENPOP}` (for example F12; "none" turns the automation off). In Run, when the next Enter would
send TU (F3) and log, and a call waits on the stack, ESM sends this key instead — it logs, thanks,
and sends the exchange to the next call. When the stack is empty, Enter sends the normal TU again.
The key must hold `{LOGTHENPOP}` in the message set of the current mode (CW, SSB or digital); a key
with `{LOGTHENNEXT}` is never chosen. See [ESM](esm.md#call-stacking).

Example (CW, Run, ESM on, F12 = `! {LOGTHENPOP} TU {F5}{F2}`, Next Call key F12):

1. K3CT and N2IC call. Type K3CT, press **Ctrl+Alt+G**, type N2IC and press **Enter** (F5+F2).
2. Copy N2IC's exchange and press **Enter**: N2IC is logged, "N2IC TU K3CT 5NN 15" is sent, K3CT is
   in the call field.
3. Copy K3CT's exchange and press **Enter**: TU, logged — the stack is empty.

## Digital Interface

In the Digital Interface window **Option+click** on a call stacks it. **Nastavení → Digitální
zásobník volaček** (Setup → Digital Call Stacking; also in Settings → Function Keys) turns on N1MM's
Digital Call Stacking: in **Run**, with a call already in the call field, a plain click on another
call

- **FIFO / FIFO mults first**: puts the clicked call on the stack (the call field stays),
- **LIFO**: puts the call from the field on the stack and the clicked call into the field.

The order chosen there is the stack's order for all modes. See
[Digital modes](digital-modes.md#call-stacking).
