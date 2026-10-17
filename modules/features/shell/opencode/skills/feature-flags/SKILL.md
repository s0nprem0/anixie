---
name: feature-flags
description: Use when adding feature flags for gradual rollouts, A/B testing, or kill switches in an application.
---

# Feature Flags

## When to Use This Skill
- Rolling out a feature to a percentage of users
- Running A/B tests between implementation variants
- Adding a kill switch for risky features
- Targeting features to specific user segments
- Cleaning up old flags after full rollout

## Workflow
1. Define the flag: name, type (boolean, multivariate, percentage), and default value
2. Choose an implementation: LaunchDarkly, Unleash, Flipt, or a custom config
3. Add flag evaluation at the point of use: `if (isEnabled("new-checkout")) { ... }`
4. Configure targeting rules: percentage rollout, user attributes, or environment
5. Set up monitoring: track flag state alongside metrics to measure impact
6. Gradually increase rollout: 1% → 10% → 50% → 100%
7. Remove the flag and dead code after full rollout

## Rules
- Name flags descriptively: `checkout-redesign-v2`, not `flag1`
- Always have a default value that falls back to the current behavior
- Set expiration dates for flags — no open-ended flags
- Don't nest flag evaluations — it creates unpredictable combinations
- Log flag state in error reports for debugging
- Clean up flags within 30 days of full rollout
