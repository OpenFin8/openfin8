# openfin8 - Business Requirements & Functionality

> Consent-first financial data sharing: the open-finance vertical of
> the Sentin8 platform. Open banking for every jurisdiction; open
> finance as the umbrella.

> Audience: product owners, business analysts, and anyone evaluating
> what the openfin8 vertical **does for the business**. For the
> overview read `README.md`; for wire-level detail read each
> service's `DESIGN.md`.

---

## 1. Business Purpose

- **The consent authority for financial data sharing** - no
  customer data leaves an institution without a live, scope-limited,
  revocable consent, enforced structurally on every request.
- **Every jurisdiction, one platform** - US (FDX), Canada (FDX/CDX),
  UK (OBL), with Brazil, EU, and Australia designed on the same
  contract: a bank activates a market by enabling one service in an
  environment, not by porting software.
- **Independently sellable recipient plane** - a recipient-only
  fintech (no bank, no ledger) composes the recipient registry and
  connection flows standalone; it does not enroll a banking vertical.
- **Cross-sector by construction** - open finance extends past
  banking (payroll, investments, insurance, energy); the vertical owns
  the umbrella so new data families need no second re-homing.

## 2. Business Scope

| # | Capability block | What the business gets | Delivered by |
|---|---|---|---|
| 1 | Consent control | No consent, no data: every provider route passes consent middleware on top of RLS; revocation stops serving on the very next call | openfin8-core + adapters |
| 2 | Consent lifecycle | ACTIVE → REVOKED (reason + initiator) or ACTIVE → EXPIRED via duration windows; expiry is introspection-driven, never cached | openfin8-core |
| 3 | Data minimization | Responses are projected to granted CSDF clusters before serialization, narrowed by scope, product category, and requested fields; unknown scopes grant nothing | openfin8-core (csdf) |
| 4 | Recipient onboarding | External recipients register dynamically (RFC 7591/7592 DCR) with sender-constrained tokens; no static recipient list | openfin8-core (two-ledger registry) |
| 5 | Money movement | Recipient-initiated transfers/payments are consent-checked by OpenFin8 and executed by Bank8:Payments - one executor | adapters → Bank8:Payments |
| 6 | Notifications | HMAC-signed webhook notifications per subscription with retry backoff; exhausted deliveries are triaged, never dropped | openfin8-core |
| 7 | Certification evidence | Per-market conformance evidence from audited traffic (FDX certification metrics; OBL conformance suite when UK lands) | adapters |
| 8 | Provider discovery | The cross-env provider catalog: recipients find and connect to any active provider | openfin8-core |

**Out of scope (owned elsewhere):** account/transaction data
(Bank8:Ledger - read via its public API), statement bytes
(Sentin8:Storage), money movement execution (Bank8:Payments),
identity/sign-in/consent ceremony hosting (Sentin8:Auth), workflow
execution (Sentin8:Flow), scheduling (Sentin8:Cron).

## 3. The Markets

| Market | Standard | Regulatory posture | Business rule |
|---|---|---|---|
| Canada | FDX v6.x | Consumer-driven banking (2026 framework target) | The bank serves `/fdx/v6/*`; version per environment (`OPENFIN8_CA_VERSION`) |
| US | FDX v6.x | CFPB-recognized standard-setting body (§1033) | Identical surface, independent version cadence (`OPENFIN8_US_VERSION`) |
| UK | OBL R/W API | CMA order + PSD2/FCA - mandated | Serving: ASPSP obligations, FAPI ceremony, intent consents |
| Brazil | Open Finance Brasil | Central Bank mandated | Designed: consent-resource + PIX initiation + ICP-Brasil mTLS |
| EU | Berlin Group openFinance | PSD2 → PSD3/FDA in flight | Serving: SCA approaches, eIDAS certificates |
| Australia | CDR | ACCC accreditation regime | Designed: CDR Register, sharing arrangements, consent dashboards |

## 4. Business Events

Family per adapter (`openfin8:ca:*` etc.), grammar
`openfin8:{xx}:{resource}:{operation}`: consent created/revoked/
expired, recipient registrations, PIP parties, notification
subscriptions - consumed by recipient-side reconciliation and the
delivery worker.

## 5. Composability Contracts

- **bank8 composes OpenFin8** (the provider role): the bank enables
  `openfin8:ca` in its env; its data plane (Ledger/Payments) is
  consumed via public APIs + the `bank8::` SDK contracts only - the
  OBVERT invariant (no bank8 database access from OpenFin8).
- **Recipient institutions compose OpenFin8 standalone**: the
  two-ledger registry is per recipient environment; a fintech needs no
  banking services to run connection flows.
- **Cross-vertical data families** (future: payroll, investments,
  insurance): new provider adapters read their sources the same way -
  public API + contracts - never another vertical's database.

## 6. Key Invariants (business-facing)

- No provider route bypasses consent middleware - structurally.
- Revoked consents are terminal; introspection can never revive one.
- No plaintext delegated tokens or webhook secrets in any column -
  secret references only.
- Out-of-scope data families return the standard's unsupported
  response, never stubbed data.
- Every jurisdiction change (version bump, capability) is per-
  environment configuration, not a redeployment of other markets.

---

**Architecture & Design:** openfin8 and its underlying concepts were
designed by [Hamid Jahanzad](https://www.linkedin.com/in/hamidjahanzad/).