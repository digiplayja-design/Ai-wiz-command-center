# KORLIX POS shared practice workspace

The same `PosScreen` is used by the standalone shell and the opt-in KORLIX AI route. `PosWorkspace` supplies deterministic cent-based cart, inventory, kitchen, cash sale and reversal operations. Persistence is injected so failures can be tested without a device or network.

```sh
flutter pub get
flutter test
flutter analyze
```

No real payment or production record is created. This client-side model must not be used as the authoritative ledger for a live merchant. See the project release record for the required server transactions, staff permissions, session integration and hardware/payment validation.
