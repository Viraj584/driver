# Demonstration risk model

Scores are policy signals, not probabilities of fraud. The evaluator in `lib/core/risk/risk_engine.dart` is deterministic and intentionally small for reproducible demonstrations.

| Signal | Weight | Reason |
|---|---:|---|
| Device change | 0.30 | `DEVICE_CHANGE` |
| GPS jump with poor accuracy | 0.05 | `GPS_UNCERTAIN` |
| GPS discontinuity with usable accuracy | 0.35 | `GPS_DISCONTINUITY` |
| Unusual speed delta | 0.35 | `IMPLAUSIBLE_SPEED_DELTA` |
| Possible handoff (correlated device/session signals) | 0.65 | `DEVICE_CHANGE`, `INCONSISTENT_SESSION` |
| Successful demonstration check | −0.25, floor 0, local demonstration only | `VERIFICATION_PASSED` |

The combined score is clamped to `[0,1]`. At `0.60`, the policy requests step-up verification. At `0.85`, it marks review required; telemetry evaluation does not freeze an account. The backend uses the same current event labels and thresholds. A simulated check result is recorded as `SIMULATED` and cannot lower risk, approve, or restrict an account; an administrator must decide the resulting state. Only the local visual demo applies the `−0.25` adjustment and shows a sample restricted state after a simulated failure. Repeated event submissions are idempotent by request ID and are not accumulated into a probability.

This is not calibrated against real fleet data. Location uncertainty, elapsed time, travel context, connectivity gaps, device replacement explanations, and adversarial input are not modeled. Production decisions require a validated model and documented policy.
