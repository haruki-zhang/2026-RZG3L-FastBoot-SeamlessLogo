# Fast-Boot Method: Patterns and Discipline

Generalised from the RZ/G3L phase-2b work, but nothing here is board-specific.
Applies to any systemd-based embedded Linux image.

---

## 1. Measurement discipline

Optimisation built on a wrong number is worse than no optimisation. Four rules.

**Pick an endpoint that corresponds to a real state.** Not "the prompt appeared",
not "the screen changed" — a state the init system can name (`graphical.target`,
a custom `app-ready.target`) or an instrumented first-frame timestamp. Console
prompts in particular are unreliable: a `Type=idle` getty deliberately waits for
the job queue to drain, so it can print seconds after boot has finished.

**Know each tool's time origin.** Per-unit blame, dependency chains, and
wall-clock plots often use different zero points (kernel start vs. userspace
start). Cross-referencing them with the wrong offset invalidates every
conclusion. Establish the offset once, from a value that appears in two tools.

**Triangulate; every tool has a blind spot.**

| Tool | Answers | Blind to |
|---|---|---|
| Per-unit duration (`blame`) | which units are slow | gaps belonging to no unit; whether slow = busy or blocked |
| Dependency chain (`critical-chain`) | one longest path | sibling constraints that finish just as late |
| Wall-clock plot (`plot`) | segment layout, gaps, object count | why a segment is long |
| Kernel log / audit records | kernel-side truth, process events | userspace intent |

A single tool will mislead. In this work the dependency chain named one service
as the gate while the plot showed a different one finishing 90 ms later.

**Report a distribution, not a best case.** Anything that blocks on a resource
produces boot-to-boot spread. Take ten boots, report P95. Treat variance itself
as a finding — it usually points at a blocking dependency.

---

## 2. Map the path before optimising

Boot time is not "the sum of slow services". Determine the shape first:

- If the path to the endpoint is **serial segments**, savings from different
  segments **add**. Attack segments, largest first.
- If it is a **parallel fan-out**, only the longest branch matters, and removing
  work elsewhere buys nothing but headroom.

Two consequences that are easy to get wrong:

**Rank segments, not units.** A per-unit ranking cannot see a gap that belongs
to no unit, and such gaps can be the largest single item on the path.

**Separate symptom from cause.** A unit that takes a long time to *become
active* is often waiting on a queue that something else filled. Optimising it
directly achieves nothing.

---

## 3. Why boot time exists: five kinds of cost

The useful question is not "what is slow" but "what kind of cost is this",
because each kind has a different fix.

| Kind | Signature | Fix | Typical size |
|---|---|---|---|
| **Volume** | real work, proportional to data | shrink the data | moderate, predictable |
| **Count** | many tiny operations, no single slow unit | reduce the number of objects | large, often invisible |
| **Blocking** | long duration, no CPU use | supply the missing resource | large, high variance |
| **Framing** | a unit far slower than the work it performs | change the abstraction | largest |
| **Ordering** | idle gaps between ready and started | remove false dependencies | moderate |

Volume is where intuition goes first and where returns are usually worst.
Count, Blocking, and Framing are where the large wins are — and all three are
poorly served by per-unit timing tools, which is why they survive so long.

---

## 4. Pattern: Count — objects the init system must model

**Principle.** Boot cost scales with the number of objects the init system
enumerates, not only with the work performed. Kernel configuration that creates
devices creates device events, which create init-system objects, which enter the
boot transaction and are processed serially.

**Why it hides.** No service is slow. Per-unit timing shows nothing. The cost
appears only as a segment in which nothing is running.

**How to find it.** Count, don't time. Enumerate the objects in the boot
transaction and group them by origin. A single kernel option that quietly
creates hundreds of legacy or compatibility devices is a common finding; so are
compatibility interfaces nothing has opened in twenty years.

**General rule.** Audit the boot by object census at least once. If one origin
accounts for a large fraction of all objects, it is almost certainly reducible
and almost certainly free of risk — nothing uses what nothing opens.

---

## 5. Pattern: Blocking — services that wait rather than work

**Principle.** A service with a long duration may be consuming no CPU at all. It
is waiting for a resource that is not yet available. The fix is to supply the
resource, never to optimise the service.

**Why it hides.** Duration looks identical to real work in every timing tool.
Only correlating with a kernel-side event ("resource became available") reveals
it — the service ends immediately after that event.

**Common blockers on embedded systems:** entropy, wall-clock time, network or
name resolution, device settle, a saturated event queue, a peer over IPC.

