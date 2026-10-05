# Run / S&P

The mode says whether you are calling CQ (**Run**) or hunting for stations (**S&P**).
It selects the set of F1–F12 messages (Run and S&P each have their own), changes the
behavior of ESM ([esm.md](esm.md)), and for each QSO it records the mode it was made in
(RadioInfo broadcast `IsRunning`). The behavior corresponds to N1MM+
([Run mode and S+P mode](https://n1mmwp.hamdocs.com/manual-windows/entry-window/#Run_mode_and_S_P_mode)).

## CQ frequency

- **F1 (CQ)** or switching to Run remembers the **CQ frequency** of the band. Each
  band has its own.
- The entry window shows it next to the Run/S&P switch (e.g. `CQ 14025.0`),
  and the bandmap shows it as a dashed line with a **CQ** marker.
- **QSY away** from the CQ frequency (by more than 300 Hz in CW and digital, 1 kHz in phone)
  switches to **S&P**.
- **Returning to the CQ frequency** of the band switches back to **Run**.
- Clicking the **CQ** marker in the bandmap returns the rig to the CQ frequency and switches to Run.

## Keys

| Key | Action |
|---|---|
| **Alt+U** | toggles Run / S&P. Switching to Run sets the CQ frequency to the current one |
| **Alt+Q** | back to the band's CQ frequency, Run, clears the fields |
| **Alt+F11** | turns automatic switching off / on (DXpeditions, several Run stations on a band) |
| **F1** | CQ: in S&P switches to Run |
| **Shift+F1…F12** | sends a message from the opposite set (in Run an S&P message and vice versa) |
| held **Shift** | the F-key grid shows the labels of the opposite set |

On a Mac, Alt is the **Option** key.

## Options (Settings → Function Keys → Run / S&P)

- **Automaticky přepínat** (Switch automatically) (on by default). Alt+F11 or the DXLog text
  commands `AUTORSP` / `NOAUTRSP` do the same. When it is off, the window shows "manual
  Run/S&P".
- **Návrat na CQ frekvenci přepne do Run** (Returning to the CQ frequency switches to Run) (on by default). Turning it off is useful
  in sprints: QSY away still switches to S&P, but you return to Run only with F1 or
  Alt+Q (N1MM "Do not automatically switch to Run on CQ-frequency").
