# Language features research (haiku agent) — with lead-agent annotations

## Confirmed SE mapping (trust)
- SE-0478 default MainActor isolation, SE-0466 -default-isolation module control, SE-0461 nonisolated(nonsending)+@concurrent → Swift 6.2
- SE-0495 @c attribute, SE-0491 module selector `::` → Swift 6.3 (release blog confirms @c SHIPPED in 6.3)
- SE-0493 async defer, SE-0516 Iterable (né BorrowingSequence), SE-0522 @diagnose, SE-0507 borrow/mutate accessors, anyAppleOS → Swift 6.4 beta
- InlineArray formerly "Vector" (SE-0453); @concurrent often conflated with old SE-0302 — the 6.2 one is SE-0461.

## ERRORS (lead annotations)
- Agent listed Span (SE-0456) and InlineArray (SE-0453) under 6.4 — WRONG: both shipped in Swift 6.2; WWDC26 just re-promoted them.
- Release dates slightly off: 6.2 = Sept 2025 (not March); 6.3 = March 24, 2026 (not April).
