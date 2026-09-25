# K203G reviewed repeated CSV rows

During statement preview, identical date, signed amount and case-insensitive description rows are flagged as repeated. The owner may check the original bank statement, confirm that every flagged line is a separate transaction, and enter a 10–500 character explanation before import. Invalid rows still block import. The confirmed explanation is submitted with the same request key and payload for safe retry after a lost response.

Saved statements marks imports with reviewed repeats, shows the explanation in detail, and includes it in the review CSV. Each line stays separate and must be matched individually to a different active recorded entry. Repeated rows from a different imported CSV remain conservatively blocked by the backend's overlap check. Neither the original CSV bytes nor any bank feed are stored.

Deploy the backend migration and API before this frontend. Verify with the bookkeeping widget suite and release web build.
