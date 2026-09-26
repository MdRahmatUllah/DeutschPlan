---
name: test-semantics-dispose-inline
description: "A widget test's SemanticsHandle must be disposed inline; addTearDown(semantics.dispose) fails, since flutter_test checks before teardowns"
metadata:
  type: feedback
---

`final semantics = tester.ensureSemantics(); … semantics.dispose();` at the end of the test body. Not `addTearDown(semantics.dispose)`: `WidgetTester._verifySemanticsHandlesWereDisposed` runs at the end of the body, before teardowns, so the test fails with "A SemanticsHandle was active at the end of the test."

**Why:** a reviewer's nit on #518 (#517) suggested addTearDown. I tried it, every run failed, and I reverted it and explained on the PR.

**How to apply:** when a reviewer asks for it, reply with the reason rather than change it. A failed expect before the inline dispose only adds that second message on top of the real failure. Related: [[test-viewinsets-physical]].
