---
description: Test terminal proxy RBAC -- verify commands are correctly allowed/denied by tier
---

Check terminal-proxy is running and RBAC is loaded:

!`docker logs trinity-terminal-proxy --tail 5`

Test the RBAC registry by running the test suite:

!`cd web/terminal-proxy && npx jest rbac-registry.test.js --no-cache 2>&1`

Check the auth-service RBAC registry tests too:

!`cd web/auth-service && npx jest rbac-registry.test.js --no-cache 2>&1`

Report test results. If any tests fail, identify the failing assertions and suggest fixes.