**Compound form: barrier targets.** A synchronisation target completes at
`max()` over its members. If several members finish within a short window of
each other, removing one promotes the next to be the new gate and buys almost
nothing. **Identify the near-simultaneous cluster and remove all of it in one
step.** This is also why a dependency-chain tool, which prints a single path, is
the wrong instrument here.

**General rule.** For every service on the path ask: *busy, or blocked?* Before
touching a barrier target, list every member that finishes within ~10% of it.

---

## 6. Pattern: Framing — work implied by the abstraction

**Principle.** The largest single cost is usually not the work the product
needs, but the general-purpose framework the distribution placed that work
inside. A fixed-function device inherits multi-user, multi-session, interactive
defaults it will never use.

**Why it hides.** It attributes cleanly to a unit, so it looks like the unit's
own cost. Nobody questions it because the unit genuinely is on the critical
path.

**How to find it.** Split a unit's start window into sub-intervals using a
second, independent source (process events in the kernel log; child units in the
plot). Then compare: *how much of this window is the payload, and how much is
the frame around it?* A large discrepancy is the finding.

Typical frames on an embedded HMI: login sessions and PAM stacks, per-user
service managers, seat/session management, service activation buses, generic
network and identity daemons.

**General rule.** For each unit on the critical path, ask what abstraction it
was placed in and whether the product needs that abstraction — not whether the
work is necessary. Often the work is 20% of the unit and the frame is 80%.

---

## 7. Cross-layer feature consistency

Removing a feature at one layer does not remove it at the others. Device tree,
kernel configuration, distro features, installed packages, and enabled services
are independent switches, and boot cost is paid by whichever switch is still on.

Practical check: for every feature the product does not have, verify it is off
at **all** layers. Disabled hardware with an enabled daemon, or a removed distro
feature with the subsystem still built into the kernel, are the two commonest
findings — and both are pure deletions with no risk.

---

## 8. Verify the change landed

Never assume a change took effect; verify the generated artefact, not the input.

Two failure modes seen in this work, both silent:

- A negative kernel-config entry was reverted because another enabled symbol
  `select`s it. Disabling the selector is what works.
- A config symbol had been removed upstream, so the entry was dropped entirely.
  Its behaviour had become an unconditional default — a *better* outcome, but
  the documentation asserting a prerequisite was now wrong.

**Rules.** Diff the produced configuration/rootfs, not the metadata. When
patching a file shipped by another recipe, assert the expected content is
present and fail the build loudly if not — otherwise an upstream update silently
reintroduces the cost. Prefer loud failure over silent degradation everywhere.

---

## 9. Sequencing and risk

Rank candidates by **saving ÷ blast radius**, not by saving alone.

1. **Deletions first** — removing work for absent features cannot regress
   behaviour, and they de-saturate the CPU, which shrinks neighbouring segments.
2. **Unblocking next** — supplying a missing resource is additive, and it also
   removes variance.
3. **Reframing last** — this is where trade-offs live (privilege, isolation,
   lost capabilities). Keep it independently revertible, state the trade-off in
   writing, and confirm the failure mode is loud rather than subtle.

Change one thing per step, re-measure, and record the number. A step whose
saving cannot be attributed is a step that will be undone by the next person.

---

## 10. Checklist

- [ ] Endpoint is a nameable state, not a console artefact
- [ ] Time origins of all tools reconciled
- [ ] Path shape known: serial segments or parallel fan-out
- [ ] Segments ranked, not just units
- [ ] Object census done; largest origin identified
- [ ] Every path service classified busy vs. blocked
- [ ] Barrier targets: whole near-simultaneous cluster identified
- [ ] Each path unit: payload vs. frame ratio estimated
- [ ] Absent features verified off at every layer
- [ ] Change verified in the produced artefact
- [ ] Patches to foreign files assert-and-fail-loudly
- [ ] Ten boots, P95 recorded per step

---

## Appendix: the worked case

Baseline 6.837 s to `graphical.target`; the path was six serial segments.

| Pattern | Finding | Cost |
|---|---|---|
| Count | one kernel option created 256 legacy device pairs → 512 init objects, 81% of the transaction, walked serially in a segment where no service ran | 1114 ms |
| Blocking + Volume | a barrier target gated by four services finishing within 110 ms: one blocked on entropy, three daemons for hardware disabled in the device tree | ~600 ms of 2204 ms |
| Framing | the compositor unit spent 2118 ms on a login session and a per-user service manager; the compositor itself needed 540 ms | 2118 ms of 2658 ms |

Volume-type work — shrinking the kernel image — was evaluated and dropped: the
remaining margin was ~100 ms, an order of magnitude below the three above. That
ordering is the point of the taxonomy.
